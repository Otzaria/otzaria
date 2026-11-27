import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/data/constants/database_constants.dart';
import 'package:otzaria/data/data_providers/database_library_provider.dart';
import 'package:otzaria/data/data_providers/db_read_worker.dart';
import 'package:otzaria/data/data_providers/official_catalog_rows.dart';
import 'package:otzaria/data/data_providers/user_books_database_holder.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import '../helpers/seforim_fixture_db.dart';
import '../test_helpers/memory_cache_provider.dart';

/// שורות הקטלוג של seforim.db נקראות על חיבור משלהן מחוץ ל-UI isolate, וזהות
/// למה שהחיבור הראשי היה מחזיר.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final provider = DatabaseLibraryProvider.instance;
  final previousDataRoot = AppPaths.cachedDataRootPath;
  late Directory tempDir;
  late String libraryPath;

  Future<void> openLibrary(
    SeforimFixtureVariant variant, {
    void Function(Database)? populate,
  }) async {
    final created = SeforimFixtureDb.create(Directory(libraryPath), variant);
    if (populate != null) {
      final db = sqlite3.open(created);
      try {
        populate(db);
      } finally {
        db.close();
      }
    }
    File(
      created,
    ).renameSync(p.join(libraryPath, DatabaseConstants.databaseFileName));
    await provider.sqliteProvider.dispose();
    provider.clearCache();
    await provider.initialize();
  }

  setUp(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
    tempDir = await Directory.systemTemp.createTemp('otzaria_catalog_off_ui');
    libraryPath = p.join(tempDir.path, 'library');
    Directory(libraryPath).createSync();
    await UserBooksDatabaseHolder.instance.close();
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
    provider.clearCache();
    await provider.sqliteProvider.dispose();
    await UserBooksDatabaseHolder.instance.close();
    AppPaths.debugOverrideDataRootPath(previousDataRoot);
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  for (final variant in [
    SeforimFixtureVariant.full,
    SeforimFixtureVariant.minimal,
    SeforimFixtureVariant.missingAuthorTables,
  ]) {
    test(
      'שורות הקטלוג זהות לשאילתה על החיבור הראשי (${variant.name})',
      () async {
        await openLibrary(variant);
        final repository = provider.sqliteProvider.repository!;
        final db = await repository.database.database;

        final rows = readOfficialCatalogSync(provider.sqliteProvider.dbPath);

        expect(
          rows.books,
          repository.database.bookDao.getAllBooksMinimal(
            db,
            withStoredFileColumns: true,
          ),
        );
        expect(
          rows.categories,
          repository.database.categoryDao.getAllCategoryRows(db),
        );
        expect(rows.authors, repository.database.bookDao.getBookAuthorsMap(db));
      },
    );
  }

  test('בניית הקטלוג אינה שואלת את החיבור של ה-UI isolate', () async {
    await openLibrary(SeforimFixtureVariant.full);
    final db = await provider.sqliteProvider.repository!.database.database;
    // טרנזקציה פתוחה על החיבור הראשי: BEGIN נוסף עליו נכשל.
    db.execute('BEGIN');
    try {
      final library = await provider.buildLibraryCatalog({}, libraryPath);
      expect(
        library.getAllBooks().map((book) => book.title),
        contains(SeforimFixtureIds.bereshitTitle),
      );
    } finally {
      db.execute('ROLLBACK');
    }
  });

  test('שם מחבר עם פסיק נשמר בשלמותו בקטלוג לצד מחבר נוסף', () async {
    const authorName = 'אלכסנדר זיסקינד מהוראדנא, בעל יסוד ושורש העבודה';
    await openLibrary(
      SeforimFixtureVariant.full,
      populate: (db) {
        db.execute('INSERT INTO author (id, name) VALUES (2, ?)', [authorName]);
        db.execute('INSERT INTO book_author (bookId, authorId) VALUES (?, 2)', [
          SeforimFixtureIds.rashiId,
        ]);
      },
    );

    final library = await provider.buildLibraryCatalog({}, libraryPath);
    final book = library.getAllBooks().singleWhere(
      (book) => book.id == SeforimFixtureIds.rashiId,
    );
    expect(book.authors, [authorName, SeforimFixtureIds.authorName]);
    expect(book.author, book.authors.join(', '));
  });

  test('השהיית קריאות אינה מפעילה שאילתת קטלוג על החיבור הראשי', () async {
    await openLibrary(SeforimFixtureVariant.full);
    final db = await provider.sqliteProvider.repository!.database.database;
    db.execute('BEGIN');
    await DbReadWorker.suspendForExternalWrite();
    try {
      await expectLater(
        provider.buildLibraryCatalog({}, libraryPath),
        throwsA(isA<DbReadWorkerSuspended>()),
      );
    } finally {
      db.execute('ROLLBACK');
      await DbReadWorker.resumeAfterExternalWrite();
    }
  });

  test('סגירה בזמן בניית הקטלוג אינה פותחת שוב את החיבור ששוחרר', () async {
    await openLibrary(SeforimFixtureVariant.full);
    await provider.buildLibraryCatalog({}, libraryPath);
    final oldDatabase = provider.sqliteProvider.repository!.database;
    final building = provider.buildLibraryCatalog({}, libraryPath);
    final cancelled = expectLater(
      building,
      throwsA(isA<DbReadWorkerSuspended>()),
    );
    try {
      // ההשהיה חייבת להקדים את הקריאה; סגירת המנוע עצמה אסינכרונית.
      await DbReadWorker.suspendForExternalWrite();
      await provider.sqliteProvider.closeForExternalWrite();
      await cancelled;
      expect(provider.sqliteProvider.isInitialized, isFalse);
      expect(oldDatabase.isOpen, isFalse);
      final dbFile = File(provider.sqliteProvider.dbPath);
      final releasedPath = '${dbFile.path}.released';
      await dbFile.rename(releasedPath);
      await File(releasedPath).rename(dbFile.path);
    } finally {
      oldDatabase.close();
      await provider.sqliteProvider.reopenAfterExternalWrite();
    }
    final library = await provider.buildLibraryCatalog({}, libraryPath);
    expect(
      library.getAllBooks().map((book) => book.title),
      contains(SeforimFixtureIds.bereshitTitle),
    );
  });
}
