import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:otzaria/widgets/controls/action_buttons.dart';
import 'package:otzaria/widgets/dialogs/app_dialog_frame.dart';
import 'package:otzaria/widgets/dialogs/app_dialog_header.dart';

/// מה לעשות בהערה שנסגרת עם שינויים שלא נשמרו.
enum NoteDraftDecision { cancel, discard, saveDraft }

/// שאלת הסגירה המשותפת לעורך ההערות בדיאלוג ולעורך בחלונית הצד (issue #1303).
Future<NoteDraftDecision?> showNoteDraftDecisionDialog(BuildContext context) {
  return showDialog<NoteDraftDecision>(
    context: context,
    builder: (context) => AppDialogFrame(
      // שלוש פעולות לא נכנסות בשורה אחת ברוחב small.
      size: AppDialogSize.medium,
      title: 'אזהרה',
      icon: FluentIcons.warning_24_regular,
      tone: AppDialogHeaderTone.error,
      actions: [
        ActionButton.neutral(
          text: 'ביטול',
          onPressed: () => Navigator.of(context).pop(NoteDraftDecision.cancel),
        ),
        ActionButton.neutral(
          errorText: true,
          text: 'סגור בלי לשמור',
          onPressed: () => Navigator.of(context).pop(NoteDraftDecision.discard),
        ),
        ActionButton.recommended(
          text: 'שמור טיוטה',
          onPressed: () =>
              Navigator.of(context).pop(NoteDraftDecision.saveDraft),
        ),
      ],
      child: Text(
        'ההערה לא נשמרה. לשמור טיוטה?',
        style:
            Theme.of(context).dialogTheme.contentTextStyle ??
            Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
      ),
    ),
  );
}
