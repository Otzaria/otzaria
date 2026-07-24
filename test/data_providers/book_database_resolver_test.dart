import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/data/constants/database_constants.dart';
import 'package:otzaria/data/data_providers/book_database_resolver.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:otzaria/data/data_providers/user_books_database_holder.dart';
import 'package:otzaria/migration/database/daos/database.dart';
import 'package:otzaria/migration/database/repository/seforim_repository.dart';
import 'package:otzaria/migration/models/book.dart' as migration_models;
import 'package:otzaria/migration/models/category.dart' as migration_models;
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:path/path.dart' as path;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BookDatabaseResolver.isLikelyUserBook', () {
    test('isUserBook=true גובר על categoryPath', () {
      expect(
        BookDatabaseResolver.isLikelyUserBook(
          isUserBook: true,
          categoryPath: '/תלמוד בבלי/סדר מועד',
        ),
        isTrue,
      );
    });

    test('categoryPath שמתחיל ב-"ספרים אישיים" מזוהה כספר משתמש', () {
      expect(
        BookDatabaseResolver.isLikelyUserBook(
          categoryPath: '/ספרים אישיים/תיקייה',
        ),
        isTrue,
      );
    });

    test('categoryPath עם פסיקים (פורמט heCategories) נתמך', () {
      // ה-resolver גם מנרמל פסיקים ל-"/" כדי להבין שתי הצורות.
      expect(
        BookDatabaseResolver.isLikelyUserBook(
          categoryPath: 'ספרים אישיים, תיקיית עבודה',
        ),
        isTrue,
      );
    });

    test('categoryPath של ספר רגיל אינו מזוהה כספר משתמש', () {
      expect(
        BookDatabaseResolver.isLikelyUserBook(
          categoryPath: '/תנ"ך/תורה/בראשית',
        ),
        isFalse,
      );
      expect(
        BookDatabaseResolver.isLikelyUserBook(
          categoryPath: 'תלמוד בבלי, סדר מועד, שבת',
        ),
        isFalse,
      );
    });

    test('categoryPath ריק או null מחזיר false (ברירת מחדל)', () {
      expect(BookDatabaseResolver.isLikelyUserBook(), isFalse);
      expect(BookDatabaseResolver.isLikelyUserBook(categoryPath: ''), isFalse);
      expect(
        BookDatabaseResolver.isLikelyUserBook(categoryPath: '   '),
        isFalse,
      );
      expect(
        BookDatabaseResolver.isLikelyUserBook(categoryPath: '/   /   '),
        isFalse,
      );
    });

    test('categoryPath עם backslashes (Windows-style) נתמך', () {
      expect(
        BookDatabaseResolver.isLikelyUserBook(
          categoryPath: r'ספרים אישיים\תיקיית עבודה',
        ),
        isTrue,
      );
    });
  });

  group('BookDatabaseResolver.buildCategoryPath', () {
    late Directory tempDir;
    late MyDatabase database;
    late SeforimRepository repository;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('otzaria-resolver-path-');
      database = MyDatabase.withPath(path.join(tempDir.path, 'test.db'));
      repository = SeforimRepository(database);
      await repository.ensureInitialized();
    });

    tearDown(() async {
      database.close();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('בונה נתיב היררכי מהקטגוריה ועד השורש', () async {
      final rootId = await repository.insertCategory(
        const migration_models.Category(title: 'תנ"ך', level: 0),
      );
      final torahId = await repository.insertCategory(
        migration_models.Category(title: 'תורה', parentId: rootId, level: 1),
      );
      final bereshitId = await repository.insertCategory(
        migration_models.Category(title: 'בראשית', parentId: torahId, level: 2),
      );

      final result = await BookDatabaseResolver.buildCategoryPath(
        repository,
        bereshitId,
      );

      expect(result, 'תנ"ך, תורה, בראשית');
    });

    test('קטגוריית שורש מחזירה רק את עצמה', () async {
      final id = await repository.insertCategory(
        const migration_models.Category(title: 'ספרים אישיים', level: 0),
      );

      final result = await BookDatabaseResolver.buildCategoryPath(
        repository,
        id,
      );

      expect(result, 'ספרים אישיים');
    });

    test('categoryId לא קיים מחזיר מחרוזת ריקה', () async {
      final result = await BookDatabaseResolver.buildCategoryPath(
        repository,
        999999,
      );

      expect(result, isEmpty);
    });
  });

  group('BookDatabaseResolver.resolveBookInCandidates', () {
    late Directory tempDir;
    late MyDatabase seforimDb;
    late MyDatabase userBooksDb;
    late SeforimRepository seforimRepo;
    late SeforimRepository userBooksRepo;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp(
        'otzaria-resolver-candidates-',
      );
      seforimDb = MyDatabase.withPath(path.join(tempDir.path, 'seforim.db'));
      userBooksDb = MyDatabase.withPath(
        path.join(tempDir.path, 'user_books.db'),
      );
      seforimRepo = SeforimRepository(seforimDb);
      userBooksRepo = SeforimRepository(userBooksDb);
      await seforimRepo.ensureInitialized();
      await userBooksRepo.ensureInitialized();
    });

    tearDown(() async {
      seforimDb.close();
      userBooksDb.close();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    /// Helper: יוצר קטגוריה (אם צריך), ספר ומחזיר את ה-categoryId שנוצר.
    Future<int> insertBookFor({
      required SeforimRepository repo,
      required String title,
      String categoryTitle = 'קטגוריה',
      String fileType = 'txt',
      String? filePath,
    }) async {
      final categoryId = await repo.insertCategory(
        migration_models.Category(title: categoryTitle, level: 0),
      );
      final sourceId = await repo.insertSource(
        'test-source-$categoryTitle',
        -1,
      );
      await repo.insertBook(
        migration_models.Book(
          categoryId: categoryId,
          sourceId: sourceId,
          title: title,
          fileType: fileType,
          filePath: filePath,
        ),
      );
      return categoryId;
    }

    test('מוצא ספר ב-candidate הראשון לפי כותרת בלבד', () async {
      await insertBookFor(repo: seforimRepo, title: 'ספר רשמי');

      final result = await BookDatabaseResolver.resolveBookInCandidates(
        title: 'ספר רשמי',
        candidates: [
          ResolvedBookRepositoryCandidate(
            repository: seforimRepo,
            isUserBooks: false,
          ),
        ],
      );

      expect(result, isNotNull);
      expect(result!.book.title, 'ספר רשמי');
      expect(result.isUserBooks, isFalse);
    });

    test('נופל לפי הסדר ל-candidate השני אם הראשון לא מצא', () async {
      await insertBookFor(repo: userBooksRepo, title: 'ספר אישי');

      final result = await BookDatabaseResolver.resolveBookInCandidates(
        title: 'ספר אישי',
        candidates: [
          ResolvedBookRepositoryCandidate(
            repository: seforimRepo,
            isUserBooks: false,
          ),
          ResolvedBookRepositoryCandidate(
            repository: userBooksRepo,
            isUserBooks: true,
          ),
        ],
      );

      expect(result, isNotNull);
      expect(result!.book.title, 'ספר אישי');
      expect(result.isUserBooks, isTrue);
    });

    test(
      'מעדיף התאמה מלאה (title+categoryId+fileType) על כותרת בלבד',
      () async {
        // יוצרים שני ספרים עם אותה כותרת בקטגוריות שונות + סוגי קבצים שונים,
        // ובודקים שההתאמה לפי categoryId+fileType מחזירה את הספר הספציפי.
        await insertBookFor(
          repo: seforimRepo,
          title: 'דו-שמי',
          categoryTitle: 'קט-1',
          fileType: 'txt',
        );
        final pdfCatId = await insertBookFor(
          repo: seforimRepo,
          title: 'דו-שמי',
          categoryTitle: 'קט-2',
          fileType: 'pdf',
        );

        final result = await BookDatabaseResolver.resolveBookInCandidates(
          title: 'דו-שמי',
          categoryId: pdfCatId,
          fileType: 'pdf',
          candidates: [
            ResolvedBookRepositoryCandidate(
              repository: seforimRepo,
              isUserBooks: false,
            ),
          ],
        );

        expect(result, isNotNull);
        expect(result!.book.title, 'דו-שמי');
        expect(result.book.categoryId, pdfCatId);
        expect(result.book.fileType, 'pdf');
      },
    );

    test('מעדיף חיפוש לפי filePath כשהוא קיים', () async {
      final externalPath = path.join(tempDir.path, 'external_book.txt');
      await File(externalPath).writeAsString('content');
      await insertBookFor(
        repo: seforimRepo,
        title: 'דרך נתיב',
        categoryTitle: 'עם-נתיב',
        fileType: 'txt',
        filePath: externalPath,
      );
      // יוצרים ספר נוסף עם אותה כותרת אבל בלי filePath — לא צריך להיבחר.
      await insertBookFor(
        repo: seforimRepo,
        title: 'דרך נתיב',
        categoryTitle: 'בלי-נתיב',
        fileType: 'txt',
      );

      final result = await BookDatabaseResolver.resolveBookInCandidates(
        title: 'דרך נתיב',
        filePath: externalPath,
        candidates: [
          ResolvedBookRepositoryCandidate(
            repository: seforimRepo,
            isUserBooks: false,
          ),
        ],
      );

      expect(result, isNotNull);
      expect(
        result!.book.filePath,
        externalPath,
        reason: 'התאמה לפי filePath מחזירה את הרשומה עם הנתיב המדויק',
      );
    });

    test('מחזיר null כשאין התאמה באף candidate', () async {
      final result = await BookDatabaseResolver.resolveBookInCandidates(
        title: 'לא קיים',
        candidates: [
          ResolvedBookRepositoryCandidate(
            repository: seforimRepo,
            isUserBooks: false,
          ),
          ResolvedBookRepositoryCandidate(
            repository: userBooksRepo,
            isUserBooks: true,
          ),
        ],
      );

      expect(result, isNull);
    });

    test('רשימת candidates ריקה מחזירה null', () async {
      final result = await BookDatabaseResolver.resolveBookInCandidates(
        title: 'כל דבר',
        candidates: const [],
      );

      expect(result, isNull);
    });
  });

  group('BookDatabaseResolver — integration (resolveBook / resolveBookById)', () {
    late Directory tempDir;
    late String libraryPath;
    late String dataRootPath;
    late MyDatabase seforimDb;
    late SeforimRepository seforimRepo;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('otzaria-resolver-int-');
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
      // נדאג ש-SqliteDataProvider יעלה מחדש עם ה-DB הטסטי
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
      'resolveBook ללא preferUserBooks: מוצא קודם ב-seforim ולא יוצר user_books.db',
      () async {
        final catId = await seforimRepo.insertCategory(
          const migration_models.Category(title: 'תורה'),
        );
        final sourceId = await seforimRepo.insertSource('test', -1);
        await seforimRepo.insertBook(
          migration_models.Book(
            categoryId: catId,
            sourceId: sourceId,
            title: 'בראשית',
            fileType: 'txt',
          ),
        );

        final resolved = await BookDatabaseResolver.resolveBook(
          title: 'בראשית',
        );

        expect(resolved, isNotNull);
        expect(resolved!.book.title, 'בראשית');
        expect(resolved.isUserBooks, isFalse);
        expect(
          await File(await AppPaths.resolveUserBooksDbPath()).exists(),
          isFalse,
          reason:
              'אין צורך ב-user_books.db כשהספר נמצא ב-seforim ולא ביקשנו אחרת',
        );
      },
    );

    test(
      'resolveBook עם preferUserBooks=true מאתר ספר ב-user_books.db',
      () async {
        // יוצרים user_books.db ומכניסים אליו ספר.
        final userBooksRepo = await UserBooksDatabaseHolder.instance.repository;
        final catId = await userBooksRepo.insertCategory(
          const migration_models.Category(title: 'ספרים אישיים'),
        );
        final sourceId = await userBooksRepo.insertSource('Personal::test', -1);
        await userBooksRepo.insertBook(
          migration_models.Book(
            categoryId: catId,
            sourceId: sourceId,
            title: 'ספר אישי',
            fileType: 'txt',
          ),
        );

        final resolved = await BookDatabaseResolver.resolveBook(
          title: 'ספר אישי',
          preferUserBooks: true,
        );

        expect(resolved, isNotNull);
        expect(resolved!.book.title, 'ספר אישי');
        expect(
          resolved.isUserBooks,
          isTrue,
          reason: 'preferUserBooks=true מחפש קודם ב-user_books',
        );
      },
    );

    test(
      'resolveBook עם officialOnly לא נופל לספר אישי בעל אותה כותרת',
      () async {
        final userBooksRepo = await UserBooksDatabaseHolder.instance.repository;
        final catId = await userBooksRepo.insertCategory(
          const migration_models.Category(title: 'ספרים אישיים'),
        );
        final sourceId = await userBooksRepo.insertSource('Personal::test', -1);
        await userBooksRepo.insertBook(
          migration_models.Book(
            categoryId: catId,
            sourceId: sourceId,
            title: 'מילון אישי',
            fileType: 'txt',
          ),
        );

        final resolved = await BookDatabaseResolver.resolveBook(
          title: 'מילון אישי',
          officialOnly: true,
        );

        expect(resolved, isNull);
      },
    );

    test('resolveBookById עם isUserBook=true מחפש רק ב-user_books', () async {
      // ב-seforim וב-user_books נוצרים ספרים נפרדים. ה-AUTOINCREMENT יקצה
      // לכל אחד id משלו — שומרים את שני המזהים כדי לבדוק שכל DB מחזיר את שלו.
      final seforimCat = await seforimRepo.insertCategory(
        const migration_models.Category(title: 'רשמי'),
      );
      final seforimSource = await seforimRepo.insertSource('seforim', -1);
      final seforimBookId = await seforimRepo.insertBook(
        migration_models.Book(
          categoryId: seforimCat,
          sourceId: seforimSource,
          title: 'בעולם הרשמי',
          fileType: 'txt',
        ),
      );

      final userBooksRepo = await UserBooksDatabaseHolder.instance.repository;
      final userCat = await userBooksRepo.insertCategory(
        const migration_models.Category(title: 'ספרים אישיים'),
      );
      final userSource = await userBooksRepo.insertSource('Personal::dup', -1);
      final userBookId = await userBooksRepo.insertBook(
        migration_models.Book(
          categoryId: userCat,
          sourceId: userSource,
          title: 'בעולם האישי',
          fileType: 'txt',
        ),
      );

      final fromUser = await BookDatabaseResolver.resolveBookById(
        userBookId,
        isUserBook: true,
      );
      expect(fromUser, isNotNull);
      expect(fromUser!.book.title, 'בעולם האישי');
      expect(fromUser.isUserBooks, isTrue);

      final fromOfficial = await BookDatabaseResolver.resolveBookById(
        seforimBookId,
      );
      expect(fromOfficial, isNotNull);
      expect(fromOfficial!.book.title, 'בעולם הרשמי');
      expect(fromOfficial.isUserBooks, isFalse);
    });

    test(
      'resolveBookById עם isUserBook=true ובלי user_books.db מחזיר null',
      () async {
        // לא יצרנו user_books.db; resolveDbPath יחזיר נתיב לקובץ שלא קיים.
        final dbPath = await AppPaths.resolveUserBooksDbPath();
        expect(
          await File(dbPath).exists(),
          isFalse,
          reason: 'הטסט מסתמך על כך שאין user_books.db',
        );

        final result = await BookDatabaseResolver.resolveBookById(
          42,
          isUserBook: true,
        );

        expect(result, isNull);
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
