import 'dart:io';

import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/data/cache/books_cache.dart';
import 'package:otzaria/data/constants/database_constants.dart';
import 'package:otzaria/data/data_providers/database_library_provider.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:otzaria/data/data_providers/user_books_database_holder.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/migration/database/daos/database.dart';
import 'package:otzaria/migration/database/repository/seforim_repository.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:path/path.dart' as path;

import '../helpers/seforim_fixture_db.dart';
import '../test_helpers/memory_cache_provider.dart';

typedef _Ids = SeforimFixtureIds;

/// אף טבלה במסד בפורמט seforim.db אינה חובה: לכל וריאנט של מסד חסר, ה-API
/// הציבורי של ה-repository וה-provider מחזיר ריק במקום לזרוק.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final variant in SeforimFixtureVariant.values) {
    final minimal = variant == SeforimFixtureVariant.minimal;
    final expectAuthors = !{
      SeforimFixtureVariant.minimal,
      SeforimFixtureVariant.missingAuthorTables,
      SeforimFixtureVariant.viewImpostor,
    }.contains(variant);
    // ב-viewImpostor רק author הוא VIEW; topic ושאר טבלאות-הצד אמיתיות.
    final expectAuthorSideTables =
        expectAuthors || variant == SeforimFixtureVariant.viewImpostor;
    final expectLinks =
        !minimal && variant != SeforimFixtureVariant.viewImpostor;
    final expectDefaults =
        !minimal && variant != SeforimFixtureVariant.missingDefaultCommentator;
    final expectAcronyms =
        !minimal && variant != SeforimFixtureVariant.viewImpostor;

    group('מסד ${variant.name}', () {
      late Directory tempDir;
      late String dbPath;
      late MyDatabase database;
      late SeforimRepository repo;

      setUp(() async {
        tempDir = await Directory.systemTemp.createTemp('otzaria_optional');
        dbPath = SeforimFixtureDb.create(tempDir, variant);
        database = MyDatabase.withPath(dbPath, readOnly: true);
        repo = SeforimRepository(database);
        await repo.ensureInitialized();
      });

      tearDown(() async {
        database.close();
        try {
          await tempDir.delete(recursive: true);
        } catch (_) {}
      });

      test('פרטי ספר — בלי טבלאות מחברים/נושאים נטען בלי קשרים', () async {
        final byId = await repo.getBook(_Ids.rashiId);
        expect(byId?.title, _Ids.rashiTitle);
        expect(
          byId!.authors.map((a) => a.name),
          expectAuthors ? [_Ids.authorName] : isEmpty,
        );
        if (!expectAuthorSideTables) {
          expect(byId.topics, isEmpty);
          expect(byId.pubPlaces, isEmpty);
          expect(byId.pubDates, isEmpty);
        }

        final byTitle = await repo.getBookByTitle(_Ids.rashiTitle);
        expect(byTitle?.id, _Ids.rashiId);
        final byCategory = await repo.getBookByTitleAndCategory(
          _Ids.rashiTitle,
          _Ids.torahCategoryId,
        );
        expect(byCategory?.id, _Ids.rashiId);
        expect(
          await repo.searchAuthorNames('רש'),
          expectAuthors ? isNotEmpty : isEmpty,
        );
        expect(
          await repo.searchBooksByAuthor('רש'),
          expectAuthors ? isNotEmpty : isEmpty,
        );
      });

      test('תוכן עניינים ומבנים חלופיים', () async {
        final toc = await repo.getBookToc(_Ids.bereshitId);
        expect(toc, minimal ? isEmpty : hasLength(1));
        expect(
          await repo.getLineBreadcrumb(_Ids.bereshitId, 0),
          minimal ? isNull : 'פרק א',
        );
        expect(
          await repo.getAltStructureBookIds(),
          minimal ? isEmpty : [_Ids.bereshitId],
        );
        expect(
          await repo.getAllAltTocFlatEntries(),
          minimal ? isEmpty : hasLength(1),
        );
      });

      test('מפרשי ברירת מחדל — טבלה חסרה נותנת רשימה ריקה', () async {
        final commentators = await repo.database.linkDao
            .selectDefaultCommentators(_Ids.bereshitId);
        expect(
          commentators.map((r) => r['targetBookTitle']),
          expectDefaults ? [_Ids.rashiTitle] : isEmpty,
        );
        expect(
          await repo.database.linkDao.selectDefaultTargums(_Ids.bereshitId),
          isEmpty,
        );
      });

      test('מפרשים, דורות, ראשי-תיבות ואינדקס הפניות', () async {
        expect(
          await repo.getAvailableCommentators(_Ids.bereshitId),
          expectLinks ? hasLength(1) : isEmpty,
        );
        expect(
          await repo.database.linkDao.selectCommentatorsByBook(_Ids.bereshitId),
          expectLinks ? isNotEmpty : isEmpty,
        );
        final generation = await repo.getBookGenerationInfo(_Ids.rashiId);
        expect(generation?.generationName, minimal ? isNull : 'ראשונים');

        final found = await repo.searchBooksForReference('רשי');
        expect(
          found.any((r) => r['matchType'] == 'acronym'),
          expectAcronyms,
        );
        expect(
          await repo.resolveRefKeyInBooks([_Ids.bereshitId], 'בראשית א א'),
          isEmpty,
        );
      });

      test('שורות הקטלוג — ספרים וקטגוריות', () async {
        final db = await database.database;
        final books = database.bookDao.getAllBooksMinimal(db);
        expect(books.map((b) => b['id']), [_Ids.bereshitId, _Ids.rashiId]);
        final noCategories =
            minimal || variant == SeforimFixtureVariant.missingCategory;
        expect(
          books.map((b) => b['categoryId']).toSet(),
          noCategories ? {0} : {_Ids.torahCategoryId},
        );
        expect(
          database.categoryDao.getAllCategoryRows(db),
          noCategories ? isEmpty : hasLength(2),
        );
        expect(
          await repo.getAllCategories(),
          noCategories ? isEmpty : hasLength(2),
        );
        expect(
          database.bookDao.getBookAuthorsMap(db),
          expectAuthors ? {_Ids.rashiId: _Ids.authorName} : isEmpty,
        );
        expect(await repo.getAllBooks(), hasLength(2));
      });

      test('שאילתות ה-isolate של ה-provider', () {
        final links = DatabaseLibraryProvider.loadBookLinksRowsForTesting(
          dbPath: dbPath,
          title: _Ids.bereshitTitle,
          categoryId: _Ids.torahCategoryId,
          fileType: 'txt',
        );
        expect(links, expectLinks ? isNotEmpty : isEmpty);

        final range =
            DatabaseLibraryProvider.loadBookLinksRowsInRangeForTesting(
              dbPath: dbPath,
              title: _Ids.bereshitTitle,
              categoryId: _Ids.torahCategoryId,
              fileType: 'txt',
              startLineIndex: 0,
              endLineIndex: 2,
            );
        expect(range, expectLinks ? isNotEmpty : isEmpty);

        final summary =
            DatabaseLibraryProvider.loadBookLinkTargetsSummaryRowsForTesting(
              dbPath: dbPath,
              title: _Ids.bereshitTitle,
              categoryId: _Ids.torahCategoryId,
            );
        expect(summary.rows, expectLinks ? isNotEmpty : isEmpty);

        expect(
          DatabaseLibraryProvider.loadAlternativeStructuresRowsForTesting(
            dbPath: dbPath,
            bookTitle: _Ids.bereshitTitle,
            categoryId: _Ids.torahCategoryId,
          ),
          minimal ? isEmpty : hasLength(1),
        );
        final marks = DatabaseLibraryProvider.loadInlineSectionMarksForTesting(
          dbPath: dbPath,
          bookTitle: _Ids.bereshitTitle,
          categoryId: _Ids.torahCategoryId,
        );
        expect(marks.markers, isEmpty);
        expect(
          DatabaseLibraryProvider.loadDibburHamatchilForTesting(
            dbPath: dbPath,
            bookTitle: _Ids.rashiTitle,
            categoryId: _Ids.torahCategoryId,
          ),
          minimal ? isEmpty : {0: 'בְּרֵאשִׁית'},
        );
        expect(
          DatabaseLibraryProvider.loadBookVersionsRowsForTesting(
            dbPath: dbPath,
            title: _Ids.bereshitTitle,
            categoryId: _Ids.torahCategoryId,
          ),
          minimal ? isEmpty : hasLength(1),
        );
        expect(
          DatabaseLibraryProvider.loadSelectableVersionKeysForTesting(
            dbPath: dbPath,
          ),
          minimal ? isEmpty : hasLength(1),
        );

        final text = DatabaseLibraryProvider.loadBookTextRangeRowsForTesting(
          dbPath: dbPath,
          title: _Ids.bereshitTitle,
          categoryId: _Ids.torahCategoryId,
          fileType: 'txt',
          startLine: 0,
          endLine: 5,
        );
        expect(text?.totalLines, 3);
        expect(text?.lines, hasLength(3));
      });
    });
  }

  group('ספר לפי כותרת וקטגוריה במסד עם קטגוריות', () {
    late Directory tempDir;
    late String dbPath;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('otzaria_optional_cat');
      dbPath = SeforimFixtureDb.create(tempDir, SeforimFixtureVariant.full);
    });

    tearDown(() async {
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}
    });

    test('דיבורי-המתחיל וסמני החלוקה מסוננים לפי הקטגוריה', () {
      expect(
        DatabaseLibraryProvider.loadDibburHamatchilForTesting(
          dbPath: dbPath,
          bookTitle: _Ids.rashiTitle,
          categoryId: _Ids.rootCategoryId,
        ),
        isEmpty,
      );
      expect(
        DatabaseLibraryProvider.loadDibburHamatchilForTesting(
          dbPath: dbPath,
          bookTitle: _Ids.rashiTitle,
          categoryId: _Ids.torahCategoryId,
        ),
        isNotEmpty,
      );
      expect(
        DatabaseLibraryProvider.loadAlternativeStructuresRowsForTesting(
          dbPath: dbPath,
          bookTitle: _Ids.bereshitTitle,
          categoryId: _Ids.rootCategoryId,
        ),
        isEmpty,
      );
    });
  });

  group('בניית הקטלוג וטעינת קישורים דרך ה-provider', () {
    late Directory tempDir;
    late String libraryPath;

    Future<void> openLibrary(SeforimFixtureVariant variant) async {
      tempDir = await Directory.systemTemp.createTemp('otzaria_optional_lib');
      libraryPath = path.join(tempDir.path, 'library');
      await Directory(libraryPath).create(recursive: true);
      final fixture = SeforimFixtureDb.create(tempDir, variant);
      await File(
        fixture,
      ).copy(path.join(libraryPath, DatabaseConstants.databaseFileName));

      await Settings.init(cacheProvider: MemoryCacheProvider());
      AppPaths.debugOverrideDataRootPath(path.join(tempDir.path, 'data_root'));
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
      BooksCache.instance.clear();
      DatabaseLibraryProvider.instance.clearCache();
      await SqliteDataProvider.instance.dispose();
      await SqliteDataProvider.instance.initialize();
    }

    tearDown(() async {
      BooksCache.instance.clear();
      DatabaseLibraryProvider.instance.clearCache();
      await SqliteDataProvider.instance.dispose();
      await UserBooksDatabaseHolder.instance.close();
      AppPaths.debugOverrideDataRootPath(null);
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}
    });

    List<String> titlesUnder(Category category) => [
      for (final book in category.books) book.title,
    ];

    for (final variant in [
      SeforimFixtureVariant.missingCategory,
      SeforimFixtureVariant.minimal,
    ]) {
      test('${variant.name}: בלי קטגוריות — הספרים תחת שורש יחיד', () async {
        await openLibrary(variant);
        final library = await DatabaseLibraryProvider.instance
            .buildLibraryCatalog({}, libraryPath);

        final root = library.subCategories.single;
        expect(root.title, kUncategorizedCategoryTitle);
        expect(titlesUnder(root), [_Ids.bereshitTitle, _Ids.rashiTitle]);
      });
    }

    test('מסד מלא: הקטלוג בנוי לפי הקטגוריות', () async {
      await openLibrary(SeforimFixtureVariant.full);
      final library = await DatabaseLibraryProvider.instance
          .buildLibraryCatalog({}, libraryPath);

      final root = library.subCategories.single;
      expect(root.title, 'תנ"ך');
      final torah = root.subCategories.single;
      expect(titlesUnder(torah), [_Ids.bereshitTitle, _Ids.rashiTitle]);
    });

    test('טבלת קישורים חסרה — חלון הקישורים ריק ולא נזרק', () async {
      await openLibrary(SeforimFixtureVariant.minimal);
      final links = await DatabaseLibraryProvider.instance.getLinksForBookRange(
        _Ids.bereshitTitle,
        0,
        'txt',
        startLineIndex: 0,
        endLineIndex: 2,
      );
      expect(links, isEmpty);
    });

    test('מסד סגור — טעינת חלון קישורים עדיין זורקת StateError', () async {
      await openLibrary(SeforimFixtureVariant.full);
      await SqliteDataProvider.instance.dispose();
      await expectLater(
        DatabaseLibraryProvider.instance.getLinksForBookRange(
          _Ids.bereshitTitle,
          _Ids.torahCategoryId,
          'txt',
          startLineIndex: 0,
          endLineIndex: 2,
        ),
        throwsStateError,
      );
    });
  });
}
