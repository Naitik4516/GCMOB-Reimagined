import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../../core/rtsp/mpv_options.dart';
import '../../../core/rtsp/rtsp_concurrency.dart';
import 'tile_player.dart';

/// One low-latency RTSP player. Grid tiles use [openSub] (muted,
/// `subtype=1`); fullscreen uses [openMain] (audio on, `subtype=0`).
///
/// Two load-path rules live here, both learned the hard way:
///
/// * Load-critical mpv flags (`rtsp-transport=tcp`, `nobuffer`, …) are
///   awaited inside [ensureFlags] BEFORE every `open()`. Firing them
///   unawaited from the constructor races the `loadlist` command, so some
///   tiles silently fell back to UDP and stalled on Wi-Fi.
/// * Every `open()` goes through [RtspOpener]: at most 3 concurrent
///   handshakes, or a full grid DDoSes the DVR and nothing loads.
class MediaKitRTSPController implements TilePlayer {
  /// Debug-only gauges.
  ///
  /// [activePlayers] counts controller instances (constructor→dispose), so
  /// parked-but-alive players still count. [activeStreams] counts currently
  /// open RTSP sessions (successful open→stop/dispose): steady state in 1x1
  /// should be 1 once the hidden SD layer suspends, while `activePlayers`
  /// stays 2 until the tile is disposed.
  static int activePlayers = 0;
  static int activeStreams = 0;

  final String debugLabel;

  late final Player player;
  late final VideoController videoController;
  Future<void>? _flagsFuture;
  bool _flagsApplied = false;
  bool _disposed = false;
  Future<void>? _opening;
  Future<void>? _disposing;
  StreamSubscription<int?>? _firstFrameSub;
  bool _streamOpen = false;

  MediaKitRTSPController({this.debugLabel = 'player'}) {
    activePlayers++;
    _debugActive();
    player = Player(
      configuration: const PlayerConfiguration(
        title: 'gcmob',
        muted: true,
        bufferSize: 4 * 1024 * 1024,
        logLevel: MPVLogLevel.error,
      ),
    );
    videoController = VideoController(
      player,
      configuration: const VideoControllerConfiguration(
        hwdec: 'auto-safe',
        // vo left as platform default (Android: gpu). Forcing gpu-next
        // breaks some Mali/Adreno drivers on TV sticks.
        enableHardwareAcceleration: true,
      ),
    );
    player.setVolume(0.0);
  }

  @override
  Stream<bool> get playing => player.stream.playing;

  @override
  Stream<int?> get width => player.stream.width;

  @override
  Stream<String> get error => player.stream.error;

  @override
  Stream<bool> get buffering => player.stream.buffering;

  @override
  Stream<Duration> get position => player.stream.position;

  @override
  bool get isBuffering => player.state.buffering;

  /// Best-effort libmpv property write via the native platform player.
  ///
  /// `setProperty` is not on the public [Player] facade, so dynamic dispatch
  /// keeps this compiling on every target. Some platforms/forks may not
  /// implement it at all; in that case this silently returns `false` and the
  /// caller keeps going — flags are an optimization, never a load blocker.
  Future<bool> _setMpv(String key, String value) async {
    try {
      final dynamic platform = player.platform;
      if (platform == null) {
        debugPrint('MediaKitRTSPController: no native platform for $key');
        return false;
      }
      final dynamic result = await platform.setProperty(key, value);
      if (result == false) {
        debugPrint('MediaKitRTSPController: $key was not applied');
        return false;
      }
      return true;
    } catch (e) {
      // Log the key only: these are static flags today, but never risk
      // printing a future credential-carrying option.
      debugPrint('MediaKitRTSPController: failed to apply $key ($e)');
      return false;
    }
  }

  /// Applies load-critical mpv flags, awaited BEFORE every `open()`.
  ///
  /// Idempotent per controller: concurrent callers share one in-flight
  /// future, and [_flagsApplied] flips only after the whole loop finishes.
  /// A failed individual property is logged but does not disable the rest;
  /// an unexpected error leaves the future retryable on the next open.
  Future<void> ensureFlags() {
    if (_flagsApplied) return Future.value();
    return _flagsFuture ??= _applyFlags();
  }

  Future<void> _applyFlags() async {
    try {
      for (final opt in kLowLatencyMpvOptions) {
        await _setMpv(opt.key, opt.value);
      }
      _flagsApplied = true;
    } finally {
      _flagsFuture = null;
    }
  }

  /// Open a low-res sub-stream tile (always muted, no audio decode).
  @override
  Future<void> openSub(String rtspUrl) {
    if (_disposed) return Future.value();
    return _trackOpen(() => _timedOpen(() async {
          await player.setVolume(0.0);
          await player.setAudioTrack(AudioTrack.no());
          await RtspOpener.run(() async {
            await ensureFlags();
            if (_disposed) return;
            await player.open(Media(rtspUrl), play: true);
          });
        }));
  }

  /// Open a high-res main-stream (fullscreen). Audio follows [withAudio].
  @override
  Future<void> openMain(String rtspUrl, {required bool withAudio}) {
    if (_disposed) return Future.value();
    return _trackOpen(() => _timedOpen(() async {
          await RtspOpener.run(() async {
            await ensureFlags();
            if (_disposed) return;
            await player.open(Media(rtspUrl), play: true);
          });
          if (_disposed) return;
          if (withAudio) {
            await player.setAudioTrack(AudioTrack.auto());
            await player.setVolume(100.0);
          } else {
            await player.setAudioTrack(AudioTrack.no());
            await player.setVolume(0.0);
          }
        }));
  }

  /// Debug-only timing: queue + handshake time for `open`, then the first
  /// sized frame. Never logs the URL (it carries credentials).
  Future<void> _timedOpen(Future<void> Function() task) async {
    final sw = Stopwatch()..start();
    if (kDebugMode) {
      unawaited(_firstFrameSub?.cancel());
      _firstFrameSub = player.stream.width.listen((w) {
        if ((w ?? 0) <= 0) return;
        debugPrint('[$debugLabel] firstFrame=${sw.elapsedMilliseconds}ms');
        unawaited(_firstFrameSub?.cancel());
        _firstFrameSub = null;
      });
    }
    var opened = false;
    try {
      await task();
      opened = true;
      _markStreamOpen();
    } finally {
      if (kDebugMode) {
        debugPrint('[$debugLabel] open=${sw.elapsedMilliseconds}ms');
        if (!opened) {
          unawaited(_firstFrameSub?.cancel());
          _firstFrameSub = null;
        }
      }
    }
  }

  void _markStreamOpen() {
    if (_streamOpen) return;
    _streamOpen = true;
    activeStreams++;
    _debugActive();
  }

  void _markStreamClosed({bool notify = true}) {
    if (!_streamOpen) return;
    _streamOpen = false;
    activeStreams--;
    if (notify) _debugActive();
  }

  void _debugActive() {
    if (kDebugMode) {
      debugPrint(
          '[$debugLabel] active=$activePlayers streams=$activeStreams');
    }
  }

  @override
  Future<void> setMuted(bool muted) async {
    if (_disposed) return;
    await player.setVolume(muted ? 0.0 : 100.0);
    await player.setAudioTrack(
        muted ? AudioTrack.no() : AudioTrack.auto());
  }

  @override
  Future<void> stop() async {
    if (_disposed) return;
    try {
      await player.stop();
    } catch (_) {
      // `_fail` is best-effort: a broken session must not throw into the
      // error path.
    }
    _markStreamClosed();
  }

  /// Tracks the current open so [dispose] can wait instead of pulling the
  /// player out from under a queued [RtspOpener] handshake.
  Future<void> _trackOpen(Future<void> Function() task) {
    late final Future<void> future;
    future = task().whenComplete(() {
      if (identical(_opening, future)) _opening = null;
    });
    _opening = future;
    return future;
  }

  @override
  Future<void> dispose() {
    if (_disposing != null) return _disposing!;
    _disposed = true;
    return _disposing = _dispose();
  }

  Future<void> _dispose() async {
    await _firstFrameSub?.cancel();
    _firstFrameSub = null;
    try {
      await _opening;
    } catch (_) {
      // An in-flight open may fail while closing; the player still needs
      // disposal.
    }
    try {
      await player.dispose();
    } finally {
      _markStreamClosed(notify: false);
      activePlayers--;
      _debugActive();
    }
  }
}
