import 'dart:async';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/search/library_line_source.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart';

import '../support/fake_line_source_engine.dart';

void main() {
  late FakeLineSourceEngine engine;

  setUp(() {
    engine = FakeLineSourceEngine();
    LibraryLineSource.debugReset(engine: engine);
  });

  tearDown(LibraryLineSource.debugReset);

  group('השעיה לכתיבה חיצונית', () {
    test('החזקה ושחרור מאוזנים, וחוזרים על עצמם בלי השעיה כפולה', () async {
      await LibraryLineSource.holdForExternalWrite();
      await LibraryLineSource.holdForExternalWrite();
      expect(engine.depth, 1);

      await LibraryLineSource.releaseExternalWriteHold();
      await LibraryLineSource.releaseExternalWriteHold();
      expect(engine.depth, 0);
      expect(engine.suspends, 1);
      expect(engine.resumes, 1);
    });

    test('שחרור בלי החזקה אינו מחדש דבר', () async {
      await LibraryLineSource.releaseExternalWriteHold();
      expect(engine.resumes, 0);
    });

    test('החזקות מקבילות מבצעות השעיה אחת בלבד', () async {
      engine.suspendGate = Completer<void>();
      final first = LibraryLineSource.holdForExternalWrite();
      final second = LibraryLineSource.holdForExternalWrite();
      final release = LibraryLineSource.releaseExternalWriteHold();
      engine.suspendGate!.complete();
      await Future.wait([first, second, release]);

      expect(engine.suspends, 1);
      expect(engine.resumes, 1);
      expect(engine.depth, 0);
    });

    test('השעיה שנכשלה אינה מחודשת בשחרור', () async {
      engine.failSuspendWith = StateError('המנוע לא נטען');
      await LibraryLineSource.holdForExternalWrite();
      await LibraryLineSource.releaseExternalWriteHold();
      expect(engine.resumes, 0);
      expect(engine.depth, 0);
    });

    test('סגירה מיידית משאירה את המקור פתוח לחיפוש הבא', () async {
      await LibraryLineSource.closeNow();
      expect(engine.suspends, 1);
      expect(engine.depth, 0);
    });

    test('סגירה מיידית בזמן החזקה אינה נוגעת בהחזקה', () async {
      await LibraryLineSource.holdForExternalWrite();
      await LibraryLineSource.closeNow();
      expect(engine.suspends, 1);
      expect(engine.depth, 1);
      await LibraryLineSource.releaseExternalWriteHold();
      expect(engine.depth, 0);
    });
  });

  group('SQLite משותף למנוע', () {
    test('נרשם פעם אחת, וקריאות מקבילות ממתינות לאותו רישום', () async {
      final results = await Future.wait([
        LibraryLineSource.ensureHostSqlite(),
        LibraryLineSource.ensureHostSqlite(),
      ]);
      expect(results, [true, true]);
      expect(await LibraryLineSource.ensureHostSqlite(), isTrue);
      expect(engine.registrations, 1);
      expect(LibraryLineSource.hostApiReady, isTrue);
    });

    test('כשהמנוע כבר מוכן אין רישום', () async {
      engine.hostReady = true;
      expect(await LibraryLineSource.ensureHostSqlite(), isTrue);
      expect(engine.registrations, 0);
    });

    test('כשל רישום משאיר אינדוקס עם טקסט, ונוסה שוב בפעם הבאה', () async {
      engine.failRegistrationWith = Exception('אין auto_extension');
      expect(await LibraryLineSource.ensureHostSqlite(), isFalse);
      expect(LibraryLineSource.hostApiReady, isFalse);

      engine.failRegistrationWith = null;
      expect(await LibraryLineSource.ensureHostSqlite(), isTrue);
      expect(engine.registrations, 2);
    });

    test('רישום שלא הפך את המנוע למוכן נחשב כשל', () async {
      engine.readyAfterRegistration = false;
      expect(await LibraryLineSource.ensureHostSqlite(), isFalse);
    });

    group('כשל רישום נכתב ליומן השגיאות', () {
      late List<Object> logged;

      setUp(() {
        logged = [];
        LibraryLineSource.registrationFailureLog = (error, _) =>
            logged.add(error);
      });

      test('חריגה ברישום — פעם אחת בלבד גם בניסיונות חוזרים', () async {
        final failure = Exception('אין auto_extension');
        engine.failRegistrationWith = failure;
        await LibraryLineSource.ensureHostSqlite();
        await LibraryLineSource.ensureHostSqlite();
        expect(engine.registrations, 2);
        expect(logged, [failure]);
      });

      test('מנוע שנשאר לא מוכן אחרי הרישום', () async {
        engine.readyAfterRegistration = false;
        await LibraryLineSource.ensureHostSqlite();
        await LibraryLineSource.ensureHostSqlite();
        expect(logged, hasLength(1));
      });

      test('מנוע שלא נטען ב-isolate אינו כשל לדיווח', () async {
        engine.failRegistrationWith = StateError(
          'flutter_rust_bridge has not been initialized. '
          'Did you forget to call `await RustLib.init();`?',
        );
        await LibraryLineSource.ensureHostSqlite();
        expect(logged, isEmpty);
      });

      test('StateError אחר מדווח', () async {
        final failure = StateError('sqlite3_auto_extension failed');
        engine.failRegistrationWith = failure;
        await LibraryLineSource.ensureHostSqlite();
        expect(logged, [failure]);
      });

      test('פעם אחת לתהליך: isolate נוסף אינו כותב שוב', () async {
        engine.failRegistrationWith = Exception('אין auto_extension');
        await LibraryLineSource.ensureHostSqlite();
        expect(logged, hasLength(1));

        final loggedByOther = await Isolate.run(() async {
          final other = FakeLineSourceEngine()
            ..failRegistrationWith = Exception('אין auto_extension');
          LibraryLineSource.debugReset(engine: other, keepProcessMarkers: true);
          var count = 0;
          LibraryLineSource.registrationFailureLog = (_, _) => count++;
          await LibraryLineSource.ensureHostSqlite();
          return count;
        });
        expect(loggedByOther, 0);
      });

      test('רישום מוצלח אינו נכתב', () async {
        expect(await LibraryLineSource.ensureHostSqlite(), isTrue);
        expect(logged, isEmpty);
      });
    });
  });

  group('נפילות לאינדוקס עם טקסט', () {
    late List<(BigInt, BigInt)> logged;

    void record(BigInt library, BigInt userBooks) =>
        logged.add((library, userBooks));

    setUp(() {
      logged = [];
      LibraryLineSource.fallbacksLog = record;
    });

    test('בלי נפילות אין דיווח', () async {
      await LibraryLineSource.reportLibraryFallbacks();
      expect(logged, isEmpty);
    });

    test('הספירה נכתבת פעם אחת לתהליך', () async {
      engine.libraryFallbacks = BigInt.from(3);
      await LibraryLineSource.reportLibraryFallbacks();
      engine.libraryFallbacks = BigInt.from(5);
      await LibraryLineSource.reportLibraryFallbacks();
      expect(logged, [(BigInt.from(3), BigInt.zero)]);
    });

    test('נפילות של ספרים אישיים בלבד נכתבות עם ספירה משלהן', () async {
      engine.userBooksFallbacks = BigInt.two;
      await LibraryLineSource.reportLibraryFallbacks();
      expect(logged, [(BigInt.zero, BigInt.two)]);
    });

    test('מנוע שלא נטען אינו מדווח', () async {
      LibraryLineSource.debugReset(engine: _ThrowingStatusEngine());
      LibraryLineSource.fallbacksLog = record;
      await LibraryLineSource.reportLibraryFallbacks();
      expect(logged, isEmpty);
    });
  });

  group('מקור הספרים האישיים', () {
    test(
      'הגדרה וסגירה מעדכנות את המצב, וחזרה על אותו נתיב אינה נשלחת',
      () async {
        expect(LibraryLineSource.userBooksConfigured, isFalse);
        await LibraryLineSource.configureUserBooks(null);
        await LibraryLineSource.configureUserBooks('/db/user_books.db');
        await LibraryLineSource.configureUserBooks('/db/user_books.db');
        expect(LibraryLineSource.userBooksConfigured, isTrue);
        await LibraryLineSource.configureUserBooks(null);
        expect(LibraryLineSource.userBooksConfigured, isFalse);
        expect(engine.userBooksCalls, ['/db/user_books.db', null]);
      },
    );

    test('הגדרה שנכשלה אינה נחשבת מוגדרת', () async {
      engine.failUserBooksWith = Exception('boom');
      await LibraryLineSource.configureUserBooks('/db/user_books.db');
      expect(LibraryLineSource.userBooksConfigured, isFalse);
    });

    test('השעיית seforim.db אינה נוגעת במקור הספרים האישיים', () async {
      await LibraryLineSource.configureUserBooks('/db/user_books.db');
      await LibraryLineSource.holdForExternalWrite();
      await LibraryLineSource.releaseExternalWriteHold();
      expect(LibraryLineSource.userBooksConfigured, isTrue);
      expect(engine.userBooksCalls, ['/db/user_books.db']);
    });
  });

  test('נתיב ריק אינו מוגדר במנוע', () async {
    await LibraryLineSource.configure('');
    await LibraryLineSource.configure('/lib/seforim.db');
    expect(engine.configuredPaths, ['/lib/seforim.db']);
  });
}

class _ThrowingStatusEngine extends FakeLineSourceEngine {
  @override
  Future<LineSourceStatus> status() =>
      Future.error(StateError('flutter_rust_bridge has not been initialized'));
}
