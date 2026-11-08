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
