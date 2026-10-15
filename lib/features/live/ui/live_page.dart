import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/platform/app_fullscreen.dart';
import '../../profiles/data/profile_store.dart';
import '../../profiles/models/dvr_profile.dart';
import '../bloc/grid_cubit.dart';
import 'camera_grid_widget.dart';

/// Live view: grid-size switcher + paging + [CameraGridWidget].
///
/// Reordering needs no mode switch: drag-and-drop on touch, right-click
/// channel picker on desktop, hold-OK grab-and-drop on TV remotes.
class LivePage extends StatelessWidget {
  final DvrProfile profile;
  final String password;

  const LivePage({super.key, required this.profile, required this.password});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => GridCubit(
        store: ProfileStore(),
        profileId: profile.id,
        gridSize: 4,
        channelCount: profile.channelCount,
      )..loadOrder(),
      child: Builder(
        builder: (context) {
          return Scaffold(
            appBar: AppBar(
              title: Text(profile.name),
              actions: [
                BlocBuilder<GridCubit, GridState>(
                  builder: (context, grid) {
                    return Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final size in const [1, 4, 9])
                          IconButton(
                            tooltip: size == 1
                                ? '1x1'
                                : size == 4
                                    ? '2x2'
                                    : '3x3',
                            icon: Icon(
                              size == 1
                                  ? Icons.crop_square
                                  : size == 4
                                      ? Icons.grid_view
                                      : Icons.grid_on,
                              color: grid.gridSize == size
                                  ? Colors.amber
                                  : Colors.white70,
                            ),
                            onPressed: () =>
                                context.read<GridCubit>().setGridSize(size),
                          ),
                        if (grid.pageCount > 1)
                          TextButton(
                            onPressed: grid.page > 0
                                ? () => context.read<GridCubit>().prevPage()
                                : null,
                            child: const Text('Prev'),
                          ),
                        if (grid.pageCount > 1)
                          Text(
                            '${grid.page + 1}/${grid.pageCount}',
                            style: const TextStyle(color: Colors.white70),
                          ),
                        if (grid.pageCount > 1)
                          TextButton(
                            onPressed: grid.page < grid.pageCount - 1
                                ? () => context.read<GridCubit>().nextPage()
                                : null,
                            child: const Text('Next'),
                          ),
                        ValueListenableBuilder<bool>(
                          valueListenable: AppFullscreen.isFullscreen,
                          builder: (_, full, child) => IconButton(
                            tooltip: full
                                ? 'Exit fullscreen (F11)'
                                : 'Fullscreen (F11)',
                            icon: Icon(full
                                ? Icons.fullscreen_exit
                                : Icons.fullscreen),
                            color: Colors.white70,
                            onPressed: () => AppFullscreen.toggle(),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
            body: CameraGridWidget(profile: profile, password: password),
          );
        },
      ),
    );
  }
}
