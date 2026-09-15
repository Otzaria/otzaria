import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:otzaria/migration/database/sqlite3_utils.dart';
import 'package:sqlite3/sqlite3.dart';

/// DB שכל `execute` בו נכשל בשגיאת ה-IO שדווחה בשטח (קוד 1546,
/// `SQLITE_IOERR_TRUNCATE`) — קטימת קובץ ה-journal חסומה.
class _TruncateBlockedDatabase implements Database {
  int executeCalls = 0;

  @override
  void execute(String sql, [List<Object?> parameters = const []]) {
    executeCalls++;
    throw SqliteException(
      extendedResultCode: 1546,
      message: 'disk I/O error',
      causingStatement: sql,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  test('WAL מופעל על קובץ תקין', () {
    final dir = Directory.systemTemp.createTempSync('plugins_host_wal');
    addTearDown(() => dir.deleteSync(recursive: true));
    final db = sqlite3.open(p.join(dir.path, 'plugins_host.db'));
    addTearDown(db.close);

    enableWalBestEffort(db, 'test');

    expect(db.select('PRAGMA journal_mode').first.values.first, 'wal');
  });

  test('closeWithCheckpoint ממזג את ה-WAL גם כשחיבור אחר פתוח', () {
    final dir = Directory.systemTemp.createTempSync('close_checkpoint');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = p.join(dir.path, 'personal_notes.db');
    final db = sqlite3.open(path);
    enableWalBestEffort(db, 'test');
    db.execute('CREATE TABLE t(x INTEGER)');
    db.execute('INSERT INTO t VALUES (1)');
    // חיבור של חלון מוסתר: בזכותו הסגירה אינה האחרונה.
    final other = sqlite3.open(path)..select('SELECT 1');
    addTearDown(other.close);

    closeWithCheckpoint(db);

    final wal = File('$path-wal');
    expect(!wal.existsSync() || wal.lengthSync() == 0, isTrue);
  });

  test('כשל בקטימת ה-journal אינו מפיל את פתיחת ה-DB', () {
    final db = _TruncateBlockedDatabase();

    expect(() => enableWalBestEffort(db, 'test'), returnsNormally);
    expect(db.executeCalls, 1);
  });
}
