import 'package:flutter/material.dart';
import 'package:otzaria/settings/l10n/settings_l10n_exports.dart';
import 'package:otzaria/widgets/dialogs/dialogs_exports.dart';

Future<String?> passwordDialog(BuildContext context) async {
  return await showDialog<String?>(
    context: context,
    barrierDismissible: false,
    // התוויות נפתרות מההקשר שפתח את הדיאלוג, שבו שפת הממשק ידועה.
    builder: (_) {
      return InputDialog(
        title: context.settingsText('הזנת סיסמה'),
        labelText: context.settingsText('סיסמה'),
        keyboardType: TextInputType.visiblePassword,
        obscureText: true,
        confirmText: context.settingsText('אישור'),
        cancelText: context.settingsText('ביטול'),
      );
    },
  );
}
