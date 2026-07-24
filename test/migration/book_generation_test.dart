import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/migration/database/daos/database.dart';
import 'package:otzaria/migration/database/repository/seforim_repository.dart';
import 'package:path/path.dart' as path;
import 'package:sqlite3/sqlite3.dart' as sqlite3;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('getBookGenerationInfoByTitle (book_generation, v3)', () {
    late Directory tempDir;
    late String dbPath;
    late MyDatabase database;
    late SeforimRepository repo;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('otzaria_gen');
      dbPath = path.join(tempDir.path, 'db.sqlite');
      final setup = sqlite3.sqlite3.open(dbPath);
      setup.execute('CREATE TABLE book (id INTEGER PRIMARY KEY, title TEXT)');
      setup.execute(
        'CREATE TABLE generation (id INTEGER PRIMARY KEY, name TEXT)',
      );
      setup.execute(
        'CREATE TABLE book_generation (bookId INTEGER, generationId INTEGER)',
      );
      setup.execute("INSERT INTO book (id, title) VALUES (1, 'בראשית')");
      setup.execute("INSERT INTO book (id, title) VALUES (2, 'ספר בלי דור')");
      setup.execute("INSERT INTO generation (id, name) VALUES (2, 'ראשונים')");
      setup.execute(
        'INSERT INTO book_generation (bookId, generationId) VALUES (1, 2)',
      );
      setup.close();

      database = MyDatabase.withPath(dbPath, readOnly: true);
      repo = SeforimRepository(database);
    });

    tearDown(() async {
      database.close();
      await tempDir.delete(recursive: true);
    });

    test('מחזיר את הדור של הספר דרך טבלת book_generation', () async {
      final info = await repo.getBookGenerationInfoByTitle('בראשית');
      expect(info, isNotNull);
      expect(info!.generationName, 'ראשונים');
      expect(info.generationId, 2);
    });

    test('מחזיר null לספר ללא דור (LEFT JOIN לא מפיל ספר)', () async {
      final info = await repo.getBookGenerationInfoByTitle('ספר בלי דור');
      expect(info, isNull);
    });
  });
}
