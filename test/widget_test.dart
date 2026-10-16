import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gcmob_reimagined/app/app.dart';
import 'package:gcmob_reimagined/core/rtsp/mpv_errors.dart';
import 'package:gcmob_reimagined/core/rtsp/rtsp_concurrency.dart';
import 'package:gcmob_reimagined/core/rtsp/rtsp_url.dart';
import 'package:gcmob_reimagined/features/live/bloc/grid_cubit.dart';
import 'package:gcmob_reimagined/features/live/ui/camera_grid_widget.dart'
    show findTileIndex;
import 'package:gcmob_reimagined/features/profiles/data/profile_store.dart';

GridCubit testGrid({
  int gridSize = 9,
  int channelCount = 16,
  List<int>? order,
  List<List<int>>? saved,
}) {
  return GridCubit(
    store: ProfileStore(),
    profileId: 'test',
    gridSize: gridSize,
    channelCount: channelCount,
    order: order,
    saveOrder: (o) async => saved?.add(o),
  );
}

void main() {
  test('Dahua RTSP URL builder uses 0-indexed channel + subtype flag', () {
    expect(
      buildDahuaRtsp(
        user: 'admin',
        pass: 'p@ss:word',
        host: '192.168.1.240',
        port: 554,
        channelOneBased: 1,
        highRes: false,
      ),
      'rtsp://admin:p%40ss%3Aword@192.168.1.240:554/cam/realmonitor?channel=0&subtype=1',
    );
    expect(
      buildDahuaRtsp(
        user: 'admin',
        pass: 'secret',
        host: '192.168.1.240',
        port: 554,
        channelOneBased: 4,
        highRes: true,
      ),
      'rtsp://admin:secret@192.168.1.240:554/cam/realmonitor?channel=3&subtype=0',
    );
  });

  test('GridCubit pages 16 channels across 3x3 tiles', () {
    final grid = testGrid();
    expect(grid.state.visibleChannels, [1, 2, 3, 4, 5, 6, 7, 8, 9]);
    expect(grid.state.pageCount, 2);
    grid.nextPage();
    expect(grid.state.visibleChannels, [10, 11, 12, 13, 14, 15, 16]);
  });

  test('swapChannels reorders and persists', () async {
    final saved = <List<int>>[];
    final grid = testGrid(gridSize: 4, channelCount: 4, saved: saved);
    await grid.swapChannels(1, 4);
    expect(grid.state.order, [4, 2, 3, 1]);
    expect(grid.state.visibleChannels, [4, 2, 3, 1]);
    expect(saved, [
      [4, 2, 3, 1]
    ]);
  });

  test('markFailed sinks tile behind working tiles, markRecovered lifts it',
      () {
    final grid = testGrid(gridSize: 4, channelCount: 4);
    grid.markFailed(2);
    grid.markFailed(1);
    expect(grid.state.visibleChannels, [3, 4, 2, 1]);
    grid.markRecovered(2);
    expect(grid.state.visibleChannels, [2, 3, 4, 1]);
  });

  test('rowCount fits partial pages without scrolling', () {
    final grid = testGrid(gridSize: 9, channelCount: 16);
    expect(grid.state.rowCount, 3);
    grid.nextPage();
    expect(grid.state.visibleChannels.length, 7);
    expect(grid.state.rowCount, 3);
  });

  test('focusChannel spotlights tile and unfocus restores layout', () {
    final grid = testGrid(gridSize: 4, channelCount: 8);
    grid.nextPage(); // page 1: channels 5-8
    grid.focusChannel(6);
    expect(grid.state.spotlight, isTrue);
    expect(grid.state.gridSize, 1);
    expect(grid.state.visibleChannels, [6]);
    grid.unfocus();
    expect(grid.state.spotlight, isFalse);
    expect(grid.state.gridSize, 4);
    expect(grid.state.page, 1);
    expect(grid.state.visibleChannels, [5, 6, 7, 8]);
  });

  test('setGridSize leaves spotlight mode', () {
    final grid = testGrid(gridSize: 4, channelCount: 8);
    grid.focusChannel(3);
    expect(grid.state.spotlight, isTrue);
    grid.setGridSize(9);
    expect(grid.state.spotlight, isFalse);
    expect(grid.state.gridSize, 9);
  });

  test('singleHd defaults on and toggles', () {
    final grid = testGrid();
    expect(grid.state.singleHd, isTrue);
    grid.setSingleHd(false);
    expect(grid.state.singleHd, isFalse);
  });

  test('isBenignLiveError filters seek notes only', () {
    expect(isBenignLiveError('Cannot seek in this stream'), isTrue);
    expect(isBenignLiveError('seek failed'), isTrue);
    // The standalone hint line carries no "cannot seek" wording.
    expect(
        isBenignLiveError(
            "You can force it with '--force-seekable=yes'."),
        isTrue);
    expect(isBenignLiveError('tcp: connection reset by peer'), isFalse);
    expect(isBenignLiveError(''), isFalse);
    expect(isBenignLiveError('Stream dropped'), isFalse);
  });

  test('findTileIndex maps keys to slots, unknown to null', () {
    const channels = [1, 3, 4, 2];
    expect(findTileIndex(const ValueKey('tile_abc_1_hd'), channels), 0);
    expect(findTileIndex(const ValueKey('tile_abc_3_sd'), channels), 1);
    expect(findTileIndex(const ValueKey('tile_abc_2_hd'), channels), 3);
    // Underscored profile ids + missing channels.
    expect(
        findTileIndex(const ValueKey('tile_my_home_dvr_4_sd'), [4]), 0);
    expect(findTileIndex(const ValueKey('tile_abc_9_hd'), channels), isNull);
    expect(findTileIndex(const ValueKey('nope'), channels), isNull);
  });

  test('RtspOpener caps concurrency and admits FIFO', () async {
    final admitted = <int>[];
    var active = 0;
    var maxActive = 0;
    final gates = List.generate(5, (_) => Completer<void>());
    Future<void> task(int i) => RtspOpener.run(() async {
          active++;
          if (active > maxActive) maxActive = active;
          admitted.add(i);
          await gates[i].future;
          active--;
        });

    final futures = [for (var i = 0; i < 5; i++) task(i)];
    // run() bodies execute synchronously to the first await: the first
    // three tasks must already hold the three slots, in call order.
    expect(admitted, [0, 1, 2]);
    for (final g in gates) {
      g.complete();
      // Let completions + queued admissions flush through the event loop.
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    await Future.wait(futures);
    expect(admitted, [0, 1, 2, 3, 4]);
    expect(maxActive, lessThanOrEqualTo(RtspOpener.maxConcurrent));
    expect(RtspOpener.isQuiescent, isTrue);
  });

  testWidgets('App boots to profile list', (WidgetTester tester) async {
    await tester.pumpWidget(const CctvApp());
    await tester.pump();
    expect(find.text('DVR Profiles'), findsOneWidget);
  });
}
