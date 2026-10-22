import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../../core/rtsp/mpv_errors.dart';
import '../../../core/rtsp/rtsp_url.dart';
import '../../profiles/models/dvr_profile.dart';
import '../player/tile_player.dart';

enum TileConn { idle, loading, playing, reconnecting, error, suspended }

class TileState extends Equatable {
  final int channel; // 1-based
  final TileConn conn;
  final String? message;
  final int retryCount;

  /// Audio state. Grid sub-stream tiles start muted; HD single tiles
  /// start unmuted (M key / tile button toggles).
  final bool muted;

  const TileState({
    required this.channel,
    this.conn = TileConn.idle,
    this.message,
    this.retryCount = 0,
    this.muted = true,
  });

  TileState copyWith({
    TileConn? conn,
    String? message,
    int? retryCount,
    bool? muted,
  }) =>
      TileState(
        channel: channel,
        conn: conn ?? this.conn,
        message: message,
        retryCount: retryCount ?? this.retryCount,
        muted: muted ?? this.muted,
      );

  @override
  List<Object?> get props => [channel, conn, message, retryCount, muted];
}

/// Owns one [TilePlayer] for a single grid tile.
///
/// * [highRes] — 1x1 tiles play the HD main-stream (audio on unless
///   muted); grid tiles play the muted SD sub-stream.
/// * Failure policy: if sized frames are not observed within
///   [connectTimeout], a mid-stream error arrives, or a `playing` feed
///   freezes for [stallTimeout], the tile goes to `error` and stays in its
///   slot — the tile shows a retry overlay and nothing is reordered. No
///   automatic reconnect is attempted; [retry] is strictly user-initiated.
///   [onFailed] only lets the spotlight view react to a dead visible layer
///   (never reorders grid tiles).
/// * [suspend]/[resume] — the hidden SD layer under a confirmed HD layer
///   stops its decoder/session; late teardown events are ignored while
///   suspended. Suspend only after the HD layer is actually playing.
class TileCubit extends Cubit<TileState> {
  final DvrProfile profile;
  final String password;
  final TilePlayer player;

  /// UI-only handle. Null in tests; business logic must never read it.
  final VideoController? videoController;

  final bool highRes;
  final void Function(int channel)? onFailed;
  final Duration connectTimeout;
  final Duration startDelay;

  /// Frozen-feed watchdog tuning. Position must advance at least once per
  /// [stallTimeout] while `playing`; buffering gets one extra interval.
  final Duration stallTimeout;
  final Duration healthInterval;

  /// Test seam for [DateTime.now]; tests advance this with fake time.
  final DateTime Function() _now;

  final List<StreamSubscription> _subs = [];
  bool _listening = false;
  bool _playing = false;
  bool _sized = false;
  bool _suspended = false;
  Completer<void>? _playingGate;

  /// Serializes mute changes so two quick taps both land in order instead of
  /// both reading the same pre-change state.
  Future<void> _muteQueue = Future<void>.value();

  /// Dead-man's switch for tolerated benign errors: rearmed on every
  /// blip, it fails the tile only if mpv is still stuck buffering when
  /// the grace period lapses.
  Timer? _stallWatch;
  static const _stallGrace = Duration(seconds: 10);

  /// Periodic liveness check for a `playing` tile. mpv advances
  /// [TilePlayer.position] while frames decode; a frozen pipeline stops.
  Timer? _healthTimer;
  Duration _lastPosition = Duration.zero;
  DateTime? _lastProgressAt;

  TileCubit({
    required this.profile,
    required this.password,
    required int channel,
    required this.player,
    required this.highRes,
    this.videoController,
    bool startMuted = true,
    this.onFailed,
    this.connectTimeout = const Duration(seconds: 15),
    // Frozen-feed watchdog; production defaults are deliberately
    // conservative. Tests pass tiny values.
    this.stallTimeout = const Duration(seconds: 20),
    this.healthInterval = const Duration(seconds: 5),
    // Staggers first opens across the grid (set from the tile's slot
    // index). Nine simultaneous mpv + MediaCodec bring-ups overwhelm
    // low-end phone SoCs; a few hundred ms apart they all succeed.
    this.startDelay = Duration.zero,
    DateTime Function()? now,
  })  : _now = now ?? DateTime.now,
        super(TileState(channel: channel, muted: startMuted));

  String get _streamUrl => buildDahuaRtsp(
        user: profile.username,
        pass: password,
        host: profile.host,
        port: profile.rtspPort,
        channelOneBased: state.channel,
        highRes: highRes,
      );

  Future<void> _openTile() => highRes
      ? player.openMain(_streamUrl, withAudio: !state.muted)
      : player.openSub(_streamUrl);

  Future<void> start() async {
    if (startDelay > Duration.zero) {
      await Future<void>.delayed(startDelay);
      if (isClosed || _suspended) return;
    }
    emit(state.copyWith(conn: TileConn.loading));
    _listen();
    try {
      await _connect(_openTile);
    } catch (e) {
      _fail('$e');
    }
  }

  /// Manual retry from the tile error overlay.
  ///
  /// The first retry opens immediately. Only repeated failures back off
  /// (2s, 4s, … capped at 10s), and a successful playback resets the
  /// counter so the next outage starts fresh.
  Future<void> retry() async {
    if (isClosed || _suspended) return;
    _stopHealthWatch();
    final previousAttempts = state.retryCount;
    emit(state.copyWith(
      conn: TileConn.reconnecting,
      retryCount: previousAttempts + 1,
    ));
    if (previousAttempts > 0) {
      await Future<void>.delayed(
        Duration(seconds: (2 * previousAttempts).clamp(2, 10)),
      );
      if (isClosed || _suspended) return;
    }
    try {
      await _connect(_openTile);
    } catch (e) {
      _fail('$e');
    }
  }

  /// Parks the player while a confirmed HD layer is the visible one.
  ///
  /// `_suspended` is set before [TilePlayer.stop] so late teardown
  /// `playing`/`error` events cannot flip the tile back to `playing` or
  /// `error`. Timers are cancelled; [resume] reopens the same stream.
  Future<void> suspend() async {
    if (isClosed || _suspended) return;
    _suspended = true;
    _playing = false;
    _sized = false;
    _stallWatch?.cancel();
    _stallWatch = null;
    _stopHealthWatch();
    // Release any in-flight connect waiter; `_fail` is already muted.
    final gate = _playingGate;
    if (gate != null && !gate.isCompleted) gate.complete();
    try {
      await player.stop();
    } catch (_) {
      // Best-effort: the session is being parked anyway.
    }
    if (isClosed || !_suspended) return;
    if (kDebugMode) {
      debugPrint('[tile ch=${state.channel}] suspend');
    }
    emit(state.copyWith(conn: TileConn.suspended));
  }

  /// Reopens a parked player (exit 1x1, HD failure, or HD→SD toggle).
  Future<void> resume() async {
    if (isClosed || !_suspended) return;
    _suspended = false;
    if (kDebugMode) {
      debugPrint('[tile ch=${state.channel}] resume');
    }
    emit(state.copyWith(conn: TileConn.loading));
    _listen();
    try {
      await _connect(_openTile);
    } catch (e) {
      _fail('$e');
    }
  }

  /// M key / tile mute button. Meaningful for HD single tiles (grid
  /// sub-streams stay muted); harmless elsewhere.
  Future<void> toggleMute() {
    if (isClosed) return Future<void>.value();
    final pending = _muteQueue.then((_) async {
      if (isClosed) return;
      final muted = !state.muted;
      try {
        await player.setMuted(muted);
      } catch (_) {
        // Keep the reported state truthful: the player rejected the change.
        return;
      }
      if (isClosed) return;
      emit(state.copyWith(muted: muted));
    });
    _muteQueue = pending;
    return pending;
  }

  void _listen() {
    if (_listening) return;
    _listening = true;
    _subs.add(player.playing.listen((playing) {
      if (isClosed || _suspended || !playing) return;
      _playing = true;
      _maybeReady();
    }));
    // `playing` fires before the first frame is decoded. The tile keeps
    // its spinner until sized frames exist, otherwise the overlay lifts
    // onto a black texture for a beat (same source Video uses to unhide).
    _subs.add(player.width.listen((w) {
      if (isClosed || _suspended) return;
      if ((w ?? 0) > 0) {
        _sized = true;
        _maybeReady();
      }
    }));
    _subs.add(player.error.listen((e) {
      // Mid-stream failure only; initial-connect failures surface via
      // the timeout gate below (error text is often empty that early).
      if (isClosed || _suspended || state.conn != TileConn.playing) return;
      if (!isBenignLiveError(e)) {
        _fail(e.isEmpty ? 'Stream dropped' : e);
        return;
      }
      // Benign on a live stream (nothing can seek it): never fatal by
      // itself — first loads often log bursts of these while the stream
      // is actually fine. Rearm the stall watchdog instead: if mpv is
      // still stuck buffering when it lapses, the session really died.
      _stallWatch?.cancel();
      _stallWatch = Timer(_stallGrace, () {
        if (isClosed || _suspended || state.conn != TileConn.playing) return;
        if (player.isBuffering) {
          _fail('Stream stalled — tap Retry');
        }
      });
    }));
    // Playback position is the liveness signal: it advances while frames
    // decode and stops when the pipeline freezes. Ignore it before the
    // first-frame gate — `_maybeReady` seeds the clock.
    _subs.add(player.position.listen((position) {
      if (isClosed || _suspended || state.conn != TileConn.playing) return;
      if (position == _lastPosition) return;
      _lastPosition = position;
      _lastProgressAt = _now();
    }));
  }

  /// Completes the connect gate once sized frames flow, then reports.
  void _maybeReady() {
    if (!_playing || !_sized || isClosed || _suspended) return;
    if (_playingGate != null && !_playingGate!.isCompleted) {
      _playingGate!.complete();
    }
    if (state.conn == TileConn.playing) return;
    _lastProgressAt = _now();
    _startHealthWatch();
    emit(state.copyWith(conn: TileConn.playing, retryCount: 0));
  }

  /// Starts the periodic frozen-feed check. The timer itself is shared
  /// across the tile's lifetime; only one `playing` window runs at a time.
  void _startHealthWatch() {
    _healthTimer ??= Timer.periodic(healthInterval, (_) {
      if (isClosed || _suspended) return;
      if (state.conn != TileConn.playing) {
        _stopHealthWatch();
        return;
      }
      final last = _lastProgressAt;
      if (last == null) return;
      // Buffering that never resolves is exactly the frozen case; give it
      // one extra interval before failing, but never restart on buffering
      // events (they are not evidence of progress).
      final limit =
          player.isBuffering ? stallTimeout + healthInterval : stallTimeout;
      if (_now().difference(last) > limit) {
        _fail('Stream stopped responding — tap Retry');
      }
    });
  }

  void _stopHealthWatch() {
    _healthTimer?.cancel();
    _healthTimer = null;
    _lastProgressAt = null;
  }

  /// Opens the stream and waits for sized frames, else throws.
  Future<void> _connect(Future<void> Function() open) async {
    _playing = false;
    _sized = false;
    _stallWatch?.cancel();
    _stallWatch = null;
    _stopHealthWatch();
    _lastPosition = Duration.zero;
    _playingGate = Completer<void>();
    await open();
    await _playingGate!.future.timeout(
      connectTimeout,
      onTimeout: () => throw TimeoutException(
          'No video for ${connectTimeout.inSeconds}s — camera offline or credentials wrong'),
    );
  }

  void _fail(String message) {
    if (isClosed || _suspended) return;
    _stallWatch?.cancel();
    _stallWatch = null;
    _stopHealthWatch();
    emit(state.copyWith(
      conn: TileConn.error,
      message: redactRtspCredentials(message),
    ));
    // Release the decoder + DVR session immediately. Otherwise mpv keeps
    // a dead session half-open, starving the working tiles of handshake
    // slots on weak DVRs.
    unawaited(player.stop());
    onFailed?.call(state.channel);
  }

  @override
  Future<void> close() async {
    // Cancellation stops event delivery synchronously; don't await the
    // returned futures, which can complete outside the caller's zone.
    for (final s in _subs) {
      unawaited(s.cancel());
    }
    _subs.clear();
    _stallWatch?.cancel();
    _stallWatch = null;
    _stopHealthWatch();
    if (_playingGate != null && !_playingGate!.isCompleted) {
      _playingGate?.complete();
    }
    await player.dispose();
    return super.close();
  }
}
