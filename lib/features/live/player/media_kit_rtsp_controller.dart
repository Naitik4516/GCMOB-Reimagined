import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../../core/rtsp/mpv_options.dart';
import '../../../core/rtsp/rtsp_concurrency.dart';

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
class MediaKitRTSPController {
  late final Player player;
  late final VideoController videoController;
  int _retries = 0;
  bool _flagsApplied = false;

  MediaKitRTSPController({String hwdec = 'auto-safe', bool muted = true}) {
    player = Player(
      configuration: PlayerConfiguration(
        title: 'gcmob',
        muted: muted,
        bufferSize: 4 * 1024 * 1024,
        logLevel: MPVLogLevel.error,
      ),
    );
    videoController = VideoController(
      player,
      configuration: VideoControllerConfiguration(
        hwdec: hwdec,
        // vo left as platform default (Android: gpu). Forcing gpu-next
        // breaks some Mali/Adreno drivers on TV sticks.
        enableHardwareAcceleration: true,
      ),
    );
    if (muted) {
      player.setVolume(0.0);
    }
  }

  /// Escape hatch: `setProperty` lives on the native platform player, not
  /// the public [Player] facade. Dynamic dispatch keeps this compiling on
  /// every target; failures are swallowed by design.
  Future<void> _setMpv(String key, String value) async {
    try {
      final dynamic platform = player.platform;
      await platform?.setProperty(key, value);
    } catch (_) {
      // Best-effort only.
    }
  }

  /// Applies load-critical mpv flags, awaited BEFORE every `open()`.
  /// Idempotent per controller; each property set is best-effort.
  Future<void> ensureFlags() async {
    if (_flagsApplied) return;
    _flagsApplied = true;
    for (final opt in kLowLatencyMpvOptions) {
      await _setMpv(opt.key, opt.value);
    }
  }

  /// Open a low-res sub-stream tile (always muted, no audio decode).
  Future<void> openSub(String rtspUrl) async {
    _retries = 0;
    await player.setVolume(0.0);
    await player.setAudioTrack(AudioTrack.no());
    await RtspOpener.run(() async {
      await ensureFlags();
      await player.open(Media(rtspUrl), play: true);
    });
  }

  /// Open a high-res main-stream (fullscreen). Audio on by default.
  Future<void> openMain(String rtspUrl, {bool withAudio = true}) =>
      openSingle(rtspUrl, withAudio: withAudio);

  /// Open any single-stream URL (fullscreen SD/HD switching).
  Future<void> openSingle(String rtspUrl, {bool withAudio = true}) async {
    await RtspOpener.run(() async {
      await ensureFlags();
      await player.open(Media(rtspUrl), play: true);
    });
    if (withAudio) {
      await player.setAudioTrack(AudioTrack.auto());
      await player.setVolume(100.0);
    } else {
      await player.setAudioTrack(AudioTrack.no());
      await player.setVolume(0.0);
    }
  }

  /// Re-open the same URL with linear backoff (2s..10s).
  Future<void> reconnect(String rtspUrl) async {
    _retries++;
    final secs = (_retries * 2).clamp(2, 10);
    await Future<void>.delayed(Duration(seconds: secs));
    await RtspOpener.run(() async {
      await ensureFlags();
      await player.open(Media(rtspUrl), play: true);
    });
  }

  Future<void> dispose() async {
    await player.dispose();
  }
}
