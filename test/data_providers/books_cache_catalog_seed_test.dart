import 'dart:io';

import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/data/cache/books_cache.dart';
import 'package:otzaria/data/constants/database_constants.dart';
import 'package:otzaria/data/data_providers/database_library_provider.dart';
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

/// שני המסלולים שקוראים את `seforim.db` בפתיחת האפליקציה ובפתיחת ספר:
/// זריעת `BooksCache` מתוך בניית הקטלוג (שמייתרת קריאה שנייה של טבלת `book`),
/// והמסלול החלופי דרך ה-isolate. הבדיקות רצות מול DB אמיתי בתיקייה זמנית.
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

  test(
    'loadBooks זורע את BooksCache — בלי זה טבלת book נקראת פעם שנייה',
    () async {
      await insertBook(repo: seforimRepo, title: 'בראשית');
      await insertBook(
        repo: seforimRepo,
        title: 'שמות',
        categoryTitle: 'נביאים',
      );

      expect(BooksCache.instance.isLoaded, isFalse);

      final byCategory = await DatabaseLibraryProvider.instance.loadBooks({});

      // אם הקטלוג לא נבנה — הכשל אינו על הזריעה אלא על ההכנה.
      expect(byCategory, isNotEmpty, reason: 'הקטלוג לא נבנה; בדוק את ההכנה');
      expect(
        BooksCache.instance.isLoaded,
        isTrue,
        reason: 'loadBooks חייב לזרוע את BooksCache',
      );
      expect(
        BooksCache.instance.books.map((b) => b.title),
        containsAll(['בראשית', 'שמות']),
      );
    },
  );

  test('warmUp טוען את הקאש דרך ה-isolate כשלא קדמה זריעה', () async {
    await insertBook(repo: seforimRepo, title: 'ויקרא');
    addTearDown(() async {
      (await FindRefDbIsolate.instance()).disposeForTesting();
    });

    await BooksCache.instance.warmUp();

    expect(BooksCache.instance.isLoaded, isTrue);
    expect(BooksCache.instance.books.single.title, 'ויקרא');
    expect(BooksCache.instance.books.single.fileType, 'txt');
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
