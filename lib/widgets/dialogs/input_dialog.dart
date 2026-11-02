import 'package:flutter/material.dart';
import 'package:otzaria/settings/l10n/settings_l10n_exports.dart';
import 'package:otzaria/core/focus_repository.dart';
import 'package:otzaria/theme/app_tokens.dart';
import 'package:otzaria/widgets/controls/action_buttons.dart';
import 'package:otzaria/widgets/dialogs/app_dialog_frame.dart';
import 'package:otzaria/widgets/dialogs/app_dialogs.dart';
import 'package:otzaria/widgets/dialogs/dialog_teardown.dart';
import 'package:otzaria/widgets/text/rtl_text_field.dart';

/// דיאלוג הזנת טקסט: Enter בשדה שומר.
class InputDialog extends StatefulWidget {
  final String title;
  final String? subtitle;
  final String labelText;
  final String? hintText;
  final String initialValue;
  final TextInputType? keyboardType;

  /// null = תווית ברירת המחדל בשפת הממשק.
  final String? cancelText;
  final String? confirmText;
  final bool obscureText;

  /// תג האייקון: מה מזינים. null = אייקון משפחת הקלט.
  final IconData? icon;

  const InputDialog({
    super.key,
    required this.title,
    this.subtitle,
    required this.labelText,
    this.hintText,
    this.initialValue = '',
    this.keyboardType,
    this.cancelText,
    this.confirmText,
    this.obscureText = false,
    this.icon,
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
    return AppDialogFrame(
      title: widget.title,
      icon: widget.icon ?? AppDialogIcons.input,
      size: AppDialogSize.small,
      onConfirm: _submit,
      actions: [
        ActionButton.neutral(
          text: widget.cancelText ?? context.settingsText('ביטול'),
          onPressed: () => Navigator.of(context).pop(),
        ),
        ActionButton.recommended(
          text: widget.confirmText ?? context.settingsText('שמור'),
          onPressed: _submit,
        ),
      ],
      child: Column(
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
  String? cancelText,
  String? confirmText,
  IconData? icon,
}) {
  return showDialogUntilTornDown<String>(
    context: context,
    builder: (_) => Directionality(
      textDirection: Directionality.of(context),
      child: InputDialog(
        title: title,
        subtitle: subtitle,
        labelText: labelText,
        hintText: hintText,
        initialValue: initialValue,
        keyboardType: keyboardType,
        cancelText: cancelText,
        confirmText: confirmText,
        icon: icon,
      ),
    ),
  );
}
