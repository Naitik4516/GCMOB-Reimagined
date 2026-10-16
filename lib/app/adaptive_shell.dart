import 'package:flutter/material.dart';

import '../core/platform/is_tv.dart';
import 'desktop_title_bar.dart';

/// Page frame that merges the app bar into the desktop window title bar.
///
/// * Windows: [DesktopTitleBar] (draggable, window buttons) on top, page
///   body below; no separate [AppBar].
/// * Linux: native KWin/GTK frame outside, regular [AppBar] inside — so
///   the window follows the OS rounding/shadow theme like other apps.
/// * Mobile/TV: a regular [Scaffold] with [AppBar] + bottom bar.
class AdaptiveShell extends StatelessWidget {
  final String title;
  final Widget? titleTrailing;
  final List<Widget> actions;
  final Widget body;
  final Widget? bottomBar;
  final Widget? floatingActionButton;

  /// Mobile only: drop the AppBar + bottom bar for immersive landscape
  /// viewing (desktop ignores this).
  final bool hideChrome;

  const AdaptiveShell({
    super.key,
    required this.title,
    required this.body,
    this.titleTrailing,
    this.actions = const [],
    this.bottomBar,
    this.floatingActionButton,
    this.hideChrome = false,
  });

  Widget _titleRow() {
    if (titleTrailing == null) {
      return Text(title, overflow: TextOverflow.ellipsis);
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(child: Text(title, overflow: TextOverflow.ellipsis)),
        const SizedBox(width: 8),
        titleTrailing!,
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (useCustomChrome) {
      return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: Column(
          children: [
            DesktopTitleBar(
              title: title,
              titleTrailing: titleTrailing,
              actions: actions,
            ),
            Expanded(child: body),
            // ignore: use_null_aware_elements (`bottomBar?` misparses here)
            if (bottomBar != null) bottomBar!,
          ],
        ),
        floatingActionButton: floatingActionButton,
      );
    }
    // Mobile/TV and Linux (native frame): regular AppBar inside the window.
    return Scaffold(
      appBar: hideChrome ? null : AppBar(title: _titleRow(), actions: actions),
      body: body,
      bottomNavigationBar: (hideChrome || bottomBar == null)
          ? null
          : SafeArea(top: false, child: bottomBar!),
      floatingActionButton: floatingActionButton,
    );
  }
}
