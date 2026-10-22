import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../bloc/grid_cubit.dart';
import 'shortcuts_help.dart';

/// Shared live-view control row.
///
/// Placements differ only in which optional pieces they show:
/// * desktop title bar — layout, SD/HD (1x1), shortcuts;
/// * phone bottom bar — layout, SD/HD (1x1), paging;
/// * landscape immersive bar — layout, SD/HD (1x1), paging, grid exit.
///
/// It owns the [GridCubit] subscription so callers only decide the layout.
/// The pager is omitted for a single page (no dead `1/1` label), and the
/// grid-exit button only appears while a channel is focused.
class LiveControls extends StatelessWidget {
  /// Desktop-only keyboard-shortcuts button.
  final bool showShortcuts;

  /// Show page chevrons/label when the grid has more than one page.
  final bool showPager;

  /// Include `current/total` next to the chevrons.
  final bool showPageLabel;

  /// Support a grid-exit button; it renders only while a channel is focused.
  final bool showGridExit;

  final VoidCallback? onGridExit;

  /// Compact visual density; every current placement uses it.
  final bool compact;

  /// Explicit icon color for the translucent immersive bar.
  final Color? iconColor;

  const LiveControls({
    super.key,
    this.showShortcuts = false,
    this.showPager = false,
    this.showPageLabel = false,
    this.showGridExit = false,
    this.onGridExit,
    this.compact = true,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<GridCubit, GridState>(
      builder: (context, grid) {
        final cubit = context.read<GridCubit>();
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _LayoutPicker(grid: grid, cubit: cubit, compact: compact),
            if (grid.gridSize == 1) ...[
              const SizedBox(width: 8),
              _QualityPicker(grid: grid, cubit: cubit, compact: compact),
            ],
            if (showPager && grid.pageCount > 1) ...[
              const SizedBox(width: 8),
              _Pager(
                grid: grid,
                cubit: cubit,
                showLabel: showPageLabel,
                iconColor: iconColor,
              ),
            ],
            if (showGridExit && grid.isFocused) ...[
              const SizedBox(width: 4),
              IconButton(
                tooltip: 'Back to grid',
                icon: const Icon(Icons.grid_view),
                color: iconColor,
                onPressed: onGridExit,
              ),
            ],
            if (showShortcuts) ...[
              const SizedBox(width: 4),
              IconButton(
                tooltip: 'Keyboard shortcuts (F1)',
                icon: const Icon(Icons.keyboard_outlined, size: 20),
                color: iconColor,
                onPressed: () => showShortcutsHelp(context),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _LayoutPicker extends StatelessWidget {
  final GridState grid;
  final GridCubit cubit;
  final bool compact;

  const _LayoutPicker({
    required this.grid,
    required this.cubit,
    required this.compact,
  });

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<int>(
      segments: const [
        ButtonSegment(
          value: 1,
          icon: Icon(Icons.crop_square, size: 16),
          tooltip: '1x1 (HD)',
        ),
        ButtonSegment(
          value: 4,
          icon: Icon(Icons.grid_view, size: 16),
          tooltip: '2x2',
        ),
        ButtonSegment(
          value: 9,
          icon: Icon(Icons.grid_on, size: 16),
          tooltip: '3x3',
        ),
      ],
      selected: {grid.gridSize},
      showSelectedIcon: false,
      style: SegmentedButton.styleFrom(
        visualDensity:
            compact ? VisualDensity.compact : VisualDensity.standard,
      ),
      onSelectionChanged: (s) => cubit.setGridSize(s.first),
    );
  }
}

class _QualityPicker extends StatelessWidget {
  final GridState grid;
  final GridCubit cubit;
  final bool compact;

  const _QualityPicker({
    required this.grid,
    required this.cubit,
    required this.compact,
  });

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<bool>(
      segments: const [
        ButtonSegment(
          value: false,
          label: Text('SD'),
          tooltip: 'Sub-stream',
        ),
        ButtonSegment(
          value: true,
          label: Text('HD'),
          tooltip: 'Main-stream',
        ),
      ],
      selected: {grid.singleHd},
      showSelectedIcon: false,
      style: SegmentedButton.styleFrom(
        visualDensity:
            compact ? VisualDensity.compact : VisualDensity.standard,
      ),
      onSelectionChanged: (s) => cubit.setSingleHd(s.first),
    );
  }
}

class _Pager extends StatelessWidget {
  final GridState grid;
  final GridCubit cubit;
  final bool showLabel;
  final Color? iconColor;

  const _Pager({
    required this.grid,
    required this.cubit,
    required this.showLabel,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    final page = grid.displayPage;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (page > 0)
          IconButton(
            tooltip: 'Previous page',
            icon: const Icon(Icons.chevron_left),
            color: iconColor,
            onPressed: () => cubit.prevPage(),
          ),
        if (showLabel)
          Text(
            '${page + 1}/${grid.pageCount}',
            style: const TextStyle(color: Colors.white70),
          ),
        if (page < grid.pageCount - 1)
          IconButton(
            tooltip: 'Next page',
            icon: const Icon(Icons.chevron_right),
            color: iconColor,
            onPressed: () => cubit.nextPage(),
          ),
      ],
    );
  }
}
