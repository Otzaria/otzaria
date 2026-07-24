import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/data/constants/database_constants.dart';
import 'package:otzaria/data/data_providers/book_composite_key.dart';
import 'package:otzaria/data/data_providers/database_library_provider.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:otzaria/data/data_providers/user_books_database_holder.dart';
import 'package:otzaria/library/models/library.dart' as library_models;
import 'package:otzaria/migration/database/daos/database.dart';
import 'package:otzaria/migration/database/repository/seforim_repository.dart';
import 'package:otzaria/migration/models/book.dart' as migration_models;
import 'package:otzaria/migration/models/category.dart' as migration_models;
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:path/path.dart' as path;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DatabaseLibraryProvider.hasBook — ניתוב seforim/user_books', () {
    late Directory tempDir;
    late String libraryPath;
    late String dataRootPath;
    late MyDatabase seforimDb;
    late SeforimRepository seforimRepo;
    final provider = DatabaseLibraryProvider.instance;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('otzaria-has-book-');
      libraryPath = path.join(tempDir.path, 'library');
      dataRootPath = path.join(tempDir.path, 'data_root');
      await Directory(libraryPath).create(recursive: true);

      await Settings.init(cacheProvider: _MemoryCacheProvider());
      AppPaths.debugOverrideDataRootPath(dataRootPath);
      await UserBooksDatabaseHolder.instance.close();
      provider.clearCache();

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

      final dbPath = path.join(libraryPath, DatabaseConstants.databaseFileName);
      seforimDb = MyDatabase.withPath(dbPath);
      seforimRepo = SeforimRepository(seforimDb);
      await seforimRepo.ensureInitialized();
      await SqliteDataProvider.instance.dispose();
      await SqliteDataProvider.instance.initialize();
    });

    tearDown(() async {
      provider.clearCache();
      await SqliteDataProvider.instance.dispose();
      await UserBooksDatabaseHolder.instance.close();
      seforimDb.close();
      AppPaths.debugOverrideDataRootPath(null);
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test(
      'cache hit ב-_cachedKeys (seforim): מחזיר true בלי לפנות ל-DB',
      () async {
        provider.seedCacheForTesting(
          keys: const [
            BookCompositeKey(
              title: 'מטמון רשמי',
              categoryId: 5,
              fileType: 'txt',
            ),
          ],
        );

        // ל-DB אין את הספר — אם הקוד פונה ל-DB ולא ל-cache, הוא יחזיר false.
        final exists = await provider.hasBook('מטמון רשמי', 5, 'txt');

        expect(exists, isTrue);
      },
    );

    test(
      'cache hit ב-_userBooksCachedKeys: מחזיר true גם כש-seforim DB ריק',
      () async {
        // טעינת ה-user_books cache דרך populateUserBooksCategoryForTesting.
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

        const userCategoryId = 42;
        provider.populateUserBooksCategoryForTesting(
          targetCategory: personalCategory,
          dbCategory: const migration_models.Category(
            id: userCategoryId,
            title: 'ספרים אישיים',
            level: 0,
          ),
          booksByCategory: const {
            userCategoryId: [
              {
                'id': 1,
                'title': 'ספר במטמון user_books',
                'categoryId': userCategoryId,
                'orderIndex': 1,
                'fileType': 'txt',
              },
            ],
          },
          categoriesByParent: const {},
          authorsByBookId: const {},
          metadata: const {},
        );

        final exists = await provider.hasBook(
          'ספר במטמון user_books',
          userCategoryId,
          'txt',
        );

        expect(exists, isTrue);
      },
    );

    test(
      '_isUserBooksCategoryId נכון אבל המפתח לא ב-cache → ניגש ל-user_books.db',
      () async {
        // נטען את ה-cache עם רשומה אחת ב-user_books, אבל נשאל על ספר שלא נמצא
        // במפה של ה-cache — כדי לבחון את הענף שניגש לקובץ ה-DB ישירות.
        final userBooksRepo = await UserBooksDatabaseHolder.instance.repository;
        final personalCatId = await userBooksRepo.insertCategory(
          const migration_models.Category(title: 'ספרים אישיים'),
        );
        final folderId = await userBooksRepo.insertCategory(
          migration_models.Category(
            title: 'תיקייה אישית',
            parentId: personalCatId,
            level: 1,
          ),
        );
        final sourceId = await userBooksRepo.insertSource(
          'Personal::has-book',
          -1,
        );
        await userBooksRepo.insertBook(
          migration_models.Book(
            categoryId: folderId,
            sourceId: sourceId,
            title: 'נמצא רק ב-DB',
            fileType: 'txt',
          ),
        );

        // נטען רק את ה-categoryId ל-_userBooksCategoryIds דרך populate —
        // עם ספר אחר במפתח, כדי שה-_userBooksCachedKeys לא יכיל את 'נמצא רק ב-DB'.
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

        provider.populateUserBooksCategoryForTesting(
          targetCategory: personalCategory,
          dbCategory: migration_models.Category(
            id: folderId,
            title: 'תיקייה אישית',
            level: 0,
          ),
          // ספר שונה במפה — כדי שה-cache hit לא יקרה
          booksByCategory: {
            folderId: const [
              {
                'id': 999,
                'title': 'ספר אחר',
                'categoryId': 0,
                'orderIndex': 1,
                'fileType': 'txt',
              },
            ],
          },
          categoriesByParent: const {},
          authorsByBookId: const {},
          metadata: const {},
        );

        // עכשיו ה-categoryId רשום כקטגוריית user_books, אבל ספר 'נמצא רק ב-DB'
        // אינו ב-_userBooksCachedKeys → הקוד צריך לפנות ישירות ל-DB.
        final exists = await provider.hasBook('נמצא רק ב-DB', folderId, 'txt');

        expect(
          exists,
          isTrue,
          reason:
              'הענף שמחפש ב-UserBooksDatabaseHolder.repository כש-categoryId הוא user_books',
        );
      },
    );

    test('Fallback ל-seforim DB כש-categoryId לא רשום בשום cache', () async {
      // לא טוענים אף cache. הוספת ספר ל-seforim DB עצמו, ועל ידי כך בודקים
      // שהקוד נופל ל-_sqliteProvider.repository.
      final catId = await seforimRepo.insertCategory(
        const migration_models.Category(title: 'הלכה'),
      );
      final sourceId = await seforimRepo.insertSource('seforim', -1);
      await seforimRepo.insertBook(
        migration_models.Book(
          categoryId: catId,
          sourceId: sourceId,
          title: 'ספר רשמי בDB',
          fileType: 'txt',
        ),
      );

      // וודאי שאף cache לא רלוונטי
      provider.clearCache();

      final exists = await provider.hasBook('ספר רשמי בDB', catId, 'txt');

      expect(exists, isTrue);
    });

    test('מחזיר false כשהספר לא נמצא בשום מקום', () async {
      provider.clearCache();
      final exists = await provider.hasBook('לא קיים בשום מקום', 99, 'txt');
      expect(exists, isFalse);
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
    if (value is T) return value;
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
