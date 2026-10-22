import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gcmob_reimagined/features/live/bloc/grid_cubit.dart';
import 'package:gcmob_reimagined/features/live/ui/live_controls.dart';

import 'helpers/test_grid.dart';

Widget _harness(GridCubit grid, Widget child) {
  return BlocProvider.value(
    value: grid,
    child: MaterialApp(
      home: Scaffold(body: Center(child: child)),
    ),
  );
}

void main() {
  testWidgets('4-tile page picks layout 4 and hides the pager', (tester) async {
    final grid = testGrid(gridSize: 4, channelCount: 4);
    addTearDown(grid.close);
    await tester.pumpWidget(_harness(
      grid,
      const LiveControls(showPager: true, showPageLabel: true),
    ));

    final layout = tester.widget<SegmentedButton<int>>(
      find.byType(SegmentedButton<int>),
    );
    expect(layout.selected, {4});
    expect(find.byType(SegmentedButton<bool>), findsNothing);
    expect(find.byTooltip('Previous page'), findsNothing);
    expect(find.byTooltip('Next page'), findsNothing);
    expect(find.text('1/1'), findsNothing);
  });

  testWidgets('1x1 shows SD/HD and HD selects the main stream',
      (tester) async {
    final grid = testGrid(gridSize: 1, channelCount: 4);
    addTearDown(grid.close);
    grid.setSingleHd(false);
    await tester.pumpWidget(_harness(grid, const LiveControls()));

    expect(find.byType(SegmentedButton<bool>), findsOneWidget);
    expect(find.text('SD'), findsOneWidget);
    expect(find.text('HD'), findsOneWidget);
    expect(grid.state.singleHd, isFalse);

    await tester.tap(find.text('HD'));
    await tester.pump();
    expect(grid.state.singleHd, isTrue);
  });

  testWidgets('pager hides chevrons at the ends and shows the page label',
      (tester) async {
    final grid = testGrid(gridSize: 9, channelCount: 16);
    addTearDown(grid.close);
    await tester.pumpWidget(_harness(
      grid,
      const LiveControls(showPager: true, showPageLabel: true),
    ));

    expect(find.byTooltip('Previous page'), findsNothing);
    expect(find.byTooltip('Next page'), findsOneWidget);
    expect(find.text('1/2'), findsOneWidget);

    grid.nextPage();
    await tester.pump();

    expect(find.byTooltip('Previous page'), findsOneWidget);
    expect(find.byTooltip('Next page'), findsNothing);
    expect(find.text('2/2'), findsOneWidget);
  });

  testWidgets('grid exit appears in focus mode and calls onGridExit',
      (tester) async {
    final grid = testGrid(gridSize: 4, channelCount: 4);
    addTearDown(grid.close);
    grid.focusChannel(2);
    var exits = 0;
    await tester.pumpWidget(_harness(
      grid,
      LiveControls(showGridExit: true, onGridExit: () => exits++),
    ));

    expect(grid.state.isFocused, isTrue);
    expect(find.byTooltip('Back to grid'), findsOneWidget);

    await tester.tap(find.byTooltip('Back to grid'));
    expect(exits, 1);
  });

  testWidgets('focused pager labels the focused channel position',
      (tester) async {
    final grid = testGrid(gridSize: 4, channelCount: 8);
    addTearDown(grid.close);
    grid.focusChannel(6);
    await tester.pumpWidget(_harness(
      grid,
      const LiveControls(showPager: true, showPageLabel: true),
    ));

    expect(find.text('6/8'), findsOneWidget);
    expect(find.byTooltip('Previous page'), findsOneWidget);
    expect(find.byTooltip('Next page'), findsOneWidget);

    grid.nextPage();
    await tester.pump();
    expect(find.text('7/8'), findsOneWidget);
    expect(grid.state.page, 0);
  });

  testWidgets('shortcuts button opens the keyboard help dialog',
      (tester) async {
    final grid = testGrid();
    addTearDown(grid.close);
    await tester.pumpWidget(
      _harness(grid, const LiveControls(showShortcuts: true)),
    );

    expect(find.byTooltip('Keyboard shortcuts (F1)'), findsOneWidget);
    await tester.tap(find.byTooltip('Keyboard shortcuts (F1)'));
    await tester.pumpAndSettle();
    expect(find.text('Keyboard shortcuts'), findsOneWidget);
  });

  testWidgets('control row stays overflow-free in a 360px bottom bar',
      (tester) async {
    final grid = testGrid(gridSize: 1, channelCount: 16);
    addTearDown(grid.close);
    await tester.pumpWidget(_harness(
      grid,
      const SizedBox(
        width: 360,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: LiveControls(showPager: true, showPageLabel: true),
        ),
      ),
    ));

    expect(tester.takeException(), isNull);
  });
}
