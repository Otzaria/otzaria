// lib/widgets/dialogs/blocking_progress_dialog.dart
// דיאלוג התקדמות חוסם לפעולה ארוכה (DD-07, משפחת "תהליך").

import 'package:flutter/material.dart';
import 'package:otzaria/settings/l10n/settings_l10n_exports.dart';
import 'package:otzaria/theme/app_surfaces.dart';
import 'package:otzaria/theme/app_tokens.dart';
import 'package:otzaria/widgets/controls/action_buttons.dart';
import 'package:otzaria/widgets/dialogs/app_dialog_frame.dart';
import 'package:otzaria/widgets/dialogs/app_dialogs.dart';

/// מריץ את [task] מאחורי דיאלוג `small` שאי אפשר לסגור: רצועה עם [title],
/// ספינר ו-[message]. הדיאלוג נסגר כשהמשימה מסתיימת, גם בשגיאה, והתוצאה (או
/// השגיאה) עוברת לקורא. [onCancel] מוסיף כפתור ביטול; המשימה עצמה צריכה
/// להסתיים כדי שהדיאלוג ייסגר.
Future<T> runWithBlockingProgress<T>({
  required BuildContext context,
  required String title,
  required Future<T> Function() task,
  String? message,
  IconData icon = AppDialogIcons.progress,
  VoidCallback? onCancel,
  String? cancelText,
}) async {
  final close = showBlockingProgress(
    context: context,
    title: title,
    message: message,
    icon: icon,
    onCancel: onCancel,
    cancelText: cancelText,
  );
  try {
    return await task();
  } finally {
    close();
  }
}

/// הדיאלוג של [runWithBlockingProgress], לזרימה שיש בה כמה נקודות יציאה.
/// מחזיר פונקציה שסוגרת אותו; קריאה נוספת לא עושה דבר.
VoidCallback showBlockingProgress({
  required BuildContext context,
  required String title,
  String? message,
  IconData icon = AppDialogIcons.progress,
  VoidCallback? onCancel,
  String? cancelText,
}) {
  final navigator = Navigator.of(context, rootNavigator: true);
  final direction = Directionality.of(context);
  final route = DialogRoute<void>(
    context: context,
    barrierDismissible: false,
    barrierColor:
        DialogTheme.of(context).barrierColor ??
        Theme.of(context).dialogTheme.barrierColor ??
        AppSurfaces.scrim(Theme.of(context).colorScheme),
    themes: InheritedTheme.capture(from: context, to: navigator.context),
    traversalEdgeBehavior: TraversalEdgeBehavior.closedLoop,
    builder: (_) => Directionality(
      textDirection: direction,
      child: _BlockingProgressDialog(
        title: title,
        message: message,
        icon: icon,
        onCancel: onCancel,
        cancelText: cancelText,
      ),
    ),
  );
  navigator.push(route);
  return () {
    if (route.isActive) route.navigator?.removeRoute(route);
  };
}

class _BlockingProgressDialog extends StatelessWidget {
  const _BlockingProgressDialog({
    required this.title,
    required this.message,
    required this.icon,
    required this.onCancel,
    required this.cancelText,
  });

  final String title;
  final String? message;
  final IconData icon;
  final VoidCallback? onCancel;

  /// null = "ביטול" בשפת הממשק.
  final String? cancelText;

  @override
  Widget build(BuildContext context) {
    final text = message;
    return AppDialogFrame(
      title: title,
      icon: icon,
      size: AppDialogSize.small,
      closeEnabled: false,
      showClose: false,
      actions: [
        if (onCancel != null)
          ActionButton.neutral(
            text: cancelText ?? context.settingsText('ביטול'),
            onPressed: onCancel,
          ),
      ],
      child: Row(
        mainAxisAlignment: text == null
            ? MainAxisAlignment.center
            : MainAxisAlignment.start,
        children: [
          const SizedBox.square(
            dimension: AppTokens.iconLG,
            child: CircularProgressIndicator(strokeWidth: 3),
          ),
          if (text != null) ...[
            const SizedBox(width: AppTokens.spaceMD),
            Expanded(
              child: Semantics(liveRegion: true, child: Text(text)),
            ),
          ],
        ],
      ),
    );
  }
}
