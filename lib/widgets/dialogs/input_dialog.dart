import 'package:flutter/material.dart';
import 'package:otzaria/core/focus_repository.dart';
import 'package:otzaria/widgets/text/rtl_text_field.dart';
import 'package:otzaria/widgets/misc/keyboard_dialog_navigation.dart';

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

class _InputDialogState extends State<InputDialog>
    with DialogNavigationMixin, DialogFocusRestorerMixin<InputDialog> {
  late final TextEditingController _controller;
  final FocusNode _textFieldFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
    registerDialogFocusRestorer(_textFieldFocusNode);
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
    final cs = Theme.of(context).colorScheme;
    final color = isConfirm ? (widget.confirmColor ?? cs.primary) : null;
    final foregroundColor = color == null
        ? null
        : (ThemeData.estimateBrightnessForColor(color) == Brightness.dark
              ? cs.surface
              : cs.onSurface);

    final showHover = isFocused && !_textFieldFocusNode.hasFocus;

    if (isConfirm) {
      return FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: showHover ? color!.withValues(alpha: 0.9) : color,
          foregroundColor: foregroundColor,
        ),
        child: Text(text),
      );
    } else {
      return FilledButton.tonal(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: showHover
              ? cs.secondaryContainer.withValues(alpha: 0.9)
              : cs.secondaryContainer,
          foregroundColor: cs.onSecondaryContainer,
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
