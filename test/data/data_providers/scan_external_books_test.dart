/// Regression tests for the external-books scan isolate.
///
/// Core behavior under test:
///  1. Unchanged file (DB row with matching size+mtime) → filtered out, not returned.
///  2. Changed file (mismatched metadata) → returned with existingBookId set.
///  3. New file (not in DB) → returned with existingBookId == null.
///  4. Unsupported extensions are filtered out.
///  5. DB-open failure fallback: all files returned as new, existingBookId == null.
///  6. Phase-1 contract: in fallback mode existingBookId is null even for
///     files that exist in the DB (Phase 2 is responsible for final recheck).
///  7-9. Phase-2 recheck (recheckBeforeInsertForTest):
///       7. File already in DB, metadata unchanged → returns true (skip insert).
///       8. File not in DB → returns false (proceed to insert).
///       9. File in DB, metadata changed → returns true AND calls
///          updateExternalBookMetadata with the new values.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sqlite3;

import 'package:otzaria/data/data_providers/database_library_provider.dart';

// ---------------------------------------------------------------------------
// Helper: create a minimal sqlite3 DB that looks like the app's book table
// (only the columns the scan isolate queries: id, filePath, fileSize,
//  lastModified).
// ---------------------------------------------------------------------------

sqlite3.Database _createTestDb(String dbPath) {
  final db = sqlite3.sqlite3.open(dbPath);
  db.execute('''
    CREATE TABLE IF NOT EXISTS book (
      id           INTEGER PRIMARY KEY,
      filePath     TEXT,
      fileSize     INTEGER,
      lastModified INTEGER
    )
  ''');
  return db;
}

void _insertBook(
  sqlite3.Database db, {
  required int id,
  required String filePath,
  required int fileSize,
  required int lastModified,
}) {
  db.execute(
    'INSERT INTO book (id, filePath, fileSize, lastModified) VALUES (?, ?, ?, ?)',
    [id, filePath, fileSize, lastModified],
  );
}

// ---------------------------------------------------------------------------

void main() {
  late Directory tmpDir;
  late String dbPath;
  late sqlite3.Database db;

  setUp(() async {
    tmpDir = await Directory.systemTemp.createTemp('scan_external_books_test_');
    dbPath = p.join(tmpDir.path, 'test.db');
    db = _createTestDb(dbPath);
  });

  tearDown(() async {
    db.close();
    await tmpDir.delete(recursive: true);
  });

  // ── helpers ──────────────────────────────────────────────────────────────

  Future<File> createTxtFile(String name, {String content = 'hello'}) async {
    final file = File(p.join(tmpDir.path, name));
    await file.writeAsString(content);
    return file;
  }

  /// Closes the write handle, calls the scan, then re-opens for tearDown.
  Future<List<Map<String, Object?>>> runScan() async {
    db.close();
    final result = await scanExternalFolderForTest(
      tmpDir.path,
      'testFolder',
      dbPath,
    );
    db = sqlite3.sqlite3.open(dbPath);
    return result;
  }

  // ── tests ────────────────────────────────────────────────────────────────

  test(
    'regression: ספר ללא שינוי לא מוחזר מהסריקה (ללא parse TOC מיותר)',
    () async {
      final file = await createTxtFile('unchanged.txt');
      final stat = await file.stat();

      _insertBook(
        db,
        id: 1,
        filePath: file.path,
        fileSize: stat.size,
        lastModified: stat.modified.millisecondsSinceEpoch,
      );

      final result = await runScan();

      expect(
        result.map((r) => r['path']),
        isNot(contains(file.path)),
        reason: 'ספר ללא שינוי לא אמור להופיע בתוצאת הסריקה',
      );
    },
  );

  test(
    'ספר עם metadata ששונה מוחזר עם existingBookId (עדכון בלבד, לא הכנסה)',
    () async {
      final file = await createTxtFile('changed.txt');
      final stat = await file.stat();

      _insertBook(
        db,
        id: 42,
        filePath: file.path,
        fileSize: stat.size + 99, // stale size
        lastModified: stat.modified.millisecondsSinceEpoch,
      );

      final result = await runScan();

      final entry = result.firstWhere(
        (r) => r['path'] == file.path,
        orElse: () => {},
      );
      expect(entry, isNotEmpty, reason: 'ספר עם שינוי חייב להופיע בתוצאה');
      expect(
        entry['existingBookId'],
        equals(42),
        reason: 'existingBookId אמור להיות מזהה הספר הקיים ב-DB',
      );
    },
  );

  test('ספר חדש (לא נמצא ב-DB) מוחזר עם existingBookId == null', () async {
    await createTxtFile('newbook.txt');

    final result = await runScan();

    final entry = result.firstWhere(
      (r) => (r['path'] as String).endsWith('newbook.txt'),
      orElse: () => {},
    );
    expect(entry, isNotEmpty, reason: 'ספר חדש חייב להופיע בתוצאה');
    expect(
      entry['existingBookId'],
      isNull,
      reason: 'ספר חדש לא אמור לקבל existingBookId',
    );
  });

  test('קבצים שאינם נתמכים (.log) מסוננים; ‎.epub נתמך ונסרק', () async {
    await createTxtFile('book.txt');
    await File(p.join(tmpDir.path, 'notes.log')).writeAsString('x');
    await File(p.join(tmpDir.path, 'book.epub')).writeAsString('x');

    final result = await runScan();

    final paths = result.map((r) => r['path'] as String).toList();
    expect(paths.any((p) => p.endsWith('.log')), isFalse);
    expect(paths.any((p) => p.endsWith('.epub')), isTrue);
  });

  test(
    'fallback: כשה-DB לא נפתח, כל הקבצים מוחזרים כחדשים (existingBookId == null)',
    () async {
      final file = await createTxtFile('any.txt');
      final stat = await file.stat();
      // Register the file so it would normally be filtered.
      _insertBook(
        db,
        id: 7,
        filePath: file.path,
        fileSize: stat.size,
        lastModified: stat.modified.millisecondsSinceEpoch,
      );

      // Use a bogus DB path → sqlite3 open will fail → fallback to "new" mode.
      const badDbPath = '/nonexistent/path/that/cannot/exist.db';
      db.close();
      final result = await scanExternalFolderForTest(
        tmpDir.path,
        'testFolder',
        badDbPath,
      );
      db = sqlite3.sqlite3.open(dbPath);

      // The file should appear because the fallback treats everything as new.
      final entry = result.firstWhere(
        (r) => r['path'] == file.path,
        orElse: () => {},
      );
      expect(
        entry,
        isNotEmpty,
        reason: 'fallback: קובץ חייב להופיע כשה-DB לא זמין',
      );
      expect(
        entry['existingBookId'],
        isNull,
        reason: 'fallback: existingBookId חייב להיות null כי לא נבדק ה-DB',
      );
    },
  );

  test('Phase-1 contract: ב-fallback mode existingBookId הוא null גם לקבצים קיימים ב-DB — '
      'Phase 2 אחראי לבדיקה הסופית לפני insert', () async {
    // This is a structural test: we verify that _DiscoveredBook with
    // existingBookId == null AND a file that already has a DB row will be
    // caught by the Phase-2 getExternalBookByFilePath re-check.
    //
    // We test the scan side: even in fallback mode the field is null (not the
    // existing ID), which is correct — Phase 2 is responsible for the final
    // authoritative check. This validates the contract between Phase 1 and 2.
    final file = await createTxtFile('existing.txt');
    final stat = await file.stat();
    _insertBook(
      db,
      id: 99,
      filePath: file.path,
      fileSize: stat.size,
      lastModified: stat.modified.millisecondsSinceEpoch,
    );

    const badDbPath = '/nonexistent/path/that/cannot/exist.db';
    db.close();
    final result = await scanExternalFolderForTest(
      tmpDir.path,
      'testFolder',
      badDbPath,
    );
    db = sqlite3.sqlite3.open(dbPath);

    // Phase 1 returns it as "new" (existingBookId == null).
    // Phase 2 must call getExternalBookByFilePath before inserting.
    // We verify the Phase 1 contract: existingBookId is null in fallback mode.
    final entry = result.firstWhere(
      (r) => r['path'] == file.path,
      orElse: () => {},
    );
    expect(
      entry['existingBookId'],
      isNull,
      reason:
          'Phase 1 fallback מחזיר null — Phase 2 אחראי לבדיקה הסופית מול repository',
    );
  });

  // ── Phase-2 recheck (recheckBeforeInsertForTest) ─────────────────────────

  group('Phase-2 recheck via recheckBeforeInsertForTest', () {
    late _FakeRepository fakeRepo;

    setUp(() {
      fakeRepo = _FakeRepository();
    });

    test(
      'ספר קיים ב-DB עם metadata זהה → מחזיר true (דלג על insert)',
      () async {
        fakeRepo.books['/books/book.txt'] = _FakeBook(
          id: 5,
          fileSize: 100,
          lastModified: 1000,
        );

        final skip = await DatabaseLibraryProvider.recheckBeforeInsertForTest(
          repository: fakeRepo,
          filePath: '/books/book.txt',
          fileSize: 100,
          lastModified: 1000,
        );

        expect(skip, isTrue, reason: 'ספר קיים ב-DB — לא יש להכניס שוב');
        expect(
          fakeRepo.updateCalls,
          isEmpty,
          reason: 'metadata זהה — אין צורך בעדכון',
        );
      },
    );

    test('ספר לא קיים ב-DB → מחזיר false (בצע insert)', () async {
      // fakeRepo is empty — no file registered
      final skip = await DatabaseLibraryProvider.recheckBeforeInsertForTest(
        repository: fakeRepo,
        filePath: '/books/newbook.txt',
        fileSize: 200,
        lastModified: 9999,
      );

      expect(skip, isFalse, reason: 'ספר חדש — יש להכניס ל-DB');
      expect(fakeRepo.updateCalls, isEmpty);
    });

    test(
      'ספר קיים ב-DB עם metadata שונה → מחזיר true ומפעיל updateExternalBookMetadata',
      () async {
        fakeRepo.books['/books/changed.txt'] = _FakeBook(
          id: 7,
          fileSize: 50,
          lastModified: 111,
        );

        final skip = await DatabaseLibraryProvider.recheckBeforeInsertForTest(
          repository: fakeRepo,
          filePath: '/books/changed.txt',
          fileSize: 999, // שונה מה-DB
          lastModified: 222, // שונה מה-DB
        );

        expect(skip, isTrue, reason: 'ספר קיים ב-DB — לא יש להכניס שוב');
        expect(
          fakeRepo.updateCalls,
          hasLength(1),
          reason: 'updateExternalBookMetadata אמור להיקרא פעם אחת',
        );
        expect(
          fakeRepo.updateCalls.first,
          equals('7:999:222'),
          reason:
              'ה-update אמור להשתמש בערכים החדשים (id=7, size=999, mtime=222)',
        );
      },
    );
  });

  // ── PersonalBooksOperationQueue ──────────────────────────────────────────
  //
  // בדיקות 10–12: תיאום פעולות — הגנה על מרוץ lifecycle.
  //  10. פעולה שנייה מתחילה רק אחרי שהראשונה סיימה (serialization).
  //  11. busyCount עולה מיד בהוספה לתור ויורד עם סיום הפעולה.
  //  12. כישלון בפעולה לא חוסם פעולות עתידיות בתור.

  group('PersonalBooksOperationQueue', () {
    test('10. פעולה שנייה מתחילה רק אחרי שהראשונה מסיימת', () async {
      final queue = PersonalBooksOperationQueue();
      final log = <String>[];
      final gate = Completer<void>();

      final f1 = queue.enqueue(() async {
        log.add('op1_start');
        await gate.future;
        log.add('op1_end');
      });

      final f2 = queue.enqueue(() async {
        log.add('op2_start');
      });

      // נותן ל-microtasks לרוץ כך ש-op1 מתחיל
      await Future.microtask(() {});
      expect(
        log,
        equals(['op1_start']),
        reason: 'op2 לא אמורה להתחיל בעוד op1 עדיין רצה',
      );

      gate.complete();
      await Future.wait([f1, f2]);

      expect(
        log,
        equals(['op1_start', 'op1_end', 'op2_start']),
        reason: 'op2 התחילה רק אחרי ש-op1 הסתיימה',
      );
    });

    test('11. busyCount עולה בהוספה ויורד עם סיום', () async {
      final queue = PersonalBooksOperationQueue();
      final gate = Completer<void>();

      expect(queue.busyCount.value, 0);
      expect(queue.isBusy, isFalse);

      final f1 = queue.enqueue(() => gate.future);

      // busyCount עולה סינכרונית עם ה-enqueue
      expect(queue.busyCount.value, 1);
      expect(queue.isBusy, isTrue);

      gate.complete();
      await f1;

      expect(queue.busyCount.value, 0);
      expect(queue.isBusy, isFalse);
    });

    test('12. כישלון בפעולה לא חוסם פעולות הבאות בתור', () async {
      final queue = PersonalBooksOperationQueue();
      final log = <String>[];

      final f1 = queue.enqueue<void>(() async {
        log.add('op1_start');
        throw Exception('intentional failure');
      });

      final f2 = queue.enqueue(() async {
        log.add('op2_start');
      });

      await Future.wait([f1.catchError((_) {}), f2]);

      expect(
        log,
        equals(['op1_start', 'op2_start']),
        reason: 'op2 רצה גם אחרי כישלון של op1',
      );
      expect(
        queue.busyCount.value,
        0,
        reason: 'busyCount חוזר ל-0 גם אחרי כישלון',
      );
    });
  });
}

// ── Duck-typed fake repository for Phase-2 recheck tests ──────────────────

class _FakeBook {
  final int id;
  final int fileSize;
  final int lastModified;
  const _FakeBook({
    required this.id,
    required this.fileSize,
    required this.lastModified,
  });
}

/// Minimal duck-typed mock: only the two methods called by _recheckBeforeInsert.
class _FakeRepository {
  final Map<String, _FakeBook?> books = {};
  final List<String> updateCalls = [];

  Future<_FakeBook?> getExternalBookByFilePath(String path) async =>
      books[path];

  Future<void> updateExternalBookMetadata(
    int id,
    int fileSize,
    int lastModified,
  ) async {
    updateCalls.add('$id:$fileSize:$lastModified');
  }
}
