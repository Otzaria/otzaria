import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
      autofocus: textFieldFocusNode == null,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) {
          return KeyEventResult.ignored;
        }

        // אם הפוקוס בשדה הטקסט, אנטר שולח את הטופס
        if (textFieldFocusNode?.hasFocus ?? false) {
          if (event.logicalKey == LogicalKeyboardKey.enter) {
            onConfirm?.call();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        }

        // חיצים - מעבר בין כפתורים
        if (event.logicalKey == LogicalKeyboardKey.arrowLeft ||
            event.logicalKey == LogicalKeyboardKey.arrowRight) {
          onFocusChange(focusedIndex == 0 ? 1 : 0);
          return KeyEventResult.handled;
        }

        // אנטר - לחיצה על הכפתור הממוקד
        if (event.logicalKey == LogicalKeyboardKey.enter) {
          if (focusedIndex == 1) {
            onConfirm?.call();
          } else {
            onCancel?.call();
          }
          return KeyEventResult.handled;
        }

        // Escape - ביטול
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
