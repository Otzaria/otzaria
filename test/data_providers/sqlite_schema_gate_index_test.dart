import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/data/book_identity.dart';
import 'package:otzaria/data/constants/database_constants.dart';
import 'package:otzaria/data/data_providers/book_composite_key.dart';
import 'package:otzaria/data/data_providers/library_provider_manager.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:otzaria/data/data_providers/tantivy_data_provider.dart';
import 'package:otzaria/data/data_providers/user_books_database_holder.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/indexing/bloc/indexing_bloc.dart';
import 'package:otzaria/indexing/bloc/indexing_event.dart';
import 'package:otzaria/indexing/bloc/indexing_state.dart';
import 'package:otzaria/indexing/repository/indexing_repository.dart';
import 'package:otzaria/indexing/utils/pending_reindex_store.dart';
import 'package:otzaria/library/hidden/hidden_library_store.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/navigation/navigation_repository.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../helpers/seforim_fixture_db.dart';
import '../test_helpers/memory_cache_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const readable = DatabaseConstants.readableDbSchemaVersion;
  final provider = SqliteDataProvider.instance;
  final manager = LibraryProviderManager.instance;
  const hidden = HiddenLibraryStore();
  late Directory temp;
  late String libraryPath;
  late String pdfPath;

  Future<void> writeOfficialSchema(int schema) async {
    await provider.dispose();
    final fixture = SeforimFixtureDb.create(temp, SeforimFixtureVariant.full);
    final db = sqlite.sqlite3.open(fixture);
    db.execute(
      "INSERT OR REPLACE INTO schema_meta VALUES ('db_schema_version', ?)",
      ['$schema'],
    );
    db.close();
    File(fixture).renameSync(p.join(libraryPath, 'seforim.db'));
  }

  Future<Library> catalog() async {
    await provider.initialize();
    return manager.buildLibraryCatalog({}, libraryPath);
  }

  Future<void> settle(IndexingBloc bloc) async {
    final settled = Completer<void>();
    bloc.add(IndexingWorkBarrier(onSettled: settled.complete));
    await settled.future.timeout(const Duration(seconds: 5));
  }

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('otzaria_schema_index_');
    libraryPath = p.join(temp.path, 'library');
    await Directory(libraryPath).create();
    await Settings.init(cacheProvider: MemoryCacheProvider());
    AppPaths.debugOverrideDataRootPath(p.join(temp.path, 'data'));
    await provider.dispose();
    await UserBooksDatabaseHolder.instance.close();
    manager.resetRuntimeState();
    DataRepository.instance.invalidateLibraryCache();
    await hidden.resetRuntimeStateForAppRestart();
    await Settings.setValue<String>(
      SettingsRepository.keyLibraryPath,
      libraryPath,
    );
    await Settings.setValue<String>(
      SettingsRepository.keyLibraryFolderName,
      '',
    );
    await Settings.setValue<String>(SettingsRepository.keyDbEffectivePath, '');
    final bavli = Directory(p.join(libraryPath, 'תלמוד בבלי'));
    await bavli.create();
    pdfPath = p.join(bavli.path, 'ברכות.pdf');
    await File(pdfPath).writeAsString('%PDF-1.4');
    final user = await UserBooksDatabaseHolder.instance.repository;
    final db = await user.database.database;
    db.execute(
      "INSERT INTO category(id,title,level) VALUES (1,'ספרים אישיים',0)",
    );
    db.execute("INSERT INTO source(id,name) VALUES (1,'local')");
    db.execute(
      "INSERT INTO book(id,categoryId,sourceId,title,isPersonal,fileType) VALUES (99,1,1,'ספר אישי קיים',1,'txt')",
    );
  });

  tearDown(() async {
    await provider.dispose();
    await UserBooksDatabaseHolder.instance.close();
    manager.resetRuntimeState();
    DataRepository.instance.invalidateLibraryCache();
    AppPaths.debugOverrideDataRootPath(null);
    await temp.delete(recursive: true);
  });

  test('סכמה נתמכת שומרת ספר אישי ומנקה רק יתום אמיתי', () async {
    await writeOfficialSchema(readable);
    final library = await catalog();
    final keys = library.getIndexableBooks().map(BookIdentity.indexedFilePath);
    expect(keys, containsAll(['uid:99', 'id:1', 'id:2']));
    final engine = _RecordingEngine();
    final index = _RecordingProvider(engine)
      ..indexedFilePaths.addAll(['uid:99', 'uid:404']);
    final removed = await IndexingRepository(index).dropOrphanedIndexEntries(
      library,
      customFolders: const [],
      attachedLibraries: const [],
    );
    expect(removed, 1);
    expect(engine.deleted, ['uid:404']);
    expect(index.indexedFilePaths, {'uid:99'});
  });

  test('סכמה חסומה אינה בונה קטלוג חלקי שמוחק אינדקס אישי', () async {
    await writeOfficialSchema(readable + 1);
    final library = await catalog();
    final engine = _RecordingEngine();
    final index = _RecordingProvider(engine)..indexedFilePaths.add('uid:99');
    final removed = await IndexingRepository(index).dropOrphanedIndexEntries(
      library,
      customFolders: const [],
      attachedLibraries: const [],
    );
    expect(removed, 0);
    expect(engine.deleted, isEmpty);
    expect(library.getAllBooks(), isEmpty);
    expect(provider.unsupportedDbSchemaVersion, readable + 1);
  });

  test('מסד חסר עדיין מאפשר את קטלוג הקבצים הרגיל', () async {
    final library = await catalog();
    expect(provider.unsupportedDbSchemaVersion, isNull);
    expect(
      library.getIndexableBooks().map(BookIdentity.indexedFilePath),
      contains(pdfPath),
    );
    final index = _RecordingProvider(_RecordingEngine());
    expect(await IndexingRepository(index).clearIndex(), isTrue);
    expect(index.clearCalls, 1);
  });

  test('חסימה משמרת סימוני שחזור ומסיימת callbacks ללא הצלחה כוזבת', () async {
    await writeOfficialSchema(readable + 1);
    await catalog();
    await hidden.markIndexReconciliationPending();
    await Settings.setValue<bool>(
      HiddenLibraryStore.pendingVisibilityIndexSetting,
      true,
    );
    final engine = _RecordingEngine();
    final index = _RecordingProvider(engine)..indexedFilePaths.add('uid:99');
    final repository = IndexingRepository(index);
    index.indexPath = p.join(temp.path, 'index');
    await Directory(index.indexPath!).create();
    final pending = PendingReindexStore.forIndex(index.indexPath)!;
    await pending.save({'id:1'});
    final bloc = IndexingBloc(repository);
    addTearDown(bloc.close);
    final states = <IndexingState>[];
    final sub = bloc.stream.listen(states.add);
    addTearDown(sub.cancel);
    final settled = Completer<void>();
    final empty = Library(categories: []);
    bloc.add(
      ReconcileHiddenIndex(
        empty,
        indexVisible: true,
        clearRestoreMarker: true,
        clearVisibilityMarker: true,
        visibilityRevision: hidden.visibilityRevision,
        onSettled: settled.complete,
      ),
    );
    await settled.future.timeout(const Duration(seconds: 5));
    bloc.add(StartIndexing(empty));
    bloc.add(
      RunIndexing(
        empty,
        changedBooks: [
          TextBook(id: 99, title: 'ספר אישי קיים', source: BookSource.user),
        ],
      ),
    );
    bloc.add(ResetAndIndex(empty));
    final deltaCompleted = Completer<bool>();
    bloc.add(
      ApplyHiddenIndexDelta(
        empty,
        newlyHidden: const [],
        newlyVisible: const [],
        onCompleted: deltaCompleted.complete,
      ),
    );
    await settle(bloc);
    expect(await deltaCompleted.future, isFalse);
    expect(await pending.load(), {'id:1', 'uid:99'});
    expect(await pending.checkLibraryPending(), isTrue);
    expect(states.whereType<IndexingComplete>(), isEmpty);
    expect(hidden.hasPendingIndexReconciliation, isTrue);
    expect(hidden.hasPendingVisibilityIndex, isTrue);
    expect(await repository.clearIndex(), isFalse);
    expect(index.clearCalls, 0);
    expect(index.indexedFilePaths, {'uid:99'});
    expect(engine.deleted, isEmpty);
  });

  test('ספרי seforim.db וספרים אישיים בקטלוג ממופים ל-DB provider', () async {
    await writeOfficialSchema(readable);
    final library = await catalog();
    final books = library.getAllBooks();
    for (final title in [SeforimFixtureIds.bereshitTitle, 'ספר אישי קיים']) {
      final book = books.singleWhere((book) => book.title == title);
      expect(
        manager.providerForKeyForTesting(BookCompositeKey.fromBook(book)!),
        same(manager.databaseProvider),
        reason: title,
      );
    }
  });

  test('מנהל מאותחל ממתין לסכמה לפני בחירת ספק חלופי', () async {
    await writeOfficialSchema(readable);
    await catalog();
    expect(manager.isInitialized, isTrue);
    expect(
      manager.getProviderForBook(
        'ספר אישי קיים',
        categoryId: 1,
        fileType: 'txt',
      ),
      isNotNull,
    );
    await writeOfficialSchema(readable + 1);
    final opening = provider.initialize();
    expect(provider.debugIsInitializing, isTrue);
    final rebuilt = manager.buildLibraryCatalog({}, libraryPath);
    await opening;
    expect((await rebuilt).getAllBooks(), isEmpty);
    expect(
      manager.getProviderForBook(
        'ספר אישי קיים',
        categoryId: 1,
        fileType: 'txt',
      ),
      isNull,
    );
  });

  test('כשל SQLite אחר משמר קטלוג קבצים ותחזוקת אינדקס רגילה', () async {
    await File(p.join(libraryPath, 'seforim.db')).writeAsString('not SQLite');
    final library = await manager.buildLibraryCatalog({}, libraryPath);
    expect(
      library.getIndexableBooks().map(BookIdentity.indexedFilePath),
      contains(pdfPath),
    );
    final index = _RecordingProvider(_RecordingEngine());
    final repository = IndexingRepository(index);
    expect(await repository.clearIndex(), isTrue);
    expect(index.clearCalls, 1);
    expect(await NavigationRepository().checkLibraryIsEmpty(), isFalse);
    await hidden.markIndexReconciliationPending();
    final bloc = IndexingBloc(repository);
    addTearDown(bloc.close);
    bloc.add(
      ReconcileHiddenIndex(
        Library(categories: []),
        indexVisible: true,
        clearRestoreMarker: true,
      ),
    );
    await settle(bloc);
    expect(hidden.hasPendingIndexReconciliation, isFalse);
    expect(bloc.state, isA<IndexingComplete>());
  });

  test('איפוס ממתין לסכמה בזמן פתיחה מחדש של מסד חסום', () async {
    await writeOfficialSchema(readable + 1);
    final index = _RecordingProvider(_RecordingEngine())
      ..indexedFilePaths.add('uid:99');
    final opening = provider.initialize();
    expect(provider.debugIsInitializing, isTrue);
    expect(provider.unsupportedDbSchemaVersion, isNull);
    final cleared = IndexingRepository(index).clearIndex();
    await opening;
    expect(await cleared, isFalse);
    expect(index.clearCalls, 0);
    expect(index.indexedFilePaths, {'uid:99'});
  });

  test('שחזור ממתין לסכמה בזמן פתיחה מחדש של מסד חסום', () async {
    await writeOfficialSchema(readable + 1);
    await hidden.markIndexReconciliationPending();
    final bloc = IndexingBloc(
      IndexingRepository(_RecordingProvider(_RecordingEngine())),
    );
    addTearDown(bloc.close);
    final settled = Completer<void>();
    final opening = provider.initialize();
    expect(provider.debugIsInitializing, isTrue);
    expect(provider.unsupportedDbSchemaVersion, isNull);
    bloc.add(
      ReconcileHiddenIndex(
        Library(categories: []),
        indexVisible: true,
        clearRestoreMarker: true,
        onSettled: settled.complete,
      ),
    );
    await opening;
    await settled.future.timeout(const Duration(seconds: 5));
    expect(hidden.hasPendingIndexReconciliation, isTrue);
    expect(bloc.state, isNot(isA<IndexingComplete>()));
  });

  test('רענון מזהה סכמה חסומה ואחרי בחירה נתמכת חוזרים לתחזוקה', () async {
    final navigation = NavigationRepository(reopenIndex: () async {});
    await writeOfficialSchema(readable);
    final original = await catalog();
    expect(
      original.getAllBooks().map((b) => b.title),
      contains('ספר אישי קיים'),
    );
    await writeOfficialSchema(readable + 1);
    await navigation.refreshLibrary();
    final blocked = await navigation.checkLibraryIsEmpty();
    final blockedLibrary = await DataRepository.instance.library;
    expect(blocked, isTrue);
    expect(blockedLibrary.getAllBooks(), isEmpty);
    await writeOfficialSchema(readable);
    await navigation.refreshLibrary();
    expect(await navigation.checkLibraryIsEmpty(), isFalse);
    final restored = await DataRepository.instance.library;
    expect(
      restored.getAllBooks().map((b) => b.title),
      contains('ספר אישי קיים'),
    );
    final index = _RecordingProvider(_RecordingEngine());
    final repository = IndexingRepository(index);
    expect(await repository.clearIndex(), isTrue);
    expect(index.clearCalls, 1);
    await hidden.markIndexReconciliationPending();
    final bloc = IndexingBloc(repository);
    addTearDown(bloc.close);
    bloc.add(
      ReconcileHiddenIndex(
        Library(categories: []),
        indexVisible: true,
        clearRestoreMarker: true,
      ),
    );
    await settle(bloc);
    expect(hidden.hasPendingIndexReconciliation, isFalse);
    expect(bloc.state, isA<IndexingComplete>());
  });
}

class _RecordingProvider implements TantivyDataProvider {
  _RecordingProvider(this.recordingEngine);
  final _RecordingEngine recordingEngine;
  int clearCalls = 0;
  String? indexPath;
  @override
  final Set<String> indexedFilePaths = {};
  @override
  final ValueNotifier<bool> isIndexing = ValueNotifier(false);
  @override
  bool get isEconomyIndexing => false;
  @override
  bool get requiresManualReindex => false;
  @override
  String? get activeIndexPath => indexPath;
  @override
  Future<SearchEngine> get engine async => recordingEngine;
  @override
  bool get isTempFallback => false;
  @override
  Future<void> clear() async {
    clearCalls++;
    indexedFilePaths.clear();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('$invocation');
}

class _RecordingEngine implements SearchEngine {
  final List<String> deleted = [];
  @override
  Future<void> deleteDocumentsByFilePaths({
    required List<String> filePaths,
  }) async {
    deleted.addAll(filePaths);
  }

  @override
  Future<void> commit() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('$invocation');
}
