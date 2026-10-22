import 'dart:async';

import 'package:gcmob_reimagined/features/live/player/tile_player.dart';

/// In-memory [TilePlayer] for cubit tests. Never touches libmpv.
class FakeTilePlayer implements TilePlayer {
  final _playing = StreamController<bool>.broadcast();
  final _width = StreamController<int?>.broadcast();
  final _error = StreamController<String>.broadcast();
  final _buffering = StreamController<bool>.broadcast();
  final _position = StreamController<Duration>.broadcast();

  /// When true, every open schedules `playing` + `width=640` on a microtask.
  bool autoPlay = true;

  /// When true, every open throws instead of recording a successful handshake.
  bool throwOnOpen = false;

  /// When true, [setMuted] throws and does not record the value.
  bool throwOnMute = false;

  bool bufferingValue = false;
  bool disposed = false;

  int openCount = 0;
  int stopCount = 0;
  int disposeCount = 0;

  final List<String> subUrls = [];
  final List<String> mainUrls = [];
  final List<bool> mainWithAudio = [];
  final List<bool> mutedValues = [];

  @override
  Stream<bool> get playing => _playing.stream;

  @override
  Stream<int?> get width => _width.stream;

  @override
  Stream<String> get error => _error.stream;

  @override
  Stream<bool> get buffering => _buffering.stream;

  @override
  Stream<Duration> get position => _position.stream;

  @override
  bool get isBuffering => bufferingValue;

  @override
  Future<void> openSub(String url) async {
    openCount++;
    subUrls.add(url);
    if (throwOnOpen) throw StateError('open failed');
    if (autoPlay) _scheduleReady();
  }

  @override
  Future<void> openMain(String url, {required bool withAudio}) async {
    openCount++;
    mainUrls.add(url);
    mainWithAudio.add(withAudio);
    if (throwOnOpen) throw StateError('open failed');
    if (autoPlay) _scheduleReady();
  }

  @override
  Future<void> setMuted(bool muted) async {
    if (throwOnMute) throw StateError('mute unavailable');
    mutedValues.add(muted);
  }

  @override
  Future<void> stop() async {
    stopCount++;
  }

  @override
  Future<void> dispose() async {
    if (disposed) return;
    disposed = true;
    disposeCount++;
    await Future.wait([
      _playing.close(),
      _width.close(),
      _error.close(),
      _buffering.close(),
      _position.close(),
    ]);
  }

  void _scheduleReady() {
    scheduleMicrotask(() {
      if (disposed) return;
      _playing.add(true);
      _width.add(640);
    });
  }

  void emitPlaying(bool value) => _playing.add(value);

  void emitWidth(int? value) => _width.add(value);

  void emitError(String message) => _error.add(message);

  void emitBuffering(bool value) {
    bufferingValue = value;
    _buffering.add(value);
  }

  void emitPosition(Duration value) => _position.add(value);
}
