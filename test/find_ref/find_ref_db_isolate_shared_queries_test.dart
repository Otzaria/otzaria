import 'dart:io';

import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/find_ref/repository/alt_toc_flat_entry.dart';
import 'package:otzaria/find_ref/repository/find_ref_db_isolate.dart';
import 'package:otzaria/migration/database/daos/database.dart';
import 'package:otzaria/migration/models/toc_entry.dart';
import 'package:otzaria/services/commentary_service.dart';
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

    // ה-worker מחזיר אובייקטים ולא Map: העתקת Map בין isolates יקרה פי 10.
    final List<TocEntry> toc = await isolate.getBookTocEntries(1);
    expect(toc.map((e) => e.id), [10, 11]);
    expect(toc.map((e) => e.text), ['פרק א', 'פרק ב']);
    expect(toc.map((e) => e.lineIndex), [0, 7]);
    expect(toc.map((e) => e.level), [0, 1]);
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
      isolate.getBookTocEntries(1),
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

  test('ביטול בחלון אחד אינו מבטל בקשות בחלון אחר', () async {
    final dbPath = await seedDb('seforim', 'בראשית');
    await Settings.setValue<String>(
      SettingsRepository.keyDbEffectivePath,
      dbPath,
    );
    final isolate = await FindRefDbIsolate.instance();
    addTearDown(isolate.disposeForTesting);
    final firstScope = FindRefDbIsolate.allocateSearchScope();
    final secondScope = FindRefDbIsolate.allocateSearchScope();

    FindRefDbIsolate.cancelSearchScopeIfRunning(firstScope, 2);
    await expectLater(
      isolate.getTocEntries(
        1,
        'בראשית',
        searchScope: firstScope,
        searchEpoch: 1,
      ),
      throwsA(isA<FindRefQueryCancelled>()),
    );
    expect(
      await isolate.getTocEntries(
        1,
        'בראשית',
        searchScope: secondScope,
        searchEpoch: 1,
      ),
      isNotEmpty,
    );
    expect(
      await isolate.getTocEntries(
        1,
        'בראשית',
        searchScope: firstScope,
        searchEpoch: 2,
      ),
      isNotEmpty,
    );
    expect(await isolate.getAllLocalBooksSlim(), hasLength(1));
  });

  test('ביטול במהלך spawn חוסם בקשה ישנה שמגיעה לאחר האתחול', () async {
    final dbPath = await seedDb('seforim', 'בראשית');
    await Settings.setValue<String>(
      SettingsRepository.keyDbEffectivePath,
      dbPath,
    );
    final scope = FindRefDbIsolate.allocateSearchScope();
    final spawning = FindRefDbIsolate.instance();
    FindRefDbIsolate.cancelSearchScopeIfRunning(scope, 2);
    final isolate = await spawning;
    addTearDown(isolate.disposeForTesting);

    await expectLater(
      isolate.getTocEntries(1, 'בראשית', searchScope: scope, searchEpoch: 1),
      throwsA(isA<FindRefQueryCancelled>()),
    );
    expect(
      await isolate.getTocEntries(
        1,
        'בראשית',
        searchScope: scope,
        searchEpoch: 2,
      ),
      isNotEmpty,
    );
  });

  test('שחרור scope מסיר את סימן הביטול בלי להשפיע על חלון אחר', () async {
    final dbPath = await seedDb('seforim', 'בראשית');
    await Settings.setValue<String>(
      SettingsRepository.keyDbEffectivePath,
      dbPath,
    );
    final isolate = await FindRefDbIsolate.instance();
    addTearDown(isolate.disposeForTesting);
    final released = FindRefDbIsolate.allocateSearchScope();
    final active = FindRefDbIsolate.allocateSearchScope();

    FindRefDbIsolate.cancelSearchScopeIfRunning(released, 2);
    FindRefDbIsolate.cancelSearchScopeIfRunning(active, 2);
    await expectLater(
      isolate.getTocEntries(1, 'בראשית', searchScope: released, searchEpoch: 1),
      throwsA(isA<FindRefQueryCancelled>()),
    );

    FindRefDbIsolate.releaseSearchScope(released);
    // A retired repository cannot send this in production. An explicit old
    // epoch here proves the worker no longer retains its watermark.
    expect(
      await isolate.getTocEntries(
        1,
        'בראשית',
        searchScope: released,
        searchEpoch: 1,
      ),
      isNotEmpty,
    );
    await expectLater(
      isolate.getTocEntries(1, 'בראשית', searchScope: active, searchEpoch: 1),
      throwsA(isA<FindRefQueryCancelled>()),
    );
  });

  test('דורות כמה מפרשים נפתרים בבקשה אחת, בסדר הבקשה', () async {
    final dbPath = await seedDb('seforim', 'רמב"ם');
    final database = MyDatabase.withPath(dbPath);
    final db = await database.database;
    db.execute(
      "INSERT INTO book (id, categoryId, sourceId, title, orderIndex, "
      "filePath, fileType) VALUES (2, 7, 1, 'משנה', 1, '/b/m.txt', 'txt'), "
      "(3, 7, 1, 'ספר בלי דור', 2, '/b/x.txt', 'txt')",
    );
    db.execute(
      "INSERT INTO generation (id, name) VALUES (1, 'ראשונים'), (2, 'חז\"ל')",
    );
    db.execute(
      'INSERT INTO book_generation (bookId, generationId) VALUES (1, 1), (2, 2)',
    );
    database.close();
    await Settings.setValue<String>(
      SettingsRepository.keyDbEffectivePath,
      dbPath,
    );
    final isolate = await FindRefDbIsolate.instance();
    addTearDown(isolate.disposeForTesting);

    expect(
      await isolate.getBookEras(['משנה', 'ספר בלי דור', 'רמב"ם', 'לא קיים']),
      [
        CommentaryEra.chazal,
        CommentaryEra.other,
        CommentaryEra.rishonim,
        CommentaryEra.other,
      ],
    );
  });

  group('חימום AltToc ברקע', () {
    const entryCount = 8;

    Future<String> seedAltTocDb({
      String name = 'seforim',
      String text = 'פרשה',
      int count = entryCount,
    }) async {
      final dbPath = await seedDb(name, 'בראשית');
      final database = MyDatabase.withPath(dbPath);
      final db = await database.database;
      db.execute(
        "INSERT INTO alt_toc_structure (id, bookId, key) VALUES (1, 1, 'p')",
      );
      for (var i = 0; i < count; i++) {
        db.execute(
          'INSERT INTO tocText (id, text) VALUES (?, ?)',
          [500 + i, '$text $i'],
        );
        // שורה נפרדת לכל ערך: ערכים באותה שורה הם כפילות שהחיפוש מצמצם.
        db.execute(
          'INSERT INTO line (id, bookId, lineIndex, content) '
          "VALUES (?, 1, ?, 'שורה')",
          [200 + i, 10 + i],
        );
        db.execute(
          'INSERT INTO alt_toc_entry (id, structureId, textId, level, lineId) '
          'VALUES (?, 1, ?, 1, ?)',
          [900 + i, 500 + i, 200 + i],
        );
      }
      database.close();
      await Settings.setValue<String>(
        SettingsRepository.keyDbEffectivePath,
        dbPath,
      );
      return dbPath;
    }

    /// מקטע של ערך אחד בכל שלב, עם השהיה אחרי כל מקטע. בברירת המחדל רק
    /// הנרמול איטי — כ-800ms.
    Future<FindRefDbIsolate> slowBuildIsolate({
      Duration phaseDelay = Duration.zero,
      Duration normalizeDelay = const Duration(milliseconds: 100),
    }) async {
      FindRefDbIsolate.debugAltTocBuildTuning = (
        chunkSize: 1,
        phaseDelay: phaseDelay,
        normalizeDelay: normalizeDelay,
      );
      addTearDown(() => FindRefDbIsolate.debugAltTocBuildTuning = null);
      final isolate = await FindRefDbIsolate.instance();
      addTearDown(isolate.disposeForTesting);
      expect(await isolate.getAllLocalBooksSlim(), hasLength(1));
      return isolate;
    }

    test('בקשה אינטראקטיבית אחרי החימום מסתיימת לפני שהחימום מסתיים', () async {
      await seedAltTocDb();
      final isolate = await slowBuildIsolate();

      var prewarmDone = false;
      final prewarm = isolate.prewarmAltTocFlat().then(
        (_) => prewarmDone = true,
      );
      await Future<void>.delayed(const Duration(milliseconds: 150));

      expect(await isolate.getTocEntries(1, 'בראשית'), isNotEmpty);
      expect(prewarmDone, isFalse, reason: 'הבקשה עקפה את החימום');

      await prewarm;
      expect(
        await isolate.searchAltTocFlat(
          const GlobalAltTocRequest(queryTokens: ['פרשה']),
        ),
        hasLength(entryCount),
      );
    });

    test('שלבי השאילתה והנתיבים מחולקים גם הם למקטעים', () async {
      await seedAltTocDb();
      // רק השלבים שלפני הנרמול איטיים: 8 ערכים לשאילתה ו-8 לנתיבים.
      final isolate = await slowBuildIsolate(
        phaseDelay: const Duration(milliseconds: 100),
        normalizeDelay: Duration.zero,
      );

      var prewarmDone = false;
      final prewarm = isolate.prewarmAltTocFlat().then(
        (_) => prewarmDone = true,
      );
      await Future<void>.delayed(const Duration(milliseconds: 250));

      expect(await isolate.getTocEntries(1, 'בראשית'), isNotEmpty);
      expect(prewarmDone, isFalse, reason: 'הבקשה עקפה את שלבי המסד');

      await prewarm;
      expect(
        await isolate.searchAltTocFlat(
          const GlobalAltTocRequest(queryTokens: ['פרשה']),
        ),
        hasLength(entryCount),
      );
    });

    test('חיפוש AltToc באמצע חימום משלים את הבנייה החלקית', () async {
      await seedAltTocDb();
      final isolate = await slowBuildIsolate();

      var prewarmDone = false;
      final prewarm = isolate.prewarmAltTocFlat().then(
        (_) => prewarmDone = true,
      );
      await Future<void>.delayed(const Duration(milliseconds: 250));

      expect(
        await isolate.searchAltTocFlat(
          const GlobalAltTocRequest(queryTokens: ['פרשה']),
        ),
        hasLength(entryCount),
      );
      expect(prewarmDone, isFalse);
      await prewarm;
      expect(
        await isolate.searchAltTocFlat(
          const GlobalAltTocRequest(queryTokens: ['פרשה', '3']),
        ),
        hasLength(1),
      );
    });

    test('החלפת ספרייה באמצע חימום זורקת את הבנייה הישנה', () async {
      await seedAltTocDb();
      final isolate = await slowBuildIsolate();

      final prewarm = isolate.prewarmAltTocFlat();
      await Future<void>.delayed(const Duration(milliseconds: 250));

      await seedAltTocDb(name: 'other', text: 'סימן', count: 3);
      FindRefDbIsolate.resetIfRunning();
      await prewarm;

      expect(
        await isolate.searchAltTocFlat(
          const GlobalAltTocRequest(queryTokens: ['פרשה']),
        ),
        isEmpty,
      );
      expect(
        await isolate.searchAltTocFlat(
          const GlobalAltTocRequest(queryTokens: ['סימן']),
        ),
        hasLength(3),
      );
    });

    test('ביטול הקלדה ממשיך לזרוק בקשות ממתינות בזמן חימום', () async {
      await seedAltTocDb();
      final isolate = await slowBuildIsolate();
      final scope = FindRefDbIsolate.allocateSearchScope();

      final prewarm = isolate.prewarmAltTocFlat();
      await Future<void>.delayed(const Duration(milliseconds: 150));
      final queued = [
        for (var i = 0; i < 20; i++)
          isolate.getTocEntries(
            1,
            'בראשית',
            searchScope: scope,
            searchEpoch: 1,
          ),
      ];
      FindRefDbIsolate.cancelSearchScopeIfRunning(scope, 2);

      var cancelled = 0;
      for (final future in queued) {
        try {
          await future;
        } on FindRefQueryCancelled {
          cancelled++;
        }
      }
      expect(cancelled, greaterThan(0));
      await prewarm;
      expect(
        await isolate.getTocEntries(
          1,
          'בראשית',
          searchScope: scope,
          searchEpoch: 2,
        ),
        isNotEmpty,
      );
    });

    test('חיפוש שממתין לבנייה אינו חוסם בקשות אחרות', () async {
      await seedAltTocDb();
      final isolate = await slowBuildIsolate();

      var searchDone = false;
      final search = isolate
          .searchAltTocFlat(const GlobalAltTocRequest(queryTokens: ['פרשה']))
          .then((rows) {
            searchDone = true;
            return rows;
          });
      await Future<void>.delayed(const Duration(milliseconds: 150));

      expect(await isolate.getTocEntries(1, 'בראשית'), isNotEmpty);
      expect(searchDone, isFalse, reason: 'הבקשה המתינה לכל הבנייה');
      expect(await search, hasLength(entryCount));
    });

    test('ביטול חיפוש שממתין לבנייה שומר את ההתקדמות', () async {
      await seedAltTocDb();
      final isolate = await slowBuildIsolate();
      final scope = FindRefDbIsolate.allocateSearchScope();

      final stale = isolate.searchAltTocFlat(
        const GlobalAltTocRequest(queryTokens: ['פרשה']),
        searchScope: scope,
        searchEpoch: 1,
      );
      await Future<void>.delayed(const Duration(milliseconds: 450));
      FindRefDbIsolate.cancelSearchScopeIfRunning(scope, 2);
      await expectLater(stale, throwsA(isA<FindRefQueryCancelled>()));

      // בלי ההתקדמות שנשמרה הבנייה הייתה מתחילה מחדש (כ-800ms).
      final stopwatch = Stopwatch()..start();
      expect(
        await isolate.searchAltTocFlat(
          const GlobalAltTocRequest(queryTokens: ['פרשה']),
          searchScope: scope,
          searchEpoch: 2,
        ),
        hasLength(entryCount),
      );
      expect(stopwatch.elapsed, lessThan(const Duration(milliseconds: 650)));
    });

    test('השהיה באמצע חימום משחררת את החיבור ואינה חושפת קאש חלקי', () async {
      await seedAltTocDb();
      final isolate = await slowBuildIsolate();
      addTearDown(FindRefDbIsolate.resumeAfterExternalWrite);

      var prewarmDone = false;
      final prewarm = isolate.prewarmAltTocFlat().then(
        (_) => prewarmDone = true,
      );
      await Future<void>.delayed(const Duration(milliseconds: 250));

      final stopwatch = Stopwatch()..start();
      expect(await FindRefDbIsolate.suspendForExternalWrite(), isTrue);
      expect(
        stopwatch.elapsed,
        lessThan(const Duration(milliseconds: 500)),
        reason: 'ההשהיה אינה ממתינה לסוף החימום',
      );
      await prewarm;
      expect(prewarmDone, isTrue);
      expect(
        await isolate.searchAltTocFlat(
          const GlobalAltTocRequest(queryTokens: ['פרשה']),
        ),
        isEmpty,
      );

      await FindRefDbIsolate.resumeAfterExternalWrite();
      expect(
        await isolate.searchAltTocFlat(
          const GlobalAltTocRequest(queryTokens: ['פרשה']),
        ),
        hasLength(entryCount),
      );
    });
  });

  test('שחרור scope במהלך spawn מנקה ביטול שהמתין לאתחול', () async {
    final dbPath = await seedDb('seforim', 'בראשית');
    await Settings.setValue<String>(
      SettingsRepository.keyDbEffectivePath,
      dbPath,
    );
    final scope = FindRefDbIsolate.allocateSearchScope();
    final spawning = FindRefDbIsolate.instance();
    FindRefDbIsolate.cancelSearchScopeIfRunning(scope, 2);
    FindRefDbIsolate.releaseSearchScope(scope);
    final isolate = await spawning;
    addTearDown(isolate.disposeForTesting);

    expect(
      await isolate.getTocEntries(
        1,
        'בראשית',
        searchScope: scope,
        searchEpoch: 1,
      ),
      isNotEmpty,
    );
  });
}
