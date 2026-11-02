import 'package:flutter/material.dart';
import 'package:otzaria/core/focus_repository.dart';
import 'package:otzaria/theme/app_tokens.dart';
import 'package:otzaria/widgets/controls/action_buttons.dart';
import 'package:otzaria/widgets/dialogs/app_dialog_header.dart';
import 'package:otzaria/widgets/text/rtl_text_field.dart';
import 'package:otzaria/widgets/misc/keyboard_dialog_navigation.dart';

/// דיאלוג הזנת טקסט: Enter בשדה שומר.
class InputDialog extends StatefulWidget {
  final String title;
  final String? subtitle;
  final String labelText;
  final String? hintText;
  final String initialValue;
  final TextInputType? keyboardType;
  final String cancelText;
  final String confirmText;
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
    this.obscureText = false,
  });

  @override
  State<InputDialog> createState() => _InputDialogState();
}

class _InputDialogState extends State<InputDialog>
    with DialogFocusRestorerMixin<InputDialog> {
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
    return DialogKeyboardNavigator(
      onConfirm: _submit,
      child: AlertDialog(
        title: AppDialogTitle(widget.title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.subtitle != null)
              Padding(
                padding: const EdgeInsets.only(bottom: AppTokens.spaceSM),
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
          ActionButton.neutral(
            text: widget.cancelText,
            onPressed: () => Navigator.of(context).pop(),
          ),
          ActionButton.recommended(
            text: widget.confirmText,
            onPressed: _submit,
          ),
        ],
      ),
    );
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
    ),
  );
}
