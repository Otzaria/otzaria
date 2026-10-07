import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/book_protection/models/book_protection.dart';
import 'package:otzaria/book_protection/repository/book_protection_repository.dart';
import 'package:otzaria/migration/database/daos/database.dart';
import 'package:otzaria/migration/database/repository/seforim_repository.dart';
import 'package:otzaria/migration/models/book.dart' as migration_models;
import 'package:otzaria/migration/models/category.dart' as migration_models;
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/links.dart';
import 'package:path/path.dart' as path;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late MyDatabase database;
  late SeforimRepository repository;
  late int categoryId;

  Future<int> insertBook(String title) async {
    final sourceId = await repository.insertSource('src', -1);
    return repository.insertBook(
      migration_models.Book(
        categoryId: categoryId,
        sourceId: sourceId,
        title: title,
      ),
    );
  }

  Future<void> createTables() async {
    final db = await database.database;
    db.execute(
      'CREATE TABLE book_banner (bookId INTEGER PRIMARY KEY NOT NULL, '
      'text TEXT NOT NULL)',
    );
    db.execute(
      'CREATE TABLE book_protection (bookId INTEGER PRIMARY KEY NOT NULL, '
      'level INTEGER NOT NULL CHECK (level >= 1))',
    );
  }

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('otzaria-protection-');
    database = MyDatabase.withPath(path.join(tempDir.path, 'seforim.db'));
    repository = SeforimRepository(database);
    await repository.ensureInitialized();
    categoryId = await repository.insertCategory(
      migration_models.Category(title: 'קטגוריה', level: 0),
    );
    BookProtectionRepository.instance.debugRepositoryFor = (source) async =>
        source.isOfficial ? repository : null;
  });

  tearDown(() async {
    BookProtectionRepository.instance.debugReset();
    database.close();
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test('בלי הטבלאות — אין הגבלה ואין באנר', () async {
    await insertBook('ספר');
    final tables = await repository.getBookProtectionTables();
    expect(tables.levels, isEmpty);
    expect(tables.banners, isEmpty);
    expect(
      await BookProtectionRepository.instance.forBook(TextBook(title: 'ספר')),
      BookProtection.none,
    );
  });

  test('טבלאות קיימות — נטענות למפה לפי bookId', () async {
    final protectedId = await insertBook('ספר מוגן');
    final bannerId = await insertBook('ספר עם באנר');
    await createTables();
    final db = await database.database;
    db.execute('INSERT INTO book_protection VALUES (?, 2)', [protectedId]);
    db.execute('INSERT INTO book_banner VALUES (?, ?)', [bannerId, 'שורה\nב']);

    final tables = await repository.getBookProtectionTables();
    expect(tables.levels, {protectedId: 2});
    expect(tables.banners, {bannerId: 'שורה\nב'});
  });

  test('טבלה שנוספה אחרי הטעינה הראשונה נקלטת', () async {
    final id = await insertBook('ספר');
    expect((await repository.getBookProtectionTables()).levels, isEmpty);
    await createTables();
    final db = await database.database;
    db.execute('INSERT INTO book_protection VALUES (?, 1)', [id]);
    expect((await repository.getBookProtectionTables()).levels, {id: 1});
  });

  test('תוכן שהוחלף בלי שינוי סכמה נקלט אחרי invalidate', () async {
    final id = await insertBook('ספר');
    await createTables();
    expect((await repository.getBookProtectionTables()).levels, isEmpty);
    final db = await database.database;
    db.execute('INSERT INTO book_protection VALUES (?, 2)', [id]);
    repository.invalidateBookProtectionTables();
    expect((await repository.getBookProtectionTables()).levels, {id: 2});
  });

  test('איתור לפי ספר, גרסה חלופית, קישור וכותרת', () async {
    final id = await insertBook('ספר מוגן');
    await insertBook('ספר חופשי');
    await createTables();
    final db = await database.database;
    db.execute('INSERT INTO book_protection VALUES (?, 1)', [id]);
    db.execute('INSERT INTO book_banner VALUES (?, ?)', [id, 'כל הזכויות']);
    final service = BookProtectionRepository.instance;

    final byBook = await service.forBook(
      TextBook(title: 'ספר מוגן', categoryId: categoryId),
    );
    expect(byBook.level, 1);
    expect(byBook.bannerText, 'כל הזכויות');

    final version = await service.forBook(
      TextBook(title: 'ספר מוגן', versionTitle: 'מהדורה אחרת'),
    );
    expect(version.level, 1);

    expect(
      (await service.forBook(TextBook(title: 'ספר חופשי'))).isProtected,
      isFalse,
    );

    final link = Link(
      heRef: 'x',
      index1: 1,
      path2: 'ספר מוגן',
      index2: 1,
      connectionType: 'commentary',
      targetBookId: id,
    );
    expect((await service.forLink(link)).level, 1);

    final linkByTitle = Link(
      heRef: 'x',
      index1: 1,
      path2: 'ספר מוגן',
      index2: 1,
      connectionType: 'commentary',
    );
    expect((await service.forLink(linkByTitle)).level, 1);

    expect(
      (await service.strictestForTitles(['ספר חופשי', 'ספר מוגן'])).level,
      1,
    );
  });

  test('ספר אישי — לעולם ללא הגבלה, גם כשהכותרת זהה', () async {
    final id = await insertBook('ספר מוגן');
    await createTables();
    final db = await database.database;
    db.execute('INSERT INTO book_protection VALUES (?, 2)', [id]);

    final userBook = TextBook(title: 'ספר מוגן', source: BookSource.user);
    expect(
      await BookProtectionRepository.instance.forBook(userBook),
      BookProtection.none,
    );
  });
}
