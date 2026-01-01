import 'package:flutter/material.dart';
import 'package:otzaria/widgets/mixins/dialog_navigation_mixin.dart';

/// דיאלוג אישור עם תמיכה באנטר וחיצים
class ConfirmationDialog extends StatefulWidget {
  final String title;
  final String content;
  final String cancelText;
  final String confirmText;
  final Color? confirmColor;
  final bool isDangerous;

  const ConfirmationDialog({
    super.key,
    required this.title,
    required this.content,
    this.cancelText = 'ביטול',
    this.confirmText = 'אישור',
    this.confirmColor,
    this.isDangerous = false,
  });

  @override
  State<ConfirmationDialog> createState() => _ConfirmationDialogState();
}

class _ConfirmationDialogState extends State<ConfirmationDialog>
    with DialogNavigationMixin {
  @override
  Widget build(BuildContext context) {
    return buildKeyboardNavigator(
      onConfirm: () => Navigator.of(context).pop(true),
      onCancel: () => Navigator.of(context).pop(false),
      child: AlertDialog(
        title: Text(widget.title),
        content: Text(widget.content),
        actions: [
          _buildButton(
            text: widget.cancelText,
            isFocused: focusedButtonIndex == 0,
            onPressed: () => Navigator.of(context).pop(false),
          ),
          _buildButton(
            text: widget.confirmText,
            isFocused: focusedButtonIndex == 1,
            isConfirm: true,
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );
  }

  Widget _buildButton({
    required String text,
    required bool isFocused,
    required VoidCallback onPressed,
    bool isConfirm = false,
  }) {
    final color = isConfirm
        ? (widget.confirmColor ??
            (widget.isDangerous ? Colors.red : Theme.of(context).primaryColor))
        : null;

    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        backgroundColor: isFocused
            ? (color ?? Theme.of(context).primaryColor).withValues(alpha: 0.1)
            : null,
        foregroundColor: color,
      ),
      child: Text(
        text,
        style: TextStyle(
          fontWeight: isFocused ? FontWeight.bold : FontWeight.normal,
        ),
      ),
    );
  }
}

/// הצגת דיאלוג אישור
Future<bool?> showConfirmationDialog({
  required BuildContext context,
  required String title,
  required String content,
  String cancelText = 'ביטול',
  String confirmText = 'אישור',
  Color? confirmColor,
  bool isDangerous = false,
  bool barrierDismissible = true,
}) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: barrierDismissible,
    builder: (context) => ConfirmationDialog(
      title: title,
      content: content,
      cancelText: cancelText,
      confirmText: confirmText,
      confirmColor: confirmColor,
      isDangerous: isDangerous,
    ),
  );
}
