import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import 'is_tv.dart';

/// App-level fullscreen: borderless window on desktop via window_manager,
/// immersive sticky system bars on Android. F11 toggles it from anywhere
/// (see `CctvApp`); [LivePage] also exposes a toggle button.
///
/// [isFullscreen] notifies listeners so toggle icons stay in sync.
class AppFullscreen {
  static const _prefKey = 'app_fullscreen';

  static final ValueNotifier<bool> isFullscreen = ValueNotifier(false);

  /// `ensureInitialized` + saved mode (desktop) or immersive bars (mobile).
  /// Safe to call once from `main()` before `runApp`.
  static Future<void> init() async {
    try {
      if (isDesktopDevice) {
        await windowManager.ensureInitialized();
        final prefs = await SharedPreferences.getInstance();
        final full = prefs.getBool(_prefKey) ?? false;
        if (full) await windowManager.setFullScreen(true);
        isFullscreen.value = full;
      } else if (!kIsWeb &&
          defaultTargetPlatform == TargetPlatform.android) {
        await SystemChrome.setEnabledSystemUIMode(
            SystemUiMode.immersiveSticky);
        isFullscreen.value = true;
      }
    } catch (_) {
      // Window controls unavailable; run windowed.
    }
  }

  static Future<void> toggle() async {
    final next = !isFullscreen.value;
    try {
      if (isDesktopDevice) {
        await windowManager.setFullScreen(next);
      } else if (!kIsWeb &&
          defaultTargetPlatform == TargetPlatform.android) {
        await SystemChrome.setEnabledSystemUIMode(next
            ? SystemUiMode.immersiveSticky
            : SystemUiMode.edgeToEdge);
      } else {
        return;
      }
      isFullscreen.value = next;
      if (isDesktopDevice) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(_prefKey, next);
      }
    } catch (_) {
      // Platform refused; stay in the current mode.
    }
  }
}
