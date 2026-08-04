import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/migration/database/daos/database.dart';
import 'package:otzaria/migration/database/repository/seforim_repository.dart';
import 'package:path/path.dart' as path;

/// בדיקות ל-[SeforimRepository.compactIfFragmented] — כיווץ user_books.db
/// אחרי מחיקות, ואיסור מוחלט לגעת ב-DB שנפתח read-only (seforim.db).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late String dbPath;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('repo-compaction-');
    dbPath = path.join(tempDir.path, 'user_books.db');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  /// ממלא את הקובץ ב-[lines] שורות ומוחק את [deleted] הראשונות שבהן,
  /// כדי לייצר דפים פנויים. מחזיר את גודל הקובץ אחרי המחיקה.
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

  test('מכווץ את הקובץ אחרי מחיקה גורפת, והנתונים שנשארו שורדים', () async {
    final sizeBeforeCompaction = await seed(lines: 8000, deleted: 7900);

    final database = MyDatabase.withPath(dbPath);
    final repository = SeforimRepository(database);
    await repository.ensureInitialized();
    addTearDown(database.close);

    expect(await repository.compactIfFragmented(), isTrue);
    expect(File(dbPath).lengthSync(), lessThan(sizeBeforeCompaction ~/ 2));

    final db = await database.database;
    expect(db.select('SELECT count(*) FROM line').first.values.first, 100);
    // 2 = MEMORY. הכיווץ מעביר זמנית ל-FILE כדי לא לבנות עותק של כל ה-DB
    // ב-RAM, וחייב להחזיר את פרופיל הקריאה למקומו.
    expect(db.select('PRAGMA temp_store').first.values.first, 2);
  });

  test('לא מכווץ כשאין דפים פנויים', () async {
    final sizeBeforeCompaction = await seed(lines: 8000, deleted: 0);

    final database = MyDatabase.withPath(dbPath);
    final repository = SeforimRepository(database);
    await repository.ensureInitialized();
    addTearDown(database.close);

    expect(await repository.compactIfFragmented(), isFalse);
    expect(File(dbPath).lengthSync(), sizeBeforeCompaction);
  });

  test('לא מכווץ כששיעור הדפים הפנויים נמוך מהסף', () async {
    // ~5% מהשורות נמחקו — לא מצדיק כתיבה מחדש של כל הקובץ.
    final sizeBeforeCompaction = await seed(lines: 8000, deleted: 400);

    final database = MyDatabase.withPath(dbPath);
    final repository = SeforimRepository(database);
    await repository.ensureInitialized();
    addTearDown(database.close);

    expect(await repository.compactIfFragmented(), isFalse);
    expect(File(dbPath).lengthSync(), sizeBeforeCompaction);
  });

  test('חיבור read-only (seforim.db) אינו נכתב כלל', () async {
    await seed(lines: 8000, deleted: 7900);
    final bytesBeforeCompaction = md5.convert(File(dbPath).readAsBytesSync());

    final database = MyDatabase.withPath(dbPath, readOnly: true);
    final repository = SeforimRepository(database);
    await repository.ensureInitialized();
    addTearDown(database.close);

    expect(await repository.compactIfFragmented(), isFalse);
    expect(
      md5.convert(File(dbPath).readAsBytesSync()),
      bytesBeforeCompaction,
      reason: 'קובץ שנפתח read-only חייב להישאר זהה בית-בית',
    );
  });
}
