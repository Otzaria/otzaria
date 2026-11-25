import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/migration/database/sqlite3_utils.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  late Database db;

  setUp(() {
    db = sqlite3.openInMemory()..execute('CREATE TABLE t (v INTEGER)');
  });

  tearDown(() => db.close());

  test('error after SQLite already rolled back keeps the original error', () {
    // SQLite מבטל בעצמו טרנזקציה אחרי disk I/O error (#5899).
    expect(
      () => withTransaction(db, () {
        db.execute('INSERT INTO t VALUES (1)');
        db.execute('ROLLBACK');
        throw StateError('disk I/O error');
      }),
      throwsA(isA<StateError>()),
    );
    expect(db.autocommit, isTrue);
    expect(db.select('SELECT * FROM t'), isEmpty);
  });

  test('error inside an active transaction rolls it back', () {
    expect(
      () => withTransaction(db, () {
        db.execute('INSERT INTO t VALUES (1)');
        throw StateError('boom');
      }),
      throwsA(isA<StateError>()),
    );
    expect(db.autocommit, isTrue);
    expect(db.select('SELECT * FROM t'), isEmpty);
  });

  test('success commits', () {
    withTransaction(db, () => db.execute('INSERT INTO t VALUES (1)'));
    expect(db.select('SELECT v FROM t').single['v'], 1);
  });
}
