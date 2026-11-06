import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/data/data_providers/db_read_worker.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:otzaria/migration/database/daos/book_dao.dart';
import 'package:otzaria/migration/database/daos/database.dart';
import 'package:otzaria/migration/models/book.dart';
import 'package:otzaria/search/library_line_source.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:path/path.dart' as path;
import 'package:sqlite3/sqlite3.dart' as sqlite3;

import '../support/fake_line_source_engine.dart';
import '../test_helpers/memory_cache_provider.dart';

void _failWorkerStartup() => throw StateError('worker unavailable for test');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final provider = SqliteDataProvider.instance;
  late Directory directory;
  late String dbPath;

  BookDao books() => provider.repository!.database.bookDao;

  Future<List<Book?>> lookups(BookDao dao) => Future.wait([
    dao.getBookById(1),
    dao.getBookByTitle('ספר'),
    dao.getBookByTitleAndCategory('ספר', 7),
    dao.getBookByTitleCategoryAndFileType('ספר', 7, 'txt'),
  ]);

  Future<void> shadowMainBookTable() async {
    final connection = await provider.repository!.database.database;
    connection.execute('PRAGMA query_only=OFF');
    connection.execute('CREATE TEMP TABLE book AS SELECT * FROM main.book');
    connection.execute('DELETE FROM temp.book');
  }

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('otzaria-book-lookup-');
    dbPath = path.join(directory.path, 'seforim.db');
    final connection = sqlite3.sqlite3.open(dbPath);
    try {
      connection.execute('CREATE TABLE category (id INTEGER PRIMARY KEY)');
      connection.execute('''
        CREATE TABLE book (
          id INTEGER PRIMARY KEY, title TEXT, categoryId INTEGER, fileType TEXT
        )
      ''');
      connection.execute('''
        INSERT INTO book VALUES
          (1, 'ספר', 7, 'txt'), (2, 'משותף', 7, 'txt'), (3, 'משותף', 8, 'pdf')
      ''');
    } finally {
      connection.close();
    }
    LibraryLineSource.debugReset(engine: FakeLineSourceEngine());
    await Settings.init(cacheProvider: MemoryCacheProvider());
    AppPaths.debugOverrideDataRootPath(path.join(directory.path, 'data'));
    await Settings.setValue(SettingsRepository.keyDbEffectivePath, dbPath);
    await provider.dispose();
    await provider.initialize();
  });

  tearDown(() async {
    DbReadWorker.workerSetUpForTesting = null;
    await DbReadWorker.resumeAfterExternalWrite();
    await provider.dispose();
    DbReadWorker.disposeForTesting();
    LibraryLineSource.debugReset();
    AppPaths.debugOverrideDataRootPath(null);
    await directory.delete(recursive: true);
  });

  test('official book lookups read on the worker connection', () async {
    await shadowMainBookTable();
    final before = DbReadWorker.sentMessageCount;
    final result = await lookups(books());

    expect(result.map((book) => book?.id), [1, 1, 1, 1]);
    expect(DbReadWorker.sentMessageCount - before, 1);
  });

  test(
    'lookup filters and missing books keep their existing meaning',
    () async {
      final dao = books();
      expect((await dao.getBookByTitleAndCategory('משותף', 8))?.id, 3);
      expect(
        (await dao.getBookByTitleCategoryAndFileType('משותף', 7, 'txt'))?.id,
        2,
      );
      expect(await dao.getBookById(99), isNull);
      expect(await dao.getBookByTitle('חסר'), isNull);
      expect(await dao.getBookByTitleAndCategory('ספר', 99), isNull);
      expect(
        await dao.getBookByTitleCategoryAndFileType('ספר', 7, 'pdf'),
        isNull,
      );
    },
  );

  test(
    'worker failure keeps book lookup fallback off the UI connection',
    () async {
      await shadowMainBookTable();
      DbReadWorker.workerSetUpForTesting = _failWorkerStartup;
      final before = DbReadWorker.sentMessageCount;

      expect((await lookups(books())).map((book) => book?.id), [1, 1, 1, 1]);
      expect(DbReadWorker.sentMessageCount, before);
    },
  );

  test('suspension rejects queued and new lookups until resumed', () async {
    await shadowMainBookTable();
    expect((await books().getBookById(1))?.id, 1);
    final queued = lookups(books());
    final queuedExpectation = expectLater(
      queued,
      throwsA(isA<DbReadWorkerSuspended>()),
    );
    expect(await DbReadWorker.suspendForExternalWrite(), isTrue);
    await queuedExpectation;
    await expectLater(lookups(books()), throwsA(isA<DbReadWorkerSuspended>()));

    await DbReadWorker.resumeAfterExternalWrite();
    expect((await lookups(books())).map((book) => book?.id), [1, 1, 1, 1]);
  });

  test(
    'a retained DAO cannot reopen the library after provider disposal',
    () async {
      final previous = books();
      expect((await previous.getBookById(1))?.id, 1);
      await provider.dispose();

      await expectLater(
        lookups(previous),
        throwsA(isA<DbReadWorkerSuspended>()),
      );
      await provider.initialize();
      expect((await lookups(books())).map((book) => book?.id), [1, 1, 1, 1]);
    },
  );

  test('worker lookups preserve support for a minimal book schema', () async {
    await provider.dispose();
    final connection = sqlite3.sqlite3.open(dbPath);
    try {
      connection.execute('DROP TABLE category');
      connection.execute('DROP TABLE book');
      connection.execute(
        'CREATE TABLE book (id INTEGER PRIMARY KEY, title TEXT)',
      );
      connection.execute("INSERT INTO book VALUES (1, 'ספר')");
    } finally {
      connection.close();
    }
    await provider.initialize();

    final result = await lookups(books());
    expect(result.map((book) => book?.id), [1, 1, 1, null]);
    expect(result.first!.categoryId, 0);
  });

  test('writable databases still read their own uncommitted changes', () async {
    final database = MyDatabase.withPath(path.join(directory.path, 'user.db'));
    final connection = await database.database;
    try {
      connection.execute('PRAGMA foreign_keys=OFF');
      connection.execute('BEGIN');
      connection.execute('''
        INSERT INTO book (id, categoryId, sourceId, title, fileType)
        VALUES (1, 7, 1, 'ספר', 'txt')
      ''');
      expect((await lookups(database.bookDao)).map((book) => book?.id), [
        1,
        1,
        1,
        1,
      ]);
    } finally {
      connection.execute('ROLLBACK');
      database.close();
    }
  });
}
