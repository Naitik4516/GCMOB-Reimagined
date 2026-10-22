import 'dart:async';

/// Minimal player surface used by [TileCubit].
///
/// Keeps business logic (connect timeout, retry policy, watchdog) independent
/// of libmpv so it can be unit-tested with a fake. The concrete
/// `MediaKitRTSPController` also exposes its `VideoController` for the UI.
abstract interface class TilePlayer {
  Stream<bool> get playing;
  Stream<int?> get width;
  Stream<String> get error;
  Stream<bool> get buffering;
  Stream<Duration> get position;
  bool get isBuffering;

  Future<void> openSub(String url);
  Future<void> openMain(String url, {required bool withAudio});
  Future<void> setMuted(bool muted);
  Future<void> stop();
  Future<void> dispose();
}
