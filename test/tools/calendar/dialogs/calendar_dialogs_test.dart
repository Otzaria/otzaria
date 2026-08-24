import 'package:flutter/gestures.dart' show kDoubleTapTimeout;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/tools/calendar/calendar_screen.dart';
import 'package:otzaria/tools/calendar/dialogs/calendar_event_dialog.dart';
import 'package:otzaria/tools/calendar/dialogs/jump_to_date_dialog.dart'
    show JumpToDatePanel;
import 'package:otzaria/tools/calendar/helpers/calendar_date_helpers.dart';
import 'package:otzaria/tools/calendar/widgets/calendar_date_picker_panel.dart';
import 'package:otzaria/tools/calendar/helpers/calendar_print_helpers.dart';
import 'package:otzaria/tools/calendar/utils/calendar_cubit.dart';
import 'package:otzaria/widgets/misc/app_dropdown_field.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

void main() {
  group('Calendar dialogs', () {
    test('day print layout resolves to day output', () {
      expect(
        resolveCalendarPrintLayout(CalendarView.day),
        CalendarPrintLayout.day,
      );
    });

    group('parseCalendarDate — לועזי', () {
      DateTime? parse(String input) => parseCalendarDate(
        input,
        currentJewishYear: 5786,
        currentGregorianYear: 2026,
      );

      test('שנה בת 4 ספרות', () {
        expect(parse('15/3/2025'), DateTime(2025, 3, 15));
      });
      test('שנה בת 2 ספרות → 20xx', () {
        expect(parse('12/7/26'), DateTime(2026, 7, 12));
      });
      test('מפריד רווח / נקודה / מקף', () {
        expect(parse('12 7'), DateTime(2026, 7, 12));
        expect(parse('12.7.26'), DateTime(2026, 7, 12));
        expect(parse('12-7'), DateTime(2026, 7, 12));
      });
      test('חודש ללא שנה → שנה נוכחית', () {
        expect(parse('12/7'), DateTime(2026, 7, 12));
      });
      test('שם חודש עם/בלי הקידומת ב', () {
        expect(parse('12/אוגוסט/26'), DateTime(2026, 8, 12));
        expect(parse('12 באוגוסט 26'), DateTime(2026, 8, 12));
      });
      test('תאריך לא חוקי נדחה', () {
        expect(parse('31/02/2026'), isNull);
      });
    });

    group('parseCalendarDate — עברי', () {
      test('שנה מקוצרת (2 אותיות) שווה לשנה מלאה', () {
        final full = parseCalendarDate('טו תמוז תשפו', currentJewishYear: 5786);
        final short = parseCalendarDate('טו תמוז פו', currentJewishYear: 5786);
        expect(full, isNotNull);
        expect(short, equals(full));
      });
      test('שנה חסרה → שנה עברית נוכחית', () {
        final withYear = parseCalendarDate(
          'טו תמוז תשפו',
          currentJewishYear: 5786,
        );
        final noYear = parseCalendarDate('טו תמוז', currentJewishYear: 5786);
        expect(noYear, equals(withYear));
      });
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

    testWidgets('taps outside the double tap timeout do not call onConfirm', (
      tester,
    ) async {
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

      await tester.tap(find.text('15'));
      await tester.pump();
      await tester.pump(kDoubleTapTimeout);
      await tester.tap(find.text('15'));
      await tester.pump();

      expect(confirmed, isFalse);
      await tester.pump(kDoubleTapTimeout);
    });

    testWidgets('quick taps on different date cells do not call onConfirm', (
      tester,
    ) async {
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

    testWidgets('double click on navigation arrows does not call onConfirm', (
      tester,
    ) async {
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

    testWidgets('desktop: הוספת שעה — עורך HH∶MM, הקלדה ו-✕ לניקוי', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1.0;
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() {
        tester.view.resetDevicePixelRatio();
        tester.binding.setSurfaceSize(null);
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showCalendarEventDialog(
                  context: context,
                  state: CalendarState.initial(),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // ברירת מחדל: אין שעה → צ'יפ 'הוספת שעה'
      expect(find.text('הוספת שעה'), findsOneWidget);

      await tester.tap(find.text('הוספת שעה'));
      await tester.pumpAndSettle();

      // העורך מוצג (מפריד ':') והצ'יפ נעלם
      expect(find.text('הוספת שעה'), findsNothing);
      expect(find.text(':'), findsNWidgets(2));

      // הקלדה מעדכנת את התאים: 09:45. pump בין הקשות כדי שהמעבר האוטומטי
      // שעה→דקות ייכנס לתוקף (כמו פריים בין הקשות אמיתיות).
      await tester.tap(find.byKey(const Key('time-hour')));
      await tester.pumpAndSettle();
      for (final key in [
        LogicalKeyboardKey.digit0,
        LogicalKeyboardKey.digit9,
        LogicalKeyboardKey.digit4,
        LogicalKeyboardKey.digit5,
      ]) {
        await tester.sendKeyEvent(key);
        await tester.pump();
      }
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byKey(const Key('time-hour')),
          matching: find.text('09'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('time-minute')),
          matching: find.text('45'),
        ),
        findsOneWidget,
      );

      // ✕ מנקה חזרה ל'הוספת שעה'
      await tester.tap(find.byTooltip('כל היום'));
      await tester.pumpAndSettle();
      expect(find.text('הוספת שעה'), findsOneWidget);
    });

    testWidgets('תאריך סיום נבחר בבורר עברי/לועזי ולא בבורר לועזי בלבד', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1.0;
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() {
        tester.view.resetDevicePixelRatio();
        tester.binding.setSurfaceSize(null);
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showCalendarEventDialog(
                  context: context,
                  state: CalendarState.initial(),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('תאריך סיום'), findsOneWidget);
      await tester.tap(find.text('בחר'));
      await tester.pumpAndSettle();

      // הבורר המשותף נפתח: לוח עם מתג עברי/לועזי + שדה הקלדה חופשית,
      // ולא ה-DatePickerDialog הלועזי של המערכת.
      expect(find.byType(CalendarDatePickerPanel), findsOneWidget);
      expect(find.byType(CalendarTypeToggleButton), findsOneWidget);
      expect(find.text('חיפוש תאריך'), findsOneWidget);
      expect(find.byType(DatePickerDialog), findsNothing);

      // הקלדת תאריך עברי עתידי ואישור ב-Enter קובעים תאריך סיום.
      await tester.enterText(find.byType(TextField).last, 'טו תמוז תשצה');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(find.textContaining('סיום:'), findsOneWidget);
    });

    testWidgets('recurring event requires a positive number of years', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1.0;
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() {
        tester.view.resetDevicePixelRatio();
        tester.binding.setSurfaceSize(null);
      });

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
      final recurrenceDropdown = tester
          .widget<AppDropdownField<RecurrenceType>>(
            find.byType(AppDropdownField<RecurrenceType>),
          );
      recurrenceDropdown.onSelected!(RecurrenceType.annualHebrew);
      await tester.pumpAndSettle();

      // גם באירוע חוזר תאריך הסיום נשאר סוף טווח הימים של האירוע.
      expect(find.text('תאריך סיום'), findsOneWidget);

      final recurringLimitToggle = tester.widget<CheckboxListTile>(
        find.byType(CheckboxListTile),
      );
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
      tester.view.devicePixelRatio = 1.0;
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() {
        tester.view.resetDevicePixelRatio();
        tester.binding.setSurfaceSize(null);
      });

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
      // בורר הצבע נפתח בכפתור ייעודי; הגוונים מוצגים ב-popup צמוד לכפתור
      await tester.tap(find.text('בחר צבע'));
      await tester.pumpAndSettle();
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
