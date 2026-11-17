import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/sqlite/sqlite3_api.dart' as sqlite3;
import 'package:otzaria/migration/database/daos/database.dart';
import 'package:otzaria/migration/models/line.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('סמן הטווח קורא תוכן רק עד לשורה שבה ביקש הקורא לעצור', () async {
    const lineCount = 4096;
    const bookId = 1;
    final database = MyDatabase.withPath(':memory:');
    addTearDown(database.close);
    final sqlite = await database.database;
    sqlite.execute('PRAGMA foreign_keys = OFF');
    sqlite.execute(
      '''
      WITH RECURSIVE indices(i) AS (
        VALUES (0)
        UNION ALL SELECT i + 1 FROM indices WHERE i + 1 < ?
      )
      INSERT INTO line (bookId, lineIndex, content, heRef)
      SELECT ?, i, 'אב', 'הספר ' || i FROM indices
    ''',
      [lineCount, bookId],
    );

    var contentReads = 0;
    sqlite.createFunction(
      functionName: 'count_content_read',
      argumentCount: const sqlite3.AllowedArgumentCount(1),
      directOnly: false,
      function: (args) {
        contentReads++;
        return args.first;
      },
    );
    sqlite.execute('''
      CREATE TEMP VIEW line AS
      SELECT id, bookId, lineIndex, count_content_read(content) AS content,
             heRef, tocEntryId
      FROM main.line
    ''');

    final lines = database.lineDao;
    final eager = await lines.selectByBookIdRange(bookId, 0, lineCount - 1);
    expect(contentReads, lineCount);

    contentReads = 0;
    final first = <Line>[];
    final stopped = await lines.visitByBookIdRange(
      bookId,
      0,
      lineCount - 1,
      (line) {
        first.add(line);
        return true;
      },
    );
    expect(stopped, isTrue);
    expect(first, [eager.first]);
    expect(contentReads, 1);

    contentReads = 0;
    final range = <Line>[];
    final exhausted = await lines.visitByBookIdRange(bookId, 7, 9, (line) {
      range.add(line);
      return false;
    });
    expect(exhausted, isFalse);
    expect(range, eager.sublist(7, 10));
    expect(contentReads, 3);
  });
}
