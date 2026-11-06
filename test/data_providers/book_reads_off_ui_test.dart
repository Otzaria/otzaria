import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/data/constants/database_constants.dart';
import 'package:otzaria/data/data_providers/db_read_worker.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:otzaria/migration/database/daos/database.dart';
import 'package:otzaria/migration/database/repository/seforim_repository.dart';
import 'package:otzaria/migration/models/book.dart' as db_models;
import 'package:otzaria/search/library_line_source.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/common.dart' show CommonDatabase;
import 'package:sqlite3/sqlite3.dart' as sqlite3;

import '../support/fake_line_source_engine.dart';
import '../test_helpers/memory_cache_provider.dart';

enum _Schema { full, noRelations, minimal }

const _relationTables = [
  'author',
  'book_author',
  'topic',
  'book_topic',
  'pub_place',
  'book_pub_place',
  'pub_date',
  'book_pub_date',
];

void _createFixture(String dbPath, _Schema schema, {String title = 'Alpha'}) {
  final db = sqlite3.sqlite3.open(dbPath);
  try {
    if (schema == _Schema.minimal) {
      db.execute('CREATE TABLE book (id INTEGER PRIMARY KEY, title TEXT)');
      db.execute(
        'INSERT INTO book VALUES (1, ?), (2, ?), (3, ?)',
        [title, title, 'Beta'],
      );
      return;
    }
    db.execute('''
      CREATE TABLE category (id INTEGER PRIMARY KEY, title TEXT, level INTEGER);
      INSERT INTO category VALUES (7, 'First', 0), (8, 'Second', 0);
      CREATE TABLE book (
        id INTEGER PRIMARY KEY, categoryId INTEGER, sourceId INTEGER,
        title TEXT, orderIndex REAL, heShortDesc TEXT, heDesc TEXT, heRef TEXT,
        totalLines INTEGER, isBaseBook INTEGER, hasTargumConnection INTEGER,
        hasReferenceConnection INTEGER, hasSourceConnection INTEGER,
        hasCommentaryConnection INTEGER, hasOtherConnection INTEGER,
        hasAltStructures INTEGER, hasTeamim INTEGER, hasNekudot INTEGER,
        isContentExternal INTEGER, externalLibraryId TEXT, isPersonal INTEGER,
        filePath TEXT, fileType TEXT, fileSize INTEGER, lastModified INTEGER,
        pages INTEGER, volume TEXT
      );
    ''');
    db.execute(
      '''
      INSERT INTO book VALUES (
        1, 7, 4, ?, 2.5, 'Short description', 'Full description', 'Alpha 1',
        120, 1, 1, 0, 1, 0, 1, 1, 0, 1, 1, 'external-alpha', 1,
        'books/alpha.txt', 'txt', 8192, 1700000000, 12, 'Volume I'
      )
    ''',
      [title],
    );
    db.execute(
      '''
      INSERT INTO book (id, categoryId, sourceId, title, orderIndex,
                        filePath, fileType)
      VALUES (2, 8, 4, ?, 1, 'books/alpha.pdf', 'pdf'),
             (3, 7, 4, 'Beta', 1, 'books/beta.txt', 'txt')
    ''',
      [title],
    );
    if (schema == _Schema.noRelations) return;
    db.execute('''
      CREATE TABLE author (id INTEGER PRIMARY KEY, name TEXT, generationId INTEGER);
      INSERT INTO author VALUES (101, 'Author A', 4), (102, 'Author B', 5),
                                (103, 'Other author', NULL);
      CREATE TABLE book_author (bookId INTEGER, authorId INTEGER);
      INSERT INTO book_author VALUES (1, 101), (1, 102), (2, 103), (99, 101);
      CREATE TABLE topic (id INTEGER PRIMARY KEY, name TEXT);
      INSERT INTO topic VALUES (201, 'Topic A'), (202, 'Topic B');
      CREATE TABLE book_topic (bookId INTEGER, topicId INTEGER);
      INSERT INTO book_topic VALUES (1, 201), (3, 202);
      CREATE TABLE pub_place (id INTEGER PRIMARY KEY, name TEXT);
      INSERT INTO pub_place VALUES (301, 'North'), (302, 'South');
      CREATE TABLE book_pub_place (bookId INTEGER, pubPlaceId INTEGER);
      INSERT INTO book_pub_place VALUES (1, 301), (2, 302);
      CREATE TABLE pub_date (id INTEGER PRIMARY KEY, date TEXT);
      INSERT INTO pub_date VALUES (401, '2020'), (402, '2021');
      CREATE TABLE book_pub_date (bookId INTEGER, pubDateId INTEGER);
      INSERT INTO book_pub_date VALUES (1, 401), (2, 402);
    ''');
  } finally {
    db.close();
  }
}

// TEMP tables are connection-local: querying the UI handle returns empty data.
void _shadowUiTables(CommonDatabase db, Iterable<String> tables) {
  db.execute('PRAGMA query_only=OFF');
  try {
    for (final table in tables) {
      db.execute(
        'CREATE TEMP TABLE "$table" AS SELECT * FROM main."$table" WHERE 0',
      );
    }
  } finally {
    db.execute('PRAGMA query_only=ON');
  }
}

Map<String, Future<Object?> Function()> _bookReads(
  SeforimRepository repo, {
  bool withFilePath = true,
}) {
  final dao = repo.database.bookDao;
  return {
    'dao.all': dao.getAllBooks,
    'dao.local': dao.getAllLocalBooks,
    'dao.slim': dao.selectAllLocalBooksSlim,
    'dao.relations': dao.getAllBooksWithRelations,
    'dao.id': () => dao.getBookById(1),
    'dao.category': () => dao.getBooksByCategory(7),
    'dao.title': () => dao.getBookByTitle('Alpha'),
    'dao.titleCategory': () => dao.getBookByTitleAndCategory('Alpha', 8),
    'dao.titleCategoryType': () =>
        dao.getBookByTitleCategoryAndFileType('Alpha', 8, 'pdf'),
    'dao.count': dao.countAllBooks,
    'dao.missingId': () => dao.getBookById(999),
    'dao.missingTitle': () => dao.getBookByTitle('Missing'),
    'dao.missingCategory': () => dao.getBooksByCategory(999),
    'dao.wrongType': () =>
        dao.getBookByTitleCategoryAndFileType('Alpha', 7, 'pdf'),
    'repo.id': () => repo.getBook(1),
    'repo.category': () => repo.getBooksByCategory(7),
    'repo.title': () => repo.getBookByTitle('Alpha'),
    'repo.titleCategory': () => repo.getBookByTitleAndCategory('Alpha', 8),
    'repo.titleCategoryType': () =>
        repo.getBookByTitleCategoryAndFileType('Alpha', 8, 'pdf'),
    'repo.all': repo.getAllBooks,
    'repo.lean': repo.getAllBooksLean,
    'repo.missingId': () => repo.getBook(999),
    'repo.missingTitle': () => repo.getBookByTitle('Missing'),
    'repo.missingCategory': () => repo.getBooksByCategory(999),
    if (withFilePath) ...{
      'dao.path': () => dao.getBookByFilePath('books/alpha.txt'),
      'dao.missingPath': () => dao.getBookByFilePath('books/missing.txt'),
      'repo.path': () => repo.getExternalBookByFilePath('books/alpha.txt'),
    },
  };
}

Object? _normalize(Object? value) {
  if (value is db_models.Book) return _normalize(value.toJson());
  if (value is List) return value.map(_normalize).toList();
  if (value is Map) {
    return {
      for (final entry in value.entries) entry.key: _normalize(entry.value),
    };
  }
  return value;
}

Future<Map<String, Object?>> _readAll(
  SeforimRepository repo, {
  bool withFilePath = true,
}) async => Map.fromEntries(
  await Future.wait(
    _bookReads(repo, withFilePath: withFilePath).entries.map(
      (entry) async => MapEntry(entry.key, _normalize(await entry.value())),
    ),
  ),
);

Future<Map<String, Object?>> _directReads(String dbPath, _Schema schema) async {
  final database = MyDatabase.withPath(dbPath, readOnly: true, official: true);
  try {
    final repo = SeforimRepository(database);
    await repo.ensureInitialized();
    return await _readAll(repo, withFilePath: schema != _Schema.minimal);
  } finally {
    database.close();
  }
}

// Construct outside the test closure so only the SendPort crosses isolates.
void Function() _failWorkerStartup(SendPort port) => () {
  port.send('startup');
  throw StateError('forced book worker startup failure');
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final provider = SqliteDataProvider.instance;
  final previousDataRoot = AppPaths.cachedDataRootPath;
  final previousWorkerSetUp = DbReadWorker.workerSetUpForTesting;
  late Directory tempDir;
  late String dbPath;

  Future<SeforimRepository> openLibrary([_Schema schema = _Schema.full]) async {
    _createFixture(dbPath, schema);
    await provider.initialize();
    expect(provider.isInitialized, isTrue);
    return provider.repository!;
  }

  setUp(() async {
    await provider.dispose();
    DbReadWorker.disposeForTesting();
    await DbReadWorker.resumeAfterExternalWrite();
    DbReadWorker.workerSetUpForTesting = null;
    LibraryLineSource.debugReset(engine: FakeLineSourceEngine());
    await Settings.init(cacheProvider: MemoryCacheProvider());
    tempDir = await Directory.systemTemp.createTemp('otzaria_book_reads_');
    final libraryPath = p.join(tempDir.path, 'library');
    Directory(libraryPath).createSync();
    dbPath = p.join(libraryPath, DatabaseConstants.databaseFileName);
    AppPaths.debugOverrideDataRootPath(p.join(tempDir.path, 'data_root'));
    await Settings.setValue<String>(
      SettingsRepository.keyLibraryPath,
      libraryPath,
    );
    await Settings.setValue<String>(
      SettingsRepository.keyLibraryFolderName,
      '',
    );
    await Settings.setValue<String>(SettingsRepository.keyDbEffectivePath, '');
  });

  tearDown(() async {
    DbReadWorker.workerSetUpForTesting = previousWorkerSetUp;
    await provider.dispose();
    DbReadWorker.disposeForTesting();
    await DbReadWorker.resumeAfterExternalWrite();
    LibraryLineSource.debugReset();
    AppPaths.debugOverrideDataRootPath(previousDataRoot);
    await tempDir.delete(recursive: true);
  });

  test('official title lookup ignores the UI connection book table', () async {
    final repo = await openLibrary();
    final raw = await repo.database.database;
    _shadowUiTables(raw, ['book']);
    expect(raw.select('SELECT COUNT(*) AS n FROM book').single['n'], 0);

    final book = await repo.database.bookDao.getBookByTitle('Alpha');

    expect(book, isNotNull);
    expect(book!.id, 1);
    expect(book.title, 'Alpha');
    expect(book.fileSize, 8192);
    expect(book.order, 2.5);
  });

  test('hydrated book relations ignore the UI connection tables', () async {
    final repo = await openLibrary();
    _shadowUiTables(await repo.database.database, _relationTables);

    final book = (await repo.getBook(1))!;

    expect(book.authors.map((author) => author.name), ['Author A', 'Author B']);
    expect(book.authors.map((author) => author.generationId), [4, 5]);
    expect(book.topics.map((topic) => topic.name), ['Topic A']);
    expect(book.pubPlaces.map((place) => place.name), ['North']);
    expect(book.pubDates.map((date) => date.date), ['2020']);
    final other = (await repo.getBook(2))!;
    expect(other.authors.map((author) => author.name), ['Other author']);
    expect(other.topics, isEmpty);
  });

  for (final schema in _Schema.values) {
    for (final fallback in [false, true]) {
      test(
        'all book reads retain direct results (${schema.name}, fallback=$fallback)',
        () async {
          final repo = await openLibrary(schema);
          final expected = await _directReads(dbPath, schema);
          _shadowUiTables(await repo.database.database, [
            'book',
            if (schema == _Schema.full) ..._relationTables,
          ]);
          final startup = ReceivePort();
          final startupObserved = Completer<void>();
          var startupCount = 0;
          final subscription = startup.listen((_) {
            startupCount++;
            if (!startupObserved.isCompleted) startupObserved.complete();
          });
          final before = DbReadWorker.sentMessageCount;
          if (fallback) {
            DbReadWorker.workerSetUpForTesting = _failWorkerStartup(
              startup.sendPort,
            );
          }
          try {
            final actual = await _readAll(
              repo,
              withFilePath: schema != _Schema.minimal,
            );
            for (final entry in expected.entries) {
              expect(actual[entry.key], entry.value, reason: entry.key);
            }
            expect(actual['dao.count'], 3);
            expect(actual['dao.missingId'], isNull);
            expect(actual['repo.missingTitle'], isNull);
            if (schema == _Schema.minimal) {
              expect(actual['dao.category'], isEmpty);
              expect(actual['repo.titleCategoryType'], isNull);
            } else {
              expect(
                (actual['dao.all']! as List).map((book) => (book as Map)['id']),
                [2, 3, 1],
              );
              expect((actual['dao.titleCategory']! as Map)['id'], 2);
            }
            if (fallback) {
              await startupObserved.future;
              expect(startupCount, 1);
              expect(DbReadWorker.sentMessageCount - before, 0);
            } else {
              expect(DbReadWorker.sentMessageCount - before, 1);
            }
          } finally {
            DbReadWorker.workerSetUpForTesting = null;
            await subscription.cancel();
            startup.close();
          }
        },
      );
    }
  }

  test(
    'book reads do not reopen a closed UI connection for schema probes',
    () async {
      final repo = await openLibrary();
      final expected = await _directReads(dbPath, _Schema.full);
      repo.database.close();
      expect(repo.database.isOpen, isFalse);

      expect(await _readAll(repo), expected);

      expect(repo.database.isOpen, isFalse);
    },
  );

  test(
    'a failing item does not discard the other book reads in its batch',
    () async {
      final repo = await openLibrary(_Schema.minimal);
      final directDatabase = MyDatabase.withPath(dbPath, readOnly: true);
      final missingColumn = throwsA(
        predicate<Object>(
          (error) => error.toString().contains('no such column: filePath'),
        ),
      );
      try {
        await expectLater(
          directDatabase.bookDao.getBookByFilePath('missing'),
          missingColumn,
        );
      } finally {
        directDatabase.close();
      }
      await repo.getBook(1);
      final before = DbReadWorker.sentMessageCount;

      final badRead = expectLater(
        repo.database.bookDao.getBookByFilePath('missing'),
        missingColumn,
      );
      final goodRead = repo.getBook(1);
      final count = repo.database.bookDao.countAllBooks();
      await badRead;

      expect((await goodRead)!.title, 'Alpha');
      expect(await count, 3);
      expect(DbReadWorker.sentMessageCount - before, 1);
    },
  );

  test('suspension blocks every official book read until resumed', () async {
    final repo = await openLibrary();
    await repo.getBook(1);
    await DbReadWorker.suspendForExternalWrite();
    final before = DbReadWorker.sentMessageCount;
    try {
      for (final entry in _bookReads(repo).entries) {
        await expectLater(
          entry.value(),
          throwsA(isA<DbReadWorkerSuspended>()),
          reason: entry.key,
        );
      }
      expect(DbReadWorker.sentMessageCount, before);
    } finally {
      await DbReadWorker.resumeAfterExternalWrite();
    }
    expect((await repo.getBook(1))!.title, 'Alpha');
  });

  test('closing cancels queued book reads until allowReopen', () async {
    final repo = await openLibrary();
    await repo.getBook(1);
    final pending = repo.getBook(1);
    final cancelled = expectLater(
      pending,
      throwsA(isA<DbReadWorkerSuspended>()),
    );

    await DbReadWorker.closeConnectionIfRunning();
    await cancelled;
    await expectLater(
      repo.database.bookDao.countAllBooks(),
      throwsA(isA<DbReadWorkerSuspended>()),
    );
    DbReadWorker.allowReopen();

    expect((await repo.getBook(1))!.title, 'Alpha');
  });

  test(
    'replacing the library invalidates old repositories and releases the file',
    () async {
      final oldRepo = await openLibrary();
      expect((await oldRepo.getBook(1))!.title, 'Alpha');
      await provider.closeForExternalWrite();
      try {
        expect(oldRepo.database.isOpen, isFalse);
        await expectLater(
          oldRepo.getBook(1),
          throwsA(isA<DbReadWorkerSuspended>()),
        );
        await File(dbPath).rename('$dbPath.previous');
        _createFixture(dbPath, _Schema.full, title: 'Gamma');
      } finally {
        await provider.reopenAfterExternalWrite();
      }
      final newRepo = provider.repository!;
      expect(identical(oldRepo, newRepo), isFalse);
      expect((await newRepo.getBook(1))!.title, 'Gamma');
      expect(await newRepo.getBookByTitle('Alpha'), isNull);
      await expectLater(
        oldRepo.database.bookDao.getBookById(1),
        throwsA(isA<DbReadWorkerSuspended>()),
      );
      await expectLater(
        oldRepo.getBookByTitle('Gamma'),
        throwsA(isA<DbReadWorkerSuspended>()),
      );
      expect(oldRepo.database.isOpen, isFalse);
    },
  );

  test(
    'disposing and reinitializing does not reactivate a stale repository',
    () async {
      final oldRepo = await openLibrary();
      await oldRepo.getBook(1);
      await provider.dispose();
      await expectLater(
        oldRepo.database.bookDao.countAllBooks(),
        throwsA(isA<DbReadWorkerSuspended>()),
      );

      await provider.initialize();

      expect((await provider.repository!.getBook(1))!.title, 'Alpha');
      await expectLater(
        oldRepo.getAllBooks(),
        throwsA(isA<DbReadWorkerSuspended>()),
      );
      expect(oldRepo.database.isOpen, isFalse);
    },
  );

  test('writable book reads retain uncommitted transaction data', () async {
    final database = MyDatabase.withPath(p.join(tempDir.path, 'writable.db'));
    final repo = SeforimRepository(database);
    try {
      await repo.ensureInitialized();
      final raw = await database.database;
      raw.execute(
        "INSERT INTO book (id, categoryId, sourceId, title) VALUES (1, 1, 1, 'Alpha')",
      );
      raw.execute("INSERT INTO author (id, name) VALUES (101, 'Author A')");
      final before = DbReadWorker.sentMessageCount;
      await DbReadWorker.suspendForExternalWrite();
      raw.execute('BEGIN');
      try {
        raw.execute("UPDATE book SET title='Pending' WHERE id=1");
        raw.execute(
          'INSERT INTO book_author (bookId, authorId) VALUES (1, 101)',
        );
        final pending = (await repo.getBookByTitle('Pending'))!;
        expect(pending.title, 'Pending');
        expect(pending.authors.map((author) => author.name), ['Author A']);
        expect(await database.bookDao.getBookByTitle('Alpha'), isNull);
        expect(await database.bookDao.countAllBooks(), 1);
        expect(DbReadWorker.sentMessageCount, before);
      } finally {
        raw.execute('ROLLBACK');
        await DbReadWorker.resumeAfterExternalWrite();
      }
      expect((await repo.getBook(1))!.title, 'Alpha');
      expect((await repo.getBook(1))!.authors, isEmpty);
    } finally {
      database.close();
    }
  });

  test(
    'attached books retain their hardened connection and file path rules',
    () async {
      final attachedPath = p.join(tempDir.path, 'attached.db');
      _createFixture(attachedPath, _Schema.full);
      final writer = sqlite3.sqlite3.open(attachedPath);
      writer.execute("UPDATE book SET filePath='../outside.txt' WHERE id=2");
      writer.close();
      final database = MyDatabase.untrusted(attachedPath);
      final repo = SeforimRepository(database);
      try {
        await repo.ensureInitialized();
        await DbReadWorker.suspendForExternalWrite();
        final before = DbReadWorker.sentMessageCount;
        try {
          final first = (await repo.getBook(1))!;
          expect(first.filePath, p.join(tempDir.path, 'books', 'alpha.txt'));
          expect(first.authors.map((author) => author.name), [
            'Author A',
            'Author B',
          ]);
          expect((await repo.getBook(2))!.filePath, isNull);
          expect(await database.bookDao.countAllBooks(), 3);
          expect(DbReadWorker.sentMessageCount, before);
          final raw = await database.database;
          expect(raw.select('PRAGMA query_only').single.values.single, 1);
          expect(raw.select('PRAGMA trusted_schema').single.values.single, 0);
          expect(raw.select('PRAGMA mmap_size').single.values.single, 0);
          expect(
            () => raw.execute("UPDATE book SET title='Changed'"),
            throwsA(isA<sqlite3.SqliteException>()),
          );
        } finally {
          await DbReadWorker.resumeAfterExternalWrite();
        }
      } finally {
        database.close();
      }
    },
  );
}
