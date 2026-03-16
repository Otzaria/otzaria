import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/migration/core/models/category.dart';
import 'package:otzaria/migration/core/models/toc_entry.dart';
import 'package:otzaria/migration/dao/daos/database.dart';
import 'package:otzaria/migration/dao/repository/seforim_repository.dart';
import 'package:path/path.dart' as path;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late MyDatabase database;
  late SeforimRepository repository;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp(
      'otzaria-negative-ids-test-',
    );
    database = MyDatabase.withPath(path.join(tempDir.path, 'test.db'));
    repository = SeforimRepository(database);
    await repository.ensureInitialized();
  });

  tearDown(() async {
    database.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  Future<int> createCategory() async {
    return repository.insertCategory(
      const Category(
        title: 'ספרים אישיים',
        parentId: null,
        level: 0,
      ),
    );
  }

  test(
      'insertExternalContentBook assigns negative ids and preserves toc hierarchy',
      () async {
    final categoryId = await createCategory();

    final bookId = await repository.insertExternalContentBook(
      categoryId: categoryId,
      title: 'ספר בדיקה',
      filePath: '/tmp/test-book.txt',
      fileType: 'txt',
      fileSize: 128,
      lastModified: 42,
      isPersonal: true,
      tocEntries: const [
        TocEntry(
          id: 1,
          bookId: 0,
          parentId: null,
          text: 'פרק א',
          level: 1,
          lineIndex: 0,
          hasChildren: true,
        ),
        TocEntry(
          id: 2,
          bookId: 0,
          parentId: 1,
          text: 'סימן א',
          level: 2,
          lineIndex: 5,
        ),
      ],
    );

    expect(bookId, lessThan(0));

    final storedBook = await repository.getBook(bookId);
    expect(storedBook, isNotNull);
    expect(storedBook!.id, bookId);

    final tocEntries = await repository.getBookTocs(bookId);
    expect(tocEntries, hasLength(2));
    expect(tocEntries.every((entry) => entry.id < 0), isTrue);

    final rootEntry = tocEntries.firstWhere((entry) => entry.level == 1);
    final childEntry = tocEntries.firstWhere((entry) => entry.level == 2);

    expect(childEntry.parentId, rootEntry.id);
  });

  test('insertTocEntry allocates negative ids when caller omits an id',
      () async {
    final categoryId = await createCategory();
    final bookId = await repository.insertExternalContentBook(
      categoryId: categoryId,
      title: 'ספר בלי תוכן',
      filePath: '/tmp/no-content.txt',
      fileType: 'txt',
      fileSize: 64,
      lastModified: 100,
      isPersonal: true,
    );

    final rootId = await repository.insertTocEntry(
      TocEntry(
        bookId: bookId,
        text: 'שער',
        level: 1,
        lineIndex: 0,
      ),
    );
    final childId = await repository.insertTocEntry(
      TocEntry(
        bookId: bookId,
        parentId: rootId,
        text: 'סעיף',
        level: 2,
        lineIndex: 1,
      ),
    );

    expect(rootId, lessThan(0));
    expect(childId, lessThan(0));

    final tocEntries = await repository.getBookTocs(bookId);
    final rootEntry = tocEntries.firstWhere((entry) => entry.id == rootId);
    final childEntry = tocEntries.firstWhere((entry) => entry.id == childId);

    expect(childEntry.parentId, rootEntry.id);
  });
}
