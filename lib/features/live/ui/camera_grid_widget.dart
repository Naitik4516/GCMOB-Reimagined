import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../app/theme.dart';
import '../../../core/platform/is_tv.dart';
import '../../profiles/models/dvr_profile.dart';
import '../bloc/grid_cubit.dart';
import '../bloc/tile_cubit.dart';
import '../player/media_kit_rtsp_controller.dart';
import 'camera_tile_widget.dart';

/// Maps a tile [Key] back to its slot index in [channels], so
/// [GridView.findChildIndexCallback] can MOVE tiles instead of recreating
/// them when sink/reorder reshuffles the order. Without this, every
/// reshuffle disposes shifted tiles and their working streams reconnect —
/// one failure avalanches across the whole grid.
///
/// Keys look like `tile_<profileId>_<channel>_hd|sd`; the profile id may
/// itself contain underscores, so the channel is parsed from the end.
int? findTileIndex(Key key, List<int> channels) {
  final value = key is ValueKey<String> ? key.value : null;
  if (value == null) return null;
  var s = value;
  if (s.endsWith('_hd') || s.endsWith('_sd')) {
    s = s.substring(0, s.length - 3);
  } else {
    return null;
  }
  final channel = int.tryParse(s.split('_').last);
  if (channel == null) return null;
  final idx = channels.indexOf(channel);
  return idx >= 0 ? idx : null;
}

/// Adaptive grid (1x1 / 2x2 / 3x3) with TV D-Pad focus traversal.
///
/// * Never scrolls: tile aspect ratio is derived from the viewport so the
///   whole page fits on screen (fixes landscape/desktop overflow).
/// * Creates one [TileCubit] per visible channel; disposes off-page players.
/// * Double-click / OK opens the channel alone (1x1, HD) via
///   [GridCubit.focusChannel]; a second double-click / Back exits.
/// * 1x1 tiles play the HD main-stream ([GridCubit.singleHd] toggles SD).
/// * Zoom works on every tile; a zoomed tile pans instead of reorder-drag.
/// * [immersive] (phone landscape): page flings + long-press reorder, no
///   immediate drag (it would eat the fling).
/// * Failed tiles sink behind working ones via [GridCubit.markFailed].
/// * Reorder (persists per profile): drag-and-drop, desktop right-click
///   channel picker, TV hold-OK to grab + OK to drop.
class CameraGridWidget extends StatefulWidget {
  final DvrProfile profile;
  final String password;
  final bool immersive;

  const CameraGridWidget({
    super.key,
    required this.profile,
    required this.password,
    this.immersive = false,
  });

  @override
  State<CameraGridWidget> createState() => _CameraGridWidgetState();
}

class _CameraGridWidgetState extends State<CameraGridWidget> {
  /// Focus nodes keyed by channel (not slot) so focus follows a channel
  /// across sink/reorder reshuffles instead of jumping to a new tile.
  final Map<int, FocusNode> _nodes = {};
  int? _grabbed;

  /// Channels currently zoomed past 1x. Their drag gesture pans the
  /// picture, so the reorder wrapper is skipped for them.
  final Set<int> _zoomed = {};

  void _onZoomChanged(int channel, bool zoomed) {
    if (zoomed == _zoomed.contains(channel)) return;
    setState(() {
      if (zoomed) {
        _zoomed.add(channel);
      } else {
        _zoomed.remove(channel);
      }
    });
  }

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
    if (grabbed != null) {
      _buzz(HapticFeedback.selectionClick());
      setState(() => _grabbed = null);
      if (grabbed != channel) {
        tileContext.read<GridCubit>().swapChannels(grabbed, channel);
      }
      return;
    }
    final grid = tileContext.read<GridCubit>();
    if (grid.state.spotlight) {
      grid.unfocus();
    } else {
      grid.focusChannel(channel);
    }
  }

  /// Esc key: cancel a grab first, otherwise leave the single view.
  void _onEscape(BuildContext tileContext) {
    if (_grabbed != null) {
      setState(() => _grabbed = null);
      return;
    }
    tileContext.read<GridCubit>().unfocus();
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

  @override
  Widget build(BuildContext context) {
    // Rebuild only the pop guard when spotlight toggles; tiles rebuild
    // via the inner BlocBuilder.
    final spotlight =
        context.select<GridCubit, bool>((c) => c.state.spotlight);
    return BlocListener<GridCubit, GridState>(
      listenWhen: (prev, next) =>
          prev.page != next.page ||
          prev.gridSize != next.gridSize ||
          prev.spotlight != next.spotlight,
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
        canPop: _grabbed == null && !spotlight,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) return;
          // System Back cancels a grab first, then leaves single view.
          if (_grabbed != null) {
            setState(() => _grabbed = null);
          } else {
            context.read<GridCubit>().unfocus();
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
                  // Roomier padding/gaps past phone widths (desktop, TV,
                  // tablets); phones stay compact. Subtract GridView
                  // padding + inter-tile gaps or the last row/column clips
                  // on wide desktop windows.
                  final roomy = isDesktopDevice ||
                      (constraints.hasBoundedWidth &&
                          constraints.maxWidth >= 700);
                  final pad = roomy ? 20.0 : 8.0;
                  final gap = roomy ? 14.0 : 8.0;
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
                  Widget view = GridView.builder(
                    // findChildIndexCallback is load-bearing: without it a
                    // sink/reorder reshuffle recreates every shifted tile
                    // (and reconnects its working stream). With it, tiles
                    // move slots with their players intact.
                    findChildIndexCallback: (key) =>
                        findTileIndex(key, channels),
                    physics: const NeverScrollableScrollPhysics(),
                    padding: EdgeInsets.all(pad),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: cross,
                      crossAxisSpacing: gap,
                      mainAxisSpacing: gap,
                      childAspectRatio: aspect,
                    ),
                    itemCount: channels.length,
                    itemBuilder: (context, i) {
                      final ch = channels[i];
                      // 1x1 tiles play HD (audio on); grids stay on SD.
                      // The quality flag is part of the key so toggling
                      // SD/HD remounts the tile and reopens the stream.
                      final hd = grid.gridSize == 1 && grid.singleHd;
                      return BlocProvider(
                        key: ValueKey(
                            'tile_${widget.profile.id}_${ch}_${hd ? 'hd' : 'sd'}'),
                        create: (tileContext) => TileCubit(
                          profile: widget.profile,
                          password: widget.password,
                          channel: ch,
                          controller: MediaKitRTSPController(),
                          highRes: hd,
                          startMuted: !hd,
                          // Slot stagger: weak SoCs cannot bring up 9
                          // decoders in the same instant (see TileCubit).
                          startDelay:
                              Duration(milliseconds: 250 * i),
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
                                  highRes: hd,
                                  zoomable: true,
                                  showFocus: grid.gridSize != 1,
                                  grabbed: _grabbed == ch,
                                  dropCandidate: dropCandidate,
                                  onSelect: () => _onTileTap(tileContext, ch),
                                  onGrab: () => _onGrab(ch),
                                  onEscape: () =>
                                      _onEscape(tileContext),
                                  onZoomChanged: (z) =>
                                      _onZoomChanged(ch, z),
                                  onPickChannel: (at) =>
                                      _pickChannel(tileContext, ch, at),
                                );
                            Widget buildFeedback() => MouseRegion(
                                  cursor: SystemMouseCursors.grabbing,
                                  child: Material(
                                    elevation: 6,
                                    borderRadius: BorderRadius.circular(
                                        CctvTheme.tileRadius),
                                    color: CctvTheme.surfaceHigh
                                        .withValues(alpha: 0.95),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 24, vertical: 16),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(
                                              Icons.open_with,
                                              color: Colors.lightBlueAccent,
                                              size: 18),
                                          const SizedBox(width: 8),
                                          Text(
                                            'CH $ch',
                                            style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 18,
                                                fontWeight:
                                                    FontWeight.w600),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                            Widget buildPlaceholder() => Opacity(
                                  opacity: 0.35,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      border: Border.all(
                                          color: Colors.white24),
                                      borderRadius: BorderRadius.circular(
                                          CctvTheme.tileRadius),
                                    ),
                                    child: Center(
                                      child: Text(
                                        'CH $ch',
                                        style: const TextStyle(
                                            color: Colors.white38),
                                      ),
                                    ),
                                  ),
                                );
                            Widget withTarget() => DragTarget<int>(
                                  onWillAcceptWithDetails: (d) =>
                                      d.data != ch,
                                  onAcceptWithDetails: (d) =>
                                      _onSwap(tileContext, d.data, ch),
                                  builder: (_, candidate, _) => buildTile(
                                      dropCandidate:
                                          candidate.isNotEmpty),
                                );
                            // Zoomed tiles pan instead of reorder-drag: a
                            // drag gesture cannot do both.
                            if (_zoomed.contains(ch)) return withTarget();
                            // Immersive pages turn on fling, so reorder
                            // waits for a long-press there — an immediate
                            // drag would eat the fling and swap by accident.
                            if (widget.immersive) {
                              return LongPressDraggable<int>(
                                data: ch,
                                maxSimultaneousDrags: 1,
                                feedback: buildFeedback(),
                                childWhenDragging: buildPlaceholder(),
                                onDragStarted: () =>
                                    _buzz(HapticFeedback.lightImpact()),
                                child: withTarget(),
                              );
                            }
                            // Immediate (slop-based) drag: a click-drag swaps
                            // without the 500ms hold a LongPressDraggable
                            // needs, which reads as "broken" with a mouse.
                            // Plain clicks still land on the tile's onTap.
                            return Draggable<int>(
                              data: ch,
                              maxSimultaneousDrags: 1,
                              feedback: buildFeedback(),
                              childWhenDragging: buildPlaceholder(),
                              onDragStarted: () =>
                                  _buzz(HapticFeedback.lightImpact()),
                              child: withTarget(),
                            );
                          },
                        ),
                      );
                    },
                  );
                  if (widget.immersive) {
                    // Fling horizontally to turn pages. Reorder still works
                    // via long-press (see above); a quick fling never holds
                    // long enough to start a drag, so pages never swap.
                    view = GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onHorizontalDragEnd: (d) {
                        final v = d.primaryVelocity ?? 0;
                        final cubit = context.read<GridCubit>();
                        if (v > 400) {
                          cubit.prevPage();
                        } else if (v < -400) {
                          cubit.nextPage();
                        }
                      },
                      child: view,
                    );
                  }
                  return view;
                },
              ),
            );
          },
        ),
      ),
    );
  }
}
