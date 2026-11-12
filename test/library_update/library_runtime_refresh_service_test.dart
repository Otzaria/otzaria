import 'dart:io';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/core/app_runtime_reset.dart';
import 'package:otzaria/core/user_state/user_state_database.dart';
import 'package:otzaria/data/cache/books_cache.dart';
import 'package:otzaria/data/data_providers/cache_database_holder.dart';
import 'package:otzaria/data/data_providers/db_read_worker.dart';
import 'package:otzaria/data/data_providers/file_system_data_provider.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:otzaria/data/data_providers/user_books_database_holder.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/data/sqlite/sqlite3_api.dart';
import 'package:otzaria/find_ref/repository/find_ref_db_isolate.dart';
import 'package:otzaria/indexing/utils/book_facet_metadata_cache.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/library_update/services/library_access_gate.dart';
import 'package:otzaria/library_update/services/library_runtime_refresh_service.dart';
import 'package:otzaria/migration/database/daos/database.dart';
import 'package:otzaria/migration/database/query_loader.dart';
import 'package:otzaria/migration/database/repository/seforim_repository.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/personal_notes/storage/personal_notes_database.dart';
import 'package:otzaria/plugins/repository/plugin_correction_draft_repository.dart';
import 'package:otzaria/plugins/services/plugin_correction_session_service.dart';
import 'package:otzaria/plugins/services/plugin_runtime_dispatcher.dart';
import 'package:otzaria/plugins/services/plugin_webview_runtime.dart';
import 'package:otzaria/plugins/storage/plugin_correction_draft_store.dart';
import 'package:otzaria/plugins/storage/plugin_system_database.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:path/path.dart' as p;

import '../test_helpers/memory_cache_provider.dart';

class _Controller extends Fake implements InAppWebViewController {
  int navigations = 0;

  @override
  Future<void> loadUrl({
    required URLRequest urlRequest,
    WebUri? allowingReadAccessTo,
    Uri? iosAllowingReadAccessTo,
  }) async => navigations++;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const refresh = LibraryRuntimeRefreshService();
  final corrections = PluginCorrectionSessionService.instance;
  final runtime = PluginRuntimeDispatcher.instance;
  late Directory temp;
  late String dbPath;
  late Database userState;
  late Database notes;
  late Database plugins;
  late SeforimRepository userBooks;
  late Database userBooksConnection;
  late Database cacheConnection;
  late SeforimRepository cache;
  late _Controller controller;
  FindRefDbIsolate? findRefWorker;

  Future<void> writeLibrary(String path, String author) async {
    final database = MyDatabase.withPath(path);
    await SeforimRepository(database).ensureInitialized();
    final db = await database.database;
    db.execute('INSERT INTO category (id, title) VALUES (1, ?)', [author]);
    db.execute("INSERT INTO source (id, name) VALUES (1, 'מקור')");
    db.execute(
      "INSERT INTO book (id, categoryId, sourceId, title) VALUES (5, 1, 1, 'ספר')",
    );
    db.execute('INSERT INTO author (id, name) VALUES (1, ?)', [author]);
    db.execute('INSERT INTO book_author (bookId, authorId) VALUES (5, 1)');
    database.close();
  }

  Future<void> expectUserDatabasesPreserved() async {
    expect(UserStateDatabase.instance.openDatabase, same(userState));
    expect(PersonalNotesDatabase.instance.openDatabase, same(notes));
    expect(PluginSystemDatabase.instance.openDatabase, same(plugins));
    expect(
      UserBooksDatabaseHolder.instance.repositoryIfInitialized,
      same(userBooks),
    );
    expect(CacheDatabaseHolder.instance.repositoryIfInitialized, same(cache));
    expect(await userBooks.database.database, same(userBooksConnection));
    expect(await cache.database.database, same(cacheConnection));
    userBooksConnection.select('SELECT 1');
    cacheConnection.select('SELECT 1');
    expect(
      userState
          .select('SELECT tabs_json FROM window_sessions')
          .single['tabs_json'],
      '["טאב שמור"]',
    );
  }

  Future<Map<String, dynamic>> beginCorrection({
    void Function(String, Map<String, dynamic>)? onEvent,
  }) {
    corrections.draftRepository = PluginCorrectionDraftRepository.isolate();
    return corrections.begin(
      owner: 'test.plugin',
      tabId: 'test.tab',
      bookId: 'ספר',
      bookUid: 'id:5',
      libraryVersion: 'v1',
      loadSource: (_) async => 'מקור',
      onEvent: onEvent,
    );
  }

  setUpAll(QueryLoader.initialize);

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('library_runtime_refresh_');
    AppPaths.debugOverrideDataRootPath(temp.path);
    await Settings.init(cacheProvider: MemoryCacheProvider());
    await Settings.setValue<String>(
      SettingsRepository.keyLibraryPath,
      temp.path,
    );
    await Settings.setValue<String>(
      SettingsRepository.keyDatabasesPath,
      p.join(temp.path, 'databases'),
    );
    dbPath = p.join(temp.path, 'seforim.db');
    await Settings.setValue<String>(
      SettingsRepository.keyDbEffectivePath,
      dbPath,
    );
    await writeLibrary(dbPath, 'מחבר א');
    await SqliteDataProvider.instance.initialize();
    FileSystemData.instance.libraryPath = temp.path;
    FileSystemData.instance.clearBookCache();
    userState = await UserStateDatabase.instance.database;
    userState.execute(
      'INSERT INTO window_sessions (slot, tabs_json, current_index, updated_at) VALUES (1, ?, 0, 0)',
      ['["טאב שמור"]'],
    );
    notes = await PersonalNotesDatabase.instance.database;
    plugins = await PluginSystemDatabase.instance.database;
    userBooks = await UserBooksDatabaseHolder.instance.repository;
    cache = await CacheDatabaseHolder.instance.repository;
    userBooksConnection = await userBooks.database.database;
    cacheConnection = await cache.database.database;
    controller = _Controller();
    runtime.registerController('test.plugin', controller);
  });

  tearDown(() async {
    plugins.execute('DROP TRIGGER IF EXISTS fail_draft_write');
    await corrections.prepareForRuntimeReset();
    await runtime.prepareForAppRestart();
    await SqliteDataProvider.instance.closeForExternalWrite();
    findRefWorker?.disposeForTesting();
    findRefWorker = null;
    await SqliteDataProvider.instance.reopenAfterExternalWrite(
      reopenDatabase: false,
    );
    DbReadWorker.disposeForTesting();
    await UserBooksDatabaseHolder.instance.close();
    await CacheDatabaseHolder.instance.close();
    await PersonalNotesDatabase.instance.close();
    await PluginSystemDatabase.instance.close();
    UserStateDatabase.instance.close();
    BookFacetMetadataCache.instance.clear();
    BooksCache.instance.clear();
    AppPaths.debugOverrideDataRootPath(null);
    await temp.delete(recursive: true);
  });

  test(
    'החלפה חוזרת מרעננת מקור ומפרקת תוספים תוך שימור מסדי המשתמש',
    () async {
      final book = TextBook(id: 5, title: 'ספר');
      List<String> authors() => BookFacetMetadataCache.instance
          .extraFacetsForBook(book, isFoundational: false)
          .where((facet) => facet.startsWith('/author/'))
          .toList();
      await BookFacetMetadataCache.instance.warmUp();
      expect(authors(), ['/author/מחבר א']);
      expect((await FileSystemData.instance.titleToPath)['ספר'], 'מחבר א');
      findRefWorker = await FindRefDbIsolate.instance();
      await findRefWorker!.getTocEntries(5, 'ספר');
      await DbReadWorker.lines(dbPath, 5, 0, 0);

      for (final author in ['מחבר ב', 'מחבר ג']) {
        final oldLibrary = Library(categories: []);
        DataRepository.instance.library = Future.value(oldLibrary);
        await DataRepository.instance.library;
        final newPath = '$dbPath.new';
        await writeLibrary(newPath, author);
        await LibraryAccessGate(renameProbe: true).runExclusive(
          dbPath: dbPath,
          body: (scope) async {
            await File(dbPath).delete();
            await File(newPath).rename(dbPath);
            scope.markDbReplaced();
          },
        );
        await refresh.refreshAfterDbUpdate();

        expect(DataRepository.instance.cachedLibraryFutureForTesting, isNull);
        expect(DataRepository.instance.lastSuccessfulLibrary, isNull);
        expect(authors(), isEmpty);
        await BookFacetMetadataCache.instance.warmUp();
        expect(authors(), ['/author/$author']);
        expect((await FileSystemData.instance.titleToPath)['ספר'], author);
        expect(SqliteDataProvider.instance.isInitialized, isTrue);
        await expectUserDatabasesPreserved();
        expect(runtime.ownsController('test.plugin', controller), isFalse);
        expect(controller.navigations, 1);
      }
    },
  );

  test('רענון מסיים תיקונים על המקור הישן ושומר טיוטה ואירוע סיום', () async {
    final events = <String>[];
    final ownerAtSessionEnd = <bool>[];
    await beginCorrection(
      onEvent: (topic, _) {
        events.add(topic);
        if (topic == 'reader.correctionSessionEnded') {
          ownerAtSessionEnd.add(
            runtime.ownsController('test.plugin', controller),
          );
        }
      },
    );
    corrections.editParagraph('test.tab', 0, 'מקור', 'תיקון');

    await refresh.refreshAfterDbUpdate();

    expect(corrections.hasSessionForTab('test.tab'), isFalse);
    expect(events, contains('reader.correctionSessionEnded'));
    expect(ownerAtSessionEnd, [true]);
    final draft = plugins
        .select(
          'SELECT changes_json, holder FROM ${PluginCorrectionDraftStore.table}',
        )
        .single;
    expect(draft['changes_json'], contains('תיקון'));
    expect(draft['holder'], isNull);
    await expectUserDatabasesPreserved();
    expect(runtime.ownsController('test.plugin', controller), isFalse);
    expect(controller.navigations, 1);
  });

  test(
    'כשל בשמירת תיקון עוצר רענון ומשאיר סשן ומאגרים זמינים לניסיון חוזר',
    () async {
      await beginCorrection();
      final oldRepository = SqliteDataProvider.instance.repository;
      plugins.execute(
        "CREATE TRIGGER fail_draft_write BEFORE UPDATE ON ${PluginCorrectionDraftStore.table} BEGIN SELECT RAISE(ABORT, 'write failed'); END",
      );
      corrections.editParagraph('test.tab', 0, 'מקור', 'תיקון שלא נשמר');

      await expectLater(refresh.refreshAfterDbUpdate(), throwsStateError);

      expect(corrections.hasSessionForTab('test.tab'), isTrue);
      expect(corrections.displayText('test.tab', 0, 'מקור'), 'תיקון שלא נשמר');
      expect(SqliteDataProvider.instance.repository, same(oldRepository));
      expect(corrections.processQuitPending, isFalse);
      await expectUserDatabasesPreserved();
      expect(runtime.ownsController('test.plugin', controller), isTrue);
      expect(controller.navigations, 0);

      plugins.execute('DROP TRIGGER fail_draft_write');
      await refresh.refreshAfterDbUpdate();
      expect(corrections.hasSessionForTab('test.tab'), isFalse);
      await expectUserDatabasesPreserved();
      expect(runtime.ownsController('test.plugin', controller), isFalse);
      expect(controller.navigations, 1);
    },
  );

  test(
    'restart מלא עדיין סוגר מסדי משתמש ו-WebViews ופותח מחדש את מצב המשתמש',
    () async {
      await resetRuntimeStateForAppRestart();

      expect(UserStateDatabase.instance.openDatabase, isNot(same(userState)));
      expect(PersonalNotesDatabase.instance.openDatabase, isNull);
      expect(PluginSystemDatabase.instance.openDatabase, isNull);
      expect(UserBooksDatabaseHolder.instance.repositoryIfInitialized, isNull);
      expect(CacheDatabaseHolder.instance.repositoryIfInitialized, isNull);
      expect(runtime.ownsController('test.plugin', controller), isFalse);
      expect(controller.navigations, 1);
      plugins = await PluginSystemDatabase.instance.database;
    },
  );
}
