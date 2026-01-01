import 'package:flutter/material.dart';
import 'package:otzaria/widgets/dialog_keyboard_navigator.dart';

mixin DialogNavigationMixin<T extends StatefulWidget> on State<T> {
  int focusedButtonIndex = 1; // 0 = Cancel, 1 = Confirm

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
