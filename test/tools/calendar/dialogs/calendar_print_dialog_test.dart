import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/tools/calendar/dialogs/calendar_print_dialog.dart';
import 'package:otzaria/tools/calendar/utils/calendar_cubit.dart';

void main() {
  Future<void> pumpDialog(WidgetTester tester, CalendarView view) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: CalendarPrintDialog(calendarView: view),
        ),
      ),
    );
  }

  double sliderMax(WidgetTester tester) =>
      tester.widget<Slider>(find.byType(Slider)).max;

  group('CalendarPrintDialog — תקרות טווח ההדפסה (issue #961)', () {
    testWidgets('חודשים: עד 24 — מכסה שנה מעוברת (13) וטווח כולל (14)', (
      tester,
    ) async {
      await pumpDialog(tester, CalendarView.month);
      expect(sliderMax(tester), 24);
    });

    testWidgets('שבועות: עד 55 — מכסה שנה מעוברת ארוכה (385 ימים)', (
      tester,
    ) async {
      await pumpDialog(tester, CalendarView.week);
      expect(sliderMax(tester), 55);
    });

    testWidgets('ימים: עד 62 — שני חודשים מלאים', (tester) async {
      await pumpDialog(tester, CalendarView.day);
      expect(sliderMax(tester), 62);
    });

    testWidgets('גרירת המחוון למקסימום ואישור מחזירים את הכמות שנבחרה', (
      tester,
    ) async {
      int? returned;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () async {
                    returned = await showCalendarPrintDialog(
                      context: context,
                      calendarView: CalendarView.month,
                    );
                  },
                  child: const Text('פתח'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('פתח'));
      await tester.pumpAndSettle();

      final slider = find.byType(Slider);
      await tester.drag(slider, const Offset(500, 0));
      await tester.pumpAndSettle();
      await tester.tap(find.text('הדפס'));
      await tester.pumpAndSettle();

      expect(returned, 24);
    });
  });
}
