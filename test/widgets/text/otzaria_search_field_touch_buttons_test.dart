import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/widgets/text/otzaria_search_field.dart';

/// q4: בשדה חיפוש צר במסך מגע כפתורי הפעולה בתוכו הם 40 (והשדה 40), אבל רק
/// כשתיבת הקלט נשארת לפחות ב-116 פיקסלים; אחרת הם נשארים 26 והשדה 36.
void main() {
  final icons = [
    FluentIcons.filter_24_regular,
    FluentIcons.book_24_regular,
    FluentIcons.globe_24_regular,
    FluentIcons.settings_24_regular,
  ];

  Future<void> pumpField(
    WidgetTester tester, {
    required double width,
    required int buttons,
    bool touch = true,
    bool slim = true,
    bool actionsBelow = false,
    bool withClear = true,
  }) async {
    final controller = TextEditingController(text: 'בראשית');
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          materialTapTargetSize: touch
              ? MaterialTapTargetSize.padded
              : MaterialTapTargetSize.shrinkWrap,
        ),
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: Align(
              alignment: Alignment.topCenter,
              child: SizedBox(
                width: width,
                child: OtzariaSearchField(
                  controller: controller,
                  hintText: 'איתור ספר או מחבר',
                  slim: slim,
                  actionsBelow: actionsBelow,
                  onClear: withClear ? () {} : null,
                  trailingActions: [
                    for (var i = 0; i < buttons; i++)
                      OtzariaSearchFieldButton(
                        icon: icons[i],
                        tooltip: 'פעולה $i',
                        onPressed: () {},
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  double buttonSize(WidgetTester tester) =>
      tester.getSize(find.byType(OtzariaSearchFieldButton).first).width;

  double fieldHeight(WidgetTester tester) =>
      tester.getSize(find.byType(TextField)).height;

  group('מגע, שדה צר', () {
    testWidgets('שני כפתורים ב-320: 40 והשדה 40', (tester) async {
      await pumpField(tester, width: 320, buttons: 2);
      expect(buttonSize(tester), 40);
      expect(fieldHeight(tester), 40);
    });

    testWidgets('ארבעה כפתורים ב-320: אין מקום, נשארים 26 והשדה 36', (
      tester,
    ) async {
      await pumpField(tester, width: 320, buttons: 4);
      expect(buttonSize(tester), 26);
      expect(fieldHeight(tester), 36);
    });

    testWidgets('ארבעה כפתורים ב-360: עדיין אין מקום (4 פיקסלים מתחת לסף)', (
      tester,
    ) async {
      await pumpField(tester, width: 360, buttons: 4);
      expect(buttonSize(tester), 26);
    });

    testWidgets('ארבעה כפתורים ב-400: יש מקום, 40', (tester) async {
      await pumpField(tester, width: 400, buttons: 4);
      expect(buttonSize(tester), 40);
      expect(fieldHeight(tester), 40);
    });

    testWidgets('בלי כפתור ניקוי הסף נמוך ב-48: ארבעה כפתורים ב-360', (
      tester,
    ) async {
      await pumpField(tester, width: 360, buttons: 4, withClear: false);
      expect(buttonSize(tester), 40);
    });

    testWidgets('פעולות מתחת לשדה לא לוקחות מהקלט: השדה 40 גם ב-320', (
      tester,
    ) async {
      await pumpField(tester, width: 320, buttons: 4, actionsBelow: true);
      // הכפתורים בשורה מתחת לשדה ממילא תופסים 48 (שטח המגע); מה שמשתנה הוא
      // השדה, שעובר מ-36 ל-40 כי אין מה שלוקח מרוחב הקלט.
      expect(fieldHeight(tester), 40);
    });
  });

  group('בלי שינוי', () {
    testWidgets('מחשב (שטח מגע מצומצם): 26 והשדה 36 גם כשיש מקום', (
      tester,
    ) async {
      await pumpField(tester, width: 480, buttons: 2, touch: false);
      expect(buttonSize(tester), 26);
      expect(fieldHeight(tester), 36);
    });

    testWidgets('שדה רחב (לא צר) במגע: 32 והשדה 48', (tester) async {
      await pumpField(tester, width: 480, buttons: 2, slim: false);
      expect(buttonSize(tester), 32);
      expect(fieldHeight(tester), 48);
    });
  });
}
