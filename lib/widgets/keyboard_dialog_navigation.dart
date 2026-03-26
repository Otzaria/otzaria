import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  keyboard_dialog_navigation.dart
//
//  מכיל את [DialogKeyboardNavigator] ו-[DialogNavigationMixin] יחדיו —
//  שניהם עוסקים אך ורק בניווט מקלדת בתוך דיאלוגים.
//
//  שאר קבצי ניווט מקלדת נשארים נפרדים:
//  • keyboard_navigator.dart  — ניווט Ctrl+Tab בין טאבים (מטרה שונה)
//  • keyboard_list_focus.dart — ניהול פוקוס ברשימות עם גלילה (מטרה שונה)
// ─────────────────────────────────────────────────────────────────────────────

/// Widget לניהול קיצורי מקלדת בדיאלוגים.
///
/// מספק:
/// - חיצים ◄► למעבר בין כפתורים
/// - Enter ללחיצה על הכפתור הממוקד
/// - Escape לביטול
/// - Enter בשדה טקסט → שליחת הטופס
class DialogKeyboardNavigator extends StatelessWidget {
  final Widget child;
  final VoidCallback? onConfirm;
  final VoidCallback? onCancel;
  final int focusedIndex;
  final ValueChanged<int> onFocusChange;
  final FocusNode? textFieldFocusNode;

  const DialogKeyboardNavigator({
    super.key,
    required this.child,
    this.onConfirm,
    this.onCancel,
    required this.focusedIndex,
    required this.onFocusChange,
    this.textFieldFocusNode,
  });

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: false,
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;

        // אם הפוקוס בשדה הטקסט, Enter שולח את הטופס
        if (textFieldFocusNode?.hasFocus ?? false) {
          if (event.logicalKey == LogicalKeyboardKey.enter) {
            onConfirm?.call();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        }

        // חיצים ◄► — מעבר בין כפתורים
        if (event.logicalKey == LogicalKeyboardKey.arrowLeft ||
            event.logicalKey == LogicalKeyboardKey.arrowRight) {
          onFocusChange(focusedIndex == 0 ? 1 : 0);
          return KeyEventResult.handled;
        }

        // Enter — לחיצה על הכפתור הממוקד
        if (event.logicalKey == LogicalKeyboardKey.enter) {
          if (focusedIndex == 1) {
            onConfirm?.call();
          } else {
            onCancel?.call();
          }
          return KeyEventResult.handled;
        }

        // Escape — ביטול
        if (event.logicalKey == LogicalKeyboardKey.escape) {
          onCancel?.call();
          return KeyEventResult.handled;
        }

        return KeyEventResult.ignored;
      },
      child: child,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  DialogNavigationMixin
// ─────────────────────────────────────────────────────────────────────────────

/// Mixin נוח לשימוש ב-[DialogKeyboardNavigator] מתוך StatefulWidget.
///
/// שימוש:
/// ```dart
/// class _MyDialogState extends State<MyDialog>
///     with DialogNavigationMixin<MyDialog> {
///
///   @override
///   Widget build(BuildContext context) {
///     return buildKeyboardNavigator(
///       child: ...,
///       onConfirm: _submit,
///       onCancel: () => Navigator.of(context).pop(),
///     );
///   }
/// }
/// ```
mixin DialogNavigationMixin<T extends StatefulWidget> on State<T> {
  /// 0 = Cancel, 1 = Confirm (ברירת מחדל: Confirm ממוקד)
  int focusedButtonIndex = 1;

  Widget buildKeyboardNavigator({
    required Widget child,
    required VoidCallback onConfirm,
    required VoidCallback onCancel,
    FocusNode? textFieldFocusNode,
  }) {
    return DialogKeyboardNavigator(
      focusedIndex: focusedButtonIndex,
      onFocusChange: (index) => setState(() => focusedButtonIndex = index),
      onConfirm: onConfirm,
      onCancel: onCancel,
      textFieldFocusNode: textFieldFocusNode,
      child: child,
    );
  }
}
