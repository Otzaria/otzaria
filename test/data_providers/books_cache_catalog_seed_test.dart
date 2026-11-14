import 'dart:async';
import 'dart:io';

import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/data/cache/books_cache.dart';
import 'package:otzaria/data/constants/database_constants.dart';
import 'package:otzaria/data/data_providers/database_library_provider.dart';
import 'package:otzaria/data/data_providers/official_catalog_rows.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:otzaria/data/data_providers/user_books_database_holder.dart';
import 'package:otzaria/find_ref/repository/find_ref_db_isolate.dart';
import 'package:otzaria/migration/database/daos/database.dart';
import 'package:otzaria/migration/database/repository/seforim_repository.dart';
import 'package:otzaria/migration/models/book.dart' as migration_models;
import 'package:otzaria/migration/models/category.dart' as migration_models;
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:path/path.dart' as path;

import '../test_helpers/memory_cache_provider.dart';

/// המסלולים שקוראים את `seforim.db` בפתיחת האפליקציה ובפתיחת ספר: בניית
/// הקטלוג ו-`BooksCache` חולקים קריאה אחת של טבלת `book`, וה-TOC עובר ב-isolate.
/// הבדיקות רצות מול DB אמיתי בתיקייה זמנית.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late String libraryPath;
  late MyDatabase seforimDb;
  late SeforimRepository seforimRepo;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('otzaria_catalog_seed');
    libraryPath = path.join(tempDir.path, 'library');
    await Directory(libraryPath).create(recursive: true);

    await Settings.init(cacheProvider: MemoryCacheProvider());
    AppPaths.debugOverrideDataRootPath(path.join(tempDir.path, 'data_root'));
    await UserBooksDatabaseHolder.instance.close();

    await Settings.setValue<String>(
      SettingsRepository.keyLibraryPath,
      libraryPath,
    );
    await Settings.setValue<String>(
      SettingsRepository.keyLibraryFolderName,
      '',
    );
    await Settings.setValue<String>(SettingsRepository.keyDbEffectivePath, '');

    seforimDb = MyDatabase.withPath(
      path.join(libraryPath, DatabaseConstants.databaseFileName),
    );
    seforimRepo = SeforimRepository(seforimDb);
    await seforimRepo.ensureInitialized();

    BooksCache.instance.clear();
    DatabaseLibraryProvider.instance.clearCache();
    await SqliteDataProvider.instance.dispose();
    await SqliteDataProvider.instance.initialize();
  });

  tearDown(() async {
    BooksCache.instance.clear();
    DatabaseLibraryProvider.instance.clearCache();
    await SqliteDataProvider.instance.dispose();
    await UserBooksDatabaseHolder.instance.close();
    seforimDb.close();
    AppPaths.debugOverrideDataRootPath(null);
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  Future<int> insertBook({
    required SeforimRepository repo,
    required String title,
    String categoryTitle = 'תורה',
  }) async {
    final categoryId = await repo.insertCategory(
      migration_models.Category(title: categoryTitle),
    );
    final sourceId = await repo.insertSource('test::$title', -1);
    return repo.insertBook(
      migration_models.Book(
        categoryId: categoryId,
        sourceId: sourceId,
        title: title,
        fileType: 'txt',
      ),
    );
  }

  Future<void> insertToc(SeforimRepository repo, int bookId) async {
    final db = await repo.database.database;
    db.execute("INSERT INTO tocText (id, text) VALUES (1, 'פרק א')");
    db.execute(
      'INSERT INTO line (id, bookId, lineIndex, content) '
      "VALUES (500, $bookId, 0, 'שורה')",
    );
    db.execute(
      'INSERT INTO tocEntry (bookId, parentId, textId, level, lineId) '
      'VALUES ($bookId, NULL, 1, 0, 500)',
    );
  }

  Future<void> insertPdfBook(SeforimRepository repo, String title) async {
    final categoryId = await repo.insertCategory(
      migration_models.Category(title: 'ספרי PDF'),
    );
    final sourceId = await repo.insertSource('test::$title', -1);
    await repo.insertBook(
      migration_models.Book(
        categoryId: categoryId,
        sourceId: sourceId,
        title: title,
        fileType: 'pdf',
        filePath: '/pdf/$title.pdf',
      ),
    );
  }

  /// סופר קריאות של שורות הקטלוג ובקשות ל-FindRef; משוחזר בסוף הבדיקה.
  ({int Function() catalogReads, int Function() findRefReads}) countReads({
    void Function()? onCatalogRead,
  }) {
    final realReader = officialCatalogReader;
    final realFallback = BooksCache.fallbackRowsReader;
    var catalogReads = 0;
    var findRefReads = 0;
    officialCatalogReader = (dbPath) {
      catalogReads++;
      onCatalogRead?.call();
      return realReader(dbPath);
    };
    BooksCache.fallbackRowsReader = () {
      findRefReads++;
      return realFallback();
    };
    addTearDown(() {
      officialCatalogReader = realReader;
      BooksCache.fallbackRowsReader = realFallback;
    });
    return (
      catalogReads: () => catalogReads,
      findRefReads: () => findRefReads,
    );
  }

  test('בניית הקטלוג לבדה זורעת את BooksCache בכל הספרים', () async {
    await insertBook(repo: seforimRepo, title: 'בראשית');
    await insertBook(repo: seforimRepo, title: 'שמות', categoryTitle: 'נביאים');
    await insertPdfBook(seforimRepo, 'ספר סרוק');

    expect(BooksCache.instance.isLoaded, isFalse);

    final library = await DatabaseLibraryProvider.instance.buildLibraryCatalog(
      {},
      libraryPath,
    );

    expect(
      library.getAllBooks().map((b) => b.title),
      containsAll(['בראשית', 'שמות']),
      reason: 'הקטלוג לא נבנה; בדוק את ההכנה',
    );
    expect(
      BooksCache.instance.isLoaded,
      isTrue,
      reason: 'בלי זריעה, ה-warmUp קורא את טבלת book פעם שנייה',
    );
    expect(
      BooksCache.instance.books.map((b) => b.title),
      containsAll(['בראשית', 'שמות', 'ספר סרוק']),
    );
    final pdf = BooksCache.instance.books.singleWhere(
      (b) => b.title == 'ספר סרוק',
    );
    expect(pdf.fileType, 'pdf');
    expect(pdf.filePath, '/pdf/ספר סרוק.pdf');
  });

  for (final warmUpFirst in [true, false]) {
    test(
      'warmUp במקביל לבניית הקטלוג קורא את טבלת book פעם אחת '
      '(${warmUpFirst ? 'warmUp' : 'הקטלוג'} ראשון)',
      () async {
        await insertBook(repo: seforimRepo, title: 'בראשית');
        final catalogReadStarted = Completer<void>();
        final reads = countReads(onCatalogRead: catalogReadStarted.complete);
        final provider = DatabaseLibraryProvider.instance;

        final Future<void> warmUp;
        final Future<Object> catalog;
        if (warmUpFirst) {
          warmUp = BooksCache.instance.warmUp();
          catalog = provider.buildLibraryCatalog({}, libraryPath);
        } else {
          catalog = provider.buildLibraryCatalog({}, libraryPath);
          await catalogReadStarted.future;
          warmUp = BooksCache.instance.warmUp();
        }
        await Future.wait([warmUp, catalog]);

        expect(reads.catalogReads(), 1);
        expect(reads.findRefReads(), 0);
        expect(BooksCache.instance.isLoaded, isTrue);
        expect(BooksCache.instance.books.single.title, 'בראשית');
      },
    );
  }

  test('warmUp לבדו (בלי קטלוג) טוען את הקאש', () async {
    await insertBook(repo: seforimRepo, title: 'ויקרא');
    final reads = countReads();

    await BooksCache.instance.warmUp();

    expect(BooksCache.instance.isLoaded, isTrue);
    expect(BooksCache.instance.books.single.title, 'ויקרא');
    expect(BooksCache.instance.books.single.fileType, 'txt');
    expect(reads.catalogReads(), 1);
    expect(reads.findRefReads(), 0);
  });

  test('clear במהלך הקריאה המשותפת פוסל את הזריעה מהקטלוג', () async {
    await insertBook(repo: seforimRepo, title: 'בראשית');
    countReads(onCatalogRead: BooksCache.instance.clear);

    await DatabaseLibraryProvider.instance.buildLibraryCatalog({}, libraryPath);

    expect(BooksCache.instance.isLoaded, isFalse);
  });

  test(
    'closeForExternalWrite משהה גם את ה-worker, ו-reopen מחזיר אותו',
    () async {
      await insertBook(repo: seforimRepo, title: 'בראשית');

      final isolate = await FindRefDbIsolate.instance();
      addTearDown(isolate.disposeForTesting);
      expect((await isolate.getAllLocalBooksSlim()), hasLength(1));

      // ה-teardown משחרר את ה-write session גם בכשל; אחרת הבדיקה הבאה
      // נתקעת על ה-gate של SqliteDataProvider.
      addTearDown(SqliteDataProvider.instance.reopenAfterExternalWrite);
      // עדכון ספרייה מוחק ומחליף את הקובץ מיד אחרי הקריאה הזו.
      await SqliteDataProvider.instance.closeForExternalWrite();
      await expectLater(
        isolate.getAllLocalBooksSlim(),
        throwsA(isA<StateError>()),
        reason: 'ה-worker חייב להיות ללא חיבור בחלון הכתיבה החיצונית',
      );

      await SqliteDataProvider.instance.reopenAfterExternalWrite();
      expect((await isolate.getAllLocalBooksSlim()), hasLength(1));
    },
  );

  group('ניתוב ה-TOC בפתיחת ספר', () {
    test('ספר seforim.db נקרא דרך ה-isolate; ספר משתמש לא', () async {
      final seforimBookId = await insertBook(
        repo: seforimRepo,
        title: 'בראשית',
      );
      await insertToc(seforimRepo, seforimBookId);

      final userRepo = await UserBooksDatabaseHolder.instance.repository;
      final userBookId = await insertBook(
        repo: userRepo,
        title: 'ספר אישי',
        categoryTitle: 'ספרים אישיים',
      );
      await insertToc(userRepo, userBookId);

      final isolate = await FindRefDbIsolate.instance();
      addTearDown(isolate.disposeForTesting);

      expect(
        (await SqliteDataProvider.instance.getBookTocFromDb(
          'בראשית',
        ))?.single.text,
        'פרק א',
      );

      // השהיית ה-worker מנטרלת אך ורק את מסלול seforim.db — הוכחה שספר
      // המשתמש אינו עובר דרכו.
      await FindRefDbIsolate.suspendForExternalWrite();
      addTearDown(FindRefDbIsolate.resumeAfterExternalWrite);

      expect(
        await SqliteDataProvider.instance.getBookTocFromDb('בראשית'),
        isNull,
      );
      expect(
        (await SqliteDataProvider.instance.getBookTocFromDb(
          'ספר אישי',
          null,
          'txt',
          BookSource.user,
        ))?.single.text,
        'פרק א',
      );
    });
  });
}
