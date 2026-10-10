import 'dart:io';

import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/find_ref/repository/find_ref_db_isolate.dart';
import 'package:otzaria/migration/database/daos/database.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:path/path.dart' as path;

import '../test_helpers/memory_cache_provider.dart';

/// בקשת תוכן-העניינים המאוגדת ב-worker: תוצאה לכל ספר בסדר הבקשה, וביטול
/// שנבדק בין ספר לספר.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('otzaria_toc_batch');
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  tearDown(() async {
    FindRefDbIsolate.debugTocBatchBookDelay = null;
    try {
      await tempDir.delete(recursive: true);
    } on FileSystemException {
      // ב-Windows שחרור ה-handle של ה-worker אינו מיידי אחרי kill.
    }
  });

  /// [bookCount] ספרים, לכל אחד "פרק א" ו"פרק ב"; לספר 1 גם AltToc.
  Future<void> seedDb(int bookCount) async {
    final dbPath = path.join(tempDir.path, 'seforim.db');
    final database = MyDatabase.withPath(dbPath);
    final db = await database.database;
    db.execute("INSERT INTO category (id, title, level) VALUES (7, 'תנך', 0)");
    db.execute("INSERT INTO source (id, name) VALUES (1, 'אוצריא')");
    db.execute(
      "INSERT INTO tocText (id, text) VALUES (1, 'פרק א'), (2, 'פרק ב'), "
      "(3, 'פרשה נח')",
    );
    for (var b = 1; b <= bookCount; b++) {
      db.execute(
        'INSERT INTO book (id, categoryId, sourceId, title, orderIndex, '
        "filePath, fileType) VALUES (?, 7, 1, ?, ?, '/b/$b.txt', 'txt')",
        [b, 'ספר $b', b],
      );
      db.execute(
        'INSERT INTO line (id, bookId, lineIndex, content) VALUES '
        "(?, ?, 0, 'שורה'), (?, ?, 5, 'שורה ב')",
        [b * 10, b, b * 10 + 1, b],
      );
      db.execute(
        'INSERT INTO tocEntry (id, bookId, parentId, textId, level, lineId) '
        'VALUES (?, ?, NULL, 1, 1, ?), (?, ?, NULL, 2, 1, ?)',
        [b * 10, b, b * 10, b * 10 + 1, b, b * 10 + 1],
      );
    }
    db.execute(
      "INSERT INTO alt_toc_structure (id, bookId, key) VALUES (1, 1, 'p')",
    );
    db.execute(
      'INSERT INTO alt_toc_entry (id, structureId, textId, level, lineId) '
      'VALUES (900, 1, 3, 1, 11)',
    );
    database.close();
    await Settings.setValue<String>(
      SettingsRepository.keyDbEffectivePath,
      dbPath,
    );
  }

  List<String> refs(List<Map<String, dynamic>> rows) => [
    for (final row in rows) row['reference'] as String,
  ];

  test('תוצאה לכל ספר בסדר הבקשה, כולל נסיגה ודילוג על AltToc', () async {
    await seedDb(3);
    final isolate = await FindRefDbIsolate.instance();
    addTearDown(isolate.disposeForTesting);

    final results = await isolate.getTocForBooks([
      (
        bookId: 2,
        bookTitle: 'ספר 2',
        queryTokens: ['ב'],
        fallbackTokens: null,
        altTocTokens: null,
      ),
      (
        bookId: 1,
        bookTitle: 'ספר 1',
        queryTokens: ['חלק', 'א'],
        fallbackTokens: ['א'],
        altTocTokens: ['נח'],
      ),
      (
        bookId: 3,
        bookTitle: 'ספר 3',
        queryTokens: ['ב'],
        fallbackTokens: null,
        altTocTokens: ['נח'],
      ),
    ]);

    expect(results, hasLength(3));
    expect(
      refs(results[0].toc),
      refs(await isolate.getTocEntries(2, 'ספר 2', queryTokens: ['ב'])),
    );
    expect(results[0].toc, isNotEmpty);
    expect(results[0].altToc, isEmpty);
    expect(
      refs(results[1].toc),
      refs(await isolate.getTocEntries(1, 'ספר 1', queryTokens: ['א'])),
      reason: 'חיפוש ריק עם הזנב נסוג לחיפוש בלעדיו',
    );
    expect(results[1].toc, isNotEmpty);
    expect(
      refs(results[1].altToc),
      refs(await isolate.getAltTocEntries(1, 'ספר 1', queryTokens: ['נח'])),
    );
    expect(results[1].altToc, isNotEmpty);
    expect(results[2].altToc, isEmpty);
  });

  test('ביטול באמצע האצווה עוצר אותה לפני הספרים הבאים', () async {
    const bookCount = 20;
    const perBook = Duration(milliseconds: 100);
    await seedDb(bookCount);
    FindRefDbIsolate.debugTocBatchBookDelay = perBook;
    final isolate = await FindRefDbIsolate.instance();
    addTearDown(isolate.disposeForTesting);
    expect(await isolate.getAllLocalBooksSlim(), hasLength(bookCount));

    final scope = FindRefDbIsolate.allocateSearchScope();
    addTearDown(() => FindRefDbIsolate.releaseSearchScope(scope));
    final stopwatch = Stopwatch()..start();
    final batch = isolate.getTocForBooks(
      [
        for (var b = 1; b <= bookCount; b++)
          (
            bookId: b,
            bookTitle: 'ספר $b',
            queryTokens: ['א'],
            fallbackTokens: null,
            altTocTokens: null,
          ),
      ],
      searchScope: scope,
      searchEpoch: 1,
    );
    await Future<void>.delayed(perBook * 2.5);
    FindRefDbIsolate.cancelSearchScopeIfRunning(scope, 2);

    await expectLater(batch, throwsA(isA<FindRefQueryCancelled>()));
    expect(
      stopwatch.elapsed,
      lessThan(perBook * (bookCount ~/ 2)),
      reason: 'האצווה נעצרה ולא המשיכה עד סוף הספרים',
    );

    // ה-worker ממשיך לשרת את המחזור החדש.
    final fresh = await isolate.getTocForBooks(
      [
        (
          bookId: 1,
          bookTitle: 'ספר 1',
          queryTokens: ['א'],
          fallbackTokens: null,
          altTocTokens: null,
        ),
      ],
      searchScope: scope,
      searchEpoch: 2,
    );
    expect(fresh.single.toc, isNotEmpty);
  });

  List<TocBatchRequest> batchOf(int bookCount) => [
    for (var b = 1; b <= bookCount; b++)
      (
        bookId: b,
        bookTitle: 'ספר $b',
        queryTokens: ['א'],
        fallbackTokens: null,
        altTocTokens: null,
      ),
  ];

  test('בקשה אינטראקטיבית נענית בין ספר לספר ולא בסוף האצווה', () async {
    const bookCount = 20;
    const perBook = Duration(milliseconds: 100);
    await seedDb(bookCount);
    FindRefDbIsolate.debugTocBatchBookDelay = perBook;
    final isolate = await FindRefDbIsolate.instance();
    addTearDown(isolate.disposeForTesting);
    expect(await isolate.getAllLocalBooksSlim(), hasLength(bookCount));

    var batchDone = false;
    final batch = isolate
        .getTocForBooks(batchOf(bookCount), searchEpoch: 1)
        .whenComplete(() => batchDone = true);
    await Future<void>.delayed(perBook * 1.5);

    final stopwatch = Stopwatch()..start();
    expect(await isolate.getBookTocEntries(1), isNotEmpty);
    expect(
      stopwatch.elapsed,
      lessThan(perBook * 3),
      reason: 'פתיחת ספר ממתינה לספר אחד של האצווה לכל היותר',
    );
    expect(batchDone, isFalse);

    final results = await batch;
    expect(results, hasLength(bookCount));
    expect(results.every((r) => r.toc.isNotEmpty), isTrue);
  });

  test('שחרור ה-scope אחרי ביטול אינו מחייה את האצווה שרצה', () async {
    const bookCount = 20;
    const perBook = Duration(milliseconds: 100);
    await seedDb(bookCount);
    FindRefDbIsolate.debugTocBatchBookDelay = perBook;
    final isolate = await FindRefDbIsolate.instance();
    addTearDown(isolate.disposeForTesting);
    expect(await isolate.getAllLocalBooksSlim(), hasLength(bookCount));

    final scope = FindRefDbIsolate.allocateSearchScope();
    final batch = isolate.getTocForBooks(
      batchOf(bookCount),
      searchScope: scope,
      searchEpoch: 1,
    );
    await Future<void>.delayed(perBook * 2.5);
    final stopwatch = Stopwatch()..start();
    // סדר הסגירה של הדיאלוג: ביטול ואז שחרור.
    FindRefDbIsolate.cancelSearchScopeIfRunning(scope, 2);
    FindRefDbIsolate.releaseSearchScope(scope);

    await expectLater(batch, throwsA(isA<FindRefQueryCancelled>()));
    expect(stopwatch.elapsed, lessThan(perBook * 3));
  });
}
