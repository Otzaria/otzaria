import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Widget גנרי לניהול ניווט מקלדת
/// תומך ב-Ctrl+Tab / Ctrl+Shift+Tab למעבר בין טאבים
/// ומאפשר ניווט עם חיצים ו-Tab בתוך תוכן הטאב
class KeyboardNavigator extends StatelessWidget {
  final Widget child;
  final int currentTabIndex;
  final int totalTabs;
  final ValueChanged<int> onTabChange;
  final FocusNode? contentFocusNode;
  final VoidCallback? onBack;

  const KeyboardNavigator({
    super.key,
    required this.child,
    required this.currentTabIndex,
    required this.totalTabs,
    required this.onTabChange,
    this.contentFocusNode,
    this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: false,
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) {
          return KeyEventResult.ignored;
        }

        // Escape - חזרה (אם מוגדר callback)
        if (event.logicalKey == LogicalKeyboardKey.escape && onBack != null) {
          onBack!();
          return KeyEventResult.handled;
        }

        // Backspace - חזרה (רק אם אין TextField ממוקד)
        if (event.logicalKey == LogicalKeyboardKey.backspace && onBack != null) {
          final focusedWidget =
              FocusManager.instance.primaryFocus?.context?.widget;
          if (focusedWidget is! EditableText && focusedWidget is! TextField) {
            onBack!();
            return KeyEventResult.handled;
          }
        }

        // Ctrl + Tab - טאב הבא
        if (event.logicalKey == LogicalKeyboardKey.tab &&
            HardwareKeyboard.instance.isControlPressed &&
            !HardwareKeyboard.instance.isShiftPressed) {
          final nextIndex = (currentTabIndex + 1) % totalTabs;
          onTabChange(nextIndex);
          return KeyEventResult.handled;
        }

        // Ctrl + Shift + Tab - טאב קודם
        if (event.logicalKey == LogicalKeyboardKey.tab &&
            HardwareKeyboard.instance.isControlPressed &&
            HardwareKeyboard.instance.isShiftPressed) {
          final prevIndex = (currentTabIndex - 1 + totalTabs) % totalTabs;
          onTabChange(prevIndex);
          return KeyEventResult.handled;
        }

        return KeyEventResult.ignored;
      },
      child: child,
    );
  }
}
