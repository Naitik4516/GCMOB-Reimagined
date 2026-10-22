import 'package:flutter/services.dart';

/// Keyboard actions handled by a focused tile.
///
/// Keep in sync with the labels in `shortcuts_help.dart`.
enum TileShortcut {
  escape,
  help,
  layout1,
  layout4,
  layout9,
  previousPage,
  nextPage,
  mute,
  confirm,
}

/// Maps a raw key to the tile action it triggers, or `null` when the key is
/// not a tile shortcut. Modifier state is intentionally ignored: the existing
/// shortcuts never required Ctrl/Alt/Shift.
TileShortcut? shortcutFor(LogicalKeyboardKey key) {
  if (key == LogicalKeyboardKey.escape) return TileShortcut.escape;
  if (key == LogicalKeyboardKey.f1) return TileShortcut.help;

  if (key == LogicalKeyboardKey.digit1 ||
      key == LogicalKeyboardKey.numpad1) {
    return TileShortcut.layout1;
  }
  if (key == LogicalKeyboardKey.digit2 ||
      key == LogicalKeyboardKey.numpad2) {
    return TileShortcut.layout4;
  }
  if (key == LogicalKeyboardKey.digit3 ||
      key == LogicalKeyboardKey.numpad3) {
    return TileShortcut.layout9;
  }

  if (key == LogicalKeyboardKey.bracketLeft ||
      key == LogicalKeyboardKey.pageUp ||
      key == LogicalKeyboardKey.channelUp) {
    return TileShortcut.previousPage;
  }
  if (key == LogicalKeyboardKey.bracketRight ||
      key == LogicalKeyboardKey.pageDown ||
      key == LogicalKeyboardKey.channelDown) {
    return TileShortcut.nextPage;
  }

  if (key == LogicalKeyboardKey.keyM) return TileShortcut.mute;
  if (key == LogicalKeyboardKey.select ||
      key == LogicalKeyboardKey.enter ||
      key == LogicalKeyboardKey.gameButtonA) {
    return TileShortcut.confirm;
  }
  return null;
}
