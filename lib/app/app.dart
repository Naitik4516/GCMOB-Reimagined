import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/platform/app_fullscreen.dart';
import '../core/platform/is_tv.dart';
import '../features/profiles/ui/profile_list_page.dart';
import 'theme.dart';

class CctvApp extends StatefulWidget {
  const CctvApp({super.key});

  @override
  State<CctvApp> createState() => _CctvAppState();
}

class _CctvAppState extends State<CctvApp> {
  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKey);
    super.dispose();
  }

  // Global handler: fires regardless of which widget holds focus. (The old
  // Focus-bubble version silently did nothing when nothing was focused —
  // that was the F11 bug.)
  bool _handleKey(KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.f11) {
      AppFullscreen.toggle();
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'gCMOB Reimagined',
      debugShowCheckedModeBanner: false,
      theme: CctvTheme.dark(),
      // Rounded window content (custom-chrome platforms only): clips
      // every route/dialog to the window radius (square again in
      // fullscreen, where rounding would show black corners). No-op on
      // mobile/TV and on Linux, where KWin rounds the native frame.
      builder: (context, child) {
        if (child == null || !useCustomChrome) {
          return child ?? const SizedBox();
        }
        return ValueListenableBuilder<bool>(
          valueListenable: AppFullscreen.isFullscreen,
          builder: (_, full, _) => ClipRRect(
            borderRadius: BorderRadius.circular(full ? 0 : 12),
            child: child,
          ),
        );
      },
      home: const ProfileListPage(),
    );
  }
}
