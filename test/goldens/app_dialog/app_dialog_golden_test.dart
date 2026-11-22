import 'package:flutter/material.dart';
import 'package:otzaria/widgets/dialogs/app_dialogs.dart';

import '../golden_harness.dart';

void main() {
  for (final brightness in Brightness.values) {
    goldenTest('AppDialog.twoActions, ${brightness.name}', (tester) async {
      await pumpGolden(
        tester,
        const AppDialog.twoActions(
          title: 'מחיקת קבוצה',
          content: 'הקבוצה "ספרי יסוד" וכל הספרים שבה יוסרו מהרשימה. להמשיך?',
          confirmText: 'מחיקה',
        ),
        brightness: brightness,
        size: const Size(640, 360),
      );
      await expectGolden('app_dialog_two_actions.${brightness.name}');
    });
  }

  // חלון צר (מתחת ל-600, DD-16): הדיאלוג ממלא את הרוחב, בבהיר ובכהה.
  for (final brightness in Brightness.values) {
    goldenTest('AppDialog.twoActions, חלון צר, ${brightness.name}', (
      tester,
    ) async {
      await pumpGolden(
        tester,
        const AppDialog.twoActions(
          title: 'מחיקת קבוצה',
          content: 'הקבוצה "ספרי יסוד" וכל הספרים שבה יוסרו מהרשימה. להמשיך?',
          confirmText: 'מחיקה',
        ),
        brightness: brightness,
        size: const Size(360, 420),
      );
      await expectGolden('app_dialog_two_actions_narrow.${brightness.name}');
    });
  }

  // תוכן ארוך: הדיאלוג נעצר בגובה המרבי וגולל, ושורת הפעולות נשארת.
  goldenTest('AppDialog.twoActions, תוכן ארוך, light', (tester) async {
    await pumpGolden(
      tester,
      AppDialog.twoActions(
        title: 'הסרת ספרים מהמעקב',
        content: List.filled(
          14,
          'הספרים שסימנת יוסרו מרשימת המעקב, והתקדמות הלימוד שלהם תימחק.',
        ).join(' '),
        confirmText: 'הסרה',
      ),
      size: const Size(480, 360),
    );
    await expectGolden('app_dialog_two_actions_long.light');
  });

  goldenTest('AppDialog.warning, dark', (tester) async {
    await pumpGolden(
      tester,
      const AppDialog.warning(
        title: 'שינויים שלא נשמרו',
        content: 'יש בטופס שינויים שלא נשמרו. לצאת בלי לשמור?',
        confirmText: 'צא בלי לשמור',
      ),
      brightness: Brightness.dark,
      size: const Size(640, 360),
    );
    await expectGolden('app_dialog_warning.dark');
  });

  goldenTest('AppDialog.warning, light', (tester) async {
    await pumpGolden(
      tester,
      const AppDialog.warning(
        title: 'שינויים שלא נשמרו',
        content: 'יש בטופס שינויים שלא נשמרו. לצאת בלי לשמור?',
        confirmText: 'צא בלי לשמור',
      ),
      size: const Size(640, 360),
    );
    await expectGolden('app_dialog_warning.light');
  });
}
