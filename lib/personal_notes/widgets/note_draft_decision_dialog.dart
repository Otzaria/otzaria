import 'package:flutter/material.dart';

/// מה לעשות בהערה שנסגרת עם שינויים שלא נשמרו.
enum NoteDraftDecision { cancel, discard, saveDraft }

/// שאלת הסגירה המשותפת לעורך ההערות בדיאלוג ולעורך בחלונית הצד (issue #1303).
Future<NoteDraftDecision?> showNoteDraftDecisionDialog(BuildContext context) {
  return showDialog<NoteDraftDecision>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('אזהרה'),
      content: const Text('ההערה לא נשמרה. לשמור טיוטה?'),
      actions: [
        FilledButton.tonal(
          onPressed: () => Navigator.of(context).pop(NoteDraftDecision.cancel),
          child: const Text('ביטול'),
        ),
        FilledButton.tonal(
          onPressed: () => Navigator.of(context).pop(NoteDraftDecision.discard),
          child: const Text('סגור בלי לשמור'),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.of(context).pop(NoteDraftDecision.saveDraft),
          child: const Text('שמור טיוטה'),
        ),
      ],
    ),
  );
}
