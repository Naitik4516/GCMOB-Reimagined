import 'package:flutter/material.dart';

import '../../../app/theme.dart';

/// Keyboard shortcut reference, opened from F1 / the `?` button.
void showShortcutsHelp(BuildContext context) {
  showDialog<void>(
    context: context,
    builder: (d) => AlertDialog(
      title: const Text('Keyboard shortcuts'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            _ShortcutRow(keys: 'F11', action: 'Toggle app fullscreen'),
            _ShortcutRow(
                keys: 'Double-click / OK',
                action: 'Open / close single-camera view'),
            _ShortcutRow(keys: '1 / 2 / 3', action: 'Grid layout 1×1 / 2×2 / 3×3'),
            _ShortcutRow(
                keys: '[ ]  or  PgUp PgDn',
                action: 'Previous / next page'),
            _ShortcutRow(
                keys: 'Mouse wheel / pinch',
                action: 'Zoom (single-camera view)'),
            _ShortcutRow(keys: 'M', action: 'Mute / unmute (single-camera)'),
            _ShortcutRow(keys: 'Esc / Back', action: 'Cancel grab, exit single view'),
            _ShortcutRow(keys: 'F1', action: 'This help'),
          ],
        ),
      ),
      actions: [
        TextButton(
          autofocus: true,
          onPressed: () => Navigator.of(d).pop(),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}

class _ShortcutRow extends StatelessWidget {
  final String keys;
  final String action;

  const _ShortcutRow({required this.keys, required this.action});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: CctvTheme.surfaceLow,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.white24),
            ),
            child: Text(
              keys,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontFamilyFallback: ['monospace'],
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Flexible(child: Text(action)),
        ],
      ),
    );
  }
}
