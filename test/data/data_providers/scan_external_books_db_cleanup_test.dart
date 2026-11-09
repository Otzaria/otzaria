import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/data_providers/database_library_provider.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sqlite3;

/// A Directory.list stream can throw *after* the read-only SQLite connection
/// has opened. On Windows, deleting the DB file detects a leaked handle.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('failed folder enumeration releases its read-only DB connection',
      () async {
    final tempDir = await Directory.systemTemp.createTemp('scan-db-cleanup-');
    try {
      final dbPath = p.join(tempDir.path, 'user_books.db');
      final db = sqlite3.sqlite3.open(dbPath);
      try {
        db.execute('CREATE TABLE book (id INTEGER PRIMARY KEY)');
      } finally {
        db.close();
      }

      final missing = p.join(tempDir.path, 'removed-folder');
      await expectLater(
        scanExternalFolderForTest(missing, 'books', dbPath),
        throwsA(isA<FileSystemException>()),
      );

      // A failing scan must not retain the database file on Windows.
      await File(dbPath).delete();
      expect(await File(dbPath).exists(), isFalse);
    } finally {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    }
  });
}
