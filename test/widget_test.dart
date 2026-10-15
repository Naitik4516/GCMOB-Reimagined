import 'package:flutter_test/flutter_test.dart';
import 'package:gcmob_reimagined/app/app.dart';
import 'package:gcmob_reimagined/core/rtsp/rtsp_url.dart';
import 'package:gcmob_reimagined/features/live/bloc/grid_cubit.dart';
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

  testWidgets('App boots to profile list', (WidgetTester tester) async {
    await tester.pumpWidget(const CctvApp());
    await tester.pump();
    expect(find.text('CCTV — DVR Profiles'), findsOneWidget);
  });
}
