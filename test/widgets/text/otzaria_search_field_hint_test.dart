import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/widgets/text/otzaria_search_field.dart';

/// רמז מקוצר לשדה חיפוש (סבב ב', סעיף 34): כשהרמז המלא לא נכנס ברוחב הפנוי
/// בשדה מוצג [OtzariaSearchField.compactHintText]. ההחלטה לפי מדידה של
/// הרוחב בפועל ושל הגדלת הטקסט, לא לפי סף קבוע של רוחב חלון.
void main() {
  const fullHint = 'איתור ספר או מחבר בספריית אוצריא';
  const compactHint = 'איתור ספר או מחבר';

  Future<void> pumpField(
    WidgetTester tester, {
    required double width,
    double textScale = 1,
    String? compact = compactHint,
  }) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: Center(
              child: SizedBox(
                width: width,
                child: OtzariaSearchField(
                  controller: controller,
                  hintText: fullHint,
                  compactHintText: compact,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  String? shownHint(WidgetTester tester) =>
      tester.widget<TextField>(find.byType(TextField)).decoration!.hintText;

  testWidgets('רוחב שבו הרמז המלא נכנס: מוצג הרמז המלא', (tester) async {
    await pumpField(tester, width: 800);

    expect(shownHint(tester), fullHint);
  });

  testWidgets('שדה צר שהרמז המלא לא נכנס בו: מוצג הרמז המקוצר', (tester) async {
    await pumpField(tester, width: 150);

    expect(shownHint(tester), compactHint);
  });

  testWidgets('הגדלת טקסט מקצרת את הרמז גם בשדה שבגודל רגיל היה מכיל אותו', (
    tester,
  ) async {
    await pumpField(tester, width: 800);
    expect(shownHint(tester), fullHint);

    await pumpField(tester, width: 800, textScale: 2.0);

    expect(shownHint(tester), compactHint);
  });

  testWidgets('בלי רמז מקוצר הרמז המלא נשאר בכל רוחב', (tester) async {
    await pumpField(tester, width: 150, compact: null);

    expect(shownHint(tester), fullHint);
  });
}
