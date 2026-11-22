import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/attached_libraries/models/attached_library.dart';
import 'package:otzaria/attached_libraries/repository/attached_library_probe.dart';
import 'package:otzaria/migration/database/untrusted_database.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sqlite3;

import '../helpers/seforim_fixture_db.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('otzaria_probe');
  });

  tearDown(() async {
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  void execute(String dbPath, String sql) {
    final db = sqlite3.sqlite3.open(dbPath);
    try {
      db.execute(sql);
    } finally {
      db.close();
    }
  }

  group('בדיקת קובץ', () {
    test('קובץ שאינו קיים', () {
      final result = AttachedLibraryProbe.probeSync(
        p.join(tempDir.path, 'missing.db'),
      );
      expect(result.problem, AttachedLibraryProblem.notFound);
    });

    test('קובץ שאינו SQLite נדחה לפי הכותרת', () {
      final path = p.join(tempDir.path, 'fake.db');
      File(path).writeAsStringSync('not a database ' * 20);
      expect(
        AttachedLibraryProbe.probeSync(path).problem,
        AttachedLibraryProblem.notSqlite,
      );
    });

    test('מסד בלי טבלת book נדחה', () {
      final path = p.join(tempDir.path, 'empty.db');
      execute(path, 'CREATE TABLE something (id INTEGER)');
      expect(
        AttachedLibraryProbe.probeSync(path).problem,
        AttachedLibraryProblem.noBooks,
      );
    });

    test('מסד מלא: יכולות, מספר ספרים וטביעת אצבע', () {
      final path = SeforimFixtureDb.create(
        tempDir,
        SeforimFixtureVariant.full,
      );
      final result = AttachedLibraryProbe.probeSync(path);
      expect(result.isOk, isTrue);
      expect(result.bookCount, 2);
      expect(result.slug, 'full');
      expect(result.displayName, 'full');
      expect(result.immutable, isFalse);
      expect(result.fingerprint!.size, File(path).lengthSync());
      expect(result.fingerprint!.dbVersion, '1');
      expect(
        result.capabilities,
        containsAll([
          AttachedLibraryCapability.categories,
          AttachedLibraryCapability.toc,
          AttachedLibraryCapability.links,
          AttachedLibraryCapability.authors,
        ]),
      );
    });

    test('VIEW או טבלה וירטואלית בשם מוכר אינם יכולת', () {
      final path = SeforimFixtureDb.create(
        tempDir,
        SeforimFixtureVariant.viewImpostor,
      );
      final result = AttachedLibraryProbe.probeSync(path);
      expect(result.isOk, isTrue);
      expect(
        result.capabilities,
        isNot(contains(AttachedLibraryCapability.authors)),
      );
      expect(
        result.capabilities,
        isNot(contains(AttachedLibraryCapability.links)),
      );
      expect(
        result.capabilities,
        isNot(contains(AttachedLibraryCapability.acronyms)),
      );
    });

    test('טבלאות תוסף אינן משפיעות על הבדיקה', () {
      final plain = AttachedLibraryProbe.probeSync(
        SeforimFixtureDb.create(tempDir, SeforimFixtureVariant.full),
      );
      final withPlugins = AttachedLibraryProbe.probeSync(
        SeforimFixtureDb.create(tempDir, SeforimFixtureVariant.pluginTables),
      );
      expect(withPlugins.isOk, isTrue);
      expect(withPlugins.capabilities, plain.capabilities);
      expect(withPlugins.bookCount, plain.bookCount);
    });

    test('מסד minimal (book + line בלבד) תקין', () {
      final result = AttachedLibraryProbe.probeSync(
        SeforimFixtureDb.create(tempDir, SeforimFixtureVariant.minimal),
      );
      expect(result.isOk, isTrue);
      expect(result.capabilities, isEmpty);
    });
  });

  group('יומן תלוי', () {
    test('קובץ -wal לא ריק לצד המסד — נדחה ואינו נפתח לכתיבה', () {
      final path = SeforimFixtureDb.create(tempDir, SeforimFixtureVariant.full);
      final writer = sqlite3.sqlite3.open(path);
      addTearDown(writer.close);
      writer.execute('PRAGMA journal_mode=WAL');
      writer.execute('PRAGMA wal_autocheckpoint=0');
      writer.execute("INSERT INTO source VALUES (99, 'pending')");
      expect(File('$path-wal').lengthSync(), greaterThan(0));
      final before = File(path).lastModifiedSync();

      final result = AttachedLibraryProbe.probeSync(path);

      expect(result.problem, AttachedLibraryProblem.pendingJournal);
      expect(File(path).lastModifiedSync(), before);
    });

    test('יומן rollback חם נדחה', () {
      final path = SeforimFixtureDb.create(tempDir, SeforimFixtureVariant.full);
      File('$path-journal').writeAsBytesSync(List.filled(512, 1));
      expect(
        AttachedLibraryProbe.probeSync(path).problem,
        AttachedLibraryProblem.pendingJournal,
      );
    });

    test('מסד במצב WAL שנסגר כראוי נפתח כ-immutable, גם בנתיב עברי', () {
      final dir = Directory(p.join(tempDir.path, 'מסדים'))..createSync();
      final path = SeforimFixtureDb.create(dir, SeforimFixtureVariant.full);
      execute(path, 'PRAGMA journal_mode=WAL');
      expect(File('$path-wal').existsSync(), isFalse);

      final result = AttachedLibraryProbe.probeSync(path);

      expect(result.isOk, isTrue);
      expect(result.immutable, isTrue);
      expect(File('$path-wal').existsSync(), isFalse);
      expect(File('$path-shm').existsSync(), isFalse);
    });
  });

  group('slug', () {
    test('library_id מ-schema_meta גובר על שם הקובץ', () {
      final path = SeforimFixtureDb.create(tempDir, SeforimFixtureVariant.full);
      execute(
        path,
        "INSERT INTO schema_meta VALUES ('library_id', 'My Library'), "
        "('library_name', 'הספרייה שלי')",
      );
      final result = AttachedLibraryProbe.probeSync(path);
      expect(result.slug, 'my-library');
      expect(result.displayName, 'הספרייה שלי');
    });

    test('שם קובץ מנוקה לצורה חוקית', () {
      expect(
        AttachedLibraryProbe.slugFor(fileName: 'My DB (1)'),
        'my-db-1',
      );
      expect(
        AttachedLibraryProbe.slugFor(fileName: 'סְפָרִים שלי'),
        'ספרים-שלי',
      );
      expect(AttachedLibraryProbe.slugFor(fileName: '|||'), 'db');
      expect(
        AttachedLibraryProbe.slugFor(libraryId: 'a|b:c', fileName: 'x'),
        'a-b-c',
      );
      expect(
        AttachedLibraryProbe.slugFor(fileName: 'x' * 100).length,
        64,
      );
    });
  });

  group('פתיחה מוקשחת', () {
    test('query_only ו-trusted_schema כבויים, כתיבה נכשלת', () {
      final path = SeforimFixtureDb.create(tempDir, SeforimFixtureVariant.full);
      final db = openUntrustedReadOnlyDatabase(path);
      addTearDown(db.close);
      expect(db.select('PRAGMA query_only').first.values.first, 1);
      expect(db.select('PRAGMA trusted_schema').first.values.first, 0);
      expect(
        () => db.execute("INSERT INTO source VALUES (5, 'x')"),
        throwsA(isA<sqlite3.SqliteException>()),
      );
    });

    test('פתיחה immutable דרך URI', () {
      final path = SeforimFixtureDb.create(tempDir, SeforimFixtureVariant.full);
      final db = openUntrustedReadOnlyDatabase(path, immutable: true);
      addTearDown(db.close);
      expect(db.select('SELECT COUNT(*) AS c FROM book').first['c'], 2);
    });
  });
}
