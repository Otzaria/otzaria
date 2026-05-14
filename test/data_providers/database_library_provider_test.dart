import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/data/constants/database_constants.dart';
import 'package:otzaria/data/data_providers/user_books_database_holder.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/data/data_providers/database_library_provider.dart';
import 'package:otzaria/library/models/library.dart' as library_models;
import 'package:otzaria/migration/models/author.dart';
import 'package:otzaria/migration/models/book.dart' as migration_models;
import 'package:otzaria/migration/models/category.dart' as migration_models;
import 'package:otzaria/migration/database/daos/database.dart';
import 'package:otzaria/migration/database/repository/seforim_repository.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:path/path.dart' as path;
import 'package:sqlite3/sqlite3.dart' as sqlite3;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DatabaseLibraryProvider', () {
    setUp(() async {
      await Settings.init(cacheProvider: _MemoryCacheProvider());
    });

    test('shouldIncludeBookByPath מסנן ספרי תלמוד בבלי כשהתיקייה חסרה', () {
      final filePath = path.join(
        '/library',
        DatabaseConstants.otzariaFolderName,
        DatabaseConstants.talmudBavliFolderName,
        'ברכות א.pdf',
      );

      expect(
        DatabaseLibraryProvider.shouldIncludeBookByPath(
          filePath,
          hasTalmudBavliDirectory: false,
          talmudBavliDirectoryPath: path.join(
            '/library',
            DatabaseConstants.otzariaFolderName,
            DatabaseConstants.talmudBavliFolderName,
          ),
        ),
        isFalse,
      );
    });

    test('shouldIncludeBookByPath משאיר קבצים אחרים גם כשהתיקייה חסרה', () {
      final otherFilePath = path.join(
        '/library',
        DatabaseConstants.otzariaFolderName,
        'משנה',
        'פאה.txt',
      );

      expect(
        DatabaseLibraryProvider.shouldIncludeBookByPath(
          otherFilePath,
          hasTalmudBavliDirectory: false,
          talmudBavliDirectoryPath: path.join(
            '/library',
            DatabaseConstants.otzariaFolderName,
            DatabaseConstants.talmudBavliFolderName,
          ),
        ),
        isTrue,
      );
    });

    test('isTalmudBavliFilePath מזהה נתיב מתוך התיקייה הייעודית', () {
      final filePath = path.join(
        '/library',
        'ספריה-מותאמת',
        DatabaseConstants.talmudBavliFolderName,
        'שבת ב.pdf',
      );

      expect(
        DatabaseConstants.isTalmudBavliFilePath(
          filePath,
          libraryPath: '/library',
          folderName: 'ספריה-מותאמת',
        ),
        isTrue,
      );
    });

    test('getTalmudBavliDirectoryPath מחזיר נתיב ליד ה-DB גם בלי תיקיית אוצריא',
        () {
      expect(
        DatabaseConstants.getTalmudBavliDirectoryPath('/library-root', ''),
        path.join('/library-root', DatabaseConstants.talmudBavliFolderName),
      );
    });

    test('isTalmudBavliFilePath מזהה גם חילוץ ידני בשורש הספרייה', () {
      final filePath = path.join(
        '/library-root',
        DatabaseConstants.talmudBavliFolderName,
        'ברכות.pdf',
      );

      expect(
        DatabaseConstants.isTalmudBavliFilePath(
          filePath,
          libraryPath: '/library-root',
          folderName: DatabaseConstants.otzariaFolderName,
        ),
        isTrue,
      );
    });

    test('loadBookLinksRowsForTesting טוען קישורים דרך sqlite ב-isolate worker',
        () async {
      final tempDir = await Directory.systemTemp.createTemp('otzaria_db_links');
      final dbPath = path.join(tempDir.path, 'db.sqlite');
      final db = sqlite3.sqlite3.open(dbPath);

      try {
        db.execute(
            'CREATE TABLE book (id INTEGER PRIMARY KEY, title TEXT, categoryId INTEGER, fileType TEXT)');
        db.execute(
            'CREATE TABLE line (id INTEGER PRIMARY KEY, lineIndex INTEGER, heRef TEXT)');
        db.execute(
            'CREATE TABLE connection_type (id INTEGER PRIMARY KEY, name TEXT)');
        db.execute(
            'CREATE TABLE link (sourceBookId INTEGER, sourceLineId INTEGER, targetLineId INTEGER, targetBookId INTEGER, connectionTypeId INTEGER)');

        db.execute(
            "INSERT INTO book (id, title, categoryId, fileType) VALUES (1, 'בראשית', 7, 'txt')");
        db.execute(
            "INSERT INTO book (id, title, categoryId, fileType) VALUES (2, 'רש''י על בראשית', 8, 'txt')");
        db.execute(
            "INSERT INTO line (id, lineIndex, heRef) VALUES (10, 0, 'א')");
        db.execute(
            "INSERT INTO line (id, lineIndex, heRef) VALUES (20, 3, 'ד')");
        db.execute(
            "INSERT INTO connection_type (id, name) VALUES (5, 'reference')");
        db.execute(
            'INSERT INTO link (sourceBookId, sourceLineId, targetLineId, targetBookId, connectionTypeId) VALUES (1, 10, 20, 2, 5)');

        final rows = DatabaseLibraryProvider.loadBookLinksRowsForTesting(
          dbPath: dbPath,
          title: 'בראשית',
          categoryId: 7,
          fileType: 'txt',
        );

        expect(rows, hasLength(1));
        expect(rows.first['sourceLineIndex'], 0);
        expect(rows.first['targetLineIndex'], 3);
        expect(rows.first['targetBookTitle'], 'רש\'י על בראשית');
        expect(rows.first['connectionTypeName'], 'reference');
      } finally {
        db.close();
        await tempDir.delete(recursive: true);
      }
    });

    test('loadBookLinksRowsInRangeForTesting מסנן לפי חלון שורות', () async {
      final tempDir = await Directory.systemTemp.createTemp('otzaria_db_range');
      final dbPath = path.join(tempDir.path, 'db.sqlite');
      final db = sqlite3.sqlite3.open(dbPath);

      try {
        db.execute(
            'CREATE TABLE book (id INTEGER PRIMARY KEY, title TEXT, categoryId INTEGER, fileType TEXT, orderIndex INTEGER)');
        db.execute(
            'CREATE TABLE line (id INTEGER PRIMARY KEY, lineIndex INTEGER, heRef TEXT)');
        db.execute(
            'CREATE TABLE connection_type (id INTEGER PRIMARY KEY, name TEXT)');
        db.execute(
            'CREATE TABLE link (sourceBookId INTEGER, sourceLineId INTEGER, targetLineId INTEGER, targetBookId INTEGER, connectionTypeId INTEGER)');

        db.execute(
            "INSERT INTO book (id, title, categoryId, fileType, orderIndex) VALUES (1, 'בראשית', 7, 'txt', 1)");
        db.execute(
            "INSERT INTO book (id, title, categoryId, fileType, orderIndex) VALUES (2, 'מפרש א', 8, 'txt', 1)");
        db.execute(
            "INSERT INTO book (id, title, categoryId, fileType, orderIndex) VALUES (3, 'מפרש ב', 8, 'txt', 2)");
        db.execute(
            "INSERT INTO line (id, lineIndex, heRef) VALUES (10, 4, 'ד')");
        db.execute(
            "INSERT INTO line (id, lineIndex, heRef) VALUES (11, 40, 'מ')");
        db.execute(
            "INSERT INTO line (id, lineIndex, heRef) VALUES (20, 0, 'א')");
        db.execute(
            "INSERT INTO line (id, lineIndex, heRef) VALUES (21, 1, 'ב')");
        db.execute(
            "INSERT INTO connection_type (id, name) VALUES (5, 'reference')");
        db.execute(
            'INSERT INTO link (sourceBookId, sourceLineId, targetLineId, targetBookId, connectionTypeId) VALUES (1, 10, 20, 2, 5)');
        db.execute(
            'INSERT INTO link (sourceBookId, sourceLineId, targetLineId, targetBookId, connectionTypeId) VALUES (1, 11, 21, 3, 5)');

        final rows = DatabaseLibraryProvider.loadBookLinksRowsInRangeForTesting(
          dbPath: dbPath,
          title: 'בראשית',
          categoryId: 7,
          fileType: 'txt',
          startLineIndex: 0,
          endLineIndex: 10,
        );

        expect(rows, hasLength(1));
        expect(rows.first['sourceLineIndex'], 4);
        expect(rows.first['targetBookTitle'], 'מפרש א');
      } finally {
        db.close();
        await tempDir.delete(recursive: true);
      }
    });

    test('loadBookLinksRowsInRangeForTesting מסנן גם לפי ספרי יעד', () async {
      final tempDir =
          await Directory.systemTemp.createTemp('otzaria_db_target');
      final dbPath = path.join(tempDir.path, 'db.sqlite');
      final db = sqlite3.sqlite3.open(dbPath);

      try {
        db.execute(
            'CREATE TABLE book (id INTEGER PRIMARY KEY, title TEXT, categoryId INTEGER, fileType TEXT, orderIndex INTEGER)');
        db.execute(
            'CREATE TABLE line (id INTEGER PRIMARY KEY, lineIndex INTEGER, heRef TEXT)');
        db.execute(
            'CREATE TABLE connection_type (id INTEGER PRIMARY KEY, name TEXT)');
        db.execute(
            'CREATE TABLE link (sourceBookId INTEGER, sourceLineId INTEGER, targetLineId INTEGER, targetBookId INTEGER, connectionTypeId INTEGER)');

        db.execute(
            "INSERT INTO book (id, title, categoryId, fileType, orderIndex) VALUES (1, 'בראשית', 7, 'txt', 1)");
        db.execute(
            "INSERT INTO book (id, title, categoryId, fileType, orderIndex) VALUES (2, 'מפרש א', 8, 'txt', 1)");
        db.execute(
            "INSERT INTO book (id, title, categoryId, fileType, orderIndex) VALUES (3, 'מפרש ב', 8, 'txt', 2)");
        db.execute(
            "INSERT INTO line (id, lineIndex, heRef) VALUES (10, 4, 'ד')");
        db.execute(
            "INSERT INTO line (id, lineIndex, heRef) VALUES (11, 5, 'ה')");
        db.execute(
            "INSERT INTO line (id, lineIndex, heRef) VALUES (20, 0, 'א')");
        db.execute(
            "INSERT INTO line (id, lineIndex, heRef) VALUES (21, 1, 'ב')");
        db.execute(
            "INSERT INTO connection_type (id, name) VALUES (5, 'COMMENTARY')");
        db.execute(
            'INSERT INTO link (sourceBookId, sourceLineId, targetLineId, targetBookId, connectionTypeId) VALUES (1, 10, 20, 2, 5)');
        db.execute(
            'INSERT INTO link (sourceBookId, sourceLineId, targetLineId, targetBookId, connectionTypeId) VALUES (1, 11, 21, 3, 5)');

        final rows = DatabaseLibraryProvider.loadBookLinksRowsInRangeForTesting(
          dbPath: dbPath,
          title: 'בראשית',
          categoryId: 7,
          fileType: 'txt',
          startLineIndex: 0,
          endLineIndex: 10,
          targetBookTitles: const ['מפרש ב'],
        );

        expect(rows, hasLength(1));
        expect(rows.first['sourceLineIndex'], 5);
        expect(rows.first['targetBookTitle'], 'מפרש ב');
      } finally {
        db.close();
        await tempDir.delete(recursive: true);
      }
    });

    test('loadAlternativeStructuresRowsForTesting טוען כותרות חלופיות מה-DB',
        () async {
      final tempDir = await Directory.systemTemp.createTemp('otzaria_db_alt');
      final dbPath = path.join(tempDir.path, 'db.sqlite');
      final db = sqlite3.sqlite3.open(dbPath);

      try {
        db.execute('CREATE TABLE book (id INTEGER PRIMARY KEY, title TEXT)');
        db.execute(
            'CREATE TABLE alt_toc_structure (id INTEGER PRIMARY KEY, bookId INTEGER, key TEXT, title TEXT, heTitle TEXT)');

        db.execute("INSERT INTO book (id, title) VALUES (1, 'בראשית')");
        db.execute(
            "INSERT INTO alt_toc_structure (id, bookId, key, title, heTitle) VALUES (9, 1, 'chapters', 'Chapters', 'פרקים')");

        final rows =
            DatabaseLibraryProvider.loadAlternativeStructuresRowsForTesting(
          dbPath: dbPath,
          bookTitle: 'בראשית',
        );

        expect(rows, hasLength(1));
        expect(rows.first['id'], 9);
        expect(rows.first['bookId'], 1);
        expect(rows.first['key'], 'chapters');
        expect(rows.first['heTitle'], 'פרקים');
      } finally {
        db.close();
        await tempDir.delete(recursive: true);
      }
    });

    test('buildLibraryCatalog שומר מחבר מה-DB וחיפוש הספריה מוצא לפי מחבר',
        () async {
      final tempDir =
          await Directory.systemTemp.createTemp('otzaria_db_minimal_books');
      final dbPath =
          path.join(tempDir.path, DatabaseConstants.databaseFileName);
      final database = MyDatabase.withPath(dbPath);
      final repository = SeforimRepository(database);
      final provider = DatabaseLibraryProvider.instance;
      final previousLibraryPath =
          Settings.getValue<String>(SettingsRepository.keyLibraryPath);
      final previousFolderName =
          Settings.getValue<String>(SettingsRepository.keyLibraryFolderName);
      final previousEffectiveDbPath =
          Settings.getValue<String>(SettingsRepository.keyDbEffectivePath);

      try {
        await provider.sqliteProvider.dispose();
        provider.clearCache();
        await repository.ensureInitialized();

        await Settings.setValue<String>(
          SettingsRepository.keyLibraryPath,
          tempDir.path,
        );
        await Settings.setValue<String>(
          SettingsRepository.keyLibraryFolderName,
          '',
        );
        await Settings.setValue<String>(
          SettingsRepository.keyDbEffectivePath,
          '',
        );

        final sourceId = await repository.insertSource('local-test', -10);
        final categoryId = await repository.insertCategory(
          const migration_models.Category(
            title: 'הלכה',
            parentId: null,
            level: 0,
          ),
        );

        await repository.insertBook(
          migration_models.Book(
            id: 1,
            categoryId: categoryId,
            sourceId: sourceId,
            title: 'ספר בדיקה',
            authors: const [Author(name: 'רש"י')],
            filePath: path.join(tempDir.path, 'book.txt'),
            fileType: 'txt',
          ),
        );

        final db = await database.database;
        db.execute('BEGIN');
        try {
          for (var index = 2; index <= 1200; index++) {
            db.execute(
              '''
              INSERT INTO book (
                id, categoryId, sourceId, title, orderIndex, totalLines, filePath, fileType
              ) VALUES (?, ?, ?, ?, ?, 0, ?, 'txt')
              ''',
              [
                index,
                categoryId,
                sourceId,
                'ספר $index',
                index,
                path.join(tempDir.path, 'book_$index.txt'),
              ],
            );
          }
          db.execute('COMMIT');
        } catch (_) {
          db.execute('ROLLBACK');
          rethrow;
        }

        await provider.initialize();
        final library = await provider.buildLibraryCatalog({}, tempDir.path);
        final books = library.subCategories.single.books;
        final targetBook =
            books.firstWhere((book) => book.title == 'ספר בדיקה');

        expect(library.subCategories, hasLength(1));
        expect(books, hasLength(1200));
        expect(targetBook.author, 'רש"י');

        final repositoryForSearch = DataRepository()
          ..library = Future.value(library);
        final results = await repositoryForSearch.findBooks(
          'רש"י',
          library.subCategories.single,
          sortByRatio: false,
        );

        expect(results, hasLength(1));
        expect(results.single.title, 'ספר בדיקה');
      } finally {
        await Settings.setValue<String>(
          SettingsRepository.keyLibraryPath,
          previousLibraryPath ?? '',
        );
        await Settings.setValue<String>(
          SettingsRepository.keyLibraryFolderName,
          previousFolderName ?? '',
        );
        await Settings.setValue<String>(
          SettingsRepository.keyDbEffectivePath,
          previousEffectiveDbPath ?? '',
        );
        await provider.sqliteProvider.dispose();
        provider.clearCache();
        database.close();
        await tempDir.delete(recursive: true);
      }
    });

    test('buildLibraryCatalog ממזג ספרים אישיים קיימים מול user_books',
        () async {
      final tempDir =
          await Directory.systemTemp.createTemp('otzaria_user_books_merge');
      final libraryPath = path.join(tempDir.path, 'library');
      final dataRootPath = path.join(tempDir.path, 'data_root');
      final dbPath = path.join(libraryPath, DatabaseConstants.databaseFileName);
      final database = MyDatabase.withPath(dbPath);
      final repository = SeforimRepository(database);
      final provider = DatabaseLibraryProvider.instance;
      final previousLibraryPath =
          Settings.getValue<String>(SettingsRepository.keyLibraryPath);
      final previousFolderName =
          Settings.getValue<String>(SettingsRepository.keyLibraryFolderName);
      final previousEffectiveDbPath =
          Settings.getValue<String>(SettingsRepository.keyDbEffectivePath);
      final previousDataRootPath = AppPaths.cachedDataRootPath;

      // ניקיון בעזרת addTearDown במקום try/finally: כל קריאה רצה
      // בנפרד גם אם הקודמת זורקת, ולכן הטסט לא משאיר Settings מלוכלכים
      // לטסטים הבאים גם אם רק חלק מהשלבים מצליחים.
      // addTearDown מבצע ב-LIFO — נרשום בסדר הפוך לרצוי, כדי שתחילה
      // ייסגרו ה-DBs ואחר כך תימחק התיקייה הזמנית.
      addTearDown(() => tempDir.delete(recursive: true));
      addTearDown(() => database.close());
      addTearDown(() => provider.clearCache());
      addTearDown(() => provider.sqliteProvider.dispose());
      addTearDown(
          () => AppPaths.debugOverrideDataRootPath(previousDataRootPath));
      addTearDown(() => UserBooksDatabaseHolder.instance.close());
      addTearDown(() async {
        await Settings.setValue<String>(
          SettingsRepository.keyDbEffectivePath,
          previousEffectiveDbPath ?? '',
        );
      });
      addTearDown(() async {
        await Settings.setValue<String>(
          SettingsRepository.keyLibraryFolderName,
          previousFolderName ?? '',
        );
      });
      addTearDown(() async {
        await Settings.setValue<String>(
          SettingsRepository.keyLibraryPath,
          previousLibraryPath ?? '',
        );
      });

      await Directory(libraryPath).create(recursive: true);
      await provider.sqliteProvider.dispose();
      provider.clearCache();
      await UserBooksDatabaseHolder.instance.close();
      AppPaths.debugOverrideDataRootPath(dataRootPath);
      await repository.ensureInitialized();

      await Settings.setValue<String>(
        SettingsRepository.keyLibraryPath,
        libraryPath,
      );
      await Settings.setValue<String>(
        SettingsRepository.keyLibraryFolderName,
        '',
      );
      await Settings.setValue<String>(
        SettingsRepository.keyDbEffectivePath,
        '',
      );

      final sourceId = await repository.insertSource('local-test', -10);
        final personalCategoryId = await repository.insertCategory(
          const migration_models.Category(
            title: 'ספרים אישיים',
            parentId: null,
            level: 0,
            orderIndex: 1,
          ),
        );
        final existingFolderId = await repository.insertCategory(
          migration_models.Category(
            title: 'תיקייה קיימת',
            parentId: personalCategoryId,
            level: 1,
            orderIndex: 1,
          ),
        );

        await repository.insertBook(
          migration_models.Book(
            id: 1,
            categoryId: existingFolderId,
            sourceId: sourceId,
            title: 'ספר ראשי',
            filePath: path.join(tempDir.path, 'main_book.txt'),
            fileType: 'txt',
          ),
        );

        final userBooksRepository =
            await UserBooksDatabaseHolder.instance.repository;
        final userSourceId =
            await userBooksRepository.insertSource('user-test', -20);
        final userPersonalCategoryId = await userBooksRepository.insertCategory(
          const migration_models.Category(
            title: 'ספרים אישיים',
            parentId: null,
            level: 0,
            orderIndex: 1,
          ),
        );
        final userExistingFolderId = await userBooksRepository.insertCategory(
          migration_models.Category(
            title: 'תיקייה קיימת',
            parentId: userPersonalCategoryId,
            level: 1,
            orderIndex: 1,
          ),
        );
        final nestedFolderId = await userBooksRepository.insertCategory(
          migration_models.Category(
            title: 'תת קטגוריה',
            parentId: userExistingFolderId,
            level: 2,
            orderIndex: 1,
          ),
        );

        await userBooksRepository.insertBook(
          migration_models.Book(
            categoryId: userExistingFolderId,
            sourceId: userSourceId,
            title: 'ספר משתמש',
            filePath: path.join(tempDir.path, 'user_book.txt'),
            fileType: 'txt',
          ),
        );
        await userBooksRepository.insertBook(
          migration_models.Book(
            categoryId: nestedFolderId,
            sourceId: userSourceId,
            title: 'ספר פנימי',
            filePath: path.join(tempDir.path, 'nested_user_book.txt'),
            fileType: 'txt',
          ),
        );

        await provider.initialize();
        final library = await provider.buildLibraryCatalog({}, libraryPath);

        final personalCategories =
            library.subCategories.where((c) => c.title == 'ספרים אישיים');
        expect(personalCategories, hasLength(1));

        final personalCategory = personalCategories.single;
        final mergedCategories = personalCategory.subCategories
            .where((c) => c.title == 'תיקייה קיימת');
        expect(mergedCategories, hasLength(1));

        final mergedCategory = mergedCategories.single;
        expect(mergedCategory.parent, same(personalCategory));
        expect(
          mergedCategory.books.map((book) => book.title),
          containsAll(['ספר ראשי', 'ספר משתמש']),
        );

        final mainBook =
            mergedCategory.books.firstWhere((book) => book.title == 'ספר ראשי');
        final userBook = mergedCategory.books
            .firstWhere((book) => book.title == 'ספר משתמש');
        expect(mainBook.category, same(mergedCategory));
        expect(userBook.category, same(mergedCategory));

        final nestedCategories =
            mergedCategory.subCategories.where((c) => c.title == 'תת קטגוריה');
        expect(nestedCategories, hasLength(1));

        final nestedCategory = nestedCategories.single;
        expect(nestedCategory.parent, same(mergedCategory));
        expect(nestedCategory.path, '/ספרים אישיים/תיקייה קיימת/תת קטגוריה');
        expect(nestedCategory.books, hasLength(1));
      expect(nestedCategory.books.single.title, 'ספר פנימי');
      expect(nestedCategory.books.single.category, same(nestedCategory));
    });

    test(
        'populateUserBooksCategoryForTesting ממלא קטגוריה קיימת בלי לשבור parent ו-category',
        () {
      final provider = DatabaseLibraryProvider.instance;
      provider.clearCache();

      final library = library_models.Library(categories: []);
      final personalCategory = library_models.Category(
        title: 'ספרים אישיים',
        description: '',
        shortDescription: '',
        order: 1,
        subCategories: [],
        books: [],
        parent: library,
      );
      library.subCategories.add(personalCategory);

      final existingCategory = library_models.Category(
        title: 'תיקייה קיימת',
        description: '',
        shortDescription: '',
        order: 1,
        subCategories: [],
        books: [],
        parent: personalCategory,
      );
      personalCategory.subCategories.add(existingCategory);

      provider.populateUserBooksCategoryForTesting(
        targetCategory: existingCategory,
        dbCategory: const migration_models.Category(
          id: 10,
          parentId: 1,
          title: 'תיקייה קיימת',
          level: 1,
          orderIndex: 1,
        ),
        booksByCategory: {
          10: [
            {
              'id': 100,
              'title': 'ספר קיים בעץ',
              'categoryId': 10,
              'orderIndex': 1,
              'fileType': 'txt',
            },
          ],
          11: [
            {
              'id': 101,
              'title': 'ספר פנימי',
              'categoryId': 11,
              'orderIndex': 1,
              'fileType': 'txt',
            },
          ],
        },
        categoriesByParent: {
          10: const [
            migration_models.Category(
              id: 11,
              parentId: 10,
              title: 'תת קטגוריה',
              level: 2,
              orderIndex: 1,
            ),
          ],
        },
        authorsByBookId: const {},
        metadata: const {},
      );

      expect(existingCategory.books, hasLength(1));
      expect(existingCategory.books.single.category, same(existingCategory));

      expect(existingCategory.subCategories, hasLength(1));
      final nestedCategory = existingCategory.subCategories.single;
      expect(nestedCategory.parent, same(existingCategory));
      expect(nestedCategory.path, '/ספרים אישיים/תיקייה קיימת/תת קטגוריה');
      expect(nestedCategory.books, hasLength(1));
      expect(nestedCategory.books.single.category, same(nestedCategory));
    });

    test('mergeLinksForTesting ממזג קישורים בלי כפילויות ושומר קישורים קודמים',
        () {
      final existing = [
        Link(
          heRef: 'א',
          index1: 75,
          path2: 'מפרש א',
          index2: 3,
          connectionType: 'reference',
        ),
        Link(
          heRef: 'ב',
          index1: 100,
          path2: 'מפרש ב',
          index2: 5,
          connectionType: 'reference',
        ),
      ];

      final incoming = [
        Link(
          heRef: 'ב',
          index1: 100,
          path2: 'מפרש ב',
          index2: 5,
          connectionType: 'reference',
        ),
        Link(
          heRef: 'ג',
          index1: 200,
          path2: 'מפרש ג',
          index2: 7,
          connectionType: 'reference',
        ),
      ];

      final merged = TextBookBloc.mergeLinksForTesting(existing, incoming);

      expect(merged, hasLength(3));
      expect(merged.map((link) => link.index1), [75, 100, 200]);
    });
  });
}

class _MemoryCacheProvider extends CacheProvider {
  final Map<String, Object?> _values = {};

  @override
  Future<void> init() async {}

  @override
  bool containsKey(String key) => _values.containsKey(key);

  @override
  Set getKeys() => _values.keys.toSet();

  @override
  bool? getBool(String key, {bool? defaultValue}) =>
      _values[key] as bool? ?? defaultValue;

  @override
  double? getDouble(String key, {double? defaultValue}) =>
      _values[key] as double? ?? defaultValue;

  @override
  int? getInt(String key, {int? defaultValue}) =>
      _values[key] as int? ?? defaultValue;

  @override
  String? getString(String key, {String? defaultValue}) =>
      _values[key] as String? ?? defaultValue;

  @override
  T? getValue<T>(String key, {T? defaultValue}) {
    final value = _values[key];
    if (value is T) {
      return value;
    }
    return defaultValue;
  }

  @override
  Future<void> remove(String key) async {
    _values.remove(key);
  }

  @override
  Future<void> removeAll() async {
    _values.clear();
  }

  @override
  Future<void> setBool(String key, bool? value) async {
    _values[key] = value;
  }

  @override
  Future<void> setDouble(String key, double? value) async {
    _values[key] = value;
  }

  @override
  Future<void> setInt(String key, int? value) async {
    _values[key] = value;
  }

  @override
  Future<void> setObject<T>(String key, T? value) async {
    _values[key] = value;
  }

  @override
  Future<void> setString(String key, String? value) async {
    _values[key] = value;
  }
}
