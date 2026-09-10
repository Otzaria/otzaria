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
import 'package:path/path.dart' as path;

/// תוצאת הרצת תרחיש: הטקסט וה-TOC שהוחזרו לספר הרשמי.
typedef _Outcome = ({String? text, List<dynamic>? toc});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// בונה סביבה עם seforim.db + user_books.db ומחזיר את התוצאה עבור
  /// הספר הרשמי "דברים".
  ///
  /// [seforimPaddingCategories] קובע כמה קטגוריות דמה יוקצו לפני "תורה"
  /// ב-seforim.db — וכך האם ה-id של "תורה" מתנגש עם id של קטגוריה
  /// ב-user_books.db (שמתחיל תמיד ב-1).
  Future<_Outcome> runScenario({
    required int seforimPaddingCategories,
    required String tempPrefix,
  }) async {
    final tempDir = await Directory.systemTemp.createTemp(tempPrefix);
    final libraryPath = path.join(tempDir.path, 'library');
    final dataRootPath = path.join(tempDir.path, 'data_root');
    final dbPath = path.join(libraryPath, DatabaseConstants.databaseFileName);
    final database = MyDatabase.withPath(dbPath);
    final repository = SeforimRepository(database);
    final provider = DatabaseLibraryProvider.instance;

    final previousLibraryPath = Settings.getValue<String>(
      SettingsRepository.keyLibraryPath,
    );
    final previousFolderName = Settings.getValue<String>(
      SettingsRepository.keyLibraryFolderName,
    );
    final previousEffectiveDbPath = Settings.getValue<String>(
      SettingsRepository.keyDbEffectivePath,
    );
    final previousDataRootPath = AppPaths.cachedDataRootPath;

    // מחיקה best-effort: ווינדוס מחזיקה נעילה על קובצי ה-DB גם אחרי close.
    addTearDown(() async {
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}
    });
    addTearDown(() => database.close());
    addTearDown(() => provider.clearCache());
    addTearDown(() => provider.sqliteProvider.dispose());
    addTearDown(() => AppPaths.debugOverrideDataRootPath(previousDataRootPath));
    addTearDown(() => UserBooksDatabaseHolder.instance.close());
    addTearDown(() async {
      await Settings.setValue<String>(
        SettingsRepository.keyDbEffectivePath,
        previousEffectiveDbPath ?? '',
      );
      await Settings.setValue<String>(
        SettingsRepository.keyLibraryFolderName,
        previousFolderName ?? '',
      );
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
    await Settings.setValue<String>(SettingsRepository.keyDbEffectivePath, '');

    // --- seforim.db: קטגוריות דמה, ואז "תורה" עם הספר "דברים" ---
    final sourceId = await repository.insertSource('local-test', -10);
    for (var i = 0; i < seforimPaddingCategories; i++) {
      await repository.insertCategory(
        migration_models.Category(
          title: 'מילוי $i',
          parentId: null,
          level: 0,
          orderIndex: i,
        ),
      );
    }
    final torahCategoryId = await repository.insertCategory(
      const migration_models.Category(
        title: 'תורה',
        parentId: null,
        level: 0,
        orderIndex: 100,
      ),
    );

    final officialFile = File(path.join(tempDir.path, 'devarim.txt'));
    await officialFile.writeAsString('אלה הדברים\nבעבר הירדן\n');
    await repository.insertBook(
      migration_models.Book(
        categoryId: torahCategoryId,
        sourceId: sourceId,
        title: 'דברים',
        filePath: officialFile.path,
        fileType: 'txt',
      ),
    );

    // --- user_books.db: "ספרים אישיים" (id 1) → "מסמכים" (id 2) ---
    final userRepo = await UserBooksDatabaseHolder.instance.repository;
    final userSourceId = await userRepo.insertSource('user-test', -20);
    final userRootId = await userRepo.insertCategory(
      const migration_models.Category(
        title: 'ספרים אישיים',
        parentId: null,
        level: 0,
        orderIndex: 1,
      ),
    );
    final userFolderId = await userRepo.insertCategory(
      migration_models.Category(
        title: 'מסמכים',
        parentId: userRootId,
        level: 1,
        orderIndex: 1,
      ),
    );
    final personalFile = File(path.join(tempDir.path, 'personal.txt'));
    await personalFile.writeAsString('ספר אישי\n');
    await userRepo.insertBook(
      migration_models.Book(
        categoryId: userFolderId,
        sourceId: userSourceId,
        title: 'ספר אישי',
        filePath: personalFile.path,
        fileType: 'txt',
      ),
    );

    await provider.initialize();
    await provider.buildLibraryCatalog({}, libraryPath);

    // הדפסה עוזרת לאבחון כשה-ids משתנים בין גרסאות סכמה.
    // ignore: avoid_print
    print(
      'תרחיש $tempPrefix: torahCategoryId=$torahCategoryId, '
      'userRootId=$userRootId, userFolderId=$userFolderId',
    );

    final text = await provider.getBookText('דברים', torahCategoryId, 'txt');
    final toc = await provider.getBookToc('דברים', torahCategoryId, 'txt');
    return (text: text, toc: toc);
  }

  group('התנגשות מזהי קטגוריות בין seforim.db ל-user_books.db', () {
    setUp(() async {
      await Settings.init(cacheProvider: _MemoryCacheProvider());
    });

    test(
      'ביקורת: בלי התנגשות ids — הספר הרשמי "דברים" נטען מ-seforim.db',
      () async {
        // "תורה" מקבל id=10, user_books מחזיק רק 1,2 — אין חפיפה.
        final outcome = await runScenario(
          seforimPaddingCategories: 9,
          tempPrefix: 'otzaria_catid_no_collision',
        );

        expect(
          outcome.text,
          isNotNull,
          reason: 'בלי התנגשות, getBookText חייב לקרוא מ-seforim.db',
        );
        expect(outcome.text, contains('אלה הדברים'));
      },
    );

    test(
      'התנגשות: id של קטגוריה רשמית זהה ל-id קטגוריה ב-user_books — '
      'הספר הרשמי עדיין נטען מ-seforim.db (issue #1296)',
      () async {
        // בלי מילוי: "תורה" מקבל id=1, וגם "ספרים אישיים" ב-user_books
        // מקבל id=1 — בדיוק התרחיש של issue #1296.
        final outcome = await runScenario(
          seforimPaddingCategories: 0,
          tempPrefix: 'otzaria_catid_collision',
        );

        expect(
          outcome.text,
          isNotNull,
          reason:
              'מזהה קטגוריה חופף אינו מספיק כדי לנתב ספר שמוכר ל-seforim '
              'למסד האישי',
        );
        expect(outcome.text, contains('אלה הדברים'));
        // המסלול האישי מחזיר null; null-לא = הניתוב חזר ל-seforim.db.
        expect(
          outcome.toc,
          isNotNull,
          reason:
              'תוכן העניינים הוא הקלט של מיפוי טקסט↔PDF — null = "לא נמצא מיקום"',
        );
      },
    );
  });
}

class _MemoryCacheProvider extends CacheProvider {
  final Map<String, dynamic> _storage = {};

  @override
  Future<void> init() async {}

  @override
  bool? getBool(String key, {bool? defaultValue}) =>
      _storage[key] as bool? ?? defaultValue;

  @override
  double? getDouble(String key, {double? defaultValue}) =>
      _storage[key] as double? ?? defaultValue;

  @override
  int? getInt(String key, {int? defaultValue}) =>
      _storage[key] as int? ?? defaultValue;

  @override
  String? getString(String key, {String? defaultValue}) =>
      _storage[key] as String? ?? defaultValue;

  @override
  Set getKeys() => _storage.keys.toSet();

  @override
  Future<void> setBool(String key, bool? value) async => _storage[key] = value;

  @override
  Future<void> setDouble(String key, double? value) async =>
      _storage[key] = value;

  @override
  Future<void> setInt(String key, int? value) async => _storage[key] = value;

  @override
  Future<void> setString(String key, String? value) async =>
      _storage[key] = value;

  @override
  Future<void> setObject<T>(String key, T? value) async =>
      _storage[key] = value;

  @override
  T? getValue<T>(String key, {T? defaultValue}) =>
      _storage[key] as T? ?? defaultValue;

  @override
  bool containsKey(String key) => _storage.containsKey(key);

  @override
  Future<void> remove(String key) async => _storage.remove(key);

  @override
  Future<void> removeAll() async => _storage.clear();
}
