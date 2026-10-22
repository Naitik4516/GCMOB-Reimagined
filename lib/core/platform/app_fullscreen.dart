import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import 'app_chrome.dart';
import 'is_tv.dart';

/// App-level fullscreen: borderless window on desktop via window_manager,
/// immersive sticky system bars on Android. F11 toggles it from anywhere
/// (see `CctvApp`); [LivePage] also exposes a toggle button.
///
/// Fullscreen hides OS chrome only; the in-app title bar/AppBar remains so
/// layout, quality, paging and exit controls stay reachable.
///
/// [isFullscreen] notifies listeners so toggle icons stay in sync.
class AppFullscreen {
  static const _prefKey = 'app_fullscreen';

  static final ValueNotifier<bool> isFullscreen = ValueNotifier(false);

  /// `ensureInitialized` + saved mode (desktop) or immersive bars (mobile).
  /// Hides the native title bar on desktop — [DesktopTitleBar] draws the
  /// replacement. Phones launch NON-fullscreen (system bars visible);
  /// only an explicitly saved choice restores immersion. Safe to call once
  /// from `main()` before `runApp`.
  static Future<void> init() async {
    try {
      if (isDesktopDevice) {
        await windowManager.ensureInitialized();
        // Floor the window so controls never crush on tiny resizes.
        await windowManager.setMinimumSize(const Size(428, 444));
        if (useCustomChrome) {
          // Transparent backdrop so the window itself can have rounded
          // corners (drawn by CctvApp). Windows-only: transparency does
          // not composite on Linux Wayland, and Linux keeps its native
          // KWin frame (theme rounding included) instead.
          await windowManager.setBackgroundColor(Colors.transparent);
          await windowManager.setTitleBarStyle(
            TitleBarStyle.hidden,
            windowButtonVisibility: false,
          );
        }
        final prefs = await SharedPreferences.getInstance();
        final full = prefs.getBool(_prefKey) ?? false;
        if (full) await windowManager.setFullScreen(true);
        isFullscreen.value = full;
      } else if (!kIsWeb &&
          defaultTargetPlatform == TargetPlatform.android) {
        final prefs = await SharedPreferences.getInstance();
        final full = prefs.getBool(_prefKey) ?? false;
        isFullscreen.value = full;
        // Reconciler also honors any current page immersion. At launch the
        // page flag is false, so this is just the saved app choice.
        await AppChrome.reconcile();
      }
    } catch (e) {
      // Window controls unavailable; run windowed.
      debugPrint('AppFullscreen.init: $e');
    }
  }

  static Future<void> toggle() async {
    final next = !isFullscreen.value;
    try {
      if (isDesktopDevice) {
        await windowManager.setFullScreen(next);
        isFullscreen.value = next;
      } else if (!kIsWeb &&
          defaultTargetPlatform == TargetPlatform.android) {
        isFullscreen.value = next;
        await AppChrome.reconcile();
      } else {
        return;
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefKey, next);
    } catch (e) {
      // Platform refused; stay in the current mode.
      debugPrint('AppFullscreen.toggle: $e');
    }
  }
}
