import 'dart:io';

import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/migration/models/book.dart';
import 'package:otzaria/migration/models/category.dart';
import 'package:otzaria/migration/database/daos/database.dart';
import 'package:otzaria/migration/database/repository/seforim_repository.dart';
import 'package:otzaria/migration/sync/file_sync_service.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/settings/services/custom_folders/custom_folder.dart';
import 'package:path/path.dart' as path;

String _sourceNameForFolder(String folderPath) {
  final normalized = path.normalize(folderPath);
  final key = Platform.isWindows ? normalized.toLowerCase() : normalized;
  return 'Personal::$key';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late MyDatabase database;
  late SeforimRepository repository;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp(
      'otzaria-file-sync-prune-test-',
    );
    await Settings.init(cacheProvider: _MemoryCacheProvider());
    // מאפסים את הסינגלטון של FileSyncService כדי שלא יחזיק repository
    // מ-tempDir של טסט קודם (שכבר נסגר).
    FileSyncService.resetSingletonForTesting();
    database = MyDatabase.withPath(path.join(tempDir.path, 'test.db'));
    repository = SeforimRepository(database);
    await repository.ensureInitialized();
  });

  tearDown(() async {
    database.close();
    FileSyncService.resetSingletonForTesting();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test(
      'syncFiles לא מוחק תיקייה מותאמת חדשה עם ספר ברמת השורש',
      () async {
    final libraryPath = path.join(tempDir.path, 'library');
    final customFolderPath = path.join(tempDir.path, 'היברו');
    await Directory(libraryPath).create(recursive: true);
    await Directory(path.join(libraryPath, 'אוצריא')).create(recursive: true);
    await Directory(customFolderPath).create(recursive: true);
    await File(path.join(customFolderPath, 'ספר חדש.txt')).writeAsString('תוכן');

    await Settings.setValue<String>(
      SettingsRepository.keyLibraryPath,
      libraryPath,
    );
    await Settings.setValue<String>(
      SettingsRepository.keyCustomFolders,
      CustomFoldersManager.saveFolders([
        CustomFolder(
          path: customFolderPath,
          addToDatabase: true,
          addedAt: DateTime(2026, 4, 13),
        ),
      ]),
    );

    final service = await FileSyncService.getInstance(repository);
    final result = await service!.syncFiles();

    final personalCategory = (await repository.getRootCategories())
        .where((category) => category.title == 'ספרים אישיים')
        .firstOrNull;
    expect(personalCategory, isNotNull);

    final customCategory = await repository.getCategoryByTitleAndParent(
      'היברו',
      personalCategory!.id,
    );
    expect(customCategory, isNotNull);

    final books = await repository.getBooksByCategory(customCategory!.id);
    expect(books.map((book) => book.title), ['ספר חדש']);
    expect(result.errors, isEmpty);
  });

  test(
      'pruneRemovedCustomFoldersFromDatabase משאיר תיקייה פעילה בלי filePath ומוחק ישנה',
      () async {
    final activeFolderPath = path.join(tempDir.path, 'active-folder');
    final removedFolderPath = path.join(tempDir.path, 'removed-folder');
    final personalCategoryId = await repository.insertCategory(
      const Category(title: 'ספרים אישיים'),
    );
    final activeCategoryId = await repository.insertCategory(
      Category(
        title: 'active-folder',
        parentId: personalCategoryId,
        level: 1,
      ),
    );
    final staleCategoryId = await repository.insertCategory(
      Category(
        title: 'removed-folder',
        parentId: personalCategoryId,
        level: 1,
      ),
    );
    final activeSourceId = await repository.insertSource(
        _sourceNameForFolder(activeFolderPath), -1);
    final staleSourceId = await repository.insertSource(
        _sourceNameForFolder(removedFolderPath), -1);

    await repository.insertBook(
      Book(
        id: 0,
        categoryId: activeCategoryId,
        sourceId: activeSourceId,
        title: 'ספר פעיל',
        isPersonal: true,
        fileType: 'txt',
        filePath: null,
      ),
    );
    await repository.insertBook(
      Book(
        id: 0,
        categoryId: staleCategoryId,
        sourceId: staleSourceId,
        title: 'ספר ישן',
        isPersonal: true,
        fileType: 'txt',
        filePath: null,
      ),
    );
    await repository.rebuildCategoryClosure();

    final service = await FileSyncService.getInstance(repository);

    await service!.pruneRemovedCustomFoldersFromDatabase([
      CustomFolder(
        path: activeFolderPath,
        addToDatabase: true,
        addedAt: DateTime(2026, 4, 13),
      ),
    ]);

    final personalChildren =
        await repository.getCategoryChildren(personalCategoryId);
    final remainingTitles =
        personalChildren.map((category) => category.title).toList();

    expect(remainingTitles, ['active-folder']);
    expect(await repository.getCategory(staleCategoryId), isNull);
    expect(await repository.getCategory(activeCategoryId), isNotNull);
  });

  // Regression test for bug introduced in commit 72ca3b4aa:
  // When a folder was added via UI (custom_folders_tile.dart → _scanAndAddExternalBooks),
  // insertCategory was called without rebuildCategoryClosure.
  // Then RefreshLibrary → _pruneRemovedCustomFoldersIfNeeded ran immediately,
  // and _categoryBelongsToAnyConfiguredFolder returned false (empty closure table),
  // so the newly-added folder was deleted right away.
  // Fix: refreshSourcesAndPruneRemovedCustomFolders now calls rebuildCategoryClosure
  // before pruneRemovedCustomFoldersFromDatabase.
  test(
      'regression: refreshSourcesAndPruneRemovedCustomFolders לא מוחק תיקייה שנוספה דרך UI ללא rebuildCategoryClosure',
      () async {
    final activeFolderPath = path.join(tempDir.path, 'my-books');

    // מדמה את _getOrCreateCategoryInDb ב-database_library_provider.dart:
    // מוסיף קטגוריות עם insertCategory בלי לקרוא ל-rebuildCategoryClosure.
    final personalCategoryId = await repository.insertCategory(
      const Category(title: 'ספרים אישיים'),
    );
    final newCategoryId = await repository.insertCategory(
      Category(
        title: 'my-books',
        parentId: personalCategoryId,
        level: 1,
      ),
    );
    final sourceId = await repository.insertSource(
      _sourceNameForFolder(activeFolderPath),
      -1,
    );
    await repository.insertBook(
      Book(
        id: 0,
        categoryId: newCategoryId,
        sourceId: sourceId,
        title: 'ספר חדש',
        isPersonal: true,
        fileType: 'txt',
        filePath: path.join(activeFolderPath, 'ספר חדש.txt'),
      ),
    );

    // בכוונה לא קוראים ל-rebuildCategoryClosure לפני refreshSources,
    // בדיוק כמו שה-UI עושה: הוסיף תיקייה ואז מיד שלח RefreshLibrary.
    // לפני התיקון, prune היה מוחק את הקטגוריה כי category_closure ריק.

    final service = await FileSyncService.getInstance(repository);

    await service!.refreshSourcesAndPruneRemovedCustomFolders([
      CustomFolder(
        path: activeFolderPath,
        addToDatabase: true,
        addedAt: DateTime(2026, 4, 17),
      ),
    ]);

    expect(
      await repository.getCategory(newCategoryId),
      isNotNull,
      reason:
          'תיקייה שנוספה דרך UI לא צריכה להימחק על ידי prune כי category_closure לא עודכן עדיין',
    );
    final books = await repository.getBooksByCategory(newCategoryId);
    expect(
      books,
      isNotEmpty,
      reason: 'ספרים בתיקייה שנוספה לא צריכים להימחק',
    );
  });

  test(
      'pruneRemovedCustomFoldersFromDatabase מוחק קטגוריה עמומה בלי הוכחת source או path',
      () async {
    final personalCategoryId = await repository.insertCategory(
      const Category(title: 'ספרים אישיים'),
    );
    final ambiguousCategoryId = await repository.insertCategory(
      Category(
        title: 'shared',
        parentId: personalCategoryId,
        level: 1,
      ),
    );
    final legacySourceId = await repository.insertSource('Personal', -1);

    await repository.insertBook(
      Book(
        id: 0,
        categoryId: ambiguousCategoryId,
        sourceId: legacySourceId,
        title: 'ספר עמום',
        isPersonal: true,
        fileType: 'txt',
        filePath: null,
      ),
    );
    await repository.rebuildCategoryClosure();

    final service = await FileSyncService.getInstance(repository);

    await service!.pruneRemovedCustomFoldersFromDatabase([
      CustomFolder(
        path: path.join(tempDir.path, 'alpha', 'shared'),
        addToDatabase: true,
        addedAt: DateTime(2026, 4, 13),
      ),
      CustomFolder(
        path: path.join(tempDir.path, 'beta', 'shared'),
        addToDatabase: true,
        addedAt: DateTime(2026, 4, 13),
      ),
    ]);

    expect(await repository.getCategory(ambiguousCategoryId), isNull);
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
