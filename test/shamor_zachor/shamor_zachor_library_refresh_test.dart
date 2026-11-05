import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:otzaria/find_ref/repository/find_ref_db_isolate.dart';
import 'package:otzaria/migration/database/daos/book_dao.dart';
import 'package:otzaria/migration/database/daos/database.dart';
import 'package:otzaria/migration/database/repository/seforim_repository.dart';
import 'package:otzaria/migration/models/book.dart' as migration;
import 'package:otzaria/migration/models/category.dart';
import 'package:otzaria/migration/models/toc_entry.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/tools/shamor_zachor/providers/shamor_zachor_data_provider.dart';
import 'package:otzaria/tools/shamor_zachor/services/shamor_zachor_bootstrap_worker.dart';

import '../test_helpers/memory_cache_provider.dart';

typedef _Fixture = ({int bookId, int secondSectionId});

class _Database extends Fake implements MyDatabase {
  final BookDao? books;
  _Database([this.books]);

  @override
  BookDao get bookDao => books!;
}

class _DeferredBookDao extends Fake implements BookDao {
  final started = Completer<void>();
  final result = Completer<migration.Book?>();

  @override
  Future<migration.Book?> getBookById(int id) {
    if (!started.isCompleted) started.complete();
    return result.future;
  }
}

class _MutableSqliteProvider extends Fake implements SqliteDataProvider {
  @override
  final ValueNotifier<SeforimRepository?> repositoryChanges;
  @override
  final String dbPath;

  _MutableSqliteProvider(this.dbPath, [MyDatabase? database])
    : repositoryChanges = ValueNotifier(
        SeforimRepository(database ?? _Database()),
      );

  @override
  SeforimRepository? get repository => repositoryChanges.value;
  @override
  bool get isInitialized => repository != null;
  @override
  Future<void> initialize() async {}

  void replace([MyDatabase? database]) {
    repositoryChanges.value = SeforimRepository(database ?? _Database());
  }
}

class _ControlledLoader {
  final loads = <Completer<Map<String, dynamic>>>[];

  Future<Map<String, dynamic>> call({
    required String dbPath,
    required List<int> trackedBookIds,
  }) {
    final load = Completer<Map<String, dynamic>>();
    loads.add(load);
    return load.future;
  }
}

Map<String, dynamic> _tree(String title) => {
  'categories': [
    {
      'name': 'תנ"ך',
      'contentType': 'text',
      'books': {
        'ספר': {
          'contentType': 'text',
          'id': 7,
          'parts': [],
          'sections': [
            {
              'id': '1',
              'title': title,
              'level': 1,
              'startPage': 0,
              'endPage': 9,
            },
          ],
        },
      },
    },
  ],
};

Future<_Fixture> _writeLibrary(String path, {int secondStart = 10}) async {
  final database = MyDatabase.withPath(path);
  final repository = SeforimRepository(database);
  await repository.ensureInitialized();
  final categoryId = await repository.insertCategory(
    const Category(title: 'תנ"ך'),
  );
  final sourceId = await repository.insertSource('test', -1);
  final bookId = await repository.insertBook(
    migration.Book(
      id: 0,
      title: 'ספר',
      categoryId: categoryId,
      sourceId: sourceId,
      totalLines: 20,
      isBaseBook: true,
      fileType: 'txt',
    ),
  );
  final db = await database.database;
  for (var line = 0; line < 20; line++) {
    db.execute(
      'INSERT INTO line (id, bookId, lineIndex, content) VALUES (?, ?, ?, ?)',
      [line + 1, bookId, line, 'שורה $line'],
    );
  }
  await repository.insertTocEntry(
    TocEntry(
      id: 0,
      bookId: bookId,
      text: 'פרק א',
      level: 1,
      lineId: 2,
      lineIndex: 1,
      isLastChild: false,
      hasChildren: false,
    ),
  );
  final secondId = await repository.insertTocEntry(
    TocEntry(
      id: 0,
      bookId: bookId,
      text: 'פרק ב',
      level: 1,
      lineId: secondStart + 1,
      lineIndex: secondStart,
      isLastChild: true,
      hasChildren: false,
    ),
  );
  database.close();
  return (bookId: bookId, secondSectionId: secondId);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  late String dbPath;
  late _Fixture fixture;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('sz_refresh_');
    dbPath = '${temp.path}/seforim.db';
    fixture = await _writeLibrary(dbPath);
    await Settings.init(cacheProvider: MemoryCacheProvider());
    await Settings.setValue<String>(
      SettingsRepository.keyLibraryPath,
      temp.path,
    );
    await Settings.setValue<String>(
      SettingsRepository.keyLibraryFolderName,
      '',
    );
    await Settings.setValue<String>(SettingsRepository.keyDbEffectivePath, '');
    await SqliteDataProvider.instance.dispose();
    await FindRefDbIsolate.resumeAfterExternalWrite();
  });

  tearDown(() async {
    await SqliteDataProvider.instance.dispose();
    (await FindRefDbIsolate.instance()).disposeForTesting();
    await temp.delete(recursive: true);
  });

  for (final change in ['patch', 'replacement', 'path reset']) {
    test('refreshes both warm caches after $change', () async {
      final sqlite = SqliteDataProvider.instance;
      await sqlite.initialize();
      var loads = 0;
      final provider = ShamorZachorDataProvider(
        sqliteDataProvider: sqlite,
        categoryTreeLoader: ({required dbPath, required trackedBookIds}) {
          loads++;
          return ShamorZachorBootstrapWorker.loadCategoryTree(
            dbPath: dbPath,
            trackedBookIds: trackedBookIds,
          );
        },
      );
      addTearDown(provider.dispose);
      await provider.ensureLoaded();
      final oldDetails = provider.getBookById(fixture.bookId)!.$1;
      final oldToc = await provider.getTocForBook(fixture.bookId);
      expect(oldDetails.sections!.last.startPage, 10);
      expect(oldToc.last.startPage, 10);

      if (change == 'path reset') {
        await sqlite.dispose();
        expect(provider.getBookById(fixture.bookId), isNull);
        final next = await Directory('${temp.path}/next').create();
        await _writeLibrary('${next.path}/seforim.db', secondStart: 5);
        await Settings.setValue<String>(
          SettingsRepository.keyLibraryPath,
          next.path,
        );
        FindRefDbIsolate.resetIfRunning();
        await sqlite.initialize();
      } else {
        await sqlite.closeForExternalWrite();
        try {
          expect(provider.getBookById(fixture.bookId), isNull);
          if (change == 'patch') {
            final writable = MyDatabase.withPath(dbPath);
            (await writable.database).execute(
              'UPDATE tocEntry SET lineId = 6, lineIndex = 5 WHERE id = ?',
              [fixture.secondSectionId],
            );
            writable.close();
          } else {
            await _writeLibrary('$dbPath.new', secondStart: 5);
            await File('$dbPath.new').rename(dbPath);
          }
        } finally {
          await sqlite.reopenAfterExternalWrite();
        }
      }
      await provider.ensureLoaded();
      final details = provider.getBookById(fixture.bookId)!.$1;
      final toc = await provider.getTocForBook(fixture.bookId);
      expect(details, isNot(same(oldDetails)));
      expect(details.sections!.last.id, '${fixture.secondSectionId}');
      expect(details.sections!.first.endPage, 4);
      expect(details.sections!.last.startPage, 5);
      expect(toc.first.endPage, 4);
      expect(toc.last.startPage, 5);
      expect(toc, isNot(same(oldToc)));
      expect(oldDetails.sections!.last.startPage, 10);
      for (var i = 0; i < 3; i++) {
        await provider.ensureLoaded();
        expect(provider.getBookById(fixture.bookId)!.$1, same(details));
        expect(await provider.getTocForBook(fixture.bookId), same(toc));
      }
      expect(loads, 2);
    });
  }

  test('an unused provider stays lazy when the repository changes', () async {
    final sqlite = _MutableSqliteProvider(dbPath);
    addTearDown(sqlite.repositoryChanges.dispose);
    final loader = _ControlledLoader();
    final provider = ShamorZachorDataProvider(
      sqliteDataProvider: sqlite,
      categoryTreeLoader: loader.call,
    );
    addTearDown(provider.dispose);
    sqlite.replace();
    await pumpEventQueue();
    expect(loader.loads, isEmpty);
    expect(provider.hasData, isFalse);
  });

  test('ensureLoaded coalesces concurrent and reentrant listeners', () async {
    final sqlite = _MutableSqliteProvider(dbPath);
    addTearDown(sqlite.repositoryChanges.dispose);
    final loader = _ControlledLoader();
    final provider = ShamorZachorDataProvider(
      sqliteDataProvider: sqlite,
      categoryTreeLoader: loader.call,
    );
    addTearDown(provider.dispose);
    Future<void>? reentrant;
    var reentrantDone = false;
    provider.addListener(() {
      if (provider.isLoading && reentrant == null) {
        reentrant = provider.ensureLoaded().then((_) {
          reentrantDone = true;
        });
      }
    });
    final first = provider.ensureLoaded();
    final second = provider.ensureLoaded();
    await pumpEventQueue();
    expect(loader.loads, hasLength(1));
    expect(reentrant, isNotNull);
    expect(reentrantDone, isFalse);
    loader.loads.single.complete(_tree('חדש'));
    await Future.wait([first, second, reentrant!]);
    expect(provider.hasData, isTrue);
    await provider.ensureLoaded();
    expect(loader.loads, hasLength(1));
  });

  for (final oldFirst in [true, false]) {
    for (final oldFails in [true, false]) {
      test('discard old load: oldFirst=$oldFirst oldFails=$oldFails', () async {
        final sqlite = _MutableSqliteProvider(dbPath);
        addTearDown(sqlite.repositoryChanges.dispose);
        final loader = _ControlledLoader();
        final provider = ShamorZachorDataProvider(
          sqliteDataProvider: sqlite,
          categoryTreeLoader: loader.call,
        );
        addTearDown(provider.dispose);
        final first = provider.ensureLoaded();
        await pumpEventQueue();
        sqlite.replace();
        await pumpEventQueue();
        expect(loader.loads, hasLength(2));
        final current = provider.ensureLoaded();
        void finishOld() {
          if (oldFails) {
            loader.loads.first.completeError(StateError('old database closed'));
          } else {
            loader.loads.first.complete(_tree('ישן'));
          }
        }

        if (oldFirst) {
          finishOld();
          await pumpEventQueue();
          expect(provider.isLoading, isTrue);
          expect(provider.hasData, isFalse);
        }
        loader.loads.last.complete(_tree('חדש'));
        await current;
        if (!oldFirst) finishOld();
        await first;
        expect(provider.getBookById(7)!.$1.sections!.single.title, 'חדש');
        expect(provider.isLoading, isFalse);
        expect(provider.error, isNull);
        expect(loader.loads, hasLength(2));
      });
    }
  }

  test(
    'discard a TOC response awaiting metadata from the old repository',
    () async {
      final oldBooks = _DeferredBookDao();
      final sqlite = _MutableSqliteProvider(dbPath, _Database(oldBooks));
      addTearDown(sqlite.repositoryChanges.dispose);
      final provider = ShamorZachorDataProvider(sqliteDataProvider: sqlite);
      addTearDown(provider.dispose);
      final oldToc = provider.getTocForBook(fixture.bookId);
      await oldBooks.started.future;
      final currentBooks = _DeferredBookDao();
      sqlite.replace(_Database(currentBooks));
      migration.Book bookWithLines(int lines) => migration.Book(
        id: fixture.bookId,
        title: 'ספר',
        categoryId: 1,
        sourceId: 1,
        totalLines: lines,
        isBaseBook: true,
        fileType: 'txt',
      );
      oldBooks.result.complete(bookWithLines(20));
      expect(await oldToc, isEmpty);
      currentBooks.result.complete(bookWithLines(25));
      final toc = await provider.getTocForBook(fixture.bookId);
      expect(toc.last.endPage, 25);
      expect(currentBooks.started.isCompleted, isTrue);
    },
  );

  test('disposing a provider discards its pending load', () async {
    final sqlite = _MutableSqliteProvider(dbPath);
    addTearDown(sqlite.repositoryChanges.dispose);
    final loader = _ControlledLoader();
    final provider = ShamorZachorDataProvider(
      sqliteDataProvider: sqlite,
      categoryTreeLoader: loader.call,
    );
    final load = provider.ensureLoaded();
    await pumpEventQueue();
    provider.dispose();
    loader.loads.single.complete(_tree('ישן'));
    await load;
    expect(provider.hasData, isFalse);
    sqlite.replace();
    await pumpEventQueue();
    expect(loader.loads, hasLength(1));
  });
}
