import 'package:flutter/material.dart';
import 'package:otzaria/theme/app_tokens.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/services.dart';
import 'package:otzaria/core/focus_repository.dart';
import 'package:otzaria/core/messages/common_messages.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/shortcuts/shortcut_helper.dart';
import 'package:otzaria/widgets/dialogs/app_dialog_frame.dart';
import 'package:otzaria/widgets/misc/rtl_icon.dart';
import 'package:otzaria/widgets/widgets_exports.dart';

/// דיאלוג לקליטת קיצור מקשים מותאם אישית
class CustomShortcutDialog extends StatefulWidget {
  final String? initialShortcut;

  /// שם הפעולה שעבורה מגדירים את הקיצור. מוצג בין הכותרת לבין "התחל הקלטה"
  /// כדי שיהיה ברור לאיזו פעולה הקיצור משויך.
  final String? actionName;

  const CustomShortcutDialog({
    super.key,
    this.initialShortcut,
    this.actionName,
  });

  @override
  State<CustomShortcutDialog> createState() => _CustomShortcutDialogState();
}

class _CustomShortcutDialogState extends State<CustomShortcutDialog>
    with DialogFocusRestorerMixin<CustomShortcutDialog> {
  final Set<LogicalKeyboardKey> _pressedKeys = {};
  final FocusNode _focusNode = FocusNode();
  String _displayText = 'לא הוגדר קיצור';
  bool _isRecording = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialShortcut != null) {
      _displayText = ShortcutHelper.formatShortcutForDisplay(
        widget.initialShortcut!,
      );
    }
    registerDialogFocusRestorer(_focusNode);
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
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

  void _confirmShortcut() {
    if (_pressedKeys.isEmpty) {
      UiSnack.showError(CommonMessages.shortcutRequired);
      return;
    }

    final shortcut = ShortcutHelper.formatKeysToShortcut(_pressedKeys);
    Navigator.pop(context, shortcut);
  }

  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: (KeyEvent event) {
        if (!_isRecording) {
          // אם לא מקליטים, אפשר אנטר לאישור
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.enter) {
            _confirmShortcut();
          }
          return;
        }

        if (event is KeyDownEvent) {
          setState(() {
            _pressedKeys.add(ShortcutHelper.logicalKeyToStore(event));
          });
          _updateDisplay();
        } else if (event is KeyUpEvent) {
          // כאשר משחררים מקש, לא מסירים אותו מיד
          // נחכה שכל המקשים ישוחררו
        }
      },
      child: AppDialogFrame(
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
        title: 'הגדרת קיצור מקשים מותאם אישית',
        icon: FluentIcons.keyboard_24_regular,
        width: 500,
        actions: [
          ActionButton.neutral(
            text: 'ביטול',
            onPressed: () => Navigator.pop(context),
          ),
          ActionButton.recommended(
            text: 'אישור',
            onPressed: _confirmShortcut,
          ),
        ],
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'התחל הקלטה ובחר קיצור',
                style: TextStyle(fontSize: AppTokens.fontMD),
              ),
              if (widget.actionName != null &&
                  widget.actionName!.isNotEmpty) ...[
                const SizedBox(height: AppTokens.spaceSM),
                Text(
                  widget.actionName!,
                  style: TextStyle(
                    fontSize: AppTokens.fontLG,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ],
              const SizedBox(height: AppTokens.spaceLG),
              Container(
                padding: const EdgeInsets.all(AppTokens.spaceLG),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: AppTokens.borderRadiusAll,
                  border: Border.all(
                    color: _isRecording
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).dividerColor,
                    width: 2,
                  ),
                ),
                child: Column(
                  children: [
                    RtlIcon(
                      _isRecording
                          ? FluentIcons.keyboard_24_filled
                          : FluentIcons.keyboard_24_regular,
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
              if (!_isRecording && _pressedKeys.isNotEmpty) ...[
                const SizedBox(height: AppTokens.spaceMD),
                Text(
                  'Enter או אישור',
                  style: TextStyle(
                    fontSize: AppTokens.fontSM,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: AppTokens.spaceMD),
              if (_isRecording)
                ActionButton.neutral(
                  onPressed: () {
                    setState(() {
                      _isRecording = false;
                      if (_pressedKeys.isEmpty) {
                        _displayText = 'לא הוגדר קיצור';
                      }
                    });
                  },
                  icon: FluentIcons.stop_24_regular,
                  text: 'עצור הקלטה',
                )
              else
                ActionButton.neutral(
                  onPressed: () {
                    setState(() {
                      _pressedKeys.clear();
                      _isRecording = true;
                      _displayText = 'לחץ על המקשים...';
                    });
                  },
                  icon: FluentIcons.record_24_regular,
                  text: 'התחל הקלטה',
                ),
            ],
          ),
        ),
      ),
    );
  }
}
