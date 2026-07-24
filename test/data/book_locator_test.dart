import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/data/book_locator.dart';
import 'package:otzaria/data/constants/database_constants.dart';
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

  late Directory tempDir;
  late String libraryPath;
  late String dataRootPath;
  late MyDatabase seforimDb;
  late SeforimRepository seforimRepo;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('otzaria-book-locator-');
    libraryPath = path.join(tempDir.path, 'library');
    dataRootPath = path.join(tempDir.path, 'data_root');
    await Directory(libraryPath).create(recursive: true);

    await Settings.init(cacheProvider: _MemoryCacheProvider());
    AppPaths.debugOverrideDataRootPath(dataRootPath);
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

    final dbPath = path.join(libraryPath, DatabaseConstants.databaseFileName);
    seforimDb = MyDatabase.withPath(dbPath);
    seforimRepo = SeforimRepository(seforimDb);
    await seforimRepo.ensureInitialized();
    await SqliteDataProvider.instance.dispose();
    await SqliteDataProvider.instance.initialize();
  });

  tearDown(() async {
    await SqliteDataProvider.instance.dispose();
    await UserBooksDatabaseHolder.instance.close();
    seforimDb.close();
    AppPaths.debugOverrideDataRootPath(null);
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  /// Helper שמוסיף ספר ל-DB וקטגוריה, מחזיר את ה-categoryId.
  Future<int> insertBookFor({
    required SeforimRepository repo,
    required String title,
    String categoryTitle = 'תורה',
  }) async {
    final catId = await repo.insertCategory(
      migration_models.Category(title: categoryTitle),
    );
    final sourceId = await repo.insertSource('test::$categoryTitle', -1);
    await repo.insertBook(
      migration_models.Book(
        categoryId: catId,
        sourceId: sourceId,
        title: title,
        fileType: 'txt',
      ),
    );
    return catId;
  }

  group('BookLocator.locateBook', () {
    test('מאתר ספר ב-seforim DB לפי categoryId', () async {
      final catId = await insertBookFor(repo: seforimRepo, title: 'בראשית');

      final location = await BookLocator.locateBook(
        'בראשית',
        categoryId: catId,
      );

      expect(location, isNotNull);
      expect(location!.source, BookSource.database);
      expect(location.book?.title, 'בראשית');
      expect(location.repository, isNotNull);
    });

    test(
      'עם categoryId — מתעלם מקטגוריית "ספרים אישיים" כשאין categoryPath',
      () async {
        // נשתמש בקטגוריה ברירת מחדל (לא ספרים אישיים) → מחפש ב-seforim כברירה.
        final userBooksRepo = await UserBooksDatabaseHolder.instance.repository;
        final userCatId = await insertBookFor(
          repo: userBooksRepo,
          title: 'ספר משתמש',
        );

        // כשמעבירים את ה-userCatId בלי category.path → אין רמז שזה user_books.
        // הקוד מנסה seforim קודם (לא נמצא) ואז user_books דרך resolveBook.
        final location = await BookLocator.locateBook(
          'ספר משתמש',
          categoryId: userCatId,
        );

        expect(location, isNotNull, reason: 'נמצא ב-user_books דרך fallback');
        expect(location!.book?.title, 'ספר משתמש');
      },
    );

    test(
      'עם category שהיא "ספרים אישיים" → preferUserBooks=true בחיפוש',
      () async {
        // מכניסים ספר בשני ה-DBs באותה כותרת — צריך לבחור ב-user_books.
        final userBooksRepo = await UserBooksDatabaseHolder.instance.repository;
        final userCatId = await insertBookFor(
          repo: userBooksRepo,
          title: 'כפול',
        );
        await insertBookFor(
          repo: seforimRepo,
          title: 'כפול',
          categoryTitle: 'הלכה',
        );

        // קטגוריה עם נתיב המתחיל ב"ספרים אישיים"
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

        final location = await BookLocator.locateBook(
          'כפול',
          category: personalCategory,
          categoryId: userCatId,
        );

        expect(location, isNotNull);
        expect(location!.book?.title, 'כפול');
        expect(
          location.book?.categoryId,
          userCatId,
          reason: 'נבחר הספר מ-user_books לפי הרמז של הקטגוריה',
        );
      },
    );

    test('בלי categoryId ובלי category, חיפוש לפי כותרת ב-seforim', () async {
      await insertBookFor(repo: seforimRepo, title: 'רק כותרת');

      final location = await BookLocator.locateBook('רק כותרת');

      expect(location, isNotNull);
      expect(location!.source, BookSource.database);
      expect(location.book?.title, 'רק כותרת');
    });

    test('ספר שלא קיים בשום DB — מחזיר null (כי גם File System ריק)', () async {
      final location = await BookLocator.locateBook('לא קיים');

      expect(location, isNull);
    });
  });

  group('BookLocator.bookExists / getBookFromDatabase', () {
    test('bookExists=true עבור ספר ב-DB', () async {
      final catId = await insertBookFor(repo: seforimRepo, title: 'ויקרא');

      final exists = await BookLocator.bookExists('ויקרא', categoryId: catId);

      expect(exists, isTrue);
    });

    test('bookExists=false עבור ספר לא קיים', () async {
      final exists = await BookLocator.bookExists('לא קיים', categoryId: 1);

      expect(exists, isFalse);
    });

    test('getBookFromDatabase מחזיר את הרשומה מ-DB', () async {
      final catId = await insertBookFor(repo: seforimRepo, title: 'במדבר');

      final book = await BookLocator.getBookFromDatabase(
        'במדבר',
        categoryId: catId,
      );

      expect(book, isNotNull);
      expect(book!.title, 'במדבר');
      expect(book.categoryId, catId);
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
