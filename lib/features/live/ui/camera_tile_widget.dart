import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../../app/theme.dart';
import '../bloc/tile_cubit.dart';

/// Single CCTV tile: video + connection overlay + D-Pad focus glow.
///
/// * Tap / quick OK press → [onSelect] (fullscreen).
/// * Touch long-press → drag & drop (the grid wraps this tile in a
///   `LongPressDraggable`, so no long-press handler lives here).
/// * TV remote: hold OK for 600ms → [onGrab]; OK on another tile drops.
/// * Desktop right-click → [onPickChannel] with the click position.
class CameraTileWidget extends StatefulWidget {
  final FocusNode focusNode;
  final VideoController videoController;
  final String label;
  final VoidCallback onSelect;
  final VoidCallback? onGrab;
  final void Function(Offset globalPosition)? onPickChannel;

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
    this.onPickChannel,
    this.grabbed = false,
    this.dropCandidate = false,
  });

  @override
  State<CameraTileWidget> createState() => _CameraTileWidgetState();
}

class _CameraTileWidgetState extends State<CameraTileWidget> {
  static const _grabHold = Duration(milliseconds: 600);
  bool _focused = false;
  bool _hovering = false;
  Timer? _holdTimer;
  DateTime? _downTime;
  bool _grabFired = false;

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_onFocus);
  }

  @override
  void dispose() {
    _holdTimer?.cancel();
    widget.focusNode.removeListener(_onFocus);
    super.dispose();
  }

  void _onFocus() {
    if (mounted) setState(() => _focused = widget.focusNode.hasFocus);
  }

  static bool _isConfirm(KeyEvent e) =>
      e.logicalKey == LogicalKeyboardKey.select ||
      e.logicalKey == LogicalKeyboardKey.enter ||
      e.logicalKey == LogicalKeyboardKey.gameButtonA;

  void _onKey(KeyEvent e) {
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

  @override
  Widget build(BuildContext context) {
    // Grabbed pick wins over drop highlight; focus wins over idle.
    final borderColor = widget.grabbed
        ? Colors.lightBlueAccent
        : widget.dropCandidate
            ? Colors.greenAccent
            : _focused
                ? CctvTheme.focusColor
                : CctvTheme.tileBorderIdle;
    final glow = widget.grabbed || widget.dropCandidate || _focused;
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
          child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            color: Colors.black,
            border: Border.all(color: borderColor, width: glow ? 4.0 : 1.0),
            boxShadow: glow
                ? [
                    BoxShadow(
                      color: borderColor.withValues(alpha: 0.6),
                      blurRadius: 16,
                    ),
                  ]
                : null,
            borderRadius: BorderRadius.circular(8),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Video(
                controller: widget.videoController,
                fill: Colors.black,
                // Livestreams are view-only: never show player controls.
                controls: NoVideoControls,
                // A monitor must resume by itself after backgrounding.
                pauseUponEnteringBackgroundMode: false,
              ),
              Positioned(
                left: 8,
                top: 6,
                child: Container(
                  color: Colors.black54,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  child: Text(widget.label,
                      style: const TextStyle(color: Colors.white, fontSize: 12)),
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
              if (_hovering && !widget.grabbed && !widget.dropCandidate)
                const Positioned(
                  right: 6,
                  bottom: 4,
                  child: Icon(Icons.drag_indicator,
                      color: Colors.white54, size: 18),
                ),
              BlocBuilder<TileCubit, TileState>(
                builder: (context, state) {
                  switch (state.conn) {
                    case TileConn.loading:
                    case TileConn.reconnecting:
                      return Container(
                        color: Colors.black45,
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const CircularProgressIndicator(),
                              const SizedBox(height: 8),
                              Text(
                                state.conn == TileConn.loading
                                    ? 'Connecting…'
                                    : 'Reconnecting…',
                                style: const TextStyle(color: Colors.white70),
                              ),
                            ],
                          ),
                        ),
                      );
                    case TileConn.error:
                      return Container(
                        color: Colors.black.withValues(alpha: 0.7),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.videocam_off,
                                  color: Colors.redAccent, size: 32),
                              const SizedBox(height: 6),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12),
                                child: Text(
                                  state.message ?? 'Stream failed',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                      color: Colors.white70, fontSize: 12),
                                ),
                              ),
                              const SizedBox(height: 6),
                              ElevatedButton(
                                onPressed: () =>
                                    context.read<TileCubit>().retry(),
                                child: const Text('Retry'),
                              ),
                            ],
                          ),
                        ),
                      );
                    case TileConn.idle:
                      return Container(
                        color: Colors.black,
                        child: const Center(
                            child: CircularProgressIndicator()),
                      );
                    case TileConn.playing:
                      return const SizedBox.shrink();
                  }
                },
              ),
            ],
          ),
          ),
        ),
      ),
    );
  }
}
