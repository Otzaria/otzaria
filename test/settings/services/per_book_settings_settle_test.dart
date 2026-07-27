import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/settings/services/per_book_settings_service.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDataRoot;
  late Directory settingsDir;

  final bookA = TextBook(title: 'ספר א');
  final bookB = TextBook(title: 'ספר ב');

  setUp(() async {
    tempDataRoot = await Directory.systemTemp.createTemp('settle_test_');
    AppPaths.debugOverrideDataRootPath(tempDataRoot.path);
    settingsDir = Directory(p.join(tempDataRoot.path, 'per_book_settings'));
  });

  tearDown(() async {
    await PerBookSettings.settle();
    AppPaths.debugOverrideDataRootPath(null);
    if (await tempDataRoot.exists()) {
      await tempDataRoot.delete(recursive: true);
    }
  });

  Future<void> saveFontSize(Book book, double size) =>
      TextBookPerBookSettings.mutate(
        book,
        (existing) =>
            (existing ?? TextBookPerBookSettings()).copyWith(fontSize: size),
      );

  group('PerBookSettings.settle — סמנטיקת ה-barrier', () {
    test('על תור ריק מסתיים בלי להשהות את ה-event loop', () async {
      final order = <String>[];
      // משימת event-loop: אם settle משהה ולו סיבוב אחד, ה-timer יקדים אותה.
      unawaited(
        Future<void>.delayed(Duration.zero).then((_) => order.add('timer')),
      );

      await PerBookSettings.settle();
      order.add('settle');

      expect(order, ['settle']);
    });

    test('ממתין לשמירה שיצאה לדרך בלי await', () async {
      final order = <String>[];
      unawaited(saveFontSize(bookA, 18).then((_) => order.add('save')));

      await PerBookSettings.settle();
      order.add('settle');

      expect(order, ['save', 'settle']);
    });

    test('אחרי ההמתנה הקובץ כבר על הדיסק', () async {
      unawaited(saveFontSize(bookA, 21));

      await PerBookSettings.settle();

      final files = await settingsDir.list().toList();
      expect(files.whereType<File>(), hasLength(1));
      expect((await TextBookPerBookSettings.load(bookA))?.fontSize, 21);
    });

    test('ממתין לכמה שמירות על אותו ספר (תור נעילה יחיד)', () async {
      final completed = <double>[];
      for (final size in [16.0, 17.0, 18.0]) {
        unawaited(saveFontSize(bookA, size).then((_) => completed.add(size)));
      }

      await PerBookSettings.settle();

      expect(completed, [16.0, 17.0, 18.0]);
      expect((await TextBookPerBookSettings.load(bookA))?.fontSize, 18.0);
    });

    test('ממתין לפעולות על ספרים שונים (תורי נעילה נפרדים)', () async {
      final completed = <String>{};
      unawaited(saveFontSize(bookA, 19).then((_) => completed.add('א')));
      unawaited(saveFontSize(bookB, 23).then((_) => completed.add('ב')));

      await PerBookSettings.settle();

      expect(completed, {'א', 'ב'});
      expect((await TextBookPerBookSettings.load(bookA))?.fontSize, 19);
      expect((await TextBookPerBookSettings.load(bookB))?.fontSize, 23);
    });

    test('ממתין גם לטעינה, לא רק לכתיבה', () async {
      await saveFontSize(bookA, 20);
      final order = <String>[];
      unawaited(
        TextBookPerBookSettings.load(bookA).then((_) => order.add('load')),
      );

      await PerBookSettings.settle();
      order.add('settle');

      expect(order, ['load', 'settle']);
    });

    test('ממתין גם למחיקה', () async {
      await saveFontSize(bookA, 20);
      final order = <String>[];
      unawaited(
        TextBookPerBookSettings.delete(bookA).then((_) => order.add('delete')),
      );

      await PerBookSettings.settle();
      order.add('settle');

      expect(order, ['delete', 'settle']);
      expect(await TextBookPerBookSettings.load(bookA), isNull);
    });

    test('קולט פעולה שנוספה בזמן ההמתנה', () async {
      Future<void>? nested;
      unawaited(
        TextBookPerBookSettings.mutate(bookA, (existing) {
          // נכנס לתור של ספר אחר בזמן ש-settle כבר ממתין לתור של ספר א.
          nested = saveFontSize(bookB, 24);
          return (existing ?? TextBookPerBookSettings()).copyWith(fontSize: 18);
        }),
      );

      await PerBookSettings.settle();

      expect(nested, isNotNull);
      expect((await TextBookPerBookSettings.load(bookB))?.fontSize, 24);
    });

    test('אינו זורק כשפעולה תלויה נכשלת', () async {
      final failing = TextBookPerBookSettings.mutate(
        bookA,
        (_) => throw StateError('כשל מכוון'),
      );
      unawaited(failing.catchError((_) {}));

      await expectLater(PerBookSettings.settle(), completes);
    });

    test('כשל בפעולה אחת אינו מונע את ההמתנה לפעולה אחרת', () async {
      var secondRan = false;
      unawaited(
        TextBookPerBookSettings.mutate(
          bookA,
          (_) => throw StateError('כשל מכוון'),
        ).catchError((_) {}),
      );
      unawaited(
        TextBookPerBookSettings.mutate(bookB, (existing) {
          secondRan = true;
          return (existing ?? TextBookPerBookSettings()).copyWith(fontSize: 25);
        }),
      );

      await PerBookSettings.settle();

      expect(secondRan, isTrue);
      expect((await TextBookPerBookSettings.load(bookB))?.fontSize, 25);
    });

    test('קריאה שנייה ברצף מסתיימת מיד — התור התרוקן', () async {
      unawaited(saveFontSize(bookA, 18));
      await PerBookSettings.settle();

      final order = <String>[];
      unawaited(
        Future<void>.delayed(Duration.zero).then((_) => order.add('timer')),
      );
      await PerBookSettings.settle();
      order.add('settle');

      expect(order, ['settle']);
    });

    test(
      'רגרסיה: אחרי ההמתנה מחיקת שורש הנתונים מצליחה (PathAccessException)',
      () async {
        // בלי ה-barrier הכתיבה מחזיקה את הקובץ פתוח, ומחיקת התיקייה
        // נכשלת ב-Windows עם errno 32.
        unawaited(saveFontSize(bookA, 18));
        unawaited(saveFontSize(bookB, 19));

        await PerBookSettings.settle();

        await expectLater(tempDataRoot.delete(recursive: true), completes);
        expect(await tempDataRoot.exists(), isFalse);
      },
    );
  });

  group('PerBookSettings.deleteAllSettings', () {
    test('מוחק את התיקייה ומחזיר true', () async {
      await saveFontSize(bookA, 18);
      expect(await settingsDir.exists(), isTrue);

      expect(await PerBookSettings.deleteAllSettings(), isTrue);

      expect(await settingsDir.exists(), isFalse);
    });

    test('ממתין לשמירה תלויה לפני המחיקה', () async {
      var saveRan = false;
      unawaited(
        TextBookPerBookSettings.mutate(bookA, (existing) {
          saveRan = true;
          return (existing ?? TextBookPerBookSettings()).copyWith(fontSize: 18);
        }),
      );
      expect(saveRan, isFalse, reason: 'השמירה עדיין לא רצה');

      expect(await PerBookSettings.deleteAllSettings(), isTrue);

      expect(saveRan, isTrue, reason: 'ה-barrier המתין לשמירה');
    });

    test('רגרסיה: הגדרה שנשמרה תוך כדי איפוס אינה קמה לתחייה', () async {
      // בלי ההמתנה הכתיבה מסתיימת אחרי המחיקה, יוצרת מחדש את התיקייה
      // ומשאירה את ההגדרה שהמשתמש ביקש לאפס.
      unawaited(saveFontSize(bookA, 18));
      unawaited(saveFontSize(bookB, 19));

      await PerBookSettings.deleteAllSettings();

      expect(await settingsDir.exists(), isFalse);
    });

    test('על תיקייה שאינה קיימת מחזיר true ואינו יוצר אותה', () async {
      expect(await settingsDir.exists(), isFalse);

      expect(await PerBookSettings.deleteAllSettings(), isTrue);

      expect(await settingsDir.exists(), isFalse);
    });

    test('אחרי איפוס הטעינה מחזירה null', () async {
      await saveFontSize(bookA, 18);
      await saveFontSize(bookB, 19);

      await PerBookSettings.deleteAllSettings();

      expect(await TextBookPerBookSettings.load(bookA), isNull);
      expect(await TextBookPerBookSettings.load(bookB), isNull);
    });

    test('שמירה חדשה אחרי איפוס יוצרת מחדש את התיקייה', () async {
      await saveFontSize(bookA, 18);
      await PerBookSettings.deleteAllSettings();

      await saveFontSize(bookA, 30);

      expect((await TextBookPerBookSettings.load(bookA))?.fontSize, 30);
    });

    test('אינו משאיר תור נעילה מזוהם', () async {
      unawaited(saveFontSize(bookA, 18));
      await PerBookSettings.deleteAllSettings();

      final order = <String>[];
      unawaited(
        Future<void>.delayed(Duration.zero).then((_) => order.add('timer')),
      );
      await PerBookSettings.settle();
      order.add('settle');

      expect(order, ['settle']);
    });

    test('מוחק גם קובצי legacy שאינם ממופתחים ב-hash', () async {
      await settingsDir.create(recursive: true);
      final legacy = File(p.join(settingsDir.path, 'settings_ספר_א.json'));
      await legacy.writeAsString('{"fontSize":18.0}');

      await PerBookSettings.deleteAllSettings();

      expect(await legacy.exists(), isFalse);
    });
  });

  group('settle מול שאר צרכני תור הנעילה', () {
    test('ממתין לניקוי התקופתי משנכנס לתור', () async {
      await saveFontSize(bookA, 18);
      await saveFontSize(bookB, 19);

      final cleanup = PerBookSettings.cleanupRedundantSettings(
        defaultFontSize: 18,
        defaultRemoveNikud: false,
        defaultShowSplitView: true,
      );
      // הסריקה שלפני ה-runLocked הראשון אינה בתור; מחכים שהניקוי ייכנס אליו.
      await Future<void>.delayed(const Duration(milliseconds: 50));

      await PerBookSettings.settle();
      await cleanup;

      // 18 היה זהה לברירת המחדל ולכן נוקה; 19 שרד.
      expect(await TextBookPerBookSettings.load(bookA), isNull);
      expect((await TextBookPerBookSettings.load(bookB))?.fontSize, 19);
    });

    test('איפוס בזמן ניקוי תקופתי — לא מתנגש ולא מחייה הגדרות', () async {
      // הניקוי מגן על עצמו בבדיקות קיום בתוך הנעילה, ולכן התוצאה זהה בכל
      // תזמון: המחיקה מצליחה, והניקוי אינו כותב קובץ אחריה.
      await saveFontSize(bookA, 18);
      await saveFontSize(bookB, 19);
      final cleanup = PerBookSettings.cleanupRedundantSettings(
        defaultFontSize: 18,
        defaultRemoveNikud: false,
        defaultShowSplitView: true,
      );

      expect(await PerBookSettings.deleteAllSettings(), isTrue);
      await expectLater(cleanup, completes);

      final leftovers = await settingsDir.exists()
          ? await settingsDir.list().toList()
          : const [];
      expect(leftovers, isEmpty);
    });

    test('ממתין גם לשמירת הגדרות PDF', () async {
      final pdf = PdfBook(title: 'ספר PDF', path: r'C:\library\a.pdf');
      final order = <String>[];
      unawaited(
        PdfBookPerBookSettings(zoom: 1.5).save(pdf).then((_) {
          order.add('pdf');
        }),
      );

      await PerBookSettings.settle();
      order.add('settle');

      expect(order, ['pdf', 'settle']);
      expect((await PdfBookPerBookSettings.load(pdf))?.zoom, 1.5);
    });

    test('ממתין לשמירות טקסט ו-PDF שיצאו לדרך יחד', () async {
      final pdf = PdfBook(title: 'ספר PDF', path: r'C:\library\a.pdf');
      unawaited(saveFontSize(bookA, 18));
      unawaited(PdfBookPerBookSettings(zoom: 2.0).save(pdf));

      await PerBookSettings.settle();

      expect((await TextBookPerBookSettings.load(bookA))?.fontSize, 18);
      expect((await PdfBookPerBookSettings.load(pdf))?.zoom, 2.0);
      await expectLater(tempDataRoot.delete(recursive: true), completes);
      await tempDataRoot.create(recursive: true);
    });

    test('שני settle במקביל — שניהם מסתיימים', () async {
      unawaited(saveFontSize(bookA, 18));
      unawaited(saveFontSize(bookB, 19));

      await expectLater(
        Future.wait([PerBookSettings.settle(), PerBookSettings.settle()]),
        completes,
      );
    });

    test('התור אינו דולף אחרי פעולות רבות', () async {
      for (var i = 0; i < 20; i++) {
        unawaited(saveFontSize(TextBook(title: 'ספר $i'), 18 + i.toDouble()));
      }
      await PerBookSettings.settle();

      final order = <String>[];
      unawaited(
        Future<void>.delayed(Duration.zero).then((_) => order.add('timer')),
      );
      await PerBookSettings.settle();
      order.add('settle');

      expect(order, ['settle'], reason: 'התור התרוקן לחלוטין');
    });
  });
}
