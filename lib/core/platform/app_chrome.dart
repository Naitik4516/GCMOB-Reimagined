import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'app_fullscreen.dart';

/// Single owner of Android system-bar visibility.
///
/// Two independent inputs can request immersion: app-level fullscreen
/// ([AppFullscreen]) and the current page's landscape mode. Reconciling
/// from both means rotation and F11 can no longer overwrite each other.
abstract final class AppChrome {
  static bool _pageImmersive = false;
  static Future<void> _pending = Future<void>.value();

  /// Pure decision function; unit-tested without platform channels.
  static SystemUiMode resolve({
    required bool appFullscreen,
    required bool pageImmersive,
  }) =>
      appFullscreen || pageImmersive
          ? SystemUiMode.immersiveSticky
          : SystemUiMode.edgeToEdge;

  static Future<void> setPageImmersive(bool value) {
    _pageImmersive = value;
    return reconcile();
  }

  /// Applies the current combination. Only Android has system UI; desktop
  /// fullscreen is handled by window_manager.
  ///
  /// Calls are serialized so a rapid rotation / F11 sequence cannot leave
  /// an older mode applied after a newer one. Platform errors are logged
  /// and never escape into fire-and-forget callers.
  static Future<void> reconcile() {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return Future<void>.value();
    }
    final mode = resolve(
      appFullscreen: AppFullscreen.isFullscreen.value,
      pageImmersive: _pageImmersive,
    );
    _pending = _pending.then((_) async {
      try {
        await SystemChrome.setEnabledSystemUIMode(mode);
      } catch (e) {
        debugPrint('AppChrome.reconcile: $e');
      }
    });
    return _pending;
  }
}
