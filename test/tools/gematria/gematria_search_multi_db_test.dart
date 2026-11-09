import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
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
import 'package:otzaria/text_book/utils/section_search_utils.dart';
import 'package:otzaria/tools/gematria/gematria_search.dart';
import 'package:otzaria/utils/text/text_manipulation.dart' as utils;
import 'package:path/path.dart' as path;

import '../../test_helpers/memory_cache_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // בראשית א,ה כפי שהוא שמור במסד.
  const gen1v5 =
      '(ה) וַיִּקְרָ֨א אֱלֹהִ֤ים&thinsp;<small>׀</small>&thinsp;לָאוֹר֙ י֔וֹם וְלַחֹ֖שֶׁךְ קָ֣רָא לָ֑יְלָה';
  const vayehiErev = 'וַֽיְהִי־עֶ֥רֶב';

  // התוצאה נשלחת כטקסט ההדגשה בפתיחת הספר, ולכן חייבת להימצא בשורה המקורית.
  bool highlights(String rawLine, String preview) =>
      cleanLineForSearch(rawLine).contains(utils.removeVolwels(preview));

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

      await Settings.init(cacheProvider: MemoryCacheProvider());
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

    test('פסק אינו יוצר תוצאה כפולה (לאור = 237)', () async {
      await insertBookWithLines(
        repo: seforimRepo,
        title: 'בראשית',
        lines: [gen1v5],
      );
      final results = await GimatriaSearch.searchInFiles(
        const <String>[],
        237,
        bookTitles: const ['בראשית'],
      );
      expect(results.map((r) => r.text).toList(), hasLength(1));
      expect(highlights(gen1v5, results.single.text), isTrue);
    });

    test('עם הכולל: פסק אינו נספר כמילה ("אלהים לאור" = 323 + 2)', () async {
      await insertBookWithLines(
        repo: seforimRepo,
        title: 'בראשית',
        lines: [gen1v5],
      );
      final results = await GimatriaSearch.searchInFiles(
        const <String>[],
        325,
        bookTitles: const ['בראשית'],
        useWithKolel: true,
      );
      final texts = results.map((r) => r.text);
      expect(texts.map(utils.removeVolwels), contains('אלהים לאור'));
      expect(texts.every((t) => highlights(gen1v5, t)), isTrue);
    });

    test('עם הכולל: מקף מפריד בין מילים ("ויהי ערב" = 31 + 272 + 2)', () async {
      await insertBookWithLines(
        repo: seforimRepo,
        title: 'בראשית',
        lines: [vayehiErev],
      );
      final results = await GimatriaSearch.searchInFiles(
        const <String>[],
        305,
        bookTitles: const ['בראשית'],
        useWithKolel: true,
      );
      expect(results, hasLength(1));
      expect(highlights(vayehiErev, results.single.text), isTrue);
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

      await Settings.init(cacheProvider: MemoryCacheProvider());
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

    test('מקף ופסק מפרידים בין מילים גם בחיפוש קבצים', () async {
      final folder = path.join(tempDir.path, 'txtbooks');
      await Directory(folder).create(recursive: true);
      await File(
        path.join(folder, 'בראשית.txt'),
      ).writeAsString('$gen1v5\n$vayehiErev\n');

      final results = await GimatriaSearch.searchInFiles(
        [folder],
        237,
      );
      expect(results, hasLength(1));

      final withKolel = await GimatriaSearch.searchInFiles(
        [folder],
        305,
        useWithKolel: true,
      );
      expect(withKolel, hasLength(1));
    });

    test('NEL אינו יוצר תוצאה כפולה ואינו נספר בכולל', () async {
      final folder = path.join(tempDir.path, 'txtbooks');
      await Directory(folder).create(recursive: true);
      await File(
        path.join(folder, 'בראשית.txt'),
      ).writeAsString('אב \u0085 גדול');

      final results = await GimatriaSearch.searchInFiles([folder], 3);
      final withKolel = await GimatriaSearch.searchInFiles(
        [folder],
        48,
        wholeVerseOnly: true,
        useWithKolel: true,
      );

      expect(results.map((result) => result.text).toList(), ['אב']);
      expect(withKolel.map((result) => result.text).toList(), ['אב גדול']);
    });
  });

  group('GimatriaSearch.extractPathFromTocEntries — פונקציה טהורה', () {
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
