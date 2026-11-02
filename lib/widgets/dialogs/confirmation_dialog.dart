import 'package:flutter/material.dart';
import 'package:otzaria/settings/l10n/settings_l10n_exports.dart';
import 'package:otzaria/widgets/dialogs/app_dialogs.dart';
import 'package:otzaria/widgets/dialogs/dialog_teardown.dart';

/// דיאלוג אישור — thin wrapper מעל [AppDialog].
/// [isDangerous] מפנה ל-[AppDialog.warning] (ביטול primary, אישור error).
class _ConfirmationDialog extends StatelessWidget {
  final String title;
  final String content;

  /// null = תווית ברירת המחדל בשפת הממשק.
  final String? cancelText;
  final String? confirmText;
  final bool isDangerous;

  /// תג האייקון: מה מאשרים. null = אייקון המשפחה.
  final IconData? icon;

  const _ConfirmationDialog({
    required this.title,
    required this.content,
    this.cancelText,
    this.confirmText,
    this.isDangerous = false,
    this.icon,
  });

  @override
  Widget build(BuildContext context) => isDangerous
      ? AppDialog.warning(
          title: title,
          content: content,
          cancelText: cancelText,
          confirmText: confirmText ?? context.settingsText('אישור'),
          icon: icon,
        )
      : AppDialog.twoActions(
          title: title,
          content: content,
          cancelText: cancelText,
          confirmText: confirmText,
          icon: icon,
        );
}

Future<bool?> showConfirmationDialog({
  required BuildContext context,
  required String title,
  required String content,
  String? cancelText,
  String? confirmText,
  bool isDangerous = false,
  bool barrierDismissible = true,
  IconData? icon,
}) => showDialogUntilTornDown<bool>(
  context: context,
  barrierDismissible: barrierDismissible,
  // הדיאלוג נבנה ב-Overlay ולכן אינו יורש את הכיווניות של המסך שפתח אותו.
  builder: (_) => Directionality(
    textDirection: Directionality.of(context),
    child: _ConfirmationDialog(
      title: title,
      content: content,
      cancelText: cancelText,
      confirmText: confirmText,
      isDangerous: isDangerous,
      icon: icon,
    ),
  ),
);
