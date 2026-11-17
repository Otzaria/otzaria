import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kosher_dart/kosher_dart.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/tools/calendar/bloc/calendar_cubit.dart';
import 'package:otzaria/tools/calendar/helpers/calendar_print_helpers.dart';
import 'package:otzaria/tools/calendar/helpers/calendar_print_options.dart';
import 'package:otzaria/tools/calendar/helpers/zmanim_helpers.dart';
import 'package:pdf/pdf.dart';
import 'package:pdfrx/pdfrx.dart' as rx;
import 'package:timezone/data/latest_all.dart' as tz;

import '../../../test_helpers/memory_cache_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  final originalModulePath = rx.Pdfrx.pdfiumModulePath;
  late Directory directory;

  setUpAll(() async {
    tz.initializeTimeZones();
    await Settings.init(cacheProvider: MemoryCacheProvider());
    directory = Directory.systemTemp.createTempSync('calendar-zmanim-pdf-');
    final moduleName = Platform.isWindows
        ? 'pdfium.dll'
        : Platform.isMacOS
        ? 'libpdfium_dart.dylib'
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
  final names = {for (final d in kZmanimRegistry) d.id: d.fullName};

  CalendarState stateFor(CalendarView view, {bool twelve = false}) {
    final jd = JewishDate.fromDateTime(date);
    return CalendarState.initial().copyWith(
      calendarView: view,
      currentGregorianDate: date,
      selectedGregorianDate: date,
      currentJewishDate: jd,
      selectedJewishDate: jd,
      selectedCity: 'ירושלים',
      dailyTimes: calculateDailyTimes(date, 'ירושלים'),
      twelveHourClock: twelve,
    );
  }

  Future<String> pdfText(
    CalendarState state, {
    Set<String>? zmanim,
    PdfPageFormat format = PdfPageFormat.a4,
    int count = 1,
  }) async {
    final document = await rx.PdfDocument.openData(
      await createCalendarPdf(
        state,
        format,
        count: count,
        printedZmanim: zmanim,
      ),
      sourceName: 'calendar-zmanim.pdf',
    );
    addTearDown(document.dispose);
    final buffer = StringBuffer();
    for (final page in document.pages) {
      buffer.writeln((await page.loadText())!.fullText);
    }
    return buffer.toString();
  }

  int clocks(String text) => RegExp(r'\d{1,2}:\d{2}').allMatches(text).length;

  /// השעה (ספרות בלבד) כפי שמודפסת; בלי סימוני הכיווניות שבמחרוזת התצוגה.
  String shown(String id, {bool twelve = false}) =>
      RegExp(r'\d{1,2}:\d{2}').firstMatch(
        zmanTimeForDisplay(
          calculateDailyTimes(date, 'ירושלים', only: {id})[id]!,
          twelveHourClock: twelve,
        ),
      )![0]!;

  group('מגבלות וברירות מחדל לפי תצוגה', () {
    test('תקרה לכל תצוגה, ובשבוע גבוהה מבחודש', () {
      expect(maxPrintedZmanim(CalendarView.month), 3);
      expect(maxPrintedZmanim(CalendarView.week), 14);
      expect(maxPrintedZmanim(CalendarView.day), isNull);
    });

    test('ברירת המחדל נכנסת בתקרה של כל תצוגה', () {
      for (final view in CalendarView.values) {
        final max = maxPrintedZmanim(view);
        final defaults = defaultPrintedZmanim(view, dayZmanim: {'chatzos'});
        if (max != null) expect(defaults.length, lessThanOrEqualTo(max));
      }
      expect(defaultPrintedZmanim(CalendarView.month), isEmpty);
      expect(defaultPrintedZmanim(CalendarView.week), {'sunrise', 'sunset'});
      expect(defaultPrintedZmanim(CalendarView.day, dayZmanim: {'chatzos'}), {
        'chatzos',
      });
    });
  });

  group('calendarPrintedZmanimFor', () {
    test('מחזיר רק את הזמנים שנבחרו, לפי השעה, בשמם העברי', () {
      final zmanim = calendarPrintedZmanimFor(
        stateFor(CalendarView.month),
        date,
        {'sunset', 'chatzos', 'sunrise'},
      );
      expect(
        [for (final (name, _) in zmanim) name],
        [
          names['sunrise'],
          names['chatzos'],
          names['sunset'],
        ],
      );
      expect(zmanim.last.$2, contains(shown('sunset')));
    });

    test('בשעון 12 שעות הזמנים מודפסים ב-AM/PM', () {
      final zmanim = calendarPrintedZmanimFor(
        stateFor(CalendarView.month, twelve: true),
        date,
        {'sunrise', 'sunset'},
      );
      expect(zmanim.first.$2, contains('AM'));
      expect(zmanim.last.$2, contains('PM'));
    });

    test('זמן שאינו רלוונטי ליום אינו מודפס', () {
      // ערב פסח לא חל ב-16.9.2026.
      final id = kZmanimRegistry.firstWhere((d) => d.category == 'ערב פסח').id;
      expect(
        calendarPrintedZmanimFor(stateFor(CalendarView.month), date, {id}),
        isEmpty,
      );
    });
  });

  group('תאי חודש', () {
    test('בלי בחירה לא מודפסת אף שעה (התנהגות קיימת)', () async {
      final text = await pdfText(stateFor(CalendarView.month));
      expect(clocks(text), 0);
    });

    test('בחירה ריקה אינה מדפיסה זמנים', () async {
      final text = await pdfText(stateFor(CalendarView.month), zmanim: {});
      expect(clocks(text), 0);
    });

    test('זמנים שנבחרו מודפסים בכל יום בחודש', () async {
      final text = await pdfText(
        stateFor(CalendarView.month),
        zmanim: {'sunrise', 'sunset'},
      );
      // תשרי תשפ"ז: 30 יום, כל אחד עם זריחה ושקיעה.
      expect(clocks(text), 60);
      expect(text, contains(names['sunrise']));
    });

    test('בעמוד לרוחב לא מודפס יותר ממה שנכנס בתא', () async {
      final text = await pdfText(
        stateFor(CalendarView.month),
        zmanim: {for (final d in kZmanimRegistry.take(40)) d.id},
        format: PdfPageFormat.a4.landscape,
      );
      // תא לרוחב נמוך מ-8 שורות: לא עשרות שעות לתא.
      expect(clocks(text), lessThan(30 * 8));
    });
  });

  group('תצוגת שבוע', () {
    test('בחירה ריקה אינה מדפיסה את זריחה ושקיעה', () async {
      expect(clocks(await pdfText(stateFor(CalendarView.week), zmanim: {})), 0);
    });
    test('בלי בחירה: זריחה ושקיעה, כמו קודם', () async {
      final text = await pdfText(stateFor(CalendarView.week));
      expect(text, contains('זריחה'));
      expect(text, contains('שקיעה'));
      expect(clocks(text), 14);
    });

    test('הזמנים שנבחרו מחליפים את זריחה ושקיעה', () async {
      final text = await pdfText(
        stateFor(CalendarView.week),
        zmanim: {'chatzos'},
      );
      expect(clocks(text), 7);
      expect(text, isNot(contains('זריחה')));
      expect(text, contains(shown('chatzos')));
    });
  });

  group('תצוגת יום', () {
    CalendarState dayState() => stateFor(
      CalendarView.day,
    ).copyWith(enabledZmanim: {'sunrise', 'sunset', 'chatzos'});

    test('בחירה ריקה אינה מדפיסה את הזמנים שהופעלו בלוח', () async {
      expect(clocks(await pdfText(dayState(), zmanim: {})), 0);
    });

    test('בלי בחירה: הזמנים שהופעלו בלוח', () async {
      expect(clocks(await pdfText(dayState())), 3);
    });

    test('הזמנים שנבחרו מחליפים את אלה שהופעלו בלוח', () async {
      final text = await pdfText(dayState(), zmanim: {'sunset'});
      expect(clocks(text), 1);
      expect(text, contains(shown('sunset')));
    });
  });

  group('שמירת הבחירה', () {
    test('אין בחירה שמורה כברירת מחדל', () {
      expect(CalendarPrintZmanimStore.load(), isNull);
    });

    test('בחירה נשמרת וחוזרת, וריקה מוחקת אותה', () async {
      await CalendarPrintZmanimStore.save({'sunrise', 'sunset'});
      expect(CalendarPrintZmanimStore.load(), {'sunrise', 'sunset'});
      await CalendarPrintZmanimStore.save(null);
      expect(CalendarPrintZmanimStore.load(), isNull);
    });

    test('בחירה ריקה נשמרת ומדפיסה אפס זמנים', () async {
      await CalendarPrintZmanimStore.save({});
      addTearDown(() => CalendarPrintZmanimStore.save(null));
      expect(CalendarPrintZmanimStore.load(), isEmpty);
      expect(clocks(await pdfText(stateFor(CalendarView.week))), 0);
    });

    test('createCalendarPdf בלי פרמטר קורא את הבחירה השמורה', () async {
      await CalendarPrintZmanimStore.save({'sunset'});
      addTearDown(() => CalendarPrintZmanimStore.save(null));
      final text = await pdfText(stateFor(CalendarView.month));
      expect(clocks(text), 30);
    });

    test('ערך שמור פגום נחשב לברירת מחדל', () async {
      await Settings.setValue<String>(CalendarPrintZmanimStore.key, '{oops');
      addTearDown(() => CalendarPrintZmanimStore.save(null));
      expect(CalendarPrintZmanimStore.load(), isNull);
    });
  });
}
