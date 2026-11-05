import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/migration/database/daos/database.dart';
import 'package:otzaria/migration/database/repository/seforim_repository.dart';
import 'package:path/path.dart' as path;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late MyDatabase db;
  late SeforimRepository repo;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('otzaria-book-relations-');
    db = MyDatabase.withPath(path.join(tempDir.path, 'seforim.db'));
    repo = SeforimRepository(db);
    await repo.ensureInitialized();
    final raw = await db.database;
    raw.execute(
      "INSERT INTO book (id, categoryId, sourceId, title) "
      "VALUES (1, 1, 1, 'בראשית'), (2, 1, 1, 'שמות')",
    );
    raw.execute(
      "INSERT INTO author (id, name) VALUES (1, 'רש\"י'), (2, 'רמב\"ן')",
    );
    raw.execute("INSERT INTO topic (id, name) VALUES (1, 'תורה')");
    // Book 9 does not exist: its relation rows must not reach any book.
    raw.execute(
      'INSERT INTO book_author (bookId, authorId) VALUES (1, 1), (2, 2), (9, 1)',
    );
    raw.execute('INSERT INTO book_topic (bookId, topicId) VALUES (2, 1)');
  });

  tearDown(() async {
    db.close();
    await tempDir.delete(recursive: true);
  });

  test('getAllBooks attaches each book its own relations', () async {
    final books = {for (final b in await repo.getAllBooks()) b.id: b};

    expect(books.keys, unorderedEquals([1, 2]));
    expect(books[1]!.authors.map((a) => a.name), ['רש"י']);
    expect(books[1]!.topics, isEmpty);
    expect(books[2]!.authors.map((a) => a.name), ['רמב"ן']);
    expect(books[2]!.topics.map((t) => t.name), ['תורה']);
  });

  group('searchAuthorNames — מילים בכל סדר (issue #4037)', () {
    const alter = 'רבי יהודה אריה ליב אלתר';

    setUp(() async {
      final raw = await db.database;
      for (final name in [alter, 'א_ב', 'א%ב', 'א\\ב', 'אגב']) {
        raw.execute('INSERT INTO author (name) VALUES (?)', [name]);
      }
    });

    test('סדר הפוך ודילוג על מילים מוצאים את המחבר', () async {
      for (final query in ['יהודה אלתר', 'אלתר יהודה', ' ליב  רבי ']) {
        expect(await repo.searchAuthorNames(query), [alter], reason: query);
      }
      expect(await repo.searchAuthorNames('אלתר רמב"ן'), isEmpty);
    });

    test('%, _ ו-\\ בכל מילה נחשבים תווים רגילים', () async {
      expect(await repo.searchAuthorNames('_'), ['א_ב']);
      expect(await repo.searchAuthorNames('%'), ['א%ב']);
      expect(await repo.searchAuthorNames('\\'), ['א\\ב']);
      expect(await repo.searchAuthorNames('ב _'), ['א_ב']);
      expect(await repo.searchAuthorNames('ב %'), ['א%ב']);
    });
  });
}
