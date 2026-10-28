import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kosher_dart/kosher_dart.dart';
import 'package:otzaria/tools/calendar/helpers/calendar_print_helpers.dart';
import 'package:otzaria/tools/calendar/helpers/zmanim_helpers.dart';
import 'package:otzaria/tools/calendar/bloc/calendar_cubit.dart';
import 'package:pdf/pdf.dart';
import 'package:timezone/data/latest_all.dart' as tz;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(tz.initializeTimeZones);

  for (final view in CalendarView.values) {
    test('לוח השנה בתצוגת ${view.name} מודפס בטקסט מעוצב וקטורי', () async {
      final state = CalendarState.initial().copyWith(calendarView: view);
      final bytes = await createCalendarPdf(state, PdfPageFormat.a4, count: 2);

      final raw = latin1.decode(bytes);
      expect(raw, contains('/Identity-H'));
      expect(raw, isNot(contains(RegExp(r'/Subtype\s*/Image'))));
      expect(RegExp(r'/Type\s*/Page(?![s\w])').allMatches(raw).length, 2);
    });
  }

  CalendarState dayState({Set<String>? enabled}) {
    final date = DateTime(2026, 9, 16);
    final base = CalendarState.initial();
    return base.copyWith(
      calendarView: CalendarView.day,
      selectedGregorianDate: date,
      dailyTimes: calculateDailyTimes(date, base.selectedCity),
      enabledZmanim: enabled,
    );
  }

  /// מספר תאי היום שצוירו: מסגרות התאים הן המלבנים החוזרים ביותר במסמך.
  int drawnCellCount(Uint8List bytes) {
    final raw = latin1.decode(bytes, allowInvalid: true);
    final rectangles = <String, int>{};
    for (final match in RegExp(r'stream\r?\n').allMatches(raw)) {
      final end = raw.indexOf('endstream', match.end);
      if (end < 0) continue;
      String content;
      try {
        content = latin1.decode(
          ZLibCodec().decode(bytes.sublist(match.end, end)),
          allowInvalid: true,
        );
      } catch (_) {
        continue;
      }
      for (final rectangle in RegExp(
        r'[-\d.]+ [-\d.]+ ([-\d.]+) ([-\d.]+) re',
      ).allMatches(content)) {
        final size = '${rectangle.group(1)}x${rectangle.group(2)}';
        rectangles[size] = (rectangles[size] ?? 0) + 1;
      }
    }
    return rectangles.values.fold<int>(0, (a, b) => a > b ? a : b);
  }

  int pageCount(Uint8List bytes) => RegExp(
    r'/Type\s*/Page(?![s\w])',
  ).allMatches(latin1.decode(bytes)).length;

  test('בתצוגת יום מודפסים רק הזמנים שהופעלו, בשמם העברי', () {
    final state = dayState(enabled: {'chatzosLayla', 'sunset', 'sunrise'});
    final zmanim = calendarPrintedZmanim(state);
    // כמו במסך: לפי השעה, וחצות לילה בסוף.
    final names = {
      for (final def in kZmanimRegistry) def.id: def.fullName,
    };
    expect(
      [for (final (name, _) in zmanim) name],
      [
        names['sunrise'],
        names['sunset'],
        names['chatzosLayla'],
      ],
    );
    for (final (name, time) in zmanim) {
      expect(name, contains(RegExp('[א-ת]')));
      expect(time, contains(RegExp('[0-9]')));
    }
  });

  test('בשעון 12 שעות הזמנים מודפסים ב-AM/PM ונשארים בסדר כרונולוגי', () {
    final state = dayState(
      enabled: {'chatzosLayla', 'sunset', 'chatzos', 'sunrise'},
    ).copyWith(twelveHourClock: true);
    final zmanim = calendarPrintedZmanim(state);
    final names = {
      for (final def in kZmanimRegistry) def.id: def.fullName,
    };
    // מיון לפי הטקסט היה מקדים את חצות היום ("12:..") לזריחה ("6:..").
    expect(
      [for (final (name, _) in zmanim) name],
      [
        names['sunrise'],
        names['chatzos'],
        names['sunset'],
        names['chatzosLayla'],
      ],
    );
    expect(
      [for (final (_, time) in zmanim) time.contains('AM') ? 'AM' : 'PM'],
      ['AM', 'PM', 'PM', 'AM'],
    );
  });

  test('חודש בן שש שורות מודפס במלואו גם לרוחב העמוד', () async {
    // תשרי תשפ"ז מתחיל בשבת — שש שורות שנדחסות לגובה עמוד A4 לרוחב.
    final greg = DateTime(2026, 9, 20);
    final jewishDate = JewishDate.fromDateTime(greg);
    final state = CalendarState.initial().copyWith(
      calendarView: CalendarView.month,
      currentGregorianDate: greg,
      selectedGregorianDate: greg,
      currentJewishDate: jewishDate,
      selectedJewishDate: jewishDate,
    );

    final bytes = await createCalendarPdf(state, PdfPageFormat.a4.landscape);

    expect(drawnCellCount(bytes), jewishDate.getDaysInJewishMonth());
  });

  test('רשימת זמנים ארוכה בתצוגת יום ממשיכה לעמוד הבא', () async {
    final all = {for (final def in kZmanimRegistry) def.id};
    final state = dayState(enabled: all);
    expect(calendarPrintedZmanim(state).length, greaterThan(40));

    final bytes = await createCalendarPdf(state, PdfPageFormat.a4);
    expect(pageCount(bytes), greaterThan(1));
  });
}
