import 'dart:io';

import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/find_ref/repository/find_ref_db_isolate.dart';
import 'package:otzaria/migration/database/daos/database.dart';
import 'package:otzaria/migration/models/toc_entry.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:path/path.dart' as path;

import '../test_helpers/memory_cache_provider.dart';

/// ה-isolate המשותף מריץ עכשיו גם את סריקת טבלת `book` וגם את ה-TOC של פתיחת
/// ספר. הבדיקות מוודאות שהשאילתות חוזרות שלמות דרך ה-`SendPort`, שהחלפת נתיב
/// ספרייה מגיעה ל-worker, ושכשל פתיחה מגיע לקורא כחריגה ולא כרשימה ריקה.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  Future<String> seedDb(String name, String bookTitle) async {
    final dbPath = path.join(tempDir.path, '$name.db');
    final database = MyDatabase.withPath(dbPath);
    final db = await database.database;
    db.execute("INSERT INTO category (id, title, level) VALUES (7, 'תנך', 0)");
    db.execute("INSERT INTO source (id, name) VALUES (1, 'אוצריא')");
    db.execute(
      "INSERT INTO book (id, categoryId, sourceId, title, orderIndex, "
      "filePath, fileType) VALUES (1, 7, 1, '$bookTitle', 3, '/b/a.txt', 'txt')",
    );
    db.execute(
      "INSERT INTO tocText (id, text) VALUES (1, 'פרק א'), (2, 'פרק ב')",
    );
    db.execute(
      "INSERT INTO line (id, bookId, lineIndex, content) VALUES "
      "(100, 1, 0, 'שורה'), (101, 1, 7, 'שורה ב')",
    );
    db.execute(
      'INSERT INTO tocEntry (id, bookId, parentId, textId, level, lineId) '
      'VALUES (10, 1, NULL, 1, 0, 100), (11, 1, 10, 2, 1, 101)',
    );
    database.close();
    return dbPath;
  }

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('otzaria_shared_isolate');
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  tearDown(() async {
    try {
      await tempDir.delete(recursive: true);
    } on FileSystemException {
      // ב-Windows שחרור ה-handle של ה-worker אינו מיידי אחרי kill; תיקיית
      // ה-temp אינה חלק מהנבדק.
    }
  });

  test('בלי worker פעיל ההשהיה מדווחת שחרור — אין handle לשחרר', () async {
    addTearDown(FindRefDbIsolate.resumeAfterExternalWrite);
    expect(await FindRefDbIsolate.suspendForExternalWrite(), isTrue);
  });

  test('שאילתות הספרים וה-TOC חוזרות מה-worker דרך SendPort', () async {
    final dbPath = await seedDb('seforim', 'בראשית');
    await Settings.setValue<String>(
      SettingsRepository.keyDbEffectivePath,
      dbPath,
    );

    final isolate = await FindRefDbIsolate.instance();
    addTearDown(isolate.disposeForTesting);

    final books = await isolate.getAllLocalBooksSlim();
    expect(books, hasLength(1));
    expect(books.first['title'], 'בראשית');
    expect(books.first['fileType'], 'txt');
    expect(books.first['orderIndex'], 3);

    final toc = (await isolate.getBookTocRows(
      1,
    )).map(TocEntry.fromMap).toList();
    expect(toc.map((e) => e.text), ['פרק א', 'פרק ב']);
    expect(toc.map((e) => e.lineIndex), [0, 7]);
    expect(toc.last.parentId, 10);
  });

  test('החלפת נתיב הספרייה מגיעה ל-worker דרך resetIfRunning', () async {
    final first = await seedDb('seforim', 'בראשית');
    await Settings.setValue<String>(
      SettingsRepository.keyDbEffectivePath,
      first,
    );

    final isolate = await FindRefDbIsolate.instance();
    addTearDown(isolate.disposeForTesting);
    expect((await isolate.getAllLocalBooksSlim()).first['title'], 'בראשית');

    final second = await seedDb('other', 'שמות');
    await Settings.setValue<String>(
      SettingsRepository.keyDbEffectivePath,
      second,
    );
    FindRefDbIsolate.resetIfRunning();

    expect((await isolate.getAllLocalBooksSlim()).first['title'], 'שמות');
  });

  test(
    'השהיה לכתיבה חיצונית מונעת פתיחה עצלה, והשחרור נפתח על הנתיב החדש',
    () async {
      final first = await seedDb('seforim', 'בראשית');
      await Settings.setValue<String>(
        SettingsRepository.keyDbEffectivePath,
        first,
      );

      final isolate = await FindRefDbIsolate.instance();
      addTearDown(isolate.disposeForTesting);
      addTearDown(FindRefDbIsolate.resumeAfterExternalWrite);
      expect((await isolate.getAllLocalBooksSlim()).first['title'], 'בראשית');

      // ההשהיה מדווחת על שחרור מאומת. מחיקת הקובץ כאן היא רק הכנת התרחיש —
      // ‏unlink ב-macOS/Linux מצליח גם עם מתאר פתוח ואינו מוכיח דבר.
      expect(await FindRefDbIsolate.suspendForExternalWrite(), isTrue);
      await File(first).delete();

      // ההוכחה שאין חיבור: שאילתה בזמן ההשהיה מקבלת שגיאה במקום לפתוח
      // את ה-DB מחדש דרך ensureRepo העצל.
      await expectLater(
        isolate.getAllLocalBooksSlim(),
        throwsA(isA<StateError>()),
      );

      final second = await seedDb('replacement', 'שמות');
      await Settings.setValue<String>(
        SettingsRepository.keyDbEffectivePath,
        second,
      );
      await FindRefDbIsolate.resumeAfterExternalWrite();

      expect((await isolate.getAllLocalBooksSlim()).first['title'], 'שמות');
    },
  );

  test('כשל פתיחת DB מגיע לקורא כחריגה ולא כרשימה ריקה', () async {
    await Settings.setValue<String>(
      SettingsRepository.keyDbEffectivePath,
      path.join(tempDir.path, 'missing', 'seforim.db'),
    );

    final isolate = await FindRefDbIsolate.instance();
    addTearDown(isolate.disposeForTesting);

    await expectLater(
      isolate.getAllLocalBooksSlim(),
      throwsA(isA<StateError>()),
    );
    await expectLater(
      isolate.getBookTocRows(1),
      throwsA(isA<StateError>()),
    );
  });

  test('הקלדה חדשה זורקת מהתור את בקשות ההקלדה הקודמת', () async {
    final dbPath = await seedDb('seforim', 'בראשית');
    // ספר עם TOC גדול — בניית המטמון שלו היא הבקשה ה"ארוכה" שתופסת את
    // ה-worker, כך שהבקשות שאחריה ממתינות בתור בזמן שהביטול מגיע.
    final database = MyDatabase.withPath(dbPath);
    final db = await database.database;
    db.execute(
      "INSERT INTO book (id, categoryId, sourceId, title, orderIndex, "
      "filePath, fileType) VALUES (2, 7, 1, 'ספר גדול', 4, '/b/c.txt', 'txt')",
    );
    db.execute(
      'INSERT INTO tocText (id, text) '
      'WITH RECURSIVE n(i) AS (SELECT 100 UNION ALL SELECT i+1 FROM n '
      "WHERE i < 20100) SELECT i, 'סימן ' || i FROM n",
    );
    db.execute(
      'INSERT INTO line (id, bookId, lineIndex, content) '
      'WITH RECURSIVE n(i) AS (SELECT 100 UNION ALL SELECT i+1 FROM n '
      "WHERE i < 20100) SELECT i + 1000, 2, i - 100, 'x' FROM n",
    );
    db.execute(
      'INSERT INTO tocEntry (id, bookId, parentId, textId, level, lineId) '
      'WITH RECURSIVE n(i) AS (SELECT 100 UNION ALL SELECT i+1 FROM n '
      'WHERE i < 20100) SELECT i, 2, NULL, i, 1, i + 1000 FROM n',
    );
    database.close();

    await Settings.setValue<String>(
      SettingsRepository.keyDbEffectivePath,
      dbPath,
    );

    final isolate = await FindRefDbIsolate.instance();
    addTearDown(isolate.disposeForTesting);
    // מוודא שה-worker מוכן ושהחיבור פתוח, כדי שהמדידה תמדוד רק את התור.
    expect(await isolate.getAllLocalBooksSlim(), hasLength(2));

    // חימום מטמון ה-TOC של הספר, כדי שהמחיר שנמדד יהיה של התור ולא של בנייה
    // חד-פעמית. גם אחרי החימום כל שאילתה מחזירה 20 אלף ערכים — יקרה דיה
    // שהתור לא יתרוקן לפני שהביטול מגיע.
    expect(
      await isolate.getTocEntries(2, 'ספר גדול', queryTokens: ['סימן']),
      hasLength(20001),
    );

    final queued = [
      for (var i = 0; i < 40; i++)
        isolate.getTocEntries(2, 'ספר גדול', queryTokens: ['סימן']),
    ];
    // נותנים לכל השליחות לצאת, ואז מקדמים מחזור — כמו הקלדה חדשה.
    await Future<void>.delayed(const Duration(milliseconds: 20));
    isolate.beginSearchEpoch();

    var cancelled = 0;
    for (final future in queued) {
      try {
        await future;
      } on FindRefQueryCancelled {
        cancelled++;
      }
    }
    expect(
      cancelled,
      greaterThan(0),
      reason: 'בקשות ממתינות של המחזור הקודם חייבות להיזרק',
    );

    // הבקשה של המחזור החדש עוברת כרגיל.
    final after = await isolate.getTocEntries(1, 'בראשית');
    expect(after, isNotEmpty);
  });

  test('בקשה שאינה של איתור מקורות אינה מבוטלת בהקלדה חדשה', () async {
    final dbPath = await seedDb('seforim', 'בראשית');
    await Settings.setValue<String>(
      SettingsRepository.keyDbEffectivePath,
      dbPath,
    );

    final isolate = await FindRefDbIsolate.instance();
    addTearDown(isolate.disposeForTesting);

    final shared = isolate.getAllLocalBooksSlim();
    isolate.beginSearchEpoch();
    expect(await shared, hasLength(1));
  });
}
