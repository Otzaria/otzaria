import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/data_providers/database_library_provider.dart';
import 'package:otzaria/data/sqlite/sqlite3_api.dart' show sqlite3;
import 'package:otzaria/migration/database/daos/database.dart';
import 'package:otzaria/user_content_import/models/user_import_models.dart';
import 'package:otzaria/user_content_import/repository/user_content_repository.dart';
import 'package:otzaria/user_content_import/services/user_import_library.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('UserImportLibrary', () {
    late Directory tempDir;
    late MyDatabase db;
    late UserImportLibrary library;
    late UserContentRepository repo;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('otzaria_library');
      db = MyDatabase.withPath(p.join(tempDir.path, 'user_books.db'));
      final raw = await db.database;
      raw.execute('PRAGMA foreign_keys = OFF');
      raw.execute("INSERT INTO source (name) VALUES ('external')");
      library = UserImportLibrary(
        db,
        resolveRef:
            ({
              required targetTitle,
              required targetCategoryId,
              required targetIsUserBook,
              required ref,
            }) async => int.tryParse(ref),
        sourceExists:
            ({required title, categoryId, required isUserBook}) async => true,
      );
      repo = UserContentRepository(db);
    });

    tearDown(() async {
      db.close();
      await tempDir.delete(recursive: true);
    });

    String write(String name, String content) {
      final path = p.join(tempDir.path, name);
      File(path).writeAsStringSync(content);
      return path;
    }

    /// קובץ קישורים תקין מ"ברכות" אל "מפרש" — נקלט בלי צורך בספרים במסד,
    /// כי הפורמט הזה מזהה את שני הצדדים לפי כותרת.
    String linksFile(String name, {int sourceLine = 3}) => write(
      name,
      'ספר_מקור,מקור_אישי,מקור,ספר_יעד,מיקום_יעד,סוג,יעד_אישי\n'
      'ברכות,לא,$sourceLine,מפרש,12,הפניה,כן\n',
    );

    Future<List<UserLinkRecord>> storedLinks() =>
        repo.forwardUserLinks('ברכות', sourceIsUserBook: false);

    test('קובץ שנוסף נשמר בספרייה עם תוכנו ומיושם', () async {
      final outcome = await library.addFiles([linksFile('קישורים.csv')]);
      expect(outcome.allErrors, isEmpty);

      final files = await library.list();
      expect(files.single.name, 'קישורים.csv');
      expect(files.single.kind, UserImportKind.links);
      expect(files.single.enabled, isTrue);
      expect(await library.contentOf(files.single.id), contains('ברכות'));
      expect(await storedLinks(), hasLength(1));
    });

    /// קישור שיובא בגרסה שקדמה לספריית הקבצים — יש לו שורה במסד בלבד.
    Future<void> legacyLink() => repo.upsertUserLink(
      const UserLinkRecord(
        sourceTitle: 'ברכות',
        sourceIsUserBook: false,
        sourceLineIndex: 40,
        targetTitle: 'מפרש',
        targetLineIndex: 1,
        connectionType: 'COMMENTARY',
      ),
    );

    test('נתונים שיובאו לפני הספרייה נשמרים כשנוסף הקובץ הראשון', () async {
      await legacyLink();
      await library.addFiles([linksFile('קישורים.csv')]);
      expect(
        (await storedLinks()).map((l) => l.sourceLineIndex),
        unorderedEquals([40, 2]),
      );

      // גם בנייה מחדש אחרי השהיה שומרת עליהם, ורק "נקה הכל" מוחק.
      await library.setEnabled((await library.list()).single.id, false);
      expect((await storedLinks()).single.sourceLineIndex, 40);
      await library.removeAll();
      expect(await storedLinks(), isEmpty);
    });

    test('קובץ תיקייה שכתב את אותו ספר כמו הבסיס אינו חוסם בנייה', () async {
      final raw = await db.database;
      void version(String source) => raw.execute(
        'INSERT OR REPLACE INTO user_book_version '
        '(versionBookId, primaryBookId, versionTitle, source) '
        "VALUES (5, 4, 'מהדורה', ?)",
        [source],
      );
      version(UserContentRepository.manualImportSource);
      await library.addFiles([linksFile('קישורים.csv')]);
      version('C:/ספרים/גרסאות.csv');

      final outcome = await library.setEnabled(
        (await library.list()).single.id,
        false,
      );

      expect(outcome.ok, isTrue);
      expect(
        raw.select('SELECT source FROM user_book_version').single['source'],
        'C:/ספרים/גרסאות.csv',
      );
    });

    test('החזרה לשימוש שנכשלת מחזירה את הקובץ למצב מושהה', () async {
      await library.addFiles([linksFile('קישורים.csv')]);
      final id = (await library.list()).single.id;
      await library.setEnabled(id, false);

      // ספר המקור נמחק בינתיים, ולכן הקובץ כבר אינו נקלט.
      final missingSource = UserImportLibrary(
        db,
        resolveRef:
            ({
              required targetTitle,
              required targetCategoryId,
              required targetIsUserBook,
              required ref,
            }) async => int.tryParse(ref),
        sourceExists:
            ({required title, categoryId, required isUserBook}) async => false,
      );
      final outcome = await missingSource.setEnabled(id, true);

      expect(outcome.ok, isFalse);
      expect((await library.list()).single.enabled, isFalse);
      expect((await library.setEnabled(id, false)).ok, isTrue);
    });

    test('השהיה מורידה את הנתונים, והחזרה מחזירה אותם', () async {
      await library.addFiles([linksFile('קישורים.csv')]);
      final id = (await library.list()).single.id;

      await library.setEnabled(id, false);
      expect(await storedLinks(), isEmpty);
      // הקובץ נשאר ברשימה — השהיה אינה מחיקה.
      expect((await library.list()).single.enabled, isFalse);

      await library.setEnabled(id, true);
      expect(await storedLinks(), hasLength(1));
    });

    test('מחיקת קובץ אחד משאירה את הנתונים של האחרים', () async {
      await library.addFiles([
        linksFile('קישורים.csv'),
        linksFile('links.csv', sourceLine: 7),
      ]);
      expect(await storedLinks(), hasLength(2));

      final first = (await library.list()).firstWhere(
        (f) => f.name == 'קישורים.csv',
      );
      await library.remove(first.id);

      expect((await library.list()).map((f) => f.name), ['links.csv']);
      expect((await storedLinks()).single.sourceLineIndex, 6);
    });

    test('ייבוא חוזר של אותו קובץ מעדכן ולא מכפיל', () async {
      final path = linksFile('קישורים.csv');
      await library.addFiles([path]);
      File(path).writeAsStringSync(
        'ספר_מקור,מקור_אישי,מקור,ספר_יעד,מיקום_יעד,סוג,יעד_אישי\n'
        'ברכות,לא,99,מפרש,12,הפניה,כן\n',
      );
      await library.addFiles([path]);

      expect(await library.list(), hasLength(1));
      expect((await storedLinks()).single.sourceLineIndex, 98);
    });

    test('ייבוא חוזר מחזיר לשימוש קובץ שהושהה', () async {
      final path = linksFile('קישורים.csv');
      await library.addFiles([path]);
      await library.setEnabled((await library.list()).single.id, false);

      await library.addFiles([path]);
      expect((await library.list()).single.enabled, isTrue);
      expect(await storedLinks(), hasLength(1));
    });

    test('removeAll מרוקן את הספרייה ואת הנתונים', () async {
      await library.addFiles([linksFile('קישורים.csv')]);
      await library.removeAll();
      expect(await library.list(), isEmpty);
      expect(await storedLinks(), isEmpty);
    });

    // #4106: כשחיבור אחר מחזיק את נעילת הכתיבה, המחיקה ממתינה לה ב-isolate
    // משלה, וה-isolate הראשי ממשיך לרוץ — כאן הוא זה שמשחרר את הנעילה.
    Future<UserImportLibraryResult> whileLocked(
      Future<UserImportLibraryResult> Function() action,
    ) async {
      final writer = sqlite3.open(db.path)..execute('BEGIN IMMEDIATE');
      Timer(const Duration(milliseconds: 300), () {
        writer.execute('COMMIT');
        writer.close();
      });
      final stopwatch = Stopwatch()..start();
      final outcome = await action();
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 3)));
      return outcome;
    }

    test('removeAll ממתין לנעילה בלי לחסום את ה-isolate הראשי', () async {
      await library.addFiles([linksFile('קישורים.csv')]);

      expect((await whileLocked(library.removeAll)).ok, isTrue);

      expect(await library.list(), isEmpty);
      expect(await storedLinks(), isEmpty);
    });

    // #4152: גם שינוי של קובץ בודד ובנייה מחדש כותבים על חיבור משלהם.
    test('remove ממתין לנעילה בלי לחסום את ה-isolate הראשי', () async {
      await library.addFiles([linksFile('קישורים.csv')]);
      final id = (await library.list()).single.id;

      expect((await whileLocked(() => library.remove(id))).ok, isTrue);

      expect(await library.list(), isEmpty);
      expect(await storedLinks(), isEmpty);
    });

    test('setEnabled ממתין לנעילה בלי לחסום את ה-isolate הראשי', () async {
      await library.addFiles([linksFile('קישורים.csv')]);
      final id = (await library.list()).single.id;

      final outcome = await whileLocked(() => library.setEnabled(id, false));

      expect(outcome.ok, isTrue);
      expect((await library.list()).single.enabled, isFalse);
      expect(await storedLinks(), isEmpty);
    });

    test('addFiles ממתין לנעילה בלי לחסום את ה-isolate הראשי', () async {
      final path = linksFile('קישורים.csv');

      final outcome = await whileLocked(() => library.addFiles([path]));

      expect(outcome.allErrors, isEmpty);
      expect(await library.list(), hasLength(1));
      expect(await storedLinks(), hasLength(1));
    });

    /// קובץ קישורים פגום — שורה בלי "מיקום_יעד" נכשלת בפענוח.
    String brokenLinksFile(String name) => write(
      name,
      'ספר_מקור,מקור_אישי,מקור,ספר_יעד,מיקום_יעד,סוג,יעד_אישי\n'
      'ברכות,לא,3,מפרש,,הפניה,כן\n',
    );

    // ⚠️ קובץ פגום אחד חוסם את הייבוא האטומי; ניקוי מחוץ לייבוא היה משאיר
    // את המשתמש בלי כלום.
    test('ייבוא שנכשל אינו מוחק את מה שכבר עבד', () async {
      await library.addFiles([linksFile('קישורים.csv')]);
      expect(await storedLinks(), hasLength(1));

      final outcome = await library.addFiles([brokenLinksFile('links.csv')]);

      expect(outcome.allErrors, isNotEmpty);
      expect(
        await storedLinks(),
        hasLength(1),
        reason: 'הקישור שעבד נמחק בגלל קובץ אחר שנכשל',
      );
    });

    test('קובץ שנכשל אינו נשאר בספרייה וחוסם אותה מכאן והלאה', () async {
      await library.addFiles([linksFile('קישורים.csv')]);
      await library.addFiles([brokenLinksFile('links.csv')]);

      // הספרייה חזרה למצבה הקודם, ולכן פעולה רגילה עליה מצליחה.
      expect((await library.list()).map((f) => f.name), ['קישורים.csv']);
      final id = (await library.list()).single.id;
      expect((await library.setEnabled(id, true)).ok, isTrue);
      expect(await storedLinks(), hasLength(1));
    });

    test('השהיה של קובץ תקין אינה מושפעת מקובץ פגום שנדחה קודם', () async {
      await library.addFiles([linksFile('קישורים.csv')]);
      await library.addFiles([brokenLinksFile('links.csv')]);

      final id = (await library.list()).single.id;
      await library.setEnabled(id, false);
      expect(await storedLinks(), isEmpty);
      await library.setEnabled(id, true);
      expect(await storedLinks(), hasLength(1));
    });

    test('קובץ ששמו אינו מזוהה נדחה ואינו נכנס לספרייה', () async {
      final outcome = await library.addFiles([write('משהו.txt', 'תוכן')]);
      expect(outcome.allErrors.single, contains('לא מזוהה'));
      expect(await library.list(), isEmpty);
    });

    test('בחירה מעורבת עם קובץ חסר או שם לא מוכר אינה משנה דבר', () async {
      await legacyLink();
      final valid = linksFile('קישורים.csv');
      final missing = p.join(tempDir.path, 'חסר.csv');
      final invalid = write('משהו.txt', 'תוכן');

      final outcome = await library.addFiles([valid, missing, invalid]);

      expect(outcome.allErrors, hasLength(2));
      expect(await library.list(), isEmpty);
      expect((await storedLinks()).single.sourceLineIndex, 40);
      final raw = await db.database;
      expect(
        raw.select(
          "SELECT name FROM sqlite_master WHERE name LIKE 'import_baseline_%'",
        ),
        isEmpty,
      );
    });

    test('כשל במהלך שינוי משאיר את הספרייה והקישורים כפי שהיו', () async {
      await library.addFiles([linksFile('קישורים.csv')]);
      final original = (await library.list()).single;
      final raw = await db.database;
      raw.execute(
        'CREATE TRIGGER fail_import_update BEFORE UPDATE ON '
        "user_import_file BEGIN SELECT RAISE(FAIL, 'blocked'); END",
      );

      await expectLater(
        library.setEnabled(original.id, false),
        throwsA(isA<Exception>()),
      );

      expect(DatabaseLibraryProvider.operationQueue.busyCount.value, 0);
      expect((await library.list()).single.enabled, isTrue);
      expect(await storedLinks(), hasLength(1));
    });

    test('כשל ב-removeAll מחזיר גם את טבלאות הבסיס', () async {
      await legacyLink();
      await library.addFiles([linksFile('קישורים.csv')]);
      final raw = await db.database;
      final baselineBefore = raw.select(
        'SELECT * FROM import_baseline_user_link',
      );
      expect(baselineBefore, hasLength(1));
      raw.execute(
        'CREATE TRIGGER fail_import_clear BEFORE DELETE ON '
        "user_link BEGIN SELECT RAISE(FAIL, 'blocked'); END",
      );

      await expectLater(library.removeAll(), throwsA(isA<Exception>()));

      expect(await library.list(), hasLength(1));
      expect(await storedLinks(), hasLength(2));
      expect(
        raw.select('SELECT * FROM import_baseline_user_link'),
        baselineBefore,
      );
    });

    test('מופעי ספרייה על אותו מסד מבצעים שינוי ובנייה בזה אחר זה', () async {
      final entered = Completer<void>();
      final release = Completer<void>();
      final slow = UserImportLibrary(
        db,
        resolveRef:
            ({
              required targetTitle,
              required targetCategoryId,
              required targetIsUserBook,
              required ref,
            }) async => int.tryParse(ref),
        sourceExists:
            ({required title, categoryId, required isUserBook}) async {
              entered.complete();
              await release.future;
              return true;
            },
      );
      final first = slow.addFiles([linksFile('קישורים.csv')]);
      await entered.future;
      var secondFinished = false;
      final second = library.removeAll().then((value) {
        secondFinished = true;
        return value;
      });
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(secondFinished, isFalse);
      expect(DatabaseLibraryProvider.operationQueue.busyCount.value, 2);

      release.complete();
      expect((await first).ok, isTrue);
      expect((await second).ok, isTrue);
      expect(await library.list(), isEmpty);
      expect(await storedLinks(), isEmpty);
      expect(DatabaseLibraryProvider.operationQueue.busyCount.value, 0);
    });

    test('הפתירה רצה בלי טרנזקציה פתוחה על החיבור הראשי', () async {
      final raw = await db.database;
      final autocommitDuringResolve = <bool>[];
      final resolving = UserImportLibrary(
        db,
        resolveRef:
            ({
              required targetTitle,
              required targetCategoryId,
              required targetIsUserBook,
              required ref,
            }) async {
              autocommitDuringResolve.add(raw.autocommit);
              return 11;
            },
        sourceExists:
            ({required title, categoryId, required isUserBook}) async => true,
      );
      final path = write(
        'קישורים.csv',
        'ספר_מקור,מקור_אישי,מקור,ספר_יעד,מיקום_יעד,סוג,יעד_אישי\n'
            'ברכות,לא,3,מפרש,פרק א,הפניה,כן\n',
      );

      expect((await resolving.addFiles([path])).allErrors, isEmpty);
      expect(autocommitDuringResolve, [isTrue]);
      expect((await storedLinks()).single.targetLineIndex, 11);
    });

    test('בלי הזרקה הפתירה האמיתית רצה ב-isolate ונכתבת באטומיות', () async {
      final raw = await db.database;
      raw.execute(
        "INSERT INTO book (categoryId, sourceId, title) VALUES (1, 1, 'מקור')",
      );
      raw.execute(
        "INSERT INTO book (categoryId, sourceId, title) VALUES (1, 1, 'מפרש')",
      );
      final targetId = raw.lastInsertRowId;
      raw.execute("INSERT INTO tocText (text) VALUES ('פרק א')");
      raw.execute(
        'INSERT INTO tocEntry (bookId, textId, level, lineIndex) '
        'VALUES (?, ?, 1, 7)',
        [targetId, raw.lastInsertRowId],
      );
      String userLinks(String name) => write(
        name,
        'מקור_אישי,מקור,ספר_יעד,מיקום_יעד,סוג,יעד_אישי\n'
        'כן,3,מפרש,פרק א,הפניה,כן\n',
      );
      final real = UserImportLibrary(db);

      final ok = await real.addFiles([userLinks('מקור.links.csv')]);
      expect(ok.allErrors, isEmpty);
      expect(ok.rebuild.linksApplied, 1);
      Future<List<UserLinkRecord>> links() =>
          repo.forwardUserLinks('מקור', sourceIsUserBook: true);
      expect((await links()).single.targetLineIndex, 7);

      final failed = await real.addFiles([userLinks('חסר.links.csv')]);
      expect(failed.allErrors.single, contains('חסר'));
      expect(await real.list(), hasLength(1));
      expect((await links()).single.targetLineIndex, 7);
    });

    test('קובץ שנמחק מהדיסק ממשיך לפעול מהתוכן השמור', () async {
      final path = linksFile('קישורים.csv');
      await library.addFiles([path]);
      File(path).deleteSync();

      // בנייה מחדש (כמו אחרי השהיה) אינה נוגעת בדיסק.
      final id = (await library.list()).single.id;
      expect((await library.setEnabled(id, true)).ok, isTrue);
      expect(await storedLinks(), hasLength(1));
    });
  });
}
