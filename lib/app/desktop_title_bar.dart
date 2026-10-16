import 'dart:async';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'theme.dart';

/// Desktop window title bar (Windows-only): a draggable region merging
/// the page title + actions with native window buttons. Rendered by
/// [AdaptiveShell] instead of [AppBar] where [useCustomChrome] holds;
/// Linux keeps its native frame. The native title bar is hidden in
/// [AppFullscreen.init].
class DesktopTitleBar extends StatelessWidget {
  final String title;
  final Widget? titleTrailing;
  final List<Widget> actions;

  const DesktopTitleBar({
    super.key,
    required this.title,
    this.titleTrailing,
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      color: CctvTheme.surfaceLow,
      padding: const EdgeInsets.only(left: 4, right: 4),
      child: Row(
        children: [
          if (Navigator.of(context).canPop())
            IconButton(
              iconSize: 18,
              tooltip: 'Back',
              icon: const Icon(Icons.arrow_back),
              onPressed: () => Navigator.of(context).pop(),
            ),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onPanStart: (_) =>
                  unawaited(windowManager.startDragging()),
              onDoubleTap: _toggleMaximize,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        title,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    if (titleTrailing != null) ...[
                      const SizedBox(width: 8),
                      titleTrailing!,
                    ],
                  ],
                ),
              ),
            ),
          ),
          ...actions,
          const _WindowButtons(),
        ],
      ),
    );
  }

  Future<void> _toggleMaximize() async {
    try {
      if (await windowManager.isMaximized()) {
        await windowManager.unmaximize();
      } else {
        await windowManager.maximize();
      }
    } catch (_) {
      // No window controls on this platform; ignore.
    }
  }
}

class _WindowButtons extends StatefulWidget {
  const _WindowButtons();

  @override
  State<_WindowButtons> createState() => _WindowButtonsState();
}

class _WindowButtonsState extends State<_WindowButtons> {
  bool _maximized = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    try {
      final m = await windowManager.isMaximized();
      if (mounted) setState(() => _maximized = m);
    } catch (_) {
      // Ignore; keep last known state.
    }
  }

  Future<void> _minimize() async {
    try {
      await windowManager.minimize();
    } catch (_) {}
  }

  Future<void> _toggleMaximize() async {
    try {
      if (await windowManager.isMaximized()) {
        await windowManager.unmaximize();
      } else {
        await windowManager.maximize();
      }
    } catch (_) {
      // Ignore.
    } finally {
      _refresh();
    }
  }

  Future<void> _close() async {
    try {
      await windowManager.close();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _WinBtn(
          icon: Icons.remove,
          tooltip: 'Minimize',
          onPressed: _minimize,
        ),
        _WinBtn(
          icon: _maximized ? Icons.filter_none : Icons.crop_square,
          tooltip: _maximized ? 'Restore' : 'Maximize',
          onPressed: _toggleMaximize,
        ),
        _WinBtn(
          icon: Icons.close,
          tooltip: 'Close',
          danger: true,
          onPressed: _close,
        ),
      ],
    );
  }
}

class _WinBtn extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final bool danger;

  const _WinBtn({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.danger = false,
  });

  @override
  State<_WinBtn> createState() => _WinBtnState();
}

class _WinBtnState extends State<_WinBtn> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: Container(
          width: 46,
          height: 44,
          color: _hover
              ? widget.danger
                  ? const Color(0xFFE81123)
                  : Colors.white10
              : Colors.transparent,
          child: Tooltip(
            message: widget.tooltip,
            child: Icon(widget.icon, size: 18),
          ),
        ),
      ),
    );
  }
}
