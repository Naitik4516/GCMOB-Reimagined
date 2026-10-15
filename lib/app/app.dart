import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/platform/app_fullscreen.dart';
import '../features/profiles/ui/profile_list_page.dart';
import 'theme.dart';

class CctvApp extends StatelessWidget {
  const CctvApp({super.key});

  // F11 toggles app fullscreen from anywhere. No autofocus: bubbled key
  // events reach this ancestor regardless of which tile holds focus, and
  // autofocus here would steal TV focus from the profile list / tiles.
  static KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.f11) {
      AppFullscreen.toggle();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'gCMOB Reimagined',
      debugShowCheckedModeBanner: false,
      theme: CctvTheme.dark(),
      home: Focus(
        onKeyEvent: _onKey,
        child: const ProfileListPage(),
      ),
    );
  }
}
