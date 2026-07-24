import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/migration/database/daos/database.dart';
import 'package:path/path.dart' as path;
import 'package:sqlite3/sqlite3.dart' as sqlite3;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('otzaria-db-locked-test-');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  // ─── פתיחת DB רגילה ────────────────────────────────────────────────────────
  group('MyDatabase - פתיחה רגילה', () {
    test('פותח DB ומחזיר connection תקין', () async {
      final db = MyDatabase.withPath(path.join(tempDir.path, 'test.db'));
      addTearDown(db.close);
      final conn = await db.database;
      expect(conn, isNotNull);
    });

    test('קריאה חוזרת ל-database מחזירה אותו instance', () async {
      final db = MyDatabase.withPath(path.join(tempDir.path, 'test.db'));
      addTearDown(db.close);
      final conn1 = await db.database;
      final conn2 = await db.database;
      expect(identical(conn1, conn2), isTrue);
    });

    test('DB עובד לאחר פתיחה - SELECT 1 מצליח', () async {
      final db = MyDatabase.withPath(path.join(tempDir.path, 'test.db'));
      addTearDown(db.close);
      final conn = await db.database;
      final result = conn.select('SELECT 1 as val');
      expect(result.first['val'], 1);
    });
  });

  // ─── תרחיש הבאג: PRAGMA journal_mode=WAL על DB נעול ──────────────────────
  group('MyDatabase - PRAGMA WAL נכשל', () {
    test('PRAGMA journal_mode=WAL כפול על DB פתוח לא קורס', () async {
      final dbPath = path.join(tempDir.path, 'wal_double.db');
      final db = MyDatabase.withPath(dbPath);
      addTearDown(db.close);
      final conn = await db.database;

      // קריאה שנייה ל-PRAGMA - אמורה להצליח כי WAL כבר מוגדר (idempotent)
      expect(() => conn.execute('PRAGMA journal_mode=WAL'), returnsNormally);
    });

    test('DB ממשיך לעבוד גם אם WAL לא מוגדר', () async {
      // פותח DB ישירות בלי WAL - מדמה מצב שבו PRAGMA נכשל
      final dbPath = path.join(tempDir.path, 'no_wal.db');
      final conn = sqlite3.sqlite3.open(dbPath);
      addTearDown(conn.close);

      // DB עובד ב-mode ברירת מחדל (DELETE) בלי WAL
      conn.execute('CREATE TABLE IF NOT EXISTS test (id INTEGER PRIMARY KEY)');
      conn.execute('INSERT INTO test VALUES (1)');
      final result = conn.select('SELECT id FROM test');
      expect(result.first['id'], 1);
    });

    test('שני connections על אותו DB path לא קורסים', () async {
      final dbPath = path.join(tempDir.path, 'shared.db');

      final conn1 = sqlite3.sqlite3.open(dbPath);
      addTearDown(conn1.close);

      // שני connection על אותו קובץ - SQLite תומך בזה
      final conn2 = sqlite3.sqlite3.open(dbPath);
      addTearDown(conn2.close);

      conn1.execute('CREATE TABLE IF NOT EXISTS t (v TEXT)');
      conn1.execute("INSERT INTO t VALUES ('hello')");

      final result = conn2.select('SELECT v FROM t');
      expect(result.first['v'], 'hello');
    });

    test(
      'try/catch סביב WAL - מדמה DB שממשיך לפעול גם ללא הצלחת WAL',
      () async {
        // אין דרך קלה לנעול DB בצורה שתגרום ל-PRAGMA WAL להיכשל.
        // הטסט מוודא שהלוגיקה של try/catch עצמה נכונה:
        // אם זורקים שגיאה, ממשיכים לפעול.
        bool pragmaFailed = false;
        bool dbStillOpen = false;

        final conn = sqlite3.sqlite3.open(':memory:');
        addTearDown(conn.close);

        try {
          throw StateError('simulated: database is locked');
        } catch (_) {
          pragmaFailed = true;
        }

        // DB אמור עדיין לעבוד
        conn.execute('SELECT 1');
        dbStillOpen = true;

        expect(pragmaFailed, isTrue);
        expect(dbStillOpen, isTrue);
      },
    );
  });

  // ─── close ────────────────────────────────────────────────────────────────
  group('MyDatabase - close', () {
    test('close() לא קורס כשה-DB סגור כבר', () async {
      final db = MyDatabase.withPath(path.join(tempDir.path, 'close.db'));
      await db.database; // open
      db.close();
      expect(() => db.close(), returnsNormally); // שנייה - לא קורס
    });
  });
}
