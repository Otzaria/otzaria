import 'package:flutter/material.dart';
import 'package:otzaria/widgets/dialogs/app_dialogs.dart';

/// דיאלוג אישור — thin wrapper מעל [AppDialog].
/// [isDangerous] מפנה ל-[AppDialog.warning] (ביטול primary, אישור error).
class ConfirmationDialog extends StatelessWidget {
  final String title;
  final String content;
  final String cancelText;
  final String confirmText;
  final bool isDangerous;

  const ConfirmationDialog({
    super.key,
    required this.title,
    required this.content,
    this.cancelText = 'ביטול',
    this.confirmText = 'אישור',
    this.isDangerous = false,
  });

  @override
  Widget build(BuildContext context) => isDangerous
      ? AppDialog.warning(
          title: title,
          content: content,
          cancelText: cancelText,
          confirmText: confirmText,
        )
      : AppDialog.twoActions(
          title: title,
          content: content,
          cancelText: cancelText,
          confirmText: confirmText,
        );
}

Future<bool?> showConfirmationDialog({
  required BuildContext context,
  required String title,
  required String content,
  String cancelText = 'ביטול',
  String confirmText = 'אישור',
  bool isDangerous = false,
  bool barrierDismissible = true,
}) => showDialog<bool>(
  context: context,
  barrierDismissible: barrierDismissible,
  builder: (_) => ConfirmationDialog(
    title: title,
    content: content,
    cancelText: cancelText,
    confirmText: confirmText,
    isDangerous: isDangerous,
  ),
);
