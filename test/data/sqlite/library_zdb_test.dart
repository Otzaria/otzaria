import 'dart:io';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/constants/database_constants.dart';
import 'package:otzaria/data/data_providers/db_read_worker.dart';
import 'package:otzaria/data/sqlite/library_vfs.dart';
import 'package:otzaria/data/sqlite/sqlite3_api.dart';
import 'package:otzaria/migration/database/daos/database.dart';
import 'package:otzaria/migration/database/journal_mode.dart';
import 'package:otzaria/migration/database/repository/seforim_repository.dart';
import 'package:otzaria/migration/database/sqlite3_utils.dart';
import 'package:otzaria/migration/database/untrusted_database.dart';
import 'package:otzaria_zvfs/otzaria_zvfs.dart';
import 'package:path/path.dart' as p;

/// מסד הספרייה הדחוס (seforim.zdb) דרך zvfs כ-VFS ברירת המחדל, ומסדים רגילים
/// שעוברים דרכו ללא שינוי.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() => expect(ensureLibraryVfs(), isTrue));

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('library_zdb_test_');
  });

  tearDown(() async {
    DbReadWorker.disposeForTesting();
    await tempDir.delete(recursive: true);
  });

  /// מסד ספרייה קטן, ו-seforim.zdb שנוצר ממנו באותה תיקייה.
  Future<String> seedZdb() async {
    final plain = p.join(tempDir.path, 'source.db');
    final database = MyDatabase.withPath(plain);
    await SeforimRepository(database).ensureInitialized();
    final db = await database.database;
    db.execute("INSERT INTO category (id, title, level) VALUES (1, 'c', 0)");
    db.execute("INSERT INTO source (id, name) VALUES (1, 's')");
    db.execute(
      'INSERT INTO book (id, categoryId, sourceId, title, orderIndex, '
      "totalLines) VALUES (1, 1, 1, 'b', 1, 0)",
    );
    database.close();
    final zdb = p.join(tempDir.path, DatabaseConstants.zdbDatabaseFileName);
    await convertToZdb(source: ZdbSource.file(plain), destination: zdb);
    File(plain).deleteSync();
    return zdb;
  }

  group('resolveLibraryDbPath', () {
    test('בלי zdb — seforim.db, גם כשאינו קיים', () {
      expect(
        DatabaseConstants.resolveLibraryDbPath(tempDir.path),
        p.join(tempDir.path, 'seforim.db'),
      );
    });

    test('zdb תקין עדיף על seforim.db', () async {
      File(p.join(tempDir.path, 'seforim.db')).writeAsStringSync('legacy');
      final zdb = await seedZdb();
      expect(DatabaseConstants.resolveLibraryDbPath(tempDir.path), zdb);
      expect(
        DatabaseConstants.resolveLibraryDbSibling(
          p.join(tempDir.path, 'seforim.db'),
        ),
        zdb,
      );
    });

    test('seforim.zdb שאינו zdb נדחה', () {
      File(p.join(tempDir.path, 'seforim.zdb')).writeAsStringSync('x' * 64);
      expect(
        DatabaseConstants.resolveLibraryDbPath(tempDir.path),
        p.join(tempDir.path, 'seforim.db'),
      );
    });

    test('נתיב בשם אחר חוזר כמות שהוא', () {
      final other = p.join(tempDir.path, 'custom.db');
      expect(DatabaseConstants.resolveLibraryDbSibling(other), other);
    });

    test('libraryDbExistsIn מזהה כל אחד משני השמות', () async {
      expect(await DatabaseConstants.libraryDbExistsIn(tempDir.path), isFalse);
      File(p.join(tempDir.path, 'seforim.zdb')).writeAsStringSync('z');
      expect(await DatabaseConstants.libraryDbExistsIn(tempDir.path), isTrue);
    });
  });

  group('mmap', () {
    int mmapSize(Database db) =>
        db.select('PRAGMA mmap_size').first.values.first as int;

    test('zdb: mmap_size=0 בכל מסלולי הפתיחה', () async {
      final zdb = await seedZdb();

      final target = openReadOnlyTarget(trustedDbTarget(zdb));
      try {
        expect(mmapSize(target), 0);
      } finally {
        target.close();
      }

      final database = MyDatabase.withPath(
        zdb,
        readOnly: true,
        official: true,
      );
      final repository = SeforimRepository(database);
      try {
        await repository.ensureInitialized();
        expect(await database.bookDao.countAllBooks(), 1);
        expect(mmapSize(await database.database), 0);
        await repository.setReadBoostMode();
        expect(mmapSize(await database.database), 0);
      } finally {
        database.close();
      }
    });

    test('מסד רגיל שומר על mmap', () async {
      final plain = p.join(tempDir.path, 'seforim.db');
      sqlite3.open(plain)
        ..execute('CREATE TABLE t (x)')
        ..close();
      final db = openReadOnlyTarget(trustedDbTarget(plain));
      try {
        expect(mmapSize(db), 67108864);
      } finally {
        db.close();
      }
    });
  });

  group('normalizeJournalModeForReadOnly על zdb', () {
    test('כותרת לוגית במצב WAL מנורמלת ל-rollback', () async {
      final zdb = await seedZdb();
      // בכותרת הגולמית של zdb בתים 18/19 אינם של SQLite; רק הקריאה הלוגית
      // רואה את ה-WAL שנכתב ל-overlay.
      final rw = sqlite3.open(zdb);
      rw.execute('PRAGMA journal_mode=WAL');
      rw.close();
      expect(readZdbBytes(zdb, 18, 2), [2, 2]);

      await normalizeJournalModeForReadOnly(zdb);

      expect(readZdbBytes(zdb, 18, 2), [1, 1]);
      final ro = sqlite3.open(zdb, mode: OpenMode.readOnly);
      try {
        expect(ro.select('SELECT count(*) AS n FROM book').first['n'], 1);
      } finally {
        ro.close();
      }
      expect(File('$zdb-wal').existsSync(), isFalse);
    });

    test('zdb פתוח בתהליך אינו נקרא מחדש', () async {
      final zdb = await seedZdb();
      final open = sqlite3.open(zdb, mode: OpenMode.readOnly);
      try {
        open.select('SELECT 1 FROM book');
        expect(isLibraryDbOpenInProcess(zdb), isTrue);
        // readZdbBytes היה נכשל כאן ב-busy; הנרמול מדלג בלי לגעת בקובץ.
        await normalizeJournalModeForReadOnly(zdb);
        expect(open.select('SELECT count(*) AS n FROM book').first['n'], 1);
      } finally {
        open.close();
      }
    });
  });

  test('warmUp משאיר את ה-zdb פתוח ב-worker עד סגירת החיבור', () async {
    final zdb = await seedZdb();
    expect(isLibraryDbOpenInProcess(zdb), isFalse);

    await DbReadWorker.warmUp(zdb);
    expect(isLibraryDbOpenInProcess(zdb), isTrue);

    await DbReadWorker.closeConnectionIfRunning();
    expect(isLibraryDbOpenInProcess(zdb), isFalse);
    DbReadWorker.allowReopen();
  });

  group('מסדים רגילים דרך zvfs (passthrough)', () {
    test('WAL, כתיבה ב-isolate אחד וקריאה מקבילה באחר', () async {
      final path = p.join(tempDir.path, 'user_state.db');
      final db = openWritableDatabase(path, 'test');
      try {
        expect(
          db.select('PRAGMA journal_mode').first.values.first,
          'wal',
        );
        db.execute('CREATE TABLE note (id INTEGER PRIMARY KEY, body TEXT)');
        db.execute("INSERT INTO note (body) VALUES ('a')");
        expect(isLibraryZdb(path), isFalse);

        final written = await Isolate.run(() {
          final other = openWritableDatabase(path, 'isolate');
          try {
            other.execute("INSERT INTO note (body) VALUES ('b')");
            return other.select('SELECT count(*) AS n FROM note').first['n'];
          } finally {
            other.close();
          }
        });
        expect(written, 2);

        final reads = await Future.wait([
          for (var i = 0; i < 3; i++)
            Isolate.run(() {
              final ro = sqlite3.open(path, mode: OpenMode.readOnly);
              try {
                return ro.select('SELECT count(*) AS n FROM note').first['n'];
              } finally {
                ro.close();
              }
            }),
        ]);
        expect(reads, [2, 2, 2]);
        expect(db.select('SELECT count(*) AS n FROM note').first['n'], 2);
      } finally {
        db.close();
      }
      expect(File(path).readAsBytesSync().sublist(0, 6), 'SQLite'.codeUnits);
    });

    test('MyDatabase כתיב (כמו user_books.db) נפתח ונפתח מחדש', () async {
      final path = p.join(tempDir.path, 'user_books.db');
      final database = MyDatabase.withPath(path);
      await SeforimRepository(database).ensureInitialized();
      (await database.database).execute(
        "INSERT INTO category (id, title, level) VALUES (1, 'c', 0)",
      );
      database.close();

      final reopened = MyDatabase.withPath(path, readOnly: true);
      try {
        final rows = (await reopened.database).select(
          'SELECT count(*) AS n FROM category',
        );
        expect(rows.first['n'], 1);
      } finally {
        reopened.close();
      }
    });
  });
}
