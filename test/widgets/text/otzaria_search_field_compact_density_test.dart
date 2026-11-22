import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/widgets/text/otzaria_search_field.dart';

/// הגדלת הכפתורים והשדה ל-40 במגע (q4) היא רק לשדה צר שלא נבע מ"צפיפות
/// ממשק: קומפקטית" שהמשתמש בחר. במצב compact השדה נשאר 36 והכפתורים 26, גם
/// במגע.
void main() {
  Future<void> pumpField(
    WidgetTester tester, {
    required AppDensity density,
    bool? slim,
    double width = 480,
  }) async {
    final controller = TextEditingController(text: 'בראשית');
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          materialTapTargetSize: MaterialTapTargetSize.padded,
          extensions: [density],
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
                  onClear: () {},
                  trailingActions: [
                    OtzariaSearchFieldButton(
                      icon: FluentIcons.filter_24_regular,
                      tooltip: 'פעולה 0',
                      onPressed: () {},
                    ),
                    OtzariaSearchFieldButton(
                      icon: FluentIcons.book_24_regular,
                      tooltip: 'פעולה 1',
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

  group('מגע, צפיפות compact', () {
    testWidgets('slim יורש מהצפיפות: השדה 36 והכפתורים 26', (tester) async {
      await pumpField(tester, density: AppDensity.compact);
      expect(fieldHeight(tester), 36);
      expect(buttonSize(tester), 26);
    });

    testWidgets('slim מפורש בצפיפות compact: גם כאן 36 ו-26', (tester) async {
      await pumpField(tester, density: AppDensity.compact, slim: true);
      expect(fieldHeight(tester), 36);
      expect(buttonSize(tester), 26);
    });
  });

  group('מגע, צפיפות רגילה', () {
    testWidgets('slim מפורש שלא מהצפיפות: 40 והכפתורים 40 כשיש מקום', (
      tester,
    ) async {
      await pumpField(tester, density: AppDensity.regular, slim: true);
      expect(fieldHeight(tester), 40);
      expect(buttonSize(tester), 40);
    });

    testWidgets('בלי slim: שדה רחב, 48', (tester) async {
      await pumpField(tester, density: AppDensity.regular);
      expect(fieldHeight(tester), 48);
      expect(buttonSize(tester), 32);
    });
  });
}
