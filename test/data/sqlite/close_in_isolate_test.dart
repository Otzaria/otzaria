import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/sqlite/sqlite3_api.dart';
import 'package:otzaria/migration/database/daos/database.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;
  late String path;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('close_in_isolate_');
    path = p.join(tempDir.path, 'library.db');
    sqlite3.open(path)
      ..execute('CREATE TABLE t (x INTEGER); INSERT INTO t VALUES (1);')
      ..close();
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  test('closeInIsolate סוגר את החיבור ומשחרר את הקובץ', () async {
    final db = sqlite3.open(path, mode: OpenMode.readOnly);
    expect(db.select('SELECT x FROM t').single['x'], 1);

    await db.closeInIsolate();

    expect(() => db.select('SELECT 1'), throwsA(anything));
    // ב-Windows קובץ עם חיבור פתוח אינו נמחק.
    File(path).deleteSync();
  });

  test('closeInBackground של מסד לקריאה בלבד משחרר את הקובץ', () async {
    final database = MyDatabase.untrusted(path);
    expect((await database.database).select('SELECT x FROM t'), hasLength(1));

    final closing = database.closeInBackground();
    expect(database.isOpen, isFalse);
    await closing;

    File(path).deleteSync();
  });
}
