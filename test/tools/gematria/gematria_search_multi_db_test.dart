import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/data/constants/database_constants.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:otzaria/data/data_providers/user_books_database_holder.dart';
import 'package:otzaria/migration/database/daos/database.dart';
import 'package:otzaria/migration/database/repository/seforim_repository.dart';
import 'package:otzaria/migration/models/book.dart' as migration_models;
import 'package:otzaria/migration/models/category.dart' as migration_models;
import 'package:otzaria/migration/models/line.dart' as migration_models;
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/tools/gematria/gematria_search.dart';
import 'package:path/path.dart' as path;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('GimatriaSearch — חיפוש על פני שני DBs', () {
    late Directory tempDir;
    late String libraryPath;
    late String dataRootPath;
    late MyDatabase seforimDb;
    late SeforimRepository seforimRepo;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp(
        'otzaria-gimatria-multi-',
      );
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

    /// Helper: יוצר ספר עם שורות, מחזיר את ה-bookId.
    Future<int> insertBookWithLines({
      required SeforimRepository repo,
      required String title,
      required List<String> lines,
    }) async {
      final catId = await repo.insertCategory(
        const migration_models.Category(title: 'תורה'),
      );
      final sourceId = await repo.insertSource('test::$title', -1);
      final bookId = await repo.insertBook(
        migration_models.Book(
          categoryId: catId,
          sourceId: sourceId,
          title: title,
          fileType: 'txt',
          totalLines: lines.length,
        ),
      );
      final lineModels = [
        for (var i = 0; i < lines.length; i++)
          migration_models.Line(
            bookId: bookId,
            lineIndex: i,
            content: lines[i],
          ),
      ];
      await repo.insertLinesBatch(lineModels);
      // totalLines כבר נשמר ב-insertBook; אם צריך לרענן:
      await repo.updateBookTotalLines(bookId, lines.length);
      return bookId;
    }

    test('כשספר נמצא רק ב-seforim — תוצאות גימטריה נמשכות משם', () async {
      // אב = 1 + 2 = 3. אנו מחפשים gimatria=3.
      await insertBookWithLines(
        repo: seforimRepo,
        title: 'בראשית',
        lines: ['אב גדול'],
      );

      final results = await GimatriaSearch.searchInFiles(
        const <String>[], // ה-folders ריקים — נכפה DB
        3,
        bookTitles: const ['בראשית'],
        gematriaMethod: 'regular',
      );

      expect(results, isNotEmpty);
      expect(
        results.any((r) => r.file == 'בראשית' && r.text.contains('אב')),
        isTrue,
      );
    });

    test(
      'כשספר נמצא רק ב-user_books — תוצאות נמשכות מ-user_books דרך resolver',
      () async {
        final userBooksRepo = await UserBooksDatabaseHolder.instance.repository;
        // ספר אישי בלבד — לא קיים ב-seforim. הקוד מקבץ אותו ל-repository
        // המתאים דרך resolveBook.
        await insertBookWithLines(
          repo: userBooksRepo,
          title: 'ספר אישי',
          lines: ['אב גדול'],
        );

        final results = await GimatriaSearch.searchInFiles(
          const <String>[],
          3,
          bookTitles: const ['ספר אישי'],
          gematriaMethod: 'regular',
        );

        expect(results, isNotEmpty);
        expect(results.first.file, 'ספר אישי');
      },
    );

    test(
      'שני ספרים: אחד ב-seforim ואחד ב-user_books — מאחד תוצאות מ-שניהם',
      () async {
        await insertBookWithLines(
          repo: seforimRepo,
          title: 'ספר רשמי',
          lines: ['אב הוא'],
        );

        final userBooksRepo = await UserBooksDatabaseHolder.instance.repository;
        await insertBookWithLines(
          repo: userBooksRepo,
          title: 'ספר אישי',
          lines: ['אב הוא'],
        );

        // gimatria('אב') = 3, gimatria('הוא') = 12, ביחד 15 — נחפש 3 (רק 'אב').
        final results = await GimatriaSearch.searchInFiles(
          const <String>[],
          3,
          bookTitles: const ['ספר רשמי', 'ספר אישי'],
          gematriaMethod: 'regular',
        );

        final files = results.map((r) => r.file).toSet();
        expect(
          files,
          containsAll(['ספר רשמי', 'ספר אישי']),
          reason: 'כל ספר מ-DB שונה תורם תוצאות',
        );
      },
    );

    test('ספר שלא קיים בשום DB מתעלמים ממנו (לא קורסים)', () async {
      await insertBookWithLines(
        repo: seforimRepo,
        title: 'קיים',
        lines: ['אב'],
      );

      final results = await GimatriaSearch.searchInFiles(
        const <String>[],
        3,
        bookTitles: const ['קיים', 'לא קיים'],
        gematriaMethod: 'regular',
      );

      // 'קיים' תורם, 'לא קיים' פשוט נדלג עליו ב-resolveBook (מחזיר null).
      expect(results, isNotEmpty);
      expect(results.every((r) => r.file == 'קיים'), isTrue);
    });

    test(
      'חיפוש בזמן write-session — ממתין לפתיחה-מחדש ומחזיר תוצאות',
      () async {
        await insertBookWithLines(
          repo: seforimRepo,
          title: 'בראשית',
          lines: ['אב גדול'],
        );

        final provider = SqliteDataProvider.instance;
        provider.debugSetExternalWriteWait(
          pollInterval: const Duration(milliseconds: 50),
          maxPolls: 200,
        );

        // write-session חיצוני פעיל: חיבור ה-RO סגור וה-gate פתוח.
        await provider.closeForExternalWrite();
        expect(provider.isInitialized, isFalse);

        // החיפוש נכנס להמתנה ל-gate; הפתיחה-מחדש משחררת אותו ומחזירה תוצאות.
        final searchFuture = GimatriaSearch.searchInFiles(
          const <String>[],
          3,
          bookTitles: const ['בראשית'],
          gematriaMethod: 'regular',
        );
        await provider.reopenAfterExternalWrite();

        final results = await searchFuture;
        expect(
          results,
          isNotEmpty,
          reason: 'החיפוש חייב להמתין ל-DB, לא ליפול ל-fallback ריק',
        );
        expect(provider.isInitialized, isTrue);
      },
    );

    test('fileLimit קוטע את הסריקה, וחיפוש עוקב חוזר מלא', () async {
      // חמש התאמות ל-gimatria=3 באותה שורה.
      await insertBookWithLines(
        repo: seforimRepo,
        title: 'בראשית',
        lines: ['אב אב אב אב אב'],
      );

      Future<List<SearchResult>> search({int? fileLimit}) =>
          GimatriaSearch.searchInFiles(
            const <String>[],
            3,
            fileLimit: fileLimit ?? 1000,
            bookTitles: const ['בראשית'],
          );

      // fileLimit=1 יוצא מהסריקה באמצע הספר ולא בסופו.
      expect(await search(fileLimit: 1), hasLength(1));

      // ה-isolate נבנה מחדש בכל קריאה; יציאה מוקדמת קודמת לא משפיעה עליו.
      expect((await search()).length, greaterThan(1));
    });
  });

  group('GimatriaSearch — fallback לקבצים כשאין DB', () {
    late Directory tempDir;
    late String libraryPath;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp(
        'otzaria-gimatria-fallback-',
      );
      libraryPath = path.join(tempDir.path, 'library');
      await Directory(libraryPath).create(recursive: true);

      await Settings.init(cacheProvider: _MemoryCacheProvider());
      AppPaths.debugOverrideDataRootPath(path.join(tempDir.path, 'data_root'));
      await Settings.setValue<String>(
        SettingsRepository.keyLibraryPath,
        libraryPath,
      );
      await Settings.setValue<String>(
        SettingsRepository.keyDbEffectivePath,
        '',
      );
      // ללא יצירת seforim.db — initialize לא יאתחל וחייבים fallback לקבצים.
      await SqliteDataProvider.instance.dispose();
    });

    tearDown(() async {
      await SqliteDataProvider.instance.dispose();
      AppPaths.debugOverrideDataRootPath(null);
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test(
      'אין DB — searchInFiles נופל לחיפוש קבצים ומחזיר תוצאות מ-txt',
      () async {
        final folder = path.join(tempDir.path, 'txtbooks');
        await Directory(folder).create(recursive: true);
        await File(path.join(folder, 'בראשית.txt')).writeAsString('אב גדול\n');

        final results = await GimatriaSearch.searchInFiles(
          [folder],
          3,
          gematriaMethod: 'regular',
        );

        expect(
          SqliteDataProvider.instance.isInitialized,
          isFalse,
          reason: 'ללא קובץ DB האתחול לא מצליח, בלי לזרוק',
        );
        expect(results, isNotEmpty, reason: 'חייב fallback לחיפוש קבצים');
        expect(results.first.text.contains('אב'), isTrue);
      },
    );
  });

  group('GimatriaSearch.extractPathFromTocEntries — פונקציה טהורה', () {
    // הטסט הקיים מכסה זאת ב-test/gematria_search_test.dart; כאן רק וידוא
    // שה-API מאופשר גם מתוך הסביבה הזו (multi-DB) — לא מבוצעת שום אינטראקציה
    // עם DB.
    test('רשימת TOC ריקה מחזירה מחרוזת ריקה (אין מידע לבנות נתיב)', () {
      final result = GimatriaSearch.extractPathFromTocEntries(
        currentLineIndex: 0,
        bookTitle: 'בראשית',
        tocEntries: const [],
      );
      expect(result, '');
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
