import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/settings/dialogs/color_picker_dialog.dart';
import 'package:otzaria/settings/l10n/settings_l10n_exports.dart';
import 'package:otzaria/theme/app_seed_colors.dart';

void main() {
  Widget wrap(SettingsLanguage language) => MaterialApp(
    home: Directionality(
      textDirection: language.textDirection,
      child: SettingsTextScope(
        language: language,
        child: Scaffold(
          body: ColorPickerTile(
            currentColor: AppSeedColors.darkBrown,
            defaultColor: AppSeedColors.darkBrown,
            onChanged: (_) {},
          ),
        ),
      ),
    ),
  );

  String label(String hebrew, SettingsLanguage language) =>
      resolveSettingsText(hebrew, language: language);

  Future<void> openPicker(
    WidgetTester tester,
    SettingsLanguage language,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(wrap(language));
    await tester.tap(find.text(label('שינוי צבע', language)));
    await tester.pumpAndSettle();
  }

  group('שם הצבע הנבחר', () {
    testWidgets('באנגלית מוצג מתורגם בשורת ההגדרה ובכותרת הדיאלוג', (
      tester,
    ) async {
      await openPicker(tester, SettingsLanguage.english);

      // פעמיים: בשורת ההגדרה שמאחורי הדיאלוג, ובכותרת הדיאלוג
      expect(find.text('Golden brown'), findsNWidgets(2));
      expect(find.text('חום זהבהב'), findsNothing);
      expect(find.text('Choose a base color'), findsOneWidget);
    });

    testWidgets('בעברית מוצג המקור', (tester) async {
      await openPicker(tester, SettingsLanguage.hebrew);

      expect(find.text('חום זהבהב'), findsNWidgets(2));
      expect(find.text('בחר צבע בסיס'), findsOneWidget);
    });
  });

  group('פריסת לוח הצבעים', () {
    // לוח הצבעים אינו טקסט; אם הוא יורש את כיוון ההגדרות, סדר העיגולים
    // מתהפך כשעוברים לאנגלית והמשתמש מחפש את הצבע במקום שבו הוא זכר אותו.
    List<Offset> swatchCenters(
      WidgetTester tester,
      SettingsLanguage language,
    ) => AppSeedColors.options
        .map(
          (entry) =>
              tester.getCenter(find.byTooltip(label(entry.name, language))),
        )
        .toList();

    for (final language in SettingsLanguage.values) {
      testWidgets('[${language.code}] העיגולים מסודרים מימין לשמאל', (
        tester,
      ) async {
        await openPicker(tester, language);
        final centers = swatchCenters(tester, language);

        for (var i = 1; i < centers.length; i++) {
          final isSameRow = centers[i].dy == centers[i - 1].dy;
          expect(
            isSameRow ? centers[i].dx : centers[i].dy,
            isSameRow
                ? lessThan(centers[i - 1].dx)
                : greaterThan(centers[i - 1].dy),
            reason: 'צבע ${AppSeedColors.options[i].name} אינו במקומו',
          );
        }
      });
    }

    testWidgets('מיקומי העיגולים זהים בשתי השפות', (tester) async {
      await openPicker(tester, SettingsLanguage.hebrew);
      final hebrew = swatchCenters(tester, SettingsLanguage.hebrew);

      await tester.tap(find.text(label('סגור', SettingsLanguage.hebrew)));
      await tester.pumpAndSettle();

      await openPicker(tester, SettingsLanguage.english);
      final english = swatchCenters(tester, SettingsLanguage.english);

      // רוחב הדיאלוג עשוי להשתנות עם אורך הכותרת — משווים מיקום יחסי לצבע הראשון
      expect(
        english.map((c) => c - english.first).toList(),
        hebrew.map((c) => c - hebrew.first).toList(),
      );
    });
  });
}
