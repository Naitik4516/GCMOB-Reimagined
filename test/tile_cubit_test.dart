import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gcmob_reimagined/features/live/bloc/tile_cubit.dart';
import 'package:gcmob_reimagined/features/profiles/models/dvr_profile.dart';

import 'helpers/fake_tile_player.dart';

const _profile = DvrProfile(
  id: 'dvr-1',
  name: 'Test DVR',
  host: '192.168.1.240',
  rtspPort: 554,
  username: 'admin',
  channelCount: 16,
);
const _password = 'secret';
const _subTimeout = Duration(milliseconds: 50);

const _subUrl =
    'rtsp://admin:secret@192.168.1.240:554/cam/realmonitor?channel=0&subtype=1';
const _mainUrl =
    'rtsp://admin:secret@192.168.1.240:554/cam/realmonitor?channel=0&subtype=0';

TileCubit _buildCubit(
  FakeTilePlayer player, {
  bool highRes = false,
  bool startMuted = true,
  Duration stallTimeout = const Duration(seconds: 20),
  Duration healthInterval = const Duration(seconds: 5),
  Duration startDelay = Duration.zero,
  DateTime Function()? now,
}) {
  return TileCubit(
    profile: _profile,
    password: _password,
    channel: 1,
    player: player,
    highRes: highRes,
    startMuted: startMuted,
    connectTimeout: _subTimeout,
    stallTimeout: stallTimeout,
    healthInterval: healthInterval,
    startDelay: startDelay,
    now: now,
  );
}

TileCubit _buildWatchdogCubit(
  FakeAsync async,
  FakeTilePlayer player, {
  Duration stallTimeout = const Duration(milliseconds: 100),
  Duration healthInterval = const Duration(milliseconds: 20),
}) {
  final base = DateTime(2026);
  return _buildCubit(
    player,
    stallTimeout: stallTimeout,
    healthInterval: healthInterval,
    now: () => base.add(async.elapsed),
  );
}

void _close(FakeAsync async, TileCubit cubit) {
  unawaited(cubit.close());
  async.flushMicrotasks();
}

void main() {
  test('start opens the SD sub-stream and reports playing after sized frames',
      () {
    fakeAsync((async) {
      final player = FakeTilePlayer();
      final cubit = _buildCubit(player);

      unawaited(cubit.start());
      async.flushMicrotasks();

      expect(cubit.state.conn, TileConn.playing);
      expect(player.subUrls, [_subUrl]);
      expect(player.mainUrls, isEmpty);
      expect(cubit.state.retryCount, 0);

      _close(async, cubit);
    });
  });

  test('playing without sized frames keeps loading then fails on timeout', () {
    fakeAsync((async) {
      final player = FakeTilePlayer()..autoPlay = false;
      final cubit = _buildCubit(player);

      unawaited(cubit.start());
      async.flushMicrotasks();
      expect(cubit.state.conn, TileConn.loading);

      player.emitPlaying(true);
      async.flushMicrotasks();
      expect(cubit.state.conn, TileConn.loading);

      async.elapse(_subTimeout);
      async.flushMicrotasks();

      expect(cubit.state.conn, TileConn.error);
      expect(cubit.state.message, contains('No video'));
      expect(player.stopCount, 1);

      _close(async, cubit);
    });
  });

  test('sized frames without playing do not report playing', () {
    fakeAsync((async) {
      final player = FakeTilePlayer()..autoPlay = false;
      final cubit = _buildCubit(player);

      unawaited(cubit.start());
      async.flushMicrotasks();
      expect(cubit.state.conn, TileConn.loading);

      player.emitWidth(640);
      async.flushMicrotasks();
      expect(cubit.state.conn, TileConn.loading);

      async.elapse(_subTimeout);
      async.flushMicrotasks();
      expect(cubit.state.conn, TileConn.error);
      expect(cubit.state.message, contains('No video'));

      _close(async, cubit);
    });
  });

  test('close before the start delay completes never opens', () {
    fakeAsync((async) {
      final player = FakeTilePlayer();
      final cubit = _buildCubit(
        player,
        startDelay: const Duration(milliseconds: 50),
      );

      unawaited(cubit.start());
      unawaited(cubit.close());
      async.flushMicrotasks();

      expect(cubit.isClosed, isTrue);
      expect(player.openCount, 0);
      expect(player.disposed, isTrue);

      async.elapse(const Duration(milliseconds: 100));
      async.flushMicrotasks();
      expect(player.openCount, 0);
    });
  });

  test('mid-stream non-benign error fails the tile and stops the player', () {
    fakeAsync((async) {
      final player = FakeTilePlayer();
      final cubit = _buildCubit(player);

      unawaited(cubit.start());
      async.flushMicrotasks();
      expect(cubit.state.conn, TileConn.playing);

      player.emitError('TCP connection reset by peer');
      async.flushMicrotasks();

      expect(cubit.state.conn, TileConn.error);
      expect(cubit.state.message, 'TCP connection reset by peer');
      expect(player.stopCount, 1);

      _close(async, cubit);
    });
  });

  test('mid-stream seek-only error is benign and keeps playing', () {
    fakeAsync((async) {
      final player = FakeTilePlayer();
      final cubit = _buildCubit(player);

      unawaited(cubit.start());
      async.flushMicrotasks();
      expect(cubit.state.conn, TileConn.playing);

      player.emitError('Cannot seek in live stream');
      async.flushMicrotasks();

      expect(cubit.state.conn, TileConn.playing);
      expect(player.stopCount, 0);

      _close(async, cubit);
    });
  });

  test('first manual retry opens immediately and success resets the count', () {
    fakeAsync((async) {
      final player = FakeTilePlayer()..autoPlay = false;
      final cubit = _buildCubit(player);

      unawaited(cubit.start());
      async.flushMicrotasks();
      async.elapse(_subTimeout);
      async.flushMicrotasks();
      expect(cubit.state.conn, TileConn.error);
      expect(cubit.state.retryCount, 0);

      player.autoPlay = true;
      unawaited(cubit.retry());
      async.flushMicrotasks();

      expect(player.openCount, 2);
      expect(cubit.state.conn, TileConn.playing);
      expect(cubit.state.retryCount, 0);

      _close(async, cubit);
    });
  });

  test('second retry after another failure waits before opening', () {
    fakeAsync((async) {
      final player = FakeTilePlayer()..autoPlay = false;
      final cubit = _buildCubit(player);

      unawaited(cubit.start());
      async.flushMicrotasks();
      async.elapse(_subTimeout);
      async.flushMicrotasks();
      expect(cubit.state.conn, TileConn.error);

      unawaited(cubit.retry());
      async.flushMicrotasks();
      expect(player.openCount, 2);
      async.elapse(_subTimeout);
      async.flushMicrotasks();
      expect(cubit.state.conn, TileConn.error);
      expect(cubit.state.retryCount, 1);

      player.autoPlay = true;
      unawaited(cubit.retry());
      async.flushMicrotasks();
      expect(cubit.state.conn, TileConn.reconnecting);
      expect(cubit.state.retryCount, 2);
      expect(player.openCount, 2);

      async.elapse(const Duration(milliseconds: 1999));
      async.flushMicrotasks();
      expect(player.openCount, 2);

      async.elapse(const Duration(milliseconds: 1));
      async.flushMicrotasks();
      expect(player.openCount, 3);
      expect(cubit.state.conn, TileConn.playing);
      expect(cubit.state.retryCount, 0);

      _close(async, cubit);
    });
  });

  test('close during a retry delay prevents the pending open', () {
    fakeAsync((async) {
      final player = FakeTilePlayer()..autoPlay = false;
      final cubit = _buildCubit(player);

      unawaited(cubit.start());
      async.flushMicrotasks();
      async.elapse(_subTimeout);
      async.flushMicrotasks();
      expect(cubit.state.conn, TileConn.error);

      unawaited(cubit.retry());
      async.flushMicrotasks();
      expect(player.openCount, 2);
      async.elapse(_subTimeout);
      async.flushMicrotasks();
      expect(cubit.state.retryCount, 1);

      unawaited(cubit.retry());
      async.flushMicrotasks();
      expect(cubit.state.conn, TileConn.reconnecting);

      unawaited(cubit.close());
      async.flushMicrotasks();
      expect(player.disposed, isTrue);
      expect(player.disposeCount, 1);

      async.elapse(const Duration(seconds: 2));
      async.flushMicrotasks();

      expect(player.openCount, 2);
    });
  });

  test('HD tile opens the main stream with audio and mutes through setMuted',
      () {
    fakeAsync((async) {
      final player = FakeTilePlayer();
      final cubit = _buildCubit(player, highRes: true, startMuted: false);

      unawaited(cubit.start());
      async.flushMicrotasks();

      expect(player.mainUrls, [_mainUrl]);
      expect(player.mainWithAudio, [true]);
      expect(player.subUrls, isEmpty);
      expect(cubit.state.conn, TileConn.playing);
      expect(cubit.state.muted, isFalse);

      unawaited(cubit.toggleMute());
      async.flushMicrotasks();
      expect(cubit.state.muted, isTrue);
      expect(player.mutedValues, [true]);

      unawaited(cubit.toggleMute());
      async.flushMicrotasks();
      expect(cubit.state.muted, isFalse);
      expect(player.mutedValues, [true, false]);

      _close(async, cubit);
    });
  });

  test('a rejected mute change leaves the reported state unchanged', () {
    fakeAsync((async) {
      final player = FakeTilePlayer()..throwOnMute = true;
      final cubit = _buildCubit(player, highRes: true, startMuted: false);

      unawaited(cubit.start());
      async.flushMicrotasks();
      expect(cubit.state.muted, isFalse);

      unawaited(cubit.toggleMute());
      async.flushMicrotasks();

      expect(cubit.state.muted, isFalse);
      expect(player.mutedValues, isEmpty);

      _close(async, cubit);
    });
  });

  test('two quick mute taps are serialized', () {
    fakeAsync((async) {
      final player = FakeTilePlayer();
      final cubit = _buildCubit(player, highRes: true, startMuted: false);

      unawaited(cubit.start());
      async.flushMicrotasks();

      unawaited(cubit.toggleMute());
      unawaited(cubit.toggleMute());
      async.flushMicrotasks();

      expect(player.mutedValues, [true, false]);
      expect(cubit.state.muted, isFalse);

      _close(async, cubit);
    });
  });

  test('a failed handshake surfaces as an error and can be retried', () {
    fakeAsync((async) {
      final player = FakeTilePlayer()..throwOnOpen = true;
      final cubit = _buildCubit(player);

      unawaited(cubit.start());
      async.flushMicrotasks();

      expect(cubit.state.conn, TileConn.error);
      expect(cubit.state.retryCount, 0);
      expect(player.stopCount, 1);

      player.throwOnOpen = false;
      unawaited(cubit.retry());
      async.flushMicrotasks();

      expect(player.openCount, 2);
      expect(cubit.state.conn, TileConn.playing);

      _close(async, cubit);
    });
  });

  test('watchdog keeps a healthy playing tile alive while position advances',
      () {
    fakeAsync((async) {
      final player = FakeTilePlayer();
      final cubit = _buildWatchdogCubit(async, player);

      unawaited(cubit.start());
      async.flushMicrotasks();
      expect(cubit.state.conn, TileConn.playing);

      for (var i = 1; i <= 10; i++) {
        async.elapse(const Duration(milliseconds: 20));
        player.emitPosition(Duration(milliseconds: i * 10));
        async.flushMicrotasks();
      }

      expect(cubit.state.conn, TileConn.playing);
      expect(player.stopCount, 0);

      _close(async, cubit);
    });
  });

  test('watchdog fails a playing tile whose position stops advancing', () {
    fakeAsync((async) {
      final player = FakeTilePlayer();
      final cubit = _buildWatchdogCubit(async, player);

      unawaited(cubit.start());
      async.flushMicrotasks();
      expect(cubit.state.conn, TileConn.playing);

      async.elapse(const Duration(milliseconds: 100));
      async.flushMicrotasks();
      expect(cubit.state.conn, TileConn.playing);

      async.elapse(const Duration(milliseconds: 20));
      async.flushMicrotasks();

      expect(cubit.state.conn, TileConn.error);
      expect(cubit.state.message, contains('stopped responding'));
      expect(player.stopCount, 1);

      _close(async, cubit);
    });
  });

  test('frozen feed while loading fails through the connect timeout', () {
    fakeAsync((async) {
      final player = FakeTilePlayer()..autoPlay = false;
      final cubit = _buildWatchdogCubit(async, player);

      unawaited(cubit.start());
      async.flushMicrotasks();
      expect(cubit.state.conn, TileConn.loading);

      async.elapse(_subTimeout);
      async.flushMicrotasks();

      expect(cubit.state.conn, TileConn.error);
      expect(cubit.state.message, contains('No video'));
      expect(player.stopCount, 1);

      _close(async, cubit);
    });
  });

  test('reconnect resets the watchdog clock', () {
    fakeAsync((async) {
      final player = FakeTilePlayer();
      final cubit = _buildWatchdogCubit(async, player);

      unawaited(cubit.start());
      async.flushMicrotasks();
      expect(cubit.state.conn, TileConn.playing);

      // Age the original playing window close to the threshold.
      async.elapse(const Duration(milliseconds: 80));
      async.flushMicrotasks();
      expect(cubit.state.conn, TileConn.playing);

      player.emitError('TCP connection reset by peer');
      async.flushMicrotasks();
      expect(cubit.state.conn, TileConn.error);
      expect(player.stopCount, 1);

      unawaited(cubit.retry());
      async.flushMicrotasks();
      expect(cubit.state.conn, TileConn.playing);

      // A stale clock would now be >stallTimeout old and fail mid-wait.
      async.elapse(const Duration(milliseconds: 80));
      async.flushMicrotasks();
      expect(cubit.state.conn, TileConn.playing);
      expect(player.stopCount, 1);

      _close(async, cubit);
    });
  });

  test('buffering extends the watchdog by one health interval', () {
    fakeAsync((async) {
      final player = FakeTilePlayer();
      final cubit = _buildWatchdogCubit(async, player);

      unawaited(cubit.start());
      async.flushMicrotasks();
      expect(cubit.state.conn, TileConn.playing);

      player.emitBuffering(true);
      async.flushMicrotasks();

      // 100ms is the normal timeout; buffering allows 120ms plus the
      // strictly-greater comparison.
      async.elapse(const Duration(milliseconds: 120));
      async.flushMicrotasks();
      expect(cubit.state.conn, TileConn.playing);

      async.elapse(const Duration(milliseconds: 20));
      async.flushMicrotasks();
      expect(cubit.state.conn, TileConn.error);
      expect(player.stopCount, 1);

      _close(async, cubit);
    });
  });

  test('close cancels the watchdog without emitting an error', () {
    fakeAsync((async) {
      final player = FakeTilePlayer();
      final cubit = _buildWatchdogCubit(async, player);

      unawaited(cubit.start());
      async.flushMicrotasks();
      expect(cubit.state.conn, TileConn.playing);

      _close(async, cubit);
      expect(player.disposed, isTrue);

      async.elapse(const Duration(milliseconds: 200));
      async.flushMicrotasks();

      expect(cubit.isClosed, isTrue);
      expect(cubit.state.conn, TileConn.playing);
      expect(player.stopCount, 0);
    });
  });

  test('suspend stops the player, cancels timers and ignores teardown events',
      () {
    fakeAsync((async) {
      final player = FakeTilePlayer();
      final cubit = _buildWatchdogCubit(async, player);

      unawaited(cubit.start());
      async.flushMicrotasks();
      expect(cubit.state.conn, TileConn.playing);

      unawaited(cubit.suspend());
      async.flushMicrotasks();
      expect(cubit.state.conn, TileConn.suspended);
      expect(player.stopCount, 1);

      // A second suspend is a no-op.
      unawaited(cubit.suspend());
      async.flushMicrotasks();
      expect(player.stopCount, 1);

      // Teardown can emit stale playing/width/error events after `stop()`;
      // they must not flip a parked tile back to playing or error.
      player.emitPlaying(true);
      player.emitWidth(640);
      player.emitError('TCP connection reset by peer');
      async.flushMicrotasks();
      expect(cubit.state.conn, TileConn.suspended);
      expect(cubit.state.message, isNull);

      // The watchdog was cancelled before it could fail the parked tile.
      async.elapse(const Duration(milliseconds: 200));
      async.flushMicrotasks();
      expect(cubit.state.conn, TileConn.suspended);

      _close(async, cubit);
    });
  });

  test('resume reopens the sub-stream and reaches playing', () {
    fakeAsync((async) {
      final player = FakeTilePlayer();
      final cubit = _buildCubit(player);

      unawaited(cubit.start());
      async.flushMicrotasks();
      expect(cubit.state.conn, TileConn.playing);
      expect(player.subUrls, [_subUrl]);

      unawaited(cubit.suspend());
      async.flushMicrotasks();
      expect(cubit.state.conn, TileConn.suspended);

      unawaited(cubit.resume());
      async.flushMicrotasks();
      expect(cubit.state.conn, TileConn.playing);
      expect(player.openCount, 2);
      expect(player.subUrls, [_subUrl, _subUrl]);
      expect(player.mainUrls, isEmpty);

      _close(async, cubit);
    });
  });

  test('resume on a live tile is a no-op', () {
    fakeAsync((async) {
      final player = FakeTilePlayer();
      final cubit = _buildCubit(player);

      unawaited(cubit.start());
      async.flushMicrotasks();
      expect(cubit.state.conn, TileConn.playing);

      unawaited(cubit.resume());
      async.flushMicrotasks();
      expect(cubit.state.conn, TileConn.playing);
      expect(player.openCount, 1);

      _close(async, cubit);
    });
  });

  test('failed resume surfaces an error and stays retryable', () {
    fakeAsync((async) {
      final player = FakeTilePlayer();
      final cubit = _buildCubit(player);

      unawaited(cubit.start());
      async.flushMicrotasks();
      unawaited(cubit.suspend());
      async.flushMicrotasks();
      expect(cubit.state.conn, TileConn.suspended);

      player.throwOnOpen = true;
      unawaited(cubit.resume());
      async.flushMicrotasks();
      expect(cubit.state.conn, TileConn.error);
      expect(cubit.state.message, isNotNull);
      expect(player.openCount, 2);

      player.throwOnOpen = false;
      unawaited(cubit.retry());
      async.flushMicrotasks();
      expect(cubit.state.conn, TileConn.playing);
      expect(player.openCount, 3);

      _close(async, cubit);
    });
  });

  test('suspend during retry backoff prevents the pending open', () {
    fakeAsync((async) {
      final player = FakeTilePlayer()..autoPlay = false;
      final cubit = _buildCubit(player);

      unawaited(cubit.start());
      async.flushMicrotasks();
      async.elapse(_subTimeout);
      async.flushMicrotasks();
      expect(cubit.state.conn, TileConn.error);

      unawaited(cubit.retry());
      async.flushMicrotasks();
      expect(player.openCount, 2);
      async.elapse(_subTimeout);
      async.flushMicrotasks();
      expect(cubit.state.retryCount, 1);

      unawaited(cubit.retry());
      async.flushMicrotasks();
      expect(cubit.state.conn, TileConn.reconnecting);
      expect(player.openCount, 2);

      unawaited(cubit.suspend());
      async.flushMicrotasks();
      expect(cubit.state.conn, TileConn.suspended);

      // The 2s backoff must not reopen a parked tile.
      async.elapse(const Duration(seconds: 2));
      async.flushMicrotasks();
      expect(player.openCount, 2);
      expect(cubit.state.conn, TileConn.suspended);

      _close(async, cubit);
    });
  });

  test('close while suspended disposes the player', () {
    fakeAsync((async) {
      final player = FakeTilePlayer();
      final cubit = _buildCubit(player);

      unawaited(cubit.start());
      async.flushMicrotasks();
      unawaited(cubit.suspend());
      async.flushMicrotasks();
      expect(cubit.state.conn, TileConn.suspended);

      _close(async, cubit);
      expect(cubit.isClosed, isTrue);
      expect(player.disposed, isTrue);
      expect(player.disposeCount, 1);
      expect(cubit.state.conn, TileConn.suspended);

      async.elapse(const Duration(seconds: 1));
      async.flushMicrotasks();
      expect(player.openCount, 1);
    });
  });
}
