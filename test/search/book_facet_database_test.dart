import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/data/constants/database_constants.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:otzaria/data/data_providers/user_books_database_holder.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/migration/database/daos/database.dart';
import 'package:otzaria/migration/database/repository/seforim_repository.dart';
import 'package:otzaria/migration/models/book.dart' as migration_models;
import 'package:otzaria/migration/models/category.dart' as migration_models;
import 'package:otzaria/migration/models/topic.dart' as migration_models;
import 'package:otzaria/models/books.dart';
import 'package:otzaria/search/book_facet.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:path/path.dart' as path;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BookFacet.resolveTopics — DB fallback', () {
    late Directory tempDir;
    late String libraryPath;
    late String dataRootPath;
    late MyDatabase seforimDb;
    late SeforimRepository seforimRepo;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('otzaria-book-facet-');
      libraryPath = path.join(tempDir.path, 'library');
      dataRootPath = path.join(tempDir.path, 'data_root');
      await Directory(libraryPath).create(recursive: true);

      await Settings.init(cacheProvider: _MemoryCacheProvider());
      AppPaths.debugOverrideDataRootPath(dataRootPath);
      await UserBooksDatabaseHolder.instance.close();

      await Settings.setValue<String>(
          SettingsRepository.keyLibraryPath, libraryPath);
      await Settings.setValue<String>(
          SettingsRepository.keyLibraryFolderName, '');
      await Settings.setValue<String>(
          SettingsRepository.keyDbEffectivePath, '');

      final dbPath = path.join(libraryPath, DatabaseConstants.databaseFileName);
      seforimDb = MyDatabase.withPath(dbPath);
      seforimRepo = SeforimRepository(seforimDb);
      await seforimRepo.ensureInitialized();
      await SqliteDataProvider.instance.dispose();
      await SqliteDataProvider.instance.initialize();

      // Library ריקה — מאלץ נפילה ל-DB
      DataRepository.instance.library = Future.value(Library(categories: []));
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

    test('initialTopics לא ריק מוחזר ישירות בלי לחפש', () async {
      final topics = await BookFacet.resolveTopics(
        title: 'משנה',
        initialTopics: 'הלכה, מועד',
        type: TextBook,
      );

      expect(topics, 'הלכה, מועד');
    });

    test('categoryPath הוא הפלט כשמסופק (וכפיל את הנפילה ל-DB)', () async {
      // הקוד מנרמל categoryPath ומחזיר אותו כ-topics לפני שניגש ל-DB.
      // בודקים שאין שגיאה ושהערך הצפוי חוזר.
      final topics = await BookFacet.resolveTopics(
        title: 'משהו',
        initialTopics: '',
        type: TextBook,
        categoryPath: '/תנ"ך/תורה',
      );

      // ה-normalization של _categoryPathToTopics: '/תנ"ך/תורה' → 'תנ"ך, תורה'
      expect(topics, 'תנ"ך, תורה');
    });

    test('topics מה-DB חוזרים כשאין categoryPath', () async {
      // יוצרים ספר ב-DB עם topic
      final catId = await seforimRepo.insertCategory(
        const migration_models.Category(title: 'הלכה'),
      );
      final sourceId = await seforimRepo.insertSource('test', -1);
      await seforimRepo.insertBook(
        migration_models.Book(
          categoryId: catId,
          sourceId: sourceId,
          title: 'ספר טסט',
          fileType: 'txt',
          topics: const [migration_models.Topic(name: 'נושא א')],
        ),
      );

      final topics = await BookFacet.resolveTopics(
        title: 'ספר טסט',
        initialTopics: '',
        type: TextBook,
      );

      expect(topics, 'נושא א');
    });

    test(
        'ללא topics ב-DB → נופל לבניית נתיב הקטגוריה מתוך seforim',
        () async {
      // יוצרים היררכיית קטגוריות ועליה ספר בלי topics — הקוד צריך לבנות
      // categoryPath היררכי.
      final rootId = await seforimRepo.insertCategory(
        const migration_models.Category(title: 'תנ"ך'),
      );
      final torahId = await seforimRepo.insertCategory(
        migration_models.Category(
            title: 'תורה', parentId: rootId, level: 1),
      );
      final sourceId = await seforimRepo.insertSource('test', -1);
      await seforimRepo.insertBook(
        migration_models.Book(
          categoryId: torahId,
          sourceId: sourceId,
          title: 'בראשית',
          fileType: 'txt',
        ),
      );

      final topics = await BookFacet.resolveTopics(
        title: 'בראשית',
        initialTopics: '',
        type: TextBook,
      );

      expect(topics, 'תנ"ך, תורה');
    });

    test(
        'categoryPath של "ספרים אישיים" → preferUserBooks → topics מ-user_books',
        () async {
      final userBooksRepo = await UserBooksDatabaseHolder.instance.repository;
      final personalId = await userBooksRepo.insertCategory(
        const migration_models.Category(title: 'ספרים אישיים'),
      );
      final folderId = await userBooksRepo.insertCategory(
        migration_models.Category(
            title: 'עבודה', parentId: personalId, level: 1),
      );
      final sourceId =
          await userBooksRepo.insertSource('Personal::test', -1);
      await userBooksRepo.insertBook(
        migration_models.Book(
          categoryId: folderId,
          sourceId: sourceId,
          title: 'ספר אישי',
          fileType: 'txt',
          topics: const [migration_models.Topic(name: 'מנהל')],
        ),
      );

      // ⚠️ resolveTopics מקצר אם יש categoryPath — _normalizeCategoryPath
      // ממיר אותו ל-topics ומחזיר ישירות. כדי שהמסלול ל-DB יקרה לא נשלח
      // categoryPath, אלא רק נשען על ה-fallback.
      final topics = await BookFacet.resolveTopics(
        title: 'ספר אישי',
        initialTopics: '',
        type: TextBook,
      );

      // ה-resolver יחפש קודם ב-seforim (לא קיים), ואז ב-user_books וייתפס שם.
      expect(topics, 'מנהל');
    });

    test('ספר שלא קיים בשום DB מחזיר מחרוזת ריקה', () async {
      final topics = await BookFacet.resolveTopics(
        title: 'לא קיים בעולם',
        initialTopics: '',
        type: TextBook,
      );

      expect(topics, '');
    });
  });

  group('BookFacet — helpers טהורים', () {
    test('topicsToPath מחזיר נתיב מחולק ב-/', () {
      expect(BookFacet.topicsToPath('הלכה, מועד'), '/הלכה/מועד');
    });

    test('topicsToPath על מחרוזת ריקה מחזיר ריק', () {
      expect(BookFacet.topicsToPath(''), '');
      expect(BookFacet.topicsToPath('   '), '');
    });

    test('resolveFacetCategoryPath: מעדיף categoryPath על topics', () {
      final result = BookFacet.resolveFacetCategoryPath(
        categoryPath: '/הלכה/יורה דעה',
        topics: 'אגדה',
      );
      expect(result, '/הלכה/יורה דעה');
    });

    test('resolveFacetCategoryPath: נופל ל-topics כש-categoryPath ריק', () {
      final result = BookFacet.resolveFacetCategoryPath(
        categoryPath: '',
        topics: 'הלכה, מועד',
      );
      expect(result, '/הלכה/מועד');
    });

    test('buildFacetPath: כולל bookId כש-bookId זמין', () {
      final result = BookFacet.buildFacetPath(
        title: 'בראשית',
        topics: 'תנ"ך, תורה',
        bookId: 42,
      );
      expect(result, '/תנ"ך/תורה/id:42');
    });

    test('buildFacetPath: כולל externalLibraryId אם קיים', () {
      final result = BookFacet.buildFacetPath(
        title: 'משלי',
        topics: 'תנ"ך, כתובים',
        externalLibraryId: 'Sefaria.Mishlei.1',
      );
      expect(result, '/תנ"ך/כתובים/ext:Sefaria.Mishlei.1');
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
