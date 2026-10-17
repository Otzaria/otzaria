import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/text_book/view/text_book_export_dialog.dart';
import 'package:otzaria/text_display/models/text_display_profile.dart';

/// דיאלוג ייצוא הספר: נפתח בלי חריגה ברוחב מסך רחב וצר, ברירת המחדל מפרופיל
/// ערוץ הייצוא, והבחירה חוזרת בלי לשנות את הפרופיל.
void main() {
  Future<Future<TextBookExportChoice?>> open(
    WidgetTester tester, {
    required double width,
    required TextDisplayProfile profile,
    bool hasDivineNames = true,
  }) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    late Future<TextBookExportChoice?> result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => result = showTextBookExportDialog(
                context,
                profile: profile,
                hasDivineNames: hasDivineNames,
              ),
              child: const Text('ייצוא'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('ייצוא'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    return result;
  }

  for (final width in [1400.0, 360.0]) {
    testWidgets('רוחב $width — נפתח, וברירת המחדל מהפרופיל חוזרת כמות שהיא', (
      tester,
    ) async {
      const profile = TextDisplayProfile(
        holyName: HolyNameDisplay.hehApostrophe,
        divineNames: DivineNamesDisplay.substitute,
      );
      final result = await open(tester, width: width, profile: profile);
      expect(find.text('שאר שמות הקודש'), findsOneWidget);
      expect(find.text('בחר פורמט לייצוא'), findsOneWidget);

      await tester.tap(find.text('Word'));
      await tester.pumpAndSettle();
      final choice = await result;
      expect(choice?.format, TextBookExportFormat.word);
      expect(choice?.holyName, HolyNameDisplay.hehApostrophe);
      expect(choice?.divineNames, DivineNamesDisplay.substitute);
    });

    testWidgets('רוחב $width — שינוי בדיאלוג חוזר, והפרופיל לא משתנה', (
      tester,
    ) async {
      const profile = TextDisplayProfile();
      final result = await open(tester, width: width, profile: profile);

      await tester.tap(find.text('בכינוי'));
      await tester.tap(find.text('יקוק'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('יי').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('טקסט'));
      await tester.pumpAndSettle();
      final choice = await result;
      expect(choice?.format, TextBookExportFormat.text);
      expect(choice?.holyName, HolyNameDisplay.doubleYod);
      expect(choice?.divineNames, DivineNamesDisplay.substitute);
      expect(profile.divineNames, DivineNamesDisplay.asIs);
      expect(profile.holyName, HolyNameDisplay.kufKuf);
    });
  }

  testWidgets('בלי מופעים בספר — אין בורר לשאר השמות', (tester) async {
    final result = await open(
      tester,
      width: 1400,
      profile: const TextDisplayProfile(),
      hasDivineNames: false,
    );
    expect(find.text('שאר שמות הקודש'), findsNothing);
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(await result, isNull);
  });
}
