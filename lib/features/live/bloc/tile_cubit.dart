import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/rtsp/rtsp_url.dart';
import '../../profiles/models/dvr_profile.dart';
import '../player/media_kit_rtsp_controller.dart';

enum TileConn { idle, loading, playing, reconnecting, error }

class TileState extends Equatable {
  final int channel; // 1-based
  final TileConn conn;
  final String? message;
  final int retryCount;

  const TileState({
    required this.channel,
    this.conn = TileConn.idle,
    this.message,
    this.retryCount = 0,
  });

  TileState copyWith({TileConn? conn, String? message, int? retryCount}) =>
      TileState(
        channel: channel,
        conn: conn ?? this.conn,
        message: message,
        retryCount: retryCount ?? this.retryCount,
      );

  @override
  List<Object?> get props => [channel, conn, message, retryCount];
}

/// Owns one [MediaKitRTSPController] for a single grid tile.
///
/// Failure policy: if `playing` is not observed within [connectTimeout]
/// (or a mid-stream error arrives), the tile goes to `error` and reports
/// via [onFailed] so the grid can sink it behind working tiles. No
/// automatic reconnect is attempted — [retry] is strictly user-initiated
/// and reports via [onRecovered] on success.
class TileCubit extends Cubit<TileState> {
  final DvrProfile profile;
  final String password;
  final MediaKitRTSPController controller;
  final void Function(int channel)? onFailed;
  final void Function(int channel)? onRecovered;
  final Duration connectTimeout;

  final List<StreamSubscription> _subs = [];
  bool _listening = false;
  bool _playing = false;
  bool _sized = false;
  Completer<void>? _playingGate;

  TileCubit({
    required this.profile,
    required this.password,
    required int channel,
    required this.controller,
    this.onFailed,
    this.onRecovered,
    this.connectTimeout = const Duration(seconds: 15),
  }) : super(TileState(channel: channel));

  String get _subUrl => buildDahuaRtsp(
        user: profile.username,
        pass: password,
        host: profile.host,
        port: profile.rtspPort,
        channelOneBased: state.channel,
        highRes: false,
      );

  Future<void> start() async {
    emit(state.copyWith(conn: TileConn.loading));
    _listen();
    try {
      await _connect(() => controller.openSub(_subUrl));
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
      await _connect(() => controller.reconnect(_subUrl));
    } catch (e) {
      _fail('$e');
    }
  }

  /// Fullscreen handoff: the tile is hidden behind fullscreen, so release
  /// its decoder once the main stream has taken over.
  void suspend() {
    if (isClosed) return;
    emit(state.copyWith(conn: TileConn.idle));
    unawaited(controller.player.stop().then<void>((_) {}, onError: (_) {}));
  }

  /// Idempotent resume after fullscreen closes. No-op when the sub-stream
  /// never stopped (main stream failed before takeover).
  void ensureSubPlaying() {
    if (isClosed || state.conn == TileConn.playing) return;
    unawaited(start());
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
      if (!isClosed && state.conn == TileConn.playing) {
        _fail(e.isEmpty ? 'Stream dropped' : e);
      }
    }));
  }

  /// Completes the connect gate once sized frames flow, then reports.
  void _maybeReady() {
    if (!_playing || !_sized || isClosed) return;
    if (_playingGate != null && !_playingGate!.isCompleted) {
      _playingGate!.complete();
    }
    if (state.conn == TileConn.playing) return;
    final wasDown = state.conn == TileConn.error ||
        state.conn == TileConn.reconnecting;
    emit(state.copyWith(conn: TileConn.playing));
    if (wasDown) onRecovered?.call(state.channel);
  }

  /// Opens the stream and waits for sized frames, else throws.
  Future<void> _connect(Future<void> Function() open) async {
    _playing = false;
    _sized = false;
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
    onFailed?.call(state.channel);
  }

  @override
  Future<void> close() async {
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
    if (_playingGate != null && !_playingGate!.isCompleted) {
      _playingGate?.complete();
    }
    await controller.dispose();
    return super.close();
  }
}
