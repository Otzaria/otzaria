import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/migration/database/daos/database.dart';
import 'package:path/path.dart' as path;

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
