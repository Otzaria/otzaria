import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/data/constants/database_constants.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:otzaria/data/data_providers/user_books_database_holder.dart';
import 'package:otzaria/migration/database/daos/database.dart';
import 'package:otzaria/migration/database/repository/seforim_repository.dart';
import 'package:otzaria/migration/models/author.dart';
import 'package:otzaria/migration/models/book.dart' as migration_models;
import 'package:otzaria/migration/models/category.dart' as migration_models;
import 'package:otzaria/models/books.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/text_book/utils/he_categories_enricher.dart';
import 'package:path/path.dart' as path;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('enrichHeCategories', () {
    late Directory tempDir;
    late String libraryPath;
    late String dataRootPath;
    late MyDatabase seforimDb;
    late SeforimRepository seforimRepo;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('otzaria-he-categories-');
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
      await SqliteDataProvider.instance.dispose();
      await UserBooksDatabaseHolder.instance.close();
      seforimDb.close();
      AppPaths.debugOverrideDataRootPath(null);
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test(
      'דילוג מוקדם: ספר עם heCategories שכבר אכלוס — לא מחזיר heCategories חדש',
      () async {
        final book = TextBook(
          title: 'ספר',
          heCategories: 'ערך-קיים',
          categoryId: 999,
          fileType: 'txt',
        );

        final result = await enrichHeCategories(book);

        // heCategories קיים — לא אמור להיות שינוי
        expect(result.heCategories, isNull);
        // ה-book לא נגע (אין מוטציה)
        expect(book.heCategories, 'ערך-קיים');
      },
    );

    test('heCategories וגם author חסרים: שניהם מוחזרים מה-DB', () async {
      final rootId = await seforimRepo.insertCategory(
        const migration_models.Category(title: 'אחרונים'),
      );
      final sourceId = await seforimRepo.insertSource('test-src', -1);
      await seforimRepo.insertBook(
        migration_models.Book(
          categoryId: rootId,
          sourceId: sourceId,
          title: 'פרי מגדים',
          fileType: 'txt',
          authors: const [Author(name: 'יוסף בן מאיר תאומים')],
        ),
      );

      final book = TextBook(
        title: 'פרי מגדים',
        categoryId: rootId,
        fileType: 'txt',
      );

      final result = await enrichHeCategories(book);

      expect(result.heCategories, 'אחרונים');
      expect(result.author, 'יוסף בן מאיר תאומים');
    });

    test('heCategories קיים אך author חסר: המחבר מושלם מה-DB', () async {
      final rootId = await seforimRepo.insertCategory(
        const migration_models.Category(title: 'אחרונים'),
      );
      final sourceId = await seforimRepo.insertSource('test-src', -1);
      await seforimRepo.insertBook(
        migration_models.Book(
          categoryId: rootId,
          sourceId: sourceId,
          title: 'פרי מגדים',
          fileType: 'txt',
          authors: const [Author(name: 'יוסף בן מאיר תאומים')],
        ),
      );

      final book = TextBook(
        title: 'פרי מגדים',
        categoryId: rootId,
        fileType: 'txt',
        heCategories: 'אחרונים',
      );

      final result = await enrichHeCategories(book);

      // heCategories לא נדרס — מושלמים רק המחבר וה-id.
      expect(result.heCategories, isNull);
      expect(result.author, 'יוסף בן מאיר תאומים');
      expect(result.resolvedId, isNotNull);
    });

    test('מחזיר heCategories מהיררכיית קטגוריות ב-seforim.db', () async {
      final rootId = await seforimRepo.insertCategory(
        const migration_models.Category(title: 'תנ"ך'),
      );
      final torahId = await seforimRepo.insertCategory(
        migration_models.Category(title: 'תורה', parentId: rootId, level: 1),
      );
      final sourceId = await seforimRepo.insertSource('test-src', -1);
      await seforimRepo.insertBook(
        migration_models.Book(
          categoryId: torahId,
          sourceId: sourceId,
          title: 'בראשית',
          fileType: 'txt',
        ),
      );

      final book = TextBook(
        title: 'בראשית',
        categoryId: torahId,
        fileType: 'txt',
      );

      final result = await enrichHeCategories(book);

      expect(result.heCategories, 'תנ"ך, תורה');
      // אין מוטציה על ה-book
      expect(book.heCategories, isNull);
    });

    test('book.isUserBook=true: מחזיר heCategories מ-user_books.db', () async {
      final userBooksRepo = await UserBooksDatabaseHolder.instance.repository;
      final personalId = await userBooksRepo.insertCategory(
        const migration_models.Category(title: 'ספרים אישיים'),
      );
      final folderId = await userBooksRepo.insertCategory(
        migration_models.Category(
          title: 'תיקיית עבודה',
          parentId: personalId,
          level: 1,
        ),
      );
      final sourceId = await userBooksRepo.insertSource('Personal::test', -1);
      await userBooksRepo.insertBook(
        migration_models.Book(
          categoryId: folderId,
          sourceId: sourceId,
          title: 'ספר אישי',
          fileType: 'txt',
        ),
      );

      final book = TextBook(
        title: 'ספר אישי',
        categoryId: folderId,
        fileType: 'txt',
        isUserBook: true,
      );

      final result = await enrichHeCategories(book);

      expect(result.heCategories, 'ספרים אישיים, תיקיית עבודה');
      expect(book.heCategories, isNull);
    });

    test(
      'book.isUserBook=true אבל user_books.db לא קיים: לא קורס, מחזיר ריק',
      () async {
        expect(
          await File(await AppPaths.resolveUserBooksDbPath()).exists(),
          isFalse,
        );

        final book = TextBook(
          title: 'לא קיים',
          categoryId: 999,
          fileType: 'txt',
          isUserBook: true,
        );

        final result = await enrichHeCategories(book);

        expect(
          result.heCategories,
          isNull,
          reason: 'בלי DB ובלי metadata.json — heCategories נשאר null',
        );
        expect(book.heCategories, isNull);
      },
    );

    test(
      'categoryPath עם פסיקים שמתחיל ב-"ספרים אישיים" מנתב ל-user_books',
      () async {
        final seforimCat = await seforimRepo.insertCategory(
          const migration_models.Category(title: 'בעולם הרשמי'),
        );
        final seforimSrc = await seforimRepo.insertSource('seforim', -1);
        await seforimRepo.insertBook(
          migration_models.Book(
            categoryId: seforimCat,
            sourceId: seforimSrc,
            title: 'ספר משותף',
            fileType: 'txt',
          ),
        );

        final userBooksRepo = await UserBooksDatabaseHolder.instance.repository;
        final personalId = await userBooksRepo.insertCategory(
          const migration_models.Category(title: 'ספרים אישיים'),
        );
        final folderId = await userBooksRepo.insertCategory(
          migration_models.Category(
            title: 'תיקיית בית',
            parentId: personalId,
            level: 1,
          ),
        );
        final userSrc = await userBooksRepo.insertSource('Personal::abc', -1);
        await userBooksRepo.insertBook(
          migration_models.Book(
            categoryId: folderId,
            sourceId: userSrc,
            title: 'ספר משותף',
            fileType: 'txt',
          ),
        );

        final book = TextBook(
          title: 'ספר משותף',
          fileType: 'txt',
          categoryPath: 'ספרים אישיים, תיקיית בית',
        );

        final result = await enrichHeCategories(book);

        expect(
          result.heCategories,
          'ספרים אישיים, תיקיית בית',
          reason: 'categoryPath מסומן כספרים אישיים → preferUserBooks',
        );
        expect(book.heCategories, isNull);
      },
    );
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
