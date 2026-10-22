import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gcmob_reimagined/features/live/ui/tile_shortcuts.dart';

void main() {
  test('maps every tile shortcut key', () {
    expect(shortcutFor(LogicalKeyboardKey.escape), TileShortcut.escape);
    expect(shortcutFor(LogicalKeyboardKey.f1), TileShortcut.help);

    for (final key in [
      LogicalKeyboardKey.digit1,
      LogicalKeyboardKey.numpad1,
    ]) {
      expect(shortcutFor(key), TileShortcut.layout1);
    }
    for (final key in [
      LogicalKeyboardKey.digit2,
      LogicalKeyboardKey.numpad2,
    ]) {
      expect(shortcutFor(key), TileShortcut.layout4);
    }
    for (final key in [
      LogicalKeyboardKey.digit3,
      LogicalKeyboardKey.numpad3,
    ]) {
      expect(shortcutFor(key), TileShortcut.layout9);
    }

    for (final key in [
      LogicalKeyboardKey.bracketLeft,
      LogicalKeyboardKey.pageUp,
      LogicalKeyboardKey.channelUp,
    ]) {
      expect(shortcutFor(key), TileShortcut.previousPage);
    }
    for (final key in [
      LogicalKeyboardKey.bracketRight,
      LogicalKeyboardKey.pageDown,
      LogicalKeyboardKey.channelDown,
    ]) {
      expect(shortcutFor(key), TileShortcut.nextPage);
    }

    expect(shortcutFor(LogicalKeyboardKey.keyM), TileShortcut.mute);
    for (final key in [
      LogicalKeyboardKey.select,
      LogicalKeyboardKey.enter,
      LogicalKeyboardKey.gameButtonA,
    ]) {
      expect(shortcutFor(key), TileShortcut.confirm);
    }
  });

  test('unmapped keys return null', () {
    expect(shortcutFor(LogicalKeyboardKey.keyA), isNull);
    expect(shortcutFor(LogicalKeyboardKey.f11), isNull);
  });
}
