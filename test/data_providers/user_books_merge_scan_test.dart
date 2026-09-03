// מצב מיזוג ספרים אישיים דרך צינור הסריקה האמיתי (scanAndAddExternalBooksFromFolder),
// בשונה מבדיקות המיזוג ב-database_library_provider_test שמכניסות ל-DB ידנית.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/data/constants/database_constants.dart';
import 'package:otzaria/data/data_providers/database_library_provider.dart';
import 'package:otzaria/data/data_providers/user_books_database_holder.dart';
import 'package:otzaria/migration/models/book.dart' as migration_models;
import 'package:otzaria/migration/models/category.dart' as migration_models;
import 'package:otzaria/migration/database/daos/database.dart';
import 'package:otzaria/migration/database/repository/seforim_repository.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/settings/services/custom_folders/custom_folder.dart';
import 'package:path/path.dart' as path;

class _MemoryCacheProvider extends CacheProvider {
  final Map<String, Object?> _values = {};

  @override
  Future<void> init() async {}

  @override
  bool containsKey(String key) => _values.containsKey(key);

  @override
  Set getKeys() => _values.keys.toSet();

  @override
  T? getValue<T>(String key, {T? defaultValue}) =>
      _values.containsKey(key) ? _values[key] as T? : defaultValue;

  @override
  bool? getBool(String key, {bool? defaultValue}) =>
      getValue<bool>(key, defaultValue: defaultValue);

  @override
  double? getDouble(String key, {double? defaultValue}) =>
      getValue<double>(key, defaultValue: defaultValue);

  @override
  int? getInt(String key, {int? defaultValue}) =>
      getValue<int>(key, defaultValue: defaultValue);

  @override
  String? getString(String key, {String? defaultValue}) =>
      getValue<String>(key, defaultValue: defaultValue);

  @override
  Future<void> remove(String key) async => _values.remove(key);

  @override
  Future<void> removeAll() async => _values.clear();

  @override
  Future<void> setBool(String key, bool? value) async => _values[key] = value;

  @override
  Future<void> setDouble(String key, double? value) async =>
      _values[key] = value;

  @override
  Future<void> setInt(String key, int? value) async => _values[key] = value;

  @override
  Future<void> setObject<T>(String key, T? value) async => _values[key] = value;

  @override
  Future<void> setString(String key, String? value) async =>
      _values[key] = value;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await Settings.init(cacheProvider: _MemoryCacheProvider());
  });

  test(
    'סריקת תיקייה אמיתית במצב מיזוג: תיקייה ללא מקבילה מוצגת בשורש',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'otzaria_user_books_merge_scan',
      );
      final libraryPath = path.join(tempDir.path, 'library');
      final dataRootPath = path.join(tempDir.path, 'data_root');
      final dbPath = path.join(libraryPath, DatabaseConstants.databaseFileName);
      final database = MyDatabase.withPath(dbPath);
      final repository = SeforimRepository(database);
      final provider = DatabaseLibraryProvider.instance;
      final previousDataRootPath = AppPaths.cachedDataRootPath;

      addTearDown(() => tempDir.delete(recursive: true));
      addTearDown(() => database.close());
      addTearDown(() => provider.clearCache());
      addTearDown(() => provider.sqliteProvider.dispose());
      addTearDown(
        () => AppPaths.debugOverrideDataRootPath(previousDataRootPath),
      );
      addTearDown(() => UserBooksDatabaseHolder.instance.close());
      addTearDown(() async {
        await Settings.setValue<bool>(
          SettingsRepository.keyMergeUserBooksIntoLibrary,
          false,
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
      await Settings.setValue<bool>(
        SettingsRepository.keyMergeUserBooksIntoLibrary,
        true,
      );

      // seforim.db: קטגוריה רשמית אחת עם ספר, כדי שיהיה עץ ראשי.
      final sourceId = await repository.insertSource('local-test', -10);
      final hasidutCategoryId = await repository.insertCategory(
        const migration_models.Category(
          title: 'חסידות',
          parentId: null,
          level: 0,
          orderIndex: 1,
        ),
      );
      await repository.insertBook(
        migration_models.Book(
          id: 1,
          categoryId: hasidutCategoryId,
          sourceId: sourceId,
          title: 'ליקוטי מוהר"ן',
          filePath: path.join(tempDir.path, 'main_book.txt'),
          fileType: 'txt',
        ),
      );

      // תיקייה אמיתית על הדיסק: "מסמכים" ובה תת-תיקייה "שיעורים" ללא מקבילה.
      final pickedFolder = Directory(path.join(tempDir.path, 'מסמכים'));
      final unmatchedDir = Directory(path.join(pickedFolder.path, 'שיעורים'));
      await unmatchedDir.create(recursive: true);
      await File(
        path.join(unmatchedDir.path, 'שיעור שבועי.txt'),
      ).writeAsString('שורה ראשונה\nשורה שניה\n');
      await File(
        path.join(pickedFolder.path, 'מכתב אישי.txt'),
      ).writeAsString('תוכן המכתב\n');

      final userBooksRepository =
          await UserBooksDatabaseHolder.instance.repository;

      // הסריקה האמיתית — כמו הוספת תיקייה מותאמת אישית בהגדרות.
      final scanResult = await provider.scanAndAddExternalBooksFromFolder(
        pickedFolder.path,
        'מסמכים',
        userBooksRepository,
      );
      expect(scanResult.fatalError, isNull);
      expect(
        scanResult.addedBooks,
        2,
        reason: 'שני קבצי txt אמורים להיקלט בסריקה',
      );

      await provider.initialize();
      final library = await provider.buildLibraryCatalog({}, libraryPath);

      // התיקייה ללא מקבילה אמורה להופיע בשורש עם הספר שבה.
      final unmatched = library.subCategories
          .where((c) => c.title == 'שיעורים')
          .toList();
      expect(
        unmatched,
        hasLength(1),
        reason: 'תיקייה ללא מקבילה אמורה להופיע בשורש הספרייה',
      );
      expect(
        unmatched.single.books.map((b) => b.title),
        contains('שיעור שבועי'),
      );

      // הקובץ שישירות בתיקייה הנבחרת — תחת "ספרים אישיים", לא בשורש.
      expect(library.books.map((b) => b.title), isNot(contains('מכתב אישי')));
      final personal = library.subCategories
          .where((c) => c.title == 'ספרים אישיים')
          .toList();
      expect(personal, hasLength(1));
      expect(personal.single.books.map((b) => b.title), contains('מכתב אישי'));
    },
  );

  test(
    'חריגה פר-תיקייה: מיזוג גלובלי דולק, אך התיקייה מוגדרת "לא ממוזגת"',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'otzaria_user_books_merge_override',
      );
      final libraryPath = path.join(tempDir.path, 'library');
      final dataRootPath = path.join(tempDir.path, 'data_root');
      final dbPath = path.join(libraryPath, DatabaseConstants.databaseFileName);
      final database = MyDatabase.withPath(dbPath);
      final repository = SeforimRepository(database);
      final provider = DatabaseLibraryProvider.instance;
      final previousDataRootPath = AppPaths.cachedDataRootPath;

      addTearDown(() => tempDir.delete(recursive: true));
      addTearDown(() => database.close());
      addTearDown(() => provider.clearCache());
      addTearDown(() => provider.sqliteProvider.dispose());
      addTearDown(
        () => AppPaths.debugOverrideDataRootPath(previousDataRootPath),
      );
      addTearDown(() => UserBooksDatabaseHolder.instance.close());
      addTearDown(() async {
        await Settings.setValue<bool>(
          SettingsRepository.keyMergeUserBooksIntoLibrary,
          false,
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
      await Settings.setValue<bool>(
        SettingsRepository.keyMergeUserBooksIntoLibrary,
        true,
      );

      final sourceId = await repository.insertSource('local-test', -10);
      final hasidutCategoryId = await repository.insertCategory(
        const migration_models.Category(
          title: 'חסידות',
          parentId: null,
          level: 0,
          orderIndex: 1,
        ),
      );
      await repository.insertBook(
        migration_models.Book(
          id: 1,
          categoryId: hasidutCategoryId,
          sourceId: sourceId,
          title: 'ליקוטי מוהר"ן',
          filePath: path.join(tempDir.path, 'main_book.txt'),
          fileType: 'txt',
        ),
      );

      final pickedFolder = Directory(path.join(tempDir.path, 'מסמכים'));
      final unmatchedDir = Directory(path.join(pickedFolder.path, 'שיעורים'));
      await unmatchedDir.create(recursive: true);
      await File(
        path.join(unmatchedDir.path, 'שיעור שבועי.txt'),
      ).writeAsString('שורה ראשונה\nשורה שניה\n');

      // החריגה שהמשתמש קבע לתיקייה זו — גוברת על המתג הגלובלי.
      await Settings.setValue<String>(
        SettingsRepository.keyCustomFolders,
        CustomFoldersManager.saveFolders([
          CustomFolder(
            path: pickedFolder.path,
            mergeIntoLibrary: false,
            addedAt: DateTime(2026, 1, 1),
          ),
        ]),
      );

      final userBooksRepository =
          await UserBooksDatabaseHolder.instance.repository;
      final scanResult = await provider.scanAndAddExternalBooksFromFolder(
        pickedFolder.path,
        'מסמכים',
        userBooksRepository,
      );
      expect(scanResult.fatalError, isNull);

      await provider.initialize();
      final library = await provider.buildLibraryCatalog({}, libraryPath);

      expect(
        library.subCategories.where((c) => c.title == 'שיעורים'),
        isEmpty,
        reason: 'התיקייה החריגה לא אמורה להתמזג לשורש',
      );
      final personal = library.subCategories
          .where((c) => c.title == 'ספרים אישיים')
          .toList();
      expect(personal, hasLength(1));
      final picked = personal.single.subCategories
          .where((c) => c.title == 'מסמכים')
          .toList();
      expect(picked, hasLength(1));
      expect(
        picked.single.subCategories.map((c) => c.title),
        contains('שיעורים'),
      );
    },
  );

  test(
    'תיקיות בעלות אותו שם עם מצבי מיזוג חלוקים חוזרות לברירת המחדל',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'otzaria_user_books_merge_same_name',
      );
      final libraryPath = path.join(tempDir.path, 'library');
      final dataRootPath = path.join(tempDir.path, 'data_root');
      final dbPath = path.join(libraryPath, DatabaseConstants.databaseFileName);
      final database = MyDatabase.withPath(dbPath);
      final repository = SeforimRepository(database);
      final provider = DatabaseLibraryProvider.instance;
      final previousDataRootPath = AppPaths.cachedDataRootPath;

      addTearDown(() => tempDir.delete(recursive: true));
      addTearDown(() => database.close());
      addTearDown(() => provider.clearCache());
      addTearDown(() => provider.sqliteProvider.dispose());
      addTearDown(
        () => AppPaths.debugOverrideDataRootPath(previousDataRootPath),
      );
      addTearDown(() => UserBooksDatabaseHolder.instance.close());
      addTearDown(() async {
        await Settings.setValue<bool>(
          SettingsRepository.keyMergeUserBooksIntoLibrary,
          false,
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
      await Settings.setValue<bool>(
        SettingsRepository.keyMergeUserBooksIntoLibrary,
        true,
      );

      final pickedFolder = Directory(
        path.join(tempDir.path, 'alpha', 'shared'),
      );
      final unmatchedDir = Directory(path.join(pickedFolder.path, 'שיעורים'));
      await unmatchedDir.create(recursive: true);
      await File(
        path.join(unmatchedDir.path, 'שיעור שבועי.txt'),
      ).writeAsString('שורה ראשונה\nשורה שניה\n');

      await Settings.setValue<String>(
        SettingsRepository.keyCustomFolders,
        CustomFoldersManager.saveFolders([
          CustomFolder(
            path: pickedFolder.path,
            mergeIntoLibrary: false,
            addedAt: DateTime(2026, 1, 1),
          ),
          CustomFolder(
            path: path.join(tempDir.path, 'beta', 'shared'),
            addedAt: DateTime(2026, 1, 2),
          ),
        ]),
      );

      final userBooksRepository =
          await UserBooksDatabaseHolder.instance.repository;
      final scanResult = await provider.scanAndAddExternalBooksFromFolder(
        pickedFolder.path,
        'shared',
        userBooksRepository,
      );
      expect(scanResult.fatalError, isNull);

      await provider.initialize();
      final library = await provider.buildLibraryCatalog({}, libraryPath);

      expect(library.subCategories.map((c) => c.title), contains('שיעורים'));
      expect(
        library.subCategories.where((c) => c.title == 'ספרים אישיים'),
        isEmpty,
      );
    },
  );
}
