import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:otzaria/utils/shortcut_helper.dart';

/// דיאלוג לקליטת קיצור מקשים מותאם אישית
class CustomShortcutDialog extends StatefulWidget {
  final String? initialShortcut;

  const CustomShortcutDialog({
    super.key,
    this.initialShortcut,
  });

  @override
  State<CustomShortcutDialog> createState() => _CustomShortcutDialogState();
}

class _CustomShortcutDialogState extends State<CustomShortcutDialog> {
  final Set<LogicalKeyboardKey> _pressedKeys = {};
  String _displayText = 'לחץ על המקשים...';
  bool _isRecording = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialShortcut != null) {
      _displayText = ShortcutHelper.formatShortcutForDisplay(widget.initialShortcut!);
    }
  }

  void _updateDisplay() {
    if (_pressedKeys.isEmpty) {
      setState(() {
        _displayText = 'לחץ על המקשים...';
      });
      return;
    }

    final shortcut = ShortcutHelper.formatKeysToShortcut(_pressedKeys);
    setState(() {
      _displayText = ShortcutHelper.formatShortcutForDisplay(shortcut);
    });
  }


  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
      focusNode: FocusNode()..requestFocus(),
      autofocus: true,
      onKeyEvent: (KeyEvent event) {
        if (!_isRecording) {
          // אם לא מקליטים, אפשר אנטר לאישור
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.enter &&
              _pressedKeys.isNotEmpty) {
            final shortcut = ShortcutHelper.formatKeysToShortcut(_pressedKeys);
            Navigator.pop(context, shortcut);
          }
          return;
        }

        if (event is KeyDownEvent) {
          setState(() {
            _pressedKeys.add(event.logicalKey);
          });
          _updateDisplay();
        } else if (event is KeyUpEvent) {
          // כאשר משחררים מקש, לא מסירים אותו מיד
          // נחכה שכל המקשים ישוחררו
        }
      },
      child: AlertDialog(
        title: const Text(
          'הגדרת קיצור מקשים מותאם אישית',
          textAlign: TextAlign.right,
        ),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'לחץ על "התחל הקלטה" ואז לחץ על צירוף המקשים הרצוי',
                textAlign: TextAlign.right,
                style: TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _isRecording
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).dividerColor,
                    width: 2,
                  ),
                ),
                child: Column(
                  children: [
                    Icon(
                      _isRecording ? Icons.keyboard : Icons.keyboard_outlined,
                      size: 48,
                      color: _isRecording
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _displayText,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: _isRecording
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              if (_isRecording)
                ElevatedButton.icon(
                  onPressed: () {
                    setState(() {
                      _isRecording = false;
                    });
                  },
                  icon: const Icon(Icons.stop),
                  label: const Text('עצור הקלטה'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.error,
                    foregroundColor: Theme.of(context).colorScheme.onError,
                  ),
                )
              else
                ElevatedButton.icon(
                  onPressed: () {
                    setState(() {
                      _pressedKeys.clear();
                      _isRecording = true;
                      _displayText = 'לחץ על המקשים...';
                    });
                  },
                  icon: const Icon(Icons.fiber_manual_record),
                  label: const Text('התחל הקלטה'),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('ביטול'),
          ),
          TextButton(
            onPressed: _pressedKeys.isEmpty
                ? null
                : () {
                    final shortcut = ShortcutHelper.formatKeysToShortcut(_pressedKeys);
                    Navigator.pop(context, shortcut);
                  },
            child: const Text('אישור'),
          ),
        ],
      ),
    );
  }
}
