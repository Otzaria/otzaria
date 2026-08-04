import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/sqlite/sqlite3_api.dart' as sqlite3;
import 'package:otzaria/migration/database/daos/database.dart';
import 'package:otzaria/migration/database/database_compaction.dart';
import 'package:path/path.dart' as path;

/// בדיקות לכיווץ קובצי SQLite — הקטנה בפועל אחרי מחיקות, אמינות מול קוראי
/// WAL מקבילים, ואיסור מוחלט לגעת ב-DB שנפתח read-only (`seforim.db`).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late String dbPath;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('db-compaction-');
    dbPath = path.join(tempDir.path, 'user_books.db');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  /// ממלא את הקובץ ב-[lines] שורות ומוחק את [deleted] הראשונות שבהן, כדי
  /// לייצר דפים פנויים. מחזיר את גודל הקובץ אחרי המחיקה.
  Future<int> seed({required int lines, required int deleted}) async {
    final database = MyDatabase.withPath(dbPath);
    final db = await database.database;
    db.execute('BEGIN');
    final content = 'א' * 500;
    for (var i = 0; i < lines; i++) {
      db.execute(
        'INSERT INTO line (bookId, lineIndex, content) VALUES (1, ?, ?)',
        [i, content],
      );
    }
    db.execute('COMMIT');
    if (deleted > 0) {
      db.execute('DELETE FROM line WHERE lineIndex < ?', [deleted]);
    }
    db.execute('PRAGMA wal_checkpoint(TRUNCATE)');
    database.close();
    return File(dbPath).lengthSync();
  }

  test('מכווץ אחרי מחיקה גורפת, והנתונים שנשארו שורדים', () async {
    final sizeBeforeCompaction = await seed(lines: 8000, deleted: 7900);

    expect(await compactSqliteFile(dbPath), isTrue);
    expect(File(dbPath).lengthSync(), lessThan(sizeBeforeCompaction ~/ 2));

    final database = MyDatabase.withPath(dbPath);
    addTearDown(database.close);
    final db = await database.database;
    expect(db.select('SELECT count(*) FROM line').first.values.first, 100);
  });

  test('לא מכווץ כשאין דפים פנויים', () async {
    final sizeBeforeCompaction = await seed(lines: 8000, deleted: 0);

    expect(await compactSqliteFile(dbPath), isFalse);
    expect(File(dbPath).lengthSync(), sizeBeforeCompaction);
  });

  test('לא מכווץ כששיעור הדפים הפנויים נמוך מהסף', () async {
    // ~5% מהשורות נמחקו — לא מצדיק כתיבה מחדש של כל הקובץ.
    final sizeBeforeCompaction = await seed(lines: 8000, deleted: 400);

    expect(await compactSqliteFile(dbPath), isFalse);
    expect(File(dbPath).lengthSync(), sizeBeforeCompaction);
  });

  test('קובץ שאינו קיים אינו נוצר', () async {
    expect(await compactSqliteFile(dbPath), isFalse);
    expect(await File(dbPath).exists(), isFalse);
  });

  group('checkpoint חסום על ידי קורא WAL מקביל', () {
    /// חיבור ארוך-חיים כמו שהאפליקציה מחזיקה לאורך הסשן. בלעדיו סגירת
    /// הקורא היא סגירת החיבור האחרון, ו-sqlite מריץ checkpoint אוטומטי
    /// שמסתיר את הבאג.
    sqlite3.Database openLongLivedConnection() {
      final connection = sqlite3.sqlite3.open(dbPath);
      connection.execute('PRAGMA busy_timeout=5000');
      connection.select('SELECT count(*) FROM line');
      return connection;
    }

    /// חיבור שמחזיק טרנזקציית קריאה פתוחה — כזה שחוסם
    /// `wal_checkpoint(TRUNCATE)` מלרוקן את היומן לקובץ הראשי.
    sqlite3.Database openBlockingReader() {
      final reader = sqlite3.sqlite3.open(dbPath);
      reader.execute('PRAGMA busy_timeout=100');
      reader.execute('BEGIN');
      reader.select('SELECT count(*) FROM line');
      return reader;
    }

    test('מחזיר false כשהקובץ לא התכווץ בפועל', () async {
      final sizeBeforeCompaction = await seed(lines: 8000, deleted: 7900);
      final appConnection = openLongLivedConnection();
      addTearDown(appConnection.close);
      final reader = openBlockingReader();
      addTearDown(reader.close);

      expect(
        await compactSqliteFile(dbPath),
        isFalse,
        reason: 'ה-PRAGMA מחזיר busy בלי לזרוק — אסור לדווח על הצלחה',
      );
      expect(File(dbPath).lengthSync(), sizeBeforeCompaction);
    });

    test('ריצה עוקבת מקטינה את הקובץ אחרי שהקורא השתחרר', () async {
      final sizeBeforeCompaction = await seed(lines: 8000, deleted: 7900);
      final appConnection = openLongLivedConnection();
      addTearDown(appConnection.close);

      final reader = openBlockingReader();
      expect(await compactSqliteFile(dbPath), isFalse);
      reader.execute('COMMIT');
      reader.close();
      expect(
        File(dbPath).lengthSync(),
        sizeBeforeCompaction,
        reason: 'שחרור הקורא לבדו אינו מקטין את הקובץ',
      );

      // ה-VACUUM כבר רץ, ולכן ה-freelist ריק ורק ההשוואה מול גודל הקובץ
      // מזהה שנשארה עבודה. בלעדיה הקובץ היה נשאר גדול לנצח.
      expect(await compactSqliteFile(dbPath), isTrue);
      expect(File(dbPath).lengthSync(), lessThan(sizeBeforeCompaction ~/ 2));
    });
  });

  test('חיבור read-only (seforim.db) אינו נכתב כלל', () async {
    await seed(lines: 8000, deleted: 7900);
    final bytesBeforeCompaction = md5.convert(File(dbPath).readAsBytesSync());

    final database = MyDatabase.withPath(dbPath, readOnly: true);
    addTearDown(database.close);

    expect(await compactDatabaseIfFragmented(database), isFalse);
    expect(
      md5.convert(File(dbPath).readAsBytesSync()),
      bytesBeforeCompaction,
      reason: 'קובץ שנפתח read-only חייב להישאר זהה בית-בית',
    );
  });

  test('חיבור כתיב מכווץ דרך compactDatabaseIfFragmented', () async {
    final sizeBeforeCompaction = await seed(lines: 8000, deleted: 7900);

    final database = MyDatabase.withPath(dbPath);
    addTearDown(database.close);

    expect(await compactDatabaseIfFragmented(database), isTrue);
    expect(File(dbPath).lengthSync(), lessThan(sizeBeforeCompaction ~/ 2));
  });
}
