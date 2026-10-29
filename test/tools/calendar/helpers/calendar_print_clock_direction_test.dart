import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kosher_dart/kosher_dart.dart';
import 'package:otzaria/tools/calendar/bloc/calendar_cubit.dart';
import 'package:otzaria/tools/calendar/helpers/calendar_print_helpers.dart';
import 'package:otzaria/tools/calendar/helpers/zmanim_helpers.dart';
import 'package:pdf/pdf.dart';
import 'package:pdfrx/pdfrx.dart' as rx;
import 'package:timezone/data/latest_all.dart' as tz;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  final originalModulePath = rx.Pdfrx.pdfiumModulePath;
  late Directory directory;

  setUpAll(() async {
    tz.initializeTimeZones();
    directory = Directory.systemTemp.createTempSync('calendar-clock-pdf-');
    final moduleName = Platform.isWindows
        ? 'pdfium.dll'
        : Platform.isMacOS
        ? 'libpdfium.dylib'
        : 'libpdfium.so';
    rx.Pdfrx.pdfiumModulePath = File(
      'build/native_assets/${Platform.operatingSystem}/$moduleName',
    ).absolute.path;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => directory.path);
    await rx.pdfrxFlutterInitialize();
  });

  tearDownAll(() async {
    rx.Pdfrx.pdfiumModulePath = originalModulePath;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await directory.delete(recursive: true);
  });

  final date = DateTime(2026, 9, 16);
  for (final view in [CalendarView.day, CalendarView.week]) {
    for (final twelve in [false, true]) {
      for (final format in [PdfPageFormat.a4, PdfPageFormat.a5]) {
        test('סדר השעה המודפסת: ${view.name}, 12h=$twelve, '
            'רוחב=${format.width}', () async {
          final state = CalendarState.initial().copyWith(
            calendarView: view,
            currentGregorianDate: date,
            selectedGregorianDate: date,
            currentJewishDate: JewishDate.fromDateTime(date),
            selectedJewishDate: JewishDate.fromDateTime(date),
            dailyTimes: calculateDailyTimes(date, 'ירושלים'),
            enabledZmanim: {
              'sunrise',
              'sunset',
              'tchilasKidushLevana3',
              'tchilasKidushLevana7',
              'sofKidushLevanaMoldos',
              'sofKidushLevana15',
            },
            twelveHourClock: twelve,
          );
          final document = await rx.PdfDocument.openData(
            await createCalendarPdf(state, format),
            sourceName: 'calendar-clock-direction.pdf',
          );
          addTearDown(document.dispose);
          var clocks = 0;
          var periods = 0;
          for (final page in document.pages) {
            final text = (await page.loadText())!;
            for (final clock in RegExp(
              r'\d{1,2}:\d{2}[.:]',
            ).allMatches(text.fullText)) {
              clocks++;
              final rects = text.charRects.sublist(clock.start, clock.end);
              for (var i = 1; i < rects.length; i++) {
                expect(rects[i].left, greaterThan(rects[i - 1].left));
              }
            }
            final matches = RegExp(
              r'(?<clock1>\d{1,2}:\d{2}[.:])'
              r'[\s\u200e\u202a\u202c\u2066\u2069]*(?<period1>AM|PM)'
              r'|(?<period2>AM|PM)[\s\u200e\u202a\u202c\u2066\u2069]*'
              r'(?<clock2>\d{1,2}:\d{2}[.:])',
            ).allMatches(text.fullText);
            for (final match in matches) {
              periods++;
              final clock =
                  match.namedGroup('clock1') ?? match.namedGroup('clock2')!;
              final period =
                  match.namedGroup('period1') ?? match.namedGroup('period2')!;
              final clockEnd =
                  match.start + match[0]!.indexOf(clock) + clock.length - 1;
              final clockRect = text.charRects[clockEnd];
              final periodRect =
                  text.charRects[match.start + match[0]!.indexOf(period)];
              if ((periodRect.bottom - clockRect.bottom).abs() < 1) {
                expect(
                  periodRect.left,
                  greaterThan(clockRect.right),
                  reason: '${match[0]}: AM/PM חייב להופיע מימין לשעה',
                );
              } else {
                expect(
                  periodRect.top,
                  lessThan(clockRect.bottom),
                  reason: '${match[0]}: בתא צר AM/PM ממשיך בשורה שאחרי השעה',
                );
              }
            }
          }
          final expected = view == CalendarView.week ? 14 : 6;
          expect(clocks, expected);
          expect(periods, twelve ? expected : 0);
        });
      }
    }
  }
}
