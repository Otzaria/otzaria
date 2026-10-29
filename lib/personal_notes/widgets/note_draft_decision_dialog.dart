import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:otzaria/widgets/controls/action_buttons.dart';
import 'package:otzaria/widgets/dialogs/app_dialog_header.dart';

/// מה לעשות בהערה שנסגרת עם שינויים שלא נשמרו.
enum NoteDraftDecision { cancel, discard, saveDraft }

/// שאלת הסגירה המשותפת לעורך ההערות בדיאלוג ולעורך בחלונית הצד (issue #1303).
Future<NoteDraftDecision?> showNoteDraftDecisionDialog(BuildContext context) {
  return showDialog<NoteDraftDecision>(
    context: context,
    builder: (context) => AlertDialog(
      title: const AppDialogTitle(
        'אזהרה',
        icon: FluentIcons.warning_24_regular,
        tone: AppDialogHeaderTone.error,
      ),
      content: const Text('ההערה לא נשמרה. לשמור טיוטה?'),
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
    ),
  );
}
