import 'package:flutter/material.dart';
import 'package:otzaria/widgets/rtl_text_field.dart';
import 'package:otzaria/widgets/mixins/dialog_navigation_mixin.dart';

/// דיאלוג הזנת טקסט עם תמיכה באנטר וחיצים
class InputDialog extends StatefulWidget {
  final String title;
  final String? subtitle;
  final String labelText;
  final String? hintText;
  final String initialValue;
  final TextInputType? keyboardType;
  final String cancelText;
  final String confirmText;
  final Color? confirmColor;
  final bool obscureText;

  const InputDialog({
    super.key,
    required this.title,
    this.subtitle,
    required this.labelText,
    this.hintText,
    this.initialValue = '',
    this.keyboardType,
    this.cancelText = 'ביטול',
    this.confirmText = 'שמור',
    this.confirmColor,
    this.obscureText = false,
  });

  @override
  State<InputDialog> createState() => _InputDialogState();
}

class _InputDialogState extends State<InputDialog> with DialogNavigationMixin {
  late final TextEditingController _controller;
  final FocusNode _textFieldFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
    // תן פוקוס לשדה הטקסט אחרי שהדיאלוג נפתח
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _textFieldFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _textFieldFocusNode.dispose();
    super.dispose();
  }

  void _submit() {
    Navigator.of(context).pop(_controller.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    return buildKeyboardNavigator(
      onConfirm: _submit,
      onCancel: () => Navigator.of(context).pop(),
      textFieldFocusNode: _textFieldFocusNode,
      child: AlertDialog(
        title: Text(widget.title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.subtitle != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: Text(
                  widget.subtitle!,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            RtlTextField(
              controller: _controller,
              focusNode: _textFieldFocusNode,
              keyboardType: widget.keyboardType,
              obscureText: widget.obscureText,
              decoration: InputDecoration(
                labelText: widget.labelText,
                hintText: widget.hintText,
              ),
              onSubmitted: (_) => _submit(),
            ),
          ],
        ),
        actions: [
          _buildButton(
            text: widget.cancelText,
            isFocused: focusedButtonIndex == 0,
            onPressed: () => Navigator.of(context).pop(),
          ),
          _buildButton(
            text: widget.confirmText,
            isFocused: focusedButtonIndex == 1,
            isConfirm: true,
            onPressed: _submit,
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
        ? (widget.confirmColor ?? Theme.of(context).primaryColor)
        : null;

    final showHover = isFocused && !_textFieldFocusNode.hasFocus;

    if (isConfirm) {
      return FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: showHover
              ? (color ?? Theme.of(context).primaryColor).withValues(alpha: 0.9)
              : null,
        ),
        child: Text(text),
      );
    } else {
      return TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          backgroundColor: showHover
              ? Theme.of(context).primaryColor.withValues(alpha: 0.1)
              : null,
        ),
        child: Text(text),
      );
    }
  }
}

/// הצגת דיאלוג הזנת טקסט
Future<String?> showInputDialog({
  required BuildContext context,
  required String title,
  String? subtitle,
  required String labelText,
  String? hintText,
  String initialValue = '',
  TextInputType? keyboardType,
  String cancelText = 'ביטול',
  String confirmText = 'שמור',
  Color? confirmColor,
}) {
  return showDialog<String>(
    context: context,
    builder: (context) => InputDialog(
      title: title,
      subtitle: subtitle,
      labelText: labelText,
      hintText: hintText,
      initialValue: initialValue,
      keyboardType: keyboardType,
      cancelText: cancelText,
      confirmText: confirmText,
      confirmColor: confirmColor,
    ),
  );
}
