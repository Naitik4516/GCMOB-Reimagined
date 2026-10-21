import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../../app/theme.dart';
import '../bloc/grid_cubit.dart';
import '../bloc/tile_cubit.dart';
import 'shortcuts_help.dart';

/// Single CCTV tile: video + connection overlay + D-Pad focus glow.
///
/// * Double-click / double-tap, or quick OK press → [onSelect] (opens or
///   closes the single-camera 1x1 view). Single click only focuses.
/// * 1x1 tiles ([zoomable]) support mouse-wheel zoom + pinch/pan via
///   [InteractiveViewer], and show a mute button ([highRes]).
/// * Touch drag (the grid wraps this tile in a `Draggable`) reorders.
/// * TV remote: hold OK for 600ms → [onGrab]; OK on another tile drops.
/// * Desktop right-click → [onPickChannel] with the click position.
/// * Esc → [onEscape] (cancel grab / exit single view).
class CameraTileWidget extends StatefulWidget {
  final FocusNode focusNode;
  final VideoController videoController;
  final String label;
  final VoidCallback onSelect;
  final VoidCallback? onGrab;
  final VoidCallback? onEscape;
  final void Function(Offset globalPosition)? onPickChannel;

  /// HD single-camera tile: unmuted stream + mute button.
  final bool highRes;

  /// Single-camera tile: wheel/pinch zoom enabled.
  final bool zoomable;

  /// Paint the amber D-Pad focus ring. Off in 1x1 — a lone tile does not
  /// need a "where am I" indicator. Focus handling (shortcuts, OK) stays.
  final bool showFocus;

  /// Fires when the zoom state flips between 1x and zoomed, so the grid
  /// can hand the drag gesture to the viewer instead of reorder-drag.
  final void Function(bool zoomed)? onZoomChanged;

  /// This tile is currently grabbed (TV grab-and-drop / reorder pick).
  final bool grabbed;

  /// A dragged tile is hovering this tile (drop highlight).
  final bool dropCandidate;

  const CameraTileWidget({
    super.key,
    required this.focusNode,
    required this.videoController,
    required this.label,
    required this.onSelect,
    this.onGrab,
    this.onEscape,
    this.onPickChannel,
    this.highRes = false,
    this.zoomable = false,
    this.showFocus = true,
    this.onZoomChanged,
    this.grabbed = false,
    this.dropCandidate = false,
  });

  @override
  State<CameraTileWidget> createState() => _CameraTileWidgetState();
}

/// Shared wheel-zoom math (single tiles + the spotlight stack):
/// cursor-anchored scale of [controller], clamped to `1.0..maxScale`.
/// Pinch/pan stay native to [InteractiveViewer] — the viewer maps wheel
/// to pan, so the wheel needs this manual matrix.
void applyWheelZoom(
    TransformationController controller, PointerSignalEvent e, double maxScale) {
  if (e is! PointerScrollEvent || e.scrollDelta.dy == 0) return;
  final current = controller.value.getMaxScaleOnAxis();
  final next =
      (current * (e.scrollDelta.dy < 0 ? 1.15 : 1 / 1.15)).clamp(1.0, maxScale);
  if (next == current) return;
  final f = next / current;
  final pos = e.localPosition;
  final anchor = Matrix4.identity()
    ..translateByDouble(pos.dx, pos.dy, 0.0, 1.0)
    ..scaleByDouble(f, f, f, 1.0)
    ..translateByDouble(-pos.dx, -pos.dy, 0.0, 1.0);
  controller.value = anchor.multiplied(controller.value);
  if (next <= 1.0) controller.value = Matrix4.identity();
}

class _CameraTileWidgetState extends State<CameraTileWidget> {
  static const _grabHold = Duration(milliseconds: 600);
  static const _maxZoom = 6.0;
  bool _focused = false;
  bool _hovering = false;
  bool _zoomed = false;
  Timer? _holdTimer;
  DateTime? _downTime;
  bool _grabFired = false;
  late final TransformationController _zoom = TransformationController();

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_onFocus);
    _zoom.addListener(_reportZoom);
  }

  @override
  void dispose() {
    _holdTimer?.cancel();
    _zoom.removeListener(_reportZoom);
    _zoom.dispose();
    widget.focusNode.removeListener(_onFocus);
    super.dispose();
  }

  void _reportZoom() {
    final zoomed = _zoom.value.getMaxScaleOnAxis() > 1.01;
    if (zoomed == _zoomed) return;
    if (mounted) setState(() => _zoomed = zoomed);
    widget.onZoomChanged?.call(zoomed);
  }

  void _onFocus() {
    if (mounted) setState(() => _focused = widget.focusNode.hasFocus);
  }

  static bool _isConfirm(KeyEvent e) =>
      e.logicalKey == LogicalKeyboardKey.select ||
      e.logicalKey == LogicalKeyboardKey.enter ||
      e.logicalKey == LogicalKeyboardKey.gameButtonA;

  void _onKey(KeyEvent e) {
    if (e is KeyDownEvent) {
      // Grid-level shortcuts, available on any focused tile.
      if (e.logicalKey == LogicalKeyboardKey.escape) {
        widget.onEscape?.call();
        return;
      }
      if (e.logicalKey == LogicalKeyboardKey.f1) {
        showShortcutsHelp(context);
        return;
      }
      final grid = context.read<GridCubit>();
      if (e.logicalKey == LogicalKeyboardKey.digit1 ||
          e.logicalKey == LogicalKeyboardKey.numpad1) {
        grid.setGridSize(1);
        return;
      }
      if (e.logicalKey == LogicalKeyboardKey.digit2 ||
          e.logicalKey == LogicalKeyboardKey.numpad2) {
        grid.setGridSize(4);
        return;
      }
      if (e.logicalKey == LogicalKeyboardKey.digit3 ||
          e.logicalKey == LogicalKeyboardKey.numpad3) {
        grid.setGridSize(9);
        return;
      }
      if (e.logicalKey == LogicalKeyboardKey.bracketLeft ||
          e.logicalKey == LogicalKeyboardKey.pageUp ||
          e.logicalKey == LogicalKeyboardKey.channelUp) {
        grid.prevPage();
        return;
      }
      if (e.logicalKey == LogicalKeyboardKey.bracketRight ||
          e.logicalKey == LogicalKeyboardKey.pageDown ||
          e.logicalKey == LogicalKeyboardKey.channelDown) {
        grid.nextPage();
        return;
      }
      if (e.logicalKey == LogicalKeyboardKey.keyM) {
        context.read<TileCubit>().toggleMute();
        return;
      }
    }
    if (!_isConfirm(e)) return;
    if (e is KeyDownEvent) {
      // Hold = grab for TV drag-and-drop; a quick press is handled on
      // key-up so hold and tap never both fire. Held keys arrive as
      // repeated KeyDownEvents (KeyDownEvent has no repeat flag), so the
      // deadline is measured against the first press, not the timer alone.
      final now = DateTime.now();
      if (_downTime == null) {
        _downTime = now;
        _grabFired = false;
        _holdTimer?.cancel();
        _holdTimer = Timer(_grabHold, () {
          _grabFired = true;
          widget.onGrab?.call();
        });
      } else if (!_grabFired && now.difference(_downTime!) >= _grabHold) {
        _holdTimer?.cancel();
        _grabFired = true;
        widget.onGrab?.call();
      }
    } else if (e is KeyUpEvent) {
      final wasTap = _downTime != null && !_grabFired;
      _downTime = null;
      _holdTimer?.cancel();
      if (wasTap) widget.onSelect();
    }
  }

  /// Mouse-wheel zoom anchored at the cursor (see [applyWheelZoom]).
  void _onWheel(PointerSignalEvent e) =>
      applyWheelZoom(_zoom, e, _maxZoom);

  Widget _video() {
    final video = Video(
      controller: widget.videoController,
      fill: Colors.black,
      // Livestreams are view-only: never show player controls.
      controls: NoVideoControls,
      // A monitor must resume by itself after backgrounding.
      pauseUponEnteringBackgroundMode: false,
    );
    if (!widget.zoomable) return video;
    return Listener(
      onPointerSignal: _onWheel,
      child: InteractiveViewer(
        transformationController: _zoom,
        minScale: 1.0,
        maxScale: _maxZoom,
        boundaryMargin: EdgeInsets.zero,
        child: video,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Grabbed pick wins over drop highlight; focus wins over idle.
    // In 1x1 the amber ring is suppressed (showFocus) — a lone tile
    // needs no "where am I" indicator.
    final paintFocus = _focused && widget.showFocus;
    final borderColor = widget.grabbed
        ? Colors.lightBlueAccent
        : widget.dropCandidate
            ? Colors.greenAccent
            : paintFocus
                ? CctvTheme.focusColor
                : CctvTheme.tileBorderIdle;
    final glow = widget.grabbed || widget.dropCandidate || paintFocus;
    return KeyboardListener(
      focusNode: widget.focusNode,
      onKeyEvent: _onKey,
      child: MouseRegion(
        // Grab cursor advertises drag-and-drop on desktop; no-op on
        // touch/TV where hover never happens.
        cursor: SystemMouseCursors.grab,
        onEnter: (_) => setState(() => _hovering = true),
        onExit: (_) => setState(() => _hovering = false),
        child: GestureDetector(
          // Single click/tap only focuses (D-Pad landing, drag start).
          // Fullscreen opens on double click (touch/mouse) or OK (TV).
          onTap: () => widget.focusNode.requestFocus(),
          onDoubleTap: () {
            widget.focusNode.requestFocus();
            widget.onSelect();
          },
          onSecondaryTapDown: (d) =>
              widget.onPickChannel?.call(d.globalPosition),
          child: AnimatedScale(
            scale: paintFocus ? CctvTheme.focusScale : 1.0,
            duration: CctvTheme.durShort,
            curve: CctvTheme.curveEmphasized,
            // NOTE: no border here — Container paints decoration UNDER
            // its child, so a full-bleed video would cover the border's
            // rounded corners. The border lives on an overlay at the top
            // of the Stack below; this container only carries the glow.
            child: AnimatedContainer(
              duration: CctvTheme.durShort,
              curve: CctvTheme.curveEmphasized,
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius:
                    BorderRadius.circular(CctvTheme.tileRadius),
                boxShadow: glow
                    ? [
                        BoxShadow(
                          color: borderColor.withValues(alpha: 0.55),
                          blurRadius: paintFocus ? 20 : 14,
                        ),
                      ]
                    : null,
              ),
              child: ClipRRect(
                borderRadius:
                    BorderRadius.circular(CctvTheme.tileRadius),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _video(),
                  Positioned(
                    left: 8,
                    top: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.65),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white10),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          BlocBuilder<TileCubit, TileState>(
                            builder: (context, state) {
                              final live =
                                  state.conn == TileConn.playing;
                              return AnimatedContainer(
                                duration: CctvTheme.durShort,
                                width: 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  color: live
                                      ? Colors.greenAccent
                                      : Colors.white38,
                                  shape: BoxShape.circle,
                                ),
                              );
                            },
                          ),
                          const SizedBox(width: 6),
                          Text(widget.label,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ),
                  if (widget.grabbed)
                    const Positioned(
                      right: 8,
                      top: 6,
                      child: Icon(Icons.open_with,
                          color: Colors.lightBlueAccent),
                    ),
                  if (widget.dropCandidate)
                    const Positioned(
                      right: 8,
                      top: 6,
                      child: Icon(Icons.move_to_inbox,
                          color: Colors.greenAccent),
                    ),
                  // Drag handle only when a drag would reorder: hidden
                  // while zoomed (drags pan the picture instead).
                  if (_hovering &&
                      !_zoomed &&
                      !widget.grabbed &&
                      !widget.dropCandidate)
                    const Positioned(
                      right: 6,
                      bottom: 4,
                      child: Icon(Icons.drag_indicator,
                          color: Colors.white54, size: 18),
                    ),
                  // HD single tiles carry audio: mute toggle lives on the
                  // tile so it stays focusable for TV remotes.
                  if (widget.highRes)
                    Positioned(
                      left: 4,
                      bottom: 4,
                      child: BlocBuilder<TileCubit, TileState>(
                        buildWhen: (prev, next) =>
                            prev.muted != next.muted,
                        builder: (muteContext, muteState) => IconButton(
                          iconSize: 20,
                          padding: const EdgeInsets.all(6),
                          constraints: const BoxConstraints(
                              minWidth: 32, minHeight: 32),
                          style: IconButton.styleFrom(
                            backgroundColor:
                                Colors.black.withValues(alpha: 0.55),
                            foregroundColor: Colors.white70,
                          ),
                          tooltip:
                              muteState.muted ? 'Unmute (M)' : 'Mute (M)',
                          icon: Icon(muteState.muted
                              ? Icons.volume_off
                              : Icons.volume_up),
                          onPressed: () => muteContext
                              .read<TileCubit>()
                              .toggleMute(),
                        ),
                      ),
                    ),
                  BlocBuilder<TileCubit, TileState>(
                    builder: (context, state) {
                      return AnimatedSwitcher(
                        duration: CctvTheme.durMed,
                        switchInCurve: CctvTheme.curveEmphasized,
                        child: _overlayFor(context, state),
                      );
                    },
                  ),
                  // Crisp rounded outline, painted ABOVE the video so
                  // square texture corners can never cover it.
                  Positioned.fill(
                    child: IgnorePointer(
                      child: AnimatedContainer(
                        duration: CctvTheme.durShort,
                        curve: CctvTheme.curveEmphasized,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(
                              CctvTheme.tileRadius),
                          border: Border.all(
                              color: borderColor,
                              width: glow ? 3.0 : 1.0),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      ),
    );
  }

  Widget? _overlayFor(BuildContext context, TileState state) {
    switch (state.conn) {
      case TileConn.loading:
      case TileConn.reconnecting:
        return Container(
          key: ValueKey(state.conn),
          color: Colors.black.withValues(alpha: 0.55),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
                const SizedBox(height: 8),
                Text(
                  state.conn == TileConn.loading
                      ? 'Connecting…'
                      : 'Reconnecting…',
                  style: const TextStyle(
                      color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
        );
      case TileConn.error:
        return Container(
          key: const ValueKey('error'),
          color: Colors.black.withValues(alpha: 0.78),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .errorContainer
                          .withValues(alpha: 0.9),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.videocam_off,
                        color: Theme.of(context)
                            .colorScheme
                            .onErrorContainer,
                        size: 24),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    state.message ?? 'Stream failed',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: Colors.white70, fontSize: 12),
                  ),
                  const SizedBox(height: 8),
                  FilledButton.tonalIcon(
                    onPressed: () =>
                        context.read<TileCubit>().retry(),
                    icon: const Icon(Icons.refresh, size: 16),
                    label: const Text('Retry'),
                    style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      textStyle: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      case TileConn.idle:
        return Container(
          key: const ValueKey('idle'),
          color: Colors.black,
          child: const Center(
              child: SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          )),
        );
      case TileConn.playing:
        return const SizedBox.shrink(key: ValueKey('playing'));
    }
  }
}
