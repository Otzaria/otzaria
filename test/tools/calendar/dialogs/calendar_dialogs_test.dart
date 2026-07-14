import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/tools/calendar/calendar_screen.dart';
import 'package:otzaria/tools/calendar/dialogs/calendar_event_dialog.dart';
import 'package:otzaria/tools/calendar/dialogs/jump_to_date_dialog.dart'
    show JumpToDatePanel;
import 'package:otzaria/tools/calendar/helpers/calendar_date_helpers.dart';
import 'package:otzaria/tools/calendar/helpers/calendar_print_helpers.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

void main() {
  group('Calendar dialogs', () {
    test('day print layout resolves to day output', () {
      expect(
        resolveCalendarPrintLayout(CalendarView.day),
        CalendarPrintLayout.day,
      );
    });

    testWidgets('invalid gregorian date is rejected', (tester) async {
      DateTime? parsedDate;

      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider(
            create: (_) => CalendarCubit(),
            child: Builder(
              builder: (context) {
                parsedDate = parseCalendarInputDate(context, '31/02/2026');
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );

      expect(parsedDate, isNull);
    });

    testWidgets('jump to date defaults to the active date', (tester) async {
      final initialDate = DateTime(2026, 4, 3);
      DateTime? selectedDate;
      bool confirmed = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: JumpToDatePanel(
              selectedDate: initialDate,
              currentDate: initialDate,
              onDateChanged: (d) => selectedDate = d,
              onCancel: () {},
              onConfirm: () {
                confirmed = true;
                selectedDate ??= initialDate;
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('פתח'));
      await tester.pumpAndSettle();

      expect(confirmed, isTrue);
      expect(selectedDate, initialDate);
    });

    testWidgets('double tap on a date cell calls onConfirm', (tester) async {
      bool confirmed = false;
      DateTime? changedTo;
      final initialDate = DateTime(2026, 4, 3);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: JumpToDatePanel(
              selectedDate: initialDate,
              currentDate: initialDate,
              showHebrew: false,
              onDateChanged: (d) => changedTo = d,
              onCancel: () {},
              onConfirm: () => confirmed = true,
            ),
          ),
        ),
      );

      // לחיצה ראשונה — בוחרת את התאריך (מפעילה onDateChanged)
      await tester.tap(find.text('15'));
      await tester.pump();
      // לחיצה שנייה מיידית — אמורה להפעיל onConfirm
      await tester.tap(find.text('15'));
      await tester.pumpAndSettle();

      expect(changedTo, equals(DateTime(2026, 4, 15)));
      expect(confirmed, isTrue);
    });

    testWidgets('quick taps on different date cells do not call onConfirm',
        (tester) async {
      bool confirmed = false;
      DateTime? changedTo;
      final initialDate = DateTime(2026, 4, 3);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: JumpToDatePanel(
              selectedDate: initialDate,
              currentDate: initialDate,
              showHebrew: false,
              onDateChanged: (d) => changedTo = d,
              onCancel: () {},
              onConfirm: () => confirmed = true,
            ),
          ),
        ),
      );

      await tester.tap(find.text('15'));
      await tester.pump();
      await tester.tap(find.text('16'));
      await tester.pumpAndSettle();

      expect(changedTo, equals(DateTime(2026, 4, 16)));
      expect(confirmed, isFalse);
    });

    testWidgets('double click on navigation arrows does not call onConfirm',
        (tester) async {
      bool confirmed = false;
      final initialDate = DateTime(2026, 4, 3);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: JumpToDatePanel(
              selectedDate: initialDate,
              currentDate: initialDate,
              showHebrew: false,
              onDateChanged: (_) {},
              onCancel: () {},
              onConfirm: () => confirmed = true,
            ),
          ),
        ),
      );

      // חיצי הניווט של CalendarDatePicker (הבא/הקודם)
      final navButtons = find.byType(IconButton);
      expect(navButtons, findsWidgets);

      // לחיצה כפולה על חץ ניווט — לא אמורה לאשר
      await tester.tap(navButtons.first);
      await tester.pump();
      await tester.tap(navButtons.first);
      await tester.pumpAndSettle();

      expect(confirmed, isFalse);
    });

    testWidgets('recurring event requires a positive number of years',
        (tester) async {
      CalendarEventDialogResult? result;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await showCalendarEventDialog(
                    context: context,
                    state: CalendarState.initial(),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byType(TextField).first,
        'אירוע בדיקה',
      );
      final recurringSwitch =
          tester.widget<SwitchListTile>(find.byType(SwitchListTile));
      recurringSwitch.onChanged!(true);
      await tester.pumpAndSettle();

      final recurringLimitToggle =
          tester.widget<CheckboxListTile>(find.byType(CheckboxListTile));
      recurringLimitToggle.onChanged!(false);
      await tester.pumpAndSettle();

      await tester.tap(find.text('צור'));
      await tester.pumpAndSettle();

      expect(find.text('צור אירוע חדש'), findsOneWidget);
      expect(result, isNull);

      await tester.enterText(find.byType(TextField).last, '3');
      await tester.tap(find.text('צור'));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.recurringYears, 3);
      expect(result!.recurrenceType, isNot(RecurrenceType.none));
    });

    testWidgets('בחירת צבע מוחזרת ב-colorIndex', (tester) async {
      CalendarEventDialogResult? result;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await showCalendarEventDialog(
                    context: context,
                    state: CalendarState.initial(),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, 'אירוע צבעוני');
      await tester.tap(find.byTooltip('ירוק'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('צור'));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      // 'ירוק' הוא אינדקס 3 בפלטת CalendarEventColors
      expect(result!.colorIndex, 3);
    });
  });
}
