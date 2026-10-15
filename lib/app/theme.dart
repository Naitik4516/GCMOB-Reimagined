import 'package:flutter/material.dart';

/// Dark CCTV theme + shared focus-glow constants for TV D-Pad UX.
class CctvTheme {
  static const focusColor = Colors.amber;
  static const tileBorderIdle = Colors.white24;

  static ThemeData dark() {
    final scheme = ColorScheme.fromSeed(
      seedColor: Colors.blueGrey,
      brightness: Brightness.dark,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: Colors.black,
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF111417),
        foregroundColor: Colors.white,
      ),
    );
  }
}
