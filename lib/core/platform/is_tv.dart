import 'package:flutter/foundation.dart';

/// Supported targets: Android (phone/tablet), Linux, Windows,
/// Android TV / Fire TV. No web / iOS / macOS runners ship.

/// True on Android (phone, tablet, TV, Fire TV). There is no pure-Dart
/// Leanback check; focus-glow UI is harmless on touch devices, so all
/// Android builds get TV-capable focus handling.
bool get isTvCapable => defaultTargetPlatform == TargetPlatform.android;

bool get isDesktopDevice =>
    defaultTargetPlatform == TargetPlatform.linux ||
    defaultTargetPlatform == TargetPlatform.windows;
