// issue #3699: בחירה בין אדר א׳ לאדר ב׳ באירוע שנתי עברי.

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/tools/calendar/bloc/calendar_cubit.dart';
import 'package:otzaria/tools/calendar/dialogs/calendar_event_dialog.dart';
import 'package:otzaria/widgets/controls/action_buttons.dart';

import '../../../support/golden_fonts.dart';

Future<CalendarEventDialogResult?> _openAndSave(
  WidgetTester tester,
  CustomEvent event, {
  String? tap,
  required Matcher choiceShown,
}) async {
  tester.view.physicalSize = const Size(360, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  CalendarEventDialogResult? result;
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('he', 'IL'),
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      supportedLocales: const [Locale('he', 'IL')],
      home: Builder(
        builder: (context) => Scaffold(
          body: ActionButton.neutral(
            text: 'פתח',
            onPressed: () async {
              result = await showCalendarEventDialog(
                context: context,
                state: CalendarState.initial(),
                existingEvent: event,
              );
            },
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('פתח'));
  await tester.pumpAndSettle();
  expect(find.text('בשנה מעוברת'), choiceShown);
  if (tap != null) {
    final option = find.text(tap);
    await tester.ensureVisible(option);
    await tester.pumpAndSettle();
    await tester.tap(option);
    await tester.pumpAndSettle();
  }
  await tester.tap(find.text('שמור שינויים'));
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
  return result;
}

CustomEvent _event({
  required int month,
  required int day,
  required DateTime date,
  RecurrenceType recurrence = RecurrenceType.annualHebrew,
}) => CustomEvent(
  id: 'adar',
  title: 'יארצייט',
  description: '',
  createdAt: DateTime(2025),
  baseGregorianDate: date,
  baseJewishYear: 5785,
  baseJewishMonth: month,
  baseJewishDay: day,
  recurrenceType: recurrence,
);

void main() {
  setUpAll(loadGoldenFonts);

  // ‏י״ד אדר תשפ״ה = 14.3.2025; א׳ ניסן תשפ״ה = 30.3.2025.
  testWidgets('אירוע שנתי באדר: בחירת אדר ב׳ נשמרת', (tester) async {
    final result = await _openAndSave(
      tester,
      _event(month: 12, day: 14, date: DateTime(2025, 3, 14)),
      tap: 'אדר ב׳',
      choiceShown: findsOneWidget,
    );
    expect(result?.leapAdarMonth, 13);
  }, variant: TargetPlatformVariant.only(goldenPlatform));

  testWidgets('אירוע שנתי באדר בלי שינוי: ברירת המחדל אדר א׳', (tester) async {
    final result = await _openAndSave(
      tester,
      _event(month: 12, day: 14, date: DateTime(2025, 3, 14)),
      choiceShown: findsOneWidget,
    );
    expect(result?.leapAdarMonth, 12);
  }, variant: TargetPlatformVariant.only(goldenPlatform));

  testWidgets('מחוץ לאדר אין בחירה', (tester) async {
    final nisan = await _openAndSave(
      tester,
      _event(month: 1, day: 1, date: DateTime(2025, 3, 30)),
      choiceShown: findsNothing,
    );
    expect(nisan?.leapAdarMonth, isNull);
  }, variant: TargetPlatformVariant.only(goldenPlatform));

  testWidgets('חזרה חודשית באדר: אין בחירה', (tester) async {
    final monthly = await _openAndSave(
      tester,
      _event(
        month: 12,
        day: 14,
        date: DateTime(2025, 3, 14),
        recurrence: RecurrenceType.monthlyHebrew,
      ),
      choiceShown: findsNothing,
    );
    expect(monthly?.leapAdarMonth, isNull);
  }, variant: TargetPlatformVariant.only(goldenPlatform));
}
