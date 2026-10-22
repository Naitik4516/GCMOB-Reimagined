import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gcmob_reimagined/features/live/bloc/grid_cubit.dart';
import 'package:gcmob_reimagined/features/profiles/data/profile_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/fake_grid_store.dart';
import 'helpers/test_grid.dart';

void main() {
  test('GridCubit pages 16 channels across 3x3 tiles', () {
    final grid = testGrid();
    expect(grid.state.visibleChannels, [1, 2, 3, 4, 5, 6, 7, 8, 9]);
    expect(grid.state.pageCount, 2);
    expect(grid.state.displayPage, 0);
    grid.nextPage();
    expect(grid.state.visibleChannels, [10, 11, 12, 13, 14, 15, 16]);
    expect(grid.state.displayPage, 1);
  });

  test('paging stops at a partial final page', () {
    final grid = testGrid(gridSize: 9, channelCount: 10);
    expect(grid.state.pageCount, 2);
    expect(grid.state.visibleChannels, [1, 2, 3, 4, 5, 6, 7, 8, 9]);

    grid.nextPage();
    expect(grid.state.page, 1);
    expect(grid.state.visibleChannels, [10]);
    expect(grid.state.rowCount, 1);

    grid.nextPage(); // no page past the last one
    expect(grid.state.page, 1);
    expect(grid.state.visibleChannels, [10]);

    grid.prevPage();
    expect(grid.state.page, 0);
    grid.prevPage(); // no page before the first one
    expect(grid.state.page, 0);
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

  test('swapChannels keeps the new order when persistence fails', () async {
    final grid = GridCubit(
      store: ProfileStore(),
      profileId: 'test',
      gridSize: 4,
      channelCount: 4,
      saveOrder: (_) async => throw StateError('read-only store'),
    );
    addTearDown(grid.close);

    await grid.swapChannels(1, 4);

    expect(grid.state.order, [4, 2, 3, 1]);
    expect(grid.state.visibleChannels, [4, 2, 3, 1]);
  });

  test('restore does not clobber a reorder that lands mid-read', () async {
    final store = FakeGridStore(order: const [2, 1, 3, 4])
      ..orderGate = Completer<void>();
    final grid = GridCubit(
      store: store,
      profileId: 'test',
      gridSize: 4,
      channelCount: 4,
    );
    addTearDown(grid.close);

    final restoring = grid.restore();
    await Future<void>.delayed(Duration.zero);
    await grid.swapChannels(1, 4);
    expect(grid.state.order, [4, 2, 3, 1]);

    store.orderGate!.complete();
    await restoring;

    expect(grid.state.order, [4, 2, 3, 1]);
    expect(store.savedOrder, [4, 2, 3, 1]);
  });

  test('restore does not clobber a layout picked mid-read', () async {
    final store = FakeGridStore(size: 9)..sizeGate = Completer<void>();
    final grid = GridCubit(
      store: store,
      profileId: 'test',
      gridSize: 4,
      channelCount: 4,
    );
    addTearDown(grid.close);

    final restoring = grid.restore();
    await Future<void>.delayed(Duration.zero);
    grid.setGridSize(1);
    expect(grid.state.layoutSize, 1);

    store.sizeGate!.complete();
    await restoring;
    await Future<void>.delayed(Duration.zero);

    expect(grid.state.layoutSize, 1);
    expect(store.savedSize, 1);
  });

  test('restores persisted order + layout across restarts', () async {
    SharedPreferences.setMockInitialValues({
      'ch_order_test': jsonEncode([4, 1, 3, 2]),
      'grid_size': 9,
    });
    final grid = testGrid(gridSize: 4, channelCount: 4);
    await grid.restore();
    expect(grid.state.order, [4, 1, 3, 2]);
    expect(grid.state.visibleChannels, [4, 1, 3, 2]);
    expect(grid.state.layoutSize, 9);
    expect(grid.state.gridSize, 9);
  });

  test('invalid persisted order is ignored', () async {
    SharedPreferences.setMockInitialValues({
      'ch_order_test': jsonEncode([9, 9, 9, 9]),
    });
    final grid = testGrid(gridSize: 4, channelCount: 4);
    await grid.restore();
    expect(grid.state.order, [1, 2, 3, 4]);
  });

  test('rowCount fits partial pages without scrolling', () {
    final grid = testGrid(gridSize: 9, channelCount: 16);
    expect(grid.state.rowCount, 3);
    grid.nextPage();
    expect(grid.state.visibleChannels.length, 7);
    expect(grid.state.rowCount, 3);
  });

  test('focusChannel keeps layout + page and unfocus restores them', () {
    final grid = testGrid(gridSize: 4, channelCount: 8);
    grid.nextPage(); // page 1: channels 5-8
    grid.focusChannel(6);
    expect(grid.state.isFocused, isTrue);
    expect(grid.state.focusedChannel, 6);
    expect(grid.state.layoutSize, 4);
    expect(grid.state.page, 1);
    expect(grid.state.gridSize, 1);
    expect(grid.state.pageCount, 8);
    expect(grid.state.visibleChannels, [6]);
    expect(grid.state.displayPage, 5);

    grid.unfocus();
    expect(grid.state.isFocused, isFalse);
    expect(grid.state.focusedChannel, isNull);
    expect(grid.state.gridSize, 4);
    expect(grid.state.page, 1);
    expect(grid.state.visibleChannels, [5, 6, 7, 8]);
  });

  test('focus from manual 1x1 returns to the same channel', () {
    final grid = testGrid(gridSize: 1, channelCount: 8);
    for (var i = 0; i < 4; i++) {
      grid.nextPage();
    }
    expect(grid.state.page, 4);
    expect(grid.state.visibleChannels, [5]);

    grid.focusChannel(5);
    expect(grid.state.focusedChannel, 5);
    expect(grid.state.layoutSize, 1);
    expect(grid.state.page, 4);

    grid.unfocus();
    expect(grid.state.page, 4);
    expect(grid.state.visibleChannels, [5]);
    expect(grid.state.gridSize, 1);
  });

  test('focused paging surfs channels without moving the grid page', () {
    final grid = testGrid(gridSize: 4, channelCount: 8);
    grid.nextPage(); // page 1
    grid.focusChannel(6);
    expect(grid.state.page, 1);
    expect(grid.state.displayPage, 5);

    grid.nextPage();
    expect(grid.state.focusedChannel, 7);
    expect(grid.state.page, 1);
    expect(grid.state.displayPage, 6);
    expect(grid.state.visibleChannels, [7]);

    grid.nextPage();
    expect(grid.state.focusedChannel, 8);
    grid.nextPage(); // no wrap past the end
    expect(grid.state.focusedChannel, 8);
    expect(grid.state.displayPage, 7);

    grid.prevPage();
    expect(grid.state.focusedChannel, 7);

    grid.focusChannel(1);
    grid.prevPage(); // no wrap before the start
    expect(grid.state.focusedChannel, 1);
    expect(grid.state.displayPage, 0);
    expect(grid.state.page, 1);
  });

  test('swapChannels keeps the focused channel focused', () async {
    final saved = <List<int>>[];
    final grid = testGrid(
      gridSize: 4,
      channelCount: 8,
      saved: saved,
    );
    grid.focusChannel(6);
    await grid.swapChannels(6, 2);

    expect(grid.state.focusedChannel, 6);
    expect(grid.state.isFocused, isTrue);
    expect(grid.state.order, [1, 6, 3, 4, 5, 2, 7, 8]);
    expect(grid.state.visibleChannels, [6]);
    expect(grid.state.displayPage, 1);
    expect(saved, [
      [1, 6, 3, 4, 5, 2, 7, 8]
    ]);
  });

  test('restore keeps an existing focus', () async {
    SharedPreferences.setMockInitialValues({
      'ch_order_test': jsonEncode([8, 7, 6, 5, 4, 3, 2, 1]),
      'grid_size': 9,
    });
    final grid = testGrid(gridSize: 4, channelCount: 8);
    grid.focusChannel(6);
    await grid.restore();

    expect(grid.state.focusedChannel, 6);
    expect(grid.state.isFocused, isTrue);
    expect(grid.state.layoutSize, 9);
    expect(grid.state.page, 0);
    expect(grid.state.visibleChannels, [6]);
  });

  test('setGridSize exits focus and resets the page', () {
    final grid = testGrid(gridSize: 4, channelCount: 8);
    grid.nextPage(); // page 1
    grid.focusChannel(6);
    grid.setGridSize(9);

    expect(grid.state.isFocused, isFalse);
    expect(grid.state.focusedChannel, isNull);
    expect(grid.state.layoutSize, 9);
    expect(grid.state.page, 0);
    expect(grid.state.gridSize, 9);
  });

  test('singleHd defaults on and toggles', () {
    final grid = testGrid();
    expect(grid.state.singleHd, isTrue);
    grid.setSingleHd(false);
    expect(grid.state.singleHd, isFalse);
  });
}
