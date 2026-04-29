import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/migration/core/models/category.dart';
import 'package:otzaria/migration/core/models/line.dart';
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
      'otzaria-reference-resolution-test-',
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

  Future<int> createCategory() {
    return repository.insertCategory(
      const Category(title: 'בדיקה', parentId: null, level: 0),
    );
  }

  Future<int> createBook(
    int categoryId,
    String title, {
    List<TocEntry>? tocEntries,
  }) {
    return repository.insertExternalContentBook(
      categoryId: categoryId,
      title: title,
      filePath: '/tmp/$title.txt',
      fileType: 'txt',
      fileSize: 0,
      lastModified: 0,
      isPersonal: true,
      tocEntries: tocEntries,
    );
  }

  test('Gemara TOC resolves amud bet to "דף ב:" heading', () async {
    final categoryId = await createCategory();
    final bookId = await createBook(
      categoryId,
      'ברכות',
      tocEntries: const [
        TocEntry(
          id: 1,
          bookId: 0,
          text: 'ברכות',
          level: 0,
          lineIndex: 0,
          hasChildren: true,
        ),
        TocEntry(
          id: 2,
          bookId: 0,
          parentId: 1,
          text: 'דף ב.',
          level: 1,
          lineIndex: 1,
        ),
        TocEntry(
          id: 3,
          bookId: 0,
          parentId: 1,
          text: 'דף ב:',
          level: 1,
          lineIndex: 16,
        ),
      ],
    );

    final results = await repository.getTocEntriesForReference(
      bookId,
      'ברכות',
      queryTokens: const ['ב', 'ב'],
    );

    expect(results, hasLength(1));
    expect(results.single['reference'], equals('ברכות דף ב:'));
    expect(results.single['segment'], equals(16));
  });

  test('Tanach verse resolves through line.heRef, not chapter TOC', () async {
    final categoryId = await createCategory();
    final bookId = await createBook(categoryId, 'בראשית');

    await repository.insertLine(
      Line(
        bookId: bookId,
        lineIndex: 2,
        content: '(א) בראשית ברא',
        heRef: 'בראשית א, א',
      ),
    );

    final result = await repository.getLineEntryForReference(
      bookId,
      'בראשית',
      'בראשית א א',
    );

    expect(result, isNotNull);
    expect(result!['reference'], equals('בראשית א, א'));
    expect(result['segment'], equals(2));
  });

  test('Tanach verse with gershayim resolves through normalized line.heRef',
      () async {
    final categoryId = await createCategory();
    final bookId = await createBook(categoryId, 'תהילים');

    await repository.insertLine(
      Line(
        bookId: bookId,
        lineIndex: 2143,
        content: 'אַשְׁרֵי תְמִימֵי דָרֶךְ',
        heRef: 'תהילים קיט, א',
      ),
    );

    final result = await repository.getLineEntryForReference(
      bookId,
      'תהילים',
      'תהילים קי"ט א',
    );

    expect(result, isNotNull);
    expect(result!['reference'], equals('תהילים קיט, א'));
    expect(result['segment'], equals(2143));
  });
}
