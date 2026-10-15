import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../profiles/models/dvr_profile.dart';
import '../bloc/grid_cubit.dart';
import '../bloc/tile_cubit.dart';
import '../player/media_kit_rtsp_controller.dart';
import 'camera_tile_widget.dart';
import 'fullscreen_page.dart';

/// Adaptive grid (1x1 / 2x2 / 3x3) with TV D-Pad focus traversal.
///
/// * Never scrolls: tile aspect ratio is derived from the viewport so the
///   whole page fits on screen (fixes landscape/desktop overflow).
/// * Creates one [TileCubit] per visible channel; disposes off-page players.
/// * Failed tiles sink behind working ones via [GridCubit.markFailed].
/// * Reorder (persists per profile): touch long-press drag-and-drop,
///   desktop right-click channel picker, TV hold-OK to grab + OK to drop.
class CameraGridWidget extends StatefulWidget {
  final DvrProfile profile;
  final String password;

  const CameraGridWidget({
    super.key,
    required this.profile,
    required this.password,
  });

  @override
  State<CameraGridWidget> createState() => _CameraGridWidgetState();
}

class _CameraGridWidgetState extends State<CameraGridWidget> {
  /// Focus nodes keyed by channel (not slot) so focus follows a channel
  /// across sink/reorder reshuffles instead of jumping to a new tile.
  final Map<int, FocusNode> _nodes = {};
  int? _grabbed;

  /// Haptics are best-effort: desktops have no vibrator and the platform
  /// channel throws there. Never let that break taps, grabs, or drops.
  static void _buzz(Future<void> call) =>
      unawaited(call.then<void>((_) {}, onError: (_) {}));

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final visible = context.read<GridCubit>().state.visibleChannels;
      if (visible.isNotEmpty) {
        _syncNodes(visible);
        _nodes[visible.first]?.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    for (final n in _nodes.values) {
      n.dispose();
    }
    _nodes.clear();
    super.dispose();
  }

  void _syncNodes(Iterable<int> channels) {
    for (final c in channels) {
      _nodes.putIfAbsent(c, () => FocusNode());
    }
  }

  void _onTileTap(BuildContext tileContext, int channel) {
    final grabbed = _grabbed;
    if (grabbed == null) {
      _openFullscreen(tileContext, channel);
      return;
    }
    _buzz(HapticFeedback.selectionClick());
    setState(() => _grabbed = null);
    if (grabbed != channel) {
      tileContext.read<GridCubit>().swapChannels(grabbed, channel);
    }
  }

  void _onGrab(int channel) {
    _buzz(HapticFeedback.selectionClick());
    setState(() => _grabbed = _grabbed == channel ? null : channel);
  }

  void _onSwap(BuildContext tileContext, int from, int to) {
    if (from == to) return;
    _buzz(HapticFeedback.mediumImpact());
    tileContext.read<GridCubit>().swapChannels(from, to);
  }

  Future<void> _pickChannel(
      BuildContext tileContext, int current, Offset at) async {
    final grid = tileContext.read<GridCubit>();
    final eff = grid.state.effectiveOrder;
    final choice = await showMenu<int>(
      context: tileContext,
      position: RelativeRect.fromLTRB(at.dx, at.dy, at.dx + 1, at.dy + 1),
      items: [
        for (final c in eff)
          if (c != current)
            PopupMenuItem(
              value: c,
              child: Text('CH $c  ·  slot ${eff.indexOf(c) + 1}'),
            ),
      ],
    );
    if (choice != null && mounted) {
      _buzz(HapticFeedback.selectionClick());
      grid.swapChannels(current, choice);
    }
  }

  void _openFullscreen(BuildContext tileContext, int channel) {
    Navigator.of(tileContext).push(
      MaterialPageRoute(
        builder: (_) => FullscreenPage(
          profile: widget.profile,
          password: widget.password,
          channel: channel,
          tileCubit: tileContext.read<TileCubit>(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<GridCubit, GridState>(
      listenWhen: (prev, next) =>
          prev.page != next.page || prev.gridSize != next.gridSize,
      listener: (listenerContext, _) {
        // A new page has no focused tile yet; land on its first tile so
        // D-Pad navigation keeps working without touching the screen.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          final visible =
              listenerContext.read<GridCubit>().state.visibleChannels;
          if (visible.isNotEmpty) {
            _syncNodes(visible);
            _nodes[visible.first]?.requestFocus();
          }
        });
      },
      child: PopScope(
        canPop: _grabbed == null,
        onPopInvokedWithResult: (didPop, _) {
          // System Back cancels a grab instead of leaving the grid.
          if (!didPop && _grabbed != null) {
            setState(() => _grabbed = null);
          }
        },
        child: BlocBuilder<GridCubit, GridState>(
          builder: (context, grid) {
            final channels = grid.visibleChannels;
            _syncNodes(channels);
            if (_grabbed != null && !channels.contains(_grabbed)) {
              _grabbed = null;
            }
            final cross = grid.crossAxisCount;
            final rows = grid.rowCount;
            return FocusTraversalGroup(
              policy: OrderedTraversalPolicy(),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  // Fit the whole page in the viewport: no scrolling.
                  // Subtract GridView padding + inter-tile gaps or the last
                  // row/column clips on wide desktop windows.
                  const pad = 8.0;
                  const gap = 8.0;
                  double aspect = 16 / 9;
                  if (constraints.hasBoundedWidth &&
                      constraints.hasBoundedHeight &&
                      constraints.maxWidth > 0 &&
                      constraints.maxHeight > 0) {
                    final tileW =
                        (constraints.maxWidth - pad * 2 - gap * (cross - 1)) /
                            cross;
                    final tileH =
                        (constraints.maxHeight - pad * 2 - gap * (rows - 1)) /
                            rows;
                    if (tileW > 0 && tileH > 0) aspect = tileW / tileH;
                  }
                  return GridView.builder(
                    physics: const NeverScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(8),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: cross,
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 8,
                      childAspectRatio: aspect,
                    ),
                    itemCount: channels.length,
                    itemBuilder: (context, i) {
                      final ch = channels[i];
                      return BlocProvider(
                        key: ValueKey('tile_${widget.profile.id}_$ch'),
                        create: (tileContext) => TileCubit(
                          profile: widget.profile,
                          password: widget.password,
                          channel: ch,
                          controller: MediaKitRTSPController(),
                          onFailed: (c) =>
                              tileContext.read<GridCubit>().markFailed(c),
                          onRecovered: (c) =>
                              tileContext.read<GridCubit>().markRecovered(c),
                        )..start(),
                        child: Builder(
                          builder: (tileContext) {
                            final cubit = tileContext.read<TileCubit>();
                            Widget buildTile({required bool dropCandidate}) =>
                                CameraTileWidget(
                                  focusNode: _nodes[ch]!,
                                  videoController:
                                      cubit.controller.videoController,
                                  label: 'CH $ch',
                                  grabbed: _grabbed == ch,
                                  dropCandidate: dropCandidate,
                                  onSelect: () => _onTileTap(tileContext, ch),
                                  onGrab: () => _onGrab(ch),
                                  onPickChannel: (at) =>
                                      _pickChannel(tileContext, ch, at),
                                );
                            // Immediate (slop-based) drag: a click-drag swaps
                            // without the 500ms hold a LongPressDraggable
                            // needs, which reads as "broken" with a mouse.
                            // Plain clicks still land on the tile's onTap.
                            return Draggable<int>(
                              data: ch,
                              maxSimultaneousDrags: 1,
                              feedback: MouseRegion(
                                cursor: SystemMouseCursors.grabbing,
                                child: Material(
                                  elevation: 6,
                                  borderRadius: BorderRadius.circular(8),
                                  color: Colors.black87,
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 24, vertical: 16),
                                    child: Text(
                                      'CH $ch',
                                      style: const TextStyle(
                                          color: Colors.white, fontSize: 18),
                                    ),
                                  ),
                                ),
                              ),
                              childWhenDragging: Opacity(
                                opacity: 0.35,
                                child: Container(
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                        color: Colors.white24),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Center(
                                    child: Text(
                                      'CH $ch',
                                      style: const TextStyle(
                                          color: Colors.white38),
                                    ),
                                  ),
                                ),
                              ),
                              onDragStarted: () =>
                                  _buzz(HapticFeedback.lightImpact()),
                              child: DragTarget<int>(
                                onWillAcceptWithDetails: (d) =>
                                    d.data != ch,
                                onAcceptWithDetails: (d) =>
                                    _onSwap(tileContext, d.data, ch),
                                builder: (_, candidate, _) => buildTile(
                                    dropCandidate: candidate.isNotEmpty),
                              ),
                            );
                          },
                        ),
                      );
                    },
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }
}
