import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/migration/database/daos/database.dart';
import 'package:otzaria/migration/database/repository/seforim_repository.dart';
import 'package:otzaria/migration/models/book.dart';
import 'package:otzaria/migration/models/category.dart';
import 'package:path/path.dart' as p;

/// רגרסיה ל-v3: getAllBookTitleToGeneration (מזין את splitByEra/מיון דורות)
/// חייב לקרוא דורות מטבלת book_generation. ב-v3 ל-author אין generationId
/// (עבר ל-book_generation); ה-query הישן נכשל ב-"no such column" וכל המפרשים
/// סווגו כ"שאר".
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late MyDatabase database;
  late SeforimRepository repository;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('otzaria-gen-v3-');
    database = MyDatabase.withPath(p.join(tempDir.path, 'test.db'));
    repository = SeforimRepository(database);
    await repository.ensureInitialized();
  });

  tearDown(() async {
    database.close();
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test('getAllBookTitleToGeneration קורא דורות מ-book_generation (v3)', () async {
    final db = await database.database;
    // book_generation נוצרת כעת ע"י סכמת האפליקציה (MyDatabase) — אין צורך
    // ליצור אותה ידנית.
    db.execute(
      "INSERT INTO generation (id, name) VALUES (1, 'ראשונים'), (2, 'אחרונים')",
    );

    final catId = await repository.insertCategory(const Category(title: 'ק'));
    final srcId = await repository.insertSource('s', -1);
    final id1 = await repository.insertBook(
      Book(
        id: 0,
        categoryId: catId,
        sourceId: srcId,
        title: 'רמב"ם',
        fileType: 'txt',
      ),
    );
    final id2 = await repository.insertBook(
      Book(
        id: 0,
        categoryId: catId,
        sourceId: srcId,
        title: 'משנה ברורה',
        fileType: 'txt',
      ),
    );
    db.execute(
      'INSERT INTO book_generation (bookId, generationId) VALUES (?, 1)',
      [id1],
    );
    db.execute(
      'INSERT INTO book_generation (bookId, generationId) VALUES (?, 2)',
      [id2],
    );

    final map = await database.authorDao.getAllBookTitleToGeneration();

    expect(map['רמב"ם'], 'ראשונים');
    expect(map['משנה ברורה'], 'אחרונים');
  });
}
