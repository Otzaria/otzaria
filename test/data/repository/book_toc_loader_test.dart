import 'dart:io';

import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/data/constants/database_constants.dart';
import 'package:otzaria/data/data_providers/database_library_provider.dart';
import 'package:otzaria/data/data_providers/user_books_database_holder.dart';
import 'package:otzaria/data/repository/book_toc_loader.dart';
import 'package:otzaria/migration/database/daos/database.dart';
import 'package:otzaria/migration/database/repository/seforim_repository.dart';
import 'package:otzaria/migration/models/book.dart' as migration_models;
import 'package:otzaria/migration/models/category.dart' as migration_models;
import 'package:otzaria/migration/models/toc_entry.dart' as migration_models;
import 'package:otzaria/models/books.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:path/path.dart' as path;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await Settings.init(cacheProvider: _MemoryCacheProvider());
  });

  test(
    'loadBookTocFallback שולף את תוכן העניינים מה-DB כשספק הספרייה אינו מחזיר '
    'אותו (issue #1296)',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'otzaria_toc_fallback',
      );
      final libraryPath = path.join(tempDir.path, 'library');
      final dataRootPath = path.join(tempDir.path, 'data_root');
      final database = MyDatabase.withPath(
        path.join(libraryPath, DatabaseConstants.databaseFileName),
      );
      final provider = DatabaseLibraryProvider.instance;
      final previousLibraryPath = Settings.getValue<String>(
        SettingsRepository.keyLibraryPath,
      );
      final previousDataRootPath = AppPaths.cachedDataRootPath;

      // addTearDown ב-LIFO: קודם ייסגרו ה-DBs ורק אז תימחק התיקייה הזמנית.
      addTearDown(() => tempDir.delete(recursive: true));
      addTearDown(() => database.close());
      addTearDown(() => provider.clearCache());
      addTearDown(() => provider.sqliteProvider.dispose());
      addTearDown(() => UserBooksDatabaseHolder.instance.close());
      addTearDown(
        () => AppPaths.debugOverrideDataRootPath(previousDataRootPath),
      );
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
      await SeforimRepository(database).ensureInitialized();
      await Settings.setValue<String>(
        SettingsRepository.keyLibraryPath,
        libraryPath,
      );

      final userRepository = await UserBooksDatabaseHolder.instance.repository;
      final sourceId = await userRepository.insertSource('user-test', -20);
      final categoryId = await userRepository.insertCategory(
        const migration_models.Category(
          title: 'ספרים אישיים',
          parentId: null,
          level: 0,
          orderIndex: 1,
        ),
      );
      final bookId = await userRepository.insertBook(
        migration_models.Book(
          categoryId: categoryId,
          sourceId: sourceId,
          title: 'ספר עם תוכן עניינים',
          fileType: 'txt',
        ),
      );
      final parentTocId = await userRepository.insertTocEntry(
        migration_models.TocEntry(
          bookId: bookId,
          text: 'שער ראשון',
          level: 1,
          lineIndex: 0,
        ),
      );
      await userRepository.insertTocEntry(
        migration_models.TocEntry(
          bookId: bookId,
          parentId: parentTocId,
          text: 'פרק א',
          level: 2,
          lineIndex: 5,
        ),
      );

      final book = TextBook(
        title: 'ספר עם תוכן עניינים',
        categoryId: categoryId,
        fileType: 'txt',
        isUserBook: true,
      );

      final toc = await loadBookTocFallback(book);

      expect(toc.map((entry) => entry.text), ['שער ראשון']);
      expect(toc.single.children.map((entry) => entry.text), ['פרק א']);
      expect(toc.single.children.single.index, 5);
    },
  );

  test('loadBookTocFallback מחזיר רשימה ריקה כשהספר אינו מוכר', () async {
    final tempDir = await Directory.systemTemp.createTemp('otzaria_toc_empty');
    final previousDataRootPath = AppPaths.cachedDataRootPath;
    addTearDown(() => tempDir.delete(recursive: true));
    addTearDown(() => UserBooksDatabaseHolder.instance.close());
    addTearDown(() => AppPaths.debugOverrideDataRootPath(previousDataRootPath));

    await UserBooksDatabaseHolder.instance.close();
    AppPaths.debugOverrideDataRootPath(path.join(tempDir.path, 'data_root'));

    final book = TextBook(title: 'ספר שאינו קיים', fileType: 'txt');

    expect(await loadBookTocFallback(book), isEmpty);
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
