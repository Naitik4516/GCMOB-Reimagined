import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:media_kit/media_kit.dart';

import '../../../core/rtsp/mpv_errors.dart';
import '../../../core/rtsp/rtsp_url.dart';
import '../../profiles/models/dvr_profile.dart';
import '../player/media_kit_rtsp_controller.dart';

enum TileConn { idle, loading, playing, reconnecting, error }

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

/// Owns one [MediaKitRTSPController] for a single grid tile.
///
/// * [highRes] — 1x1 tiles play the HD main-stream (audio on unless
///   muted); grid tiles play the muted SD sub-stream.
/// * Failure policy: if sized frames are not observed within
///   [connectTimeout] (or a mid-stream error arrives), the tile goes to
///   `error` and stays in its slot — the tile shows a retry overlay and
///   nothing is reordered. No automatic reconnect is attempted; [retry]
///   is strictly user-initiated. [onFailed] only lets the spotlight view
///   react to a dead visible layer (never reorders grid tiles).
class TileCubit extends Cubit<TileState> {
  final DvrProfile profile;
  final String password;
  final MediaKitRTSPController controller;
  final bool highRes;
  final void Function(int channel)? onFailed;
  final Duration connectTimeout;
  final Duration startDelay;

  final List<StreamSubscription> _subs = [];
  bool _listening = false;
  bool _playing = false;
  bool _sized = false;
  Completer<void>? _playingGate;

  /// Dead-man's switch for tolerated benign errors: rearmed on every
  /// blip, it fails the tile only if mpv is still stuck buffering when
  /// the grace period lapses.
  Timer? _stallWatch;
  static const _stallGrace = Duration(seconds: 10);

  TileCubit({
    required this.profile,
    required this.password,
    required int channel,
    required this.controller,
    this.highRes = false,
    bool startMuted = true,
    this.onFailed,
    this.connectTimeout = const Duration(seconds: 15),
    // Staggers first opens across the grid (set from the tile's slot
    // index). Nine simultaneous mpv + MediaCodec bring-ups overwhelm
    // low-end phone SoCs; a few hundred ms apart they all succeed.
    this.startDelay = Duration.zero,
  }) : super(TileState(channel: channel, muted: startMuted));

  String get _streamUrl => buildDahuaRtsp(
        user: profile.username,
        pass: password,
        host: profile.host,
        port: profile.rtspPort,
        channelOneBased: state.channel,
        highRes: highRes,
      );

  Future<void> _openTile() => highRes
      ? controller.openMain(_streamUrl, withAudio: !state.muted)
      : controller.openSub(_streamUrl);

  Future<void> start() async {
    if (startDelay > Duration.zero) {
      await Future<void>.delayed(startDelay);
      if (isClosed) return;
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
  Future<void> retry() async {
    if (isClosed) return;
    emit(state.copyWith(
      conn: TileConn.reconnecting,
      retryCount: state.retryCount + 1,
    ));
    try {
      await _connect(() => controller.reconnect(_streamUrl));
    } catch (e) {
      _fail('$e');
    }
  }

  /// M key / tile mute button. Meaningful for HD single tiles (grid
  /// sub-streams stay muted); harmless elsewhere.
  Future<void> toggleMute() async {
    if (isClosed) return;
    final muted = !state.muted;
    emit(state.copyWith(muted: muted));
    try {
      await controller.player.setVolume(muted ? 0.0 : 100.0);
      if (highRes) {
        await controller.player.setAudioTrack(
            muted ? AudioTrack.no() : AudioTrack.auto());
      }
    } catch (_) {
      // Best-effort; tile state already reflects the intent.
    }
  }

  void _listen() {
    if (_listening) return;
    _listening = true;
    _subs.add(controller.player.stream.playing.listen((playing) {
      if (isClosed || !playing) return;
      _playing = true;
      _maybeReady();
    }));
    // `playing` fires before the first frame is decoded. The tile keeps
    // its spinner until sized frames exist, otherwise the overlay lifts
    // onto a black texture for a beat (same source Video uses to unhide).
    _subs.add(controller.player.stream.width.listen((w) {
      if (isClosed) return;
      if ((w ?? 0) > 0) {
        _sized = true;
        _maybeReady();
      }
    }));
    _subs.add(controller.player.stream.error.listen((e) {
      // Mid-stream failure only; initial-connect failures surface via
      // the timeout gate below (error text is often empty that early).
      if (isClosed || state.conn != TileConn.playing) return;
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
        if (isClosed || state.conn != TileConn.playing) return;
        if (controller.player.state.buffering) {
          _fail('Stream stalled — tap Retry');
        }
      });
    }));
  }

  /// Completes the connect gate once sized frames flow, then reports.
  void _maybeReady() {
    if (!_playing || !_sized || isClosed) return;
    if (_playingGate != null && !_playingGate!.isCompleted) {
      _playingGate!.complete();
    }
    if (state.conn == TileConn.playing) return;
    emit(state.copyWith(conn: TileConn.playing));
  }

  /// Opens the stream and waits for sized frames, else throws.
  Future<void> _connect(Future<void> Function() open) async {
    _playing = false;
    _sized = false;
    _stallWatch?.cancel();
    _playingGate = Completer<void>();
    await open();
    await _playingGate!.future.timeout(
      connectTimeout,
      onTimeout: () => throw TimeoutException(
          'No video for ${connectTimeout.inSeconds}s — camera offline or credentials wrong'),
    );
  }

  void _fail(String message) {
    if (isClosed) return;
    emit(state.copyWith(conn: TileConn.error, message: message));
    // Release the decoder + DVR session immediately. Otherwise mpv keeps
    // a dead session half-open (and its own reconnect loop spinning),
    // starving the working tiles of handshake slots on weak DVRs.
    unawaited(controller.player.stop().then<void>((_) {}, onError: (_) {}));
    onFailed?.call(state.channel);
  }

  @override
  Future<void> close() async {
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
    _stallWatch?.cancel();
    if (_playingGate != null && !_playingGate!.isCompleted) {
      _playingGate?.complete();
    }
    await controller.dispose();
    return super.close();
  }
}
