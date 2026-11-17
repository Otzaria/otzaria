import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/sqlite/sqlite3_api.dart' as sqlite3;
import 'package:otzaria/migration/database/daos/database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final journal in ['DELETE', 'WAL']) {
    test('קריאת טווח אינה חוסמת כותב ב-$journal ושומרת על תמונת מצב', () async {
      final directory = Directory.systemTemp.createTempSync('line-dao-');
      addTearDown(() => directory.deleteSync(recursive: true));
      final path = '${directory.path}${Platform.pathSeparator}seforim.db';
      final writer = sqlite3.sqlite3.open(path);
      addTearDown(writer.close);
      writer.execute('PRAGMA busy_timeout=0');
      expect(
        writer.select('PRAGMA journal_mode=$journal').single.columnAt(0),
        journal.toLowerCase(),
      );
      writer.execute('''
        CREATE TABLE line (id INTEGER PRIMARY KEY, bookId, lineIndex, content);
        INSERT INTO line VALUES
          (1, 1, 8, 'אב'), (2, 1, 7, 'גד'), (3, 1, 6, 'הו'), (4, 2, 8, 'זח');
      ''');
      if (journal == 'WAL') writer.execute('PRAGMA wal_checkpoint(TRUNCATE)');

      final database = MyDatabase.withPath(path, readOnly: true);
      addTearDown(database.close);
      final reader = await database.database;
      expect(
        reader.select('PRAGMA journal_mode').single.columnAt(0),
        journal.toLowerCase(),
      );
      final dao = database.lineDao;
      final lines = (await dao.selectIndexedContentByBookIdRange(
        1,
        7,
        8,
      )).iterator;
      expect(lines.moveNext(), isTrue);
      expect(lines.current, (lineIndex: 7, content: 'גד'));

      writer.execute("UPDATE line SET content = 'כל' WHERE id = 1");
      if (journal == 'WAL') {
        final checkpoint = writer.select('PRAGMA wal_checkpoint(TRUNCATE)');
        expect(checkpoint.single['busy'], 0);
      }

      expect(lines.moveNext(), isTrue);
      expect(lines.current, (lineIndex: 8, content: 'אב'));
      expect(lines.moveNext(), isFalse);
      expect(await dao.selectIndexedContentByBookIdRange(1, 8, 8), [
        (lineIndex: 8, content: 'כל'),
      ]);
    });
  }

  test('תוכן מפוצל מפוענח לפי הצורך ושורה בלי תוכן מוחזרת ריקה', () async {
    final database = MyDatabase.withPath(':memory:');
    addTearDown(database.close);
    final sqlite = await database.database;
    sqlite.execute('''
      DROP TABLE line;
      CREATE TABLE line (id INTEGER PRIMARY KEY, bookId, lineIndex);
      CREATE TABLE line_content (id INTEGER PRIMARY KEY, content);
      INSERT INTO line VALUES (1, 1, 1), (2, 1, 2), (3, 1, 3);
      INSERT INTO line_content VALUES (1, 'אב'), (3, X'0102');
    ''');

    final dao = database.lineDao;
    final lines = await dao.selectIndexedContentByBookIdRange(1, 1, 3);
    expect(lines.take(2), [
      (lineIndex: 1, content: 'אב'),
      (lineIndex: 2, content: ''),
    ]);
    expect(() => lines.last, throwsFormatException);
  });
}
