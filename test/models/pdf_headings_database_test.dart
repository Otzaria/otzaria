import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/data/constants/database_constants.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:otzaria/data/data_providers/user_books_database_holder.dart';
import 'package:otzaria/find_ref/repository/find_ref_db_isolate.dart';
import 'package:otzaria/migration/database/daos/database.dart';
import 'package:otzaria/migration/database/repository/seforim_repository.dart';
import 'package:otzaria/migration/models/book.dart' as migration_models;
import 'package:otzaria/migration/models/category.dart' as migration_models;
import 'package:otzaria/migration/models/toc_entry.dart' as migration_models;
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/models/pdf_headings.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:path/path.dart' as path;

import '../test_helpers/memory_cache_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late String libraryPath;
  late String dataRootPath;
  late MyDatabase seforimDb;
  late SeforimRepository seforimRepo;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('otzaria-pdf-headings-');
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
    await Settings.setValue<String>(SettingsRepository.keyDbEffectivePath, '');

    final dbPath = path.join(libraryPath, DatabaseConstants.databaseFileName);
    seforimDb = MyDatabase.withPath(dbPath);
    seforimRepo = SeforimRepository(seforimDb);
    await seforimRepo.ensureInitialized();
    await SqliteDataProvider.instance.dispose();
    await SqliteDataProvider.instance.initialize();
  });

  tearDown(() async {
    (await FindRefDbIsolate.instance()).disposeForTesting();
    await SqliteDataProvider.instance.dispose();
    await UserBooksDatabaseHolder.instance.close();
    seforimDb.close();
    AppPaths.debugOverrideDataRootPath(null);
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  /// Helper: יוצר ספר עם TOC entries עם lineIndex. מחזיר את bookId שנוצר.
  Future<int> insertBookWithToc({
    required SeforimRepository repo,
    required String title,
    required Map<String, int> headings,
    int categoryId = 1,
  }) async {
    final catId = await repo.insertCategory(
      const migration_models.Category(title: 'תורה'),
    );
    final sourceId = await repo.insertSource('test', -1);
    final bookId = await repo.insertBook(
      migration_models.Book(
        categoryId: catId,
        sourceId: sourceId,
        title: title,
        fileType: 'pdf',
      ),
    );
    for (final entry in headings.entries) {
      await repo.insertTocEntry(
        migration_models.TocEntry(
          bookId: bookId,
          text: entry.key,
          level: 1,
          lineIndex: entry.value,
        ),
      );
    }
    return bookId;
  }

  group('PdfHeadings.loadFromDatabase', () {
    test('מחזיר null אם הספר לא נמצא בשום DB', () async {
      final result = await PdfHeadings.loadFromDatabase('לא קיים');
      expect(result, isNull);
    });

    test('מאכלס מפת כותרות מ-seforim.db', () async {
      await insertBookWithToc(
        repo: seforimRepo,
        title: 'בראשית',
        headings: {'פרק א': 0, 'פרק ב': 30},
      );

      final result = await PdfHeadings.loadFromDatabase('בראשית');

      expect(result, isNotNull);
      expect(result!.bookTitle, 'בראשית');
      expect(result.headingsMap, {'פרק א': 0, 'פרק ב': 30});
      expect(result.getLineNumberForHeading('פרק א'), 0);
      expect(result.getLineNumberForHeading('פרק ב'), 30);
    });

    test(
      'preferUserBooks=true מאתר את הספר ב-user_books.db ולא ב-seforim',
      () async {
        // אותו שם ספר בשני ה-DBs עם headings שונים. preferUserBooks=true חייב
        // לבחור את ה-user_books.
        await insertBookWithToc(
          repo: seforimRepo,
          title: 'משותף',
          headings: {'מ-seforim': 5},
        );

        final userBooksRepo = await UserBooksDatabaseHolder.instance.repository;
        await insertBookWithToc(
          repo: userBooksRepo,
          title: 'משותף',
          headings: {'מ-user-books': 12},
        );

        final fromUser = await PdfHeadings.loadFromDatabase(
          'משותף',
          preferSource: BookSource.user,
        );
        final fromOfficial = await PdfHeadings.loadFromDatabase('משותף');

        expect(fromUser?.headingsMap, {'מ-user-books': 12});
        expect(fromOfficial?.headingsMap, {'מ-seforim': 5});
      },
    );

    test(
      'TOC של user_books.db נקרא בחיבור נפרד, לא בחיבור ה-UI (#4028)',
      () async {
        final userBooksRepo = await UserBooksDatabaseHolder.instance.repository;
        await insertBookWithToc(
          repo: userBooksRepo,
          title: 'אישי',
          headings: {'פרק א': 3},
        );
        // מחיקה שלא נשמרה גלויה רק לחיבור הראשי; קריאה ב-isolate לא רואה אותה.
        final mainConnection = await userBooksRepo.database.database;
        mainConnection.execute('BEGIN');
        mainConnection.execute('DELETE FROM tocEntry');
        addTearDown(() => mainConnection.execute('ROLLBACK'));

        final result = await PdfHeadings.loadFromDatabase(
          'אישי',
          preferSource: BookSource.user,
        );

        expect(result?.headingsMap, {'פרק א': 3});
      },
    );

    test('מחזיר null כשאין כותרות עם lineIndex', () async {
      // מכניסים ספר עם entry שאין לו lineIndex — ה-buildHeadingsMap מסנן אותם.
      final catId = await seforimRepo.insertCategory(
        const migration_models.Category(title: 'תורה'),
      );
      final sourceId = await seforimRepo.insertSource('test', -1);
      final bookId = await seforimRepo.insertBook(
        migration_models.Book(
          categoryId: catId,
          sourceId: sourceId,
          title: 'בלי-line-index',
          fileType: 'pdf',
        ),
      );
      await seforimRepo.insertTocEntry(
        migration_models.TocEntry(
          bookId: bookId,
          text: 'כותרת בלי שורה',
          level: 1,
          // lineIndex: null → מסונן במפה
        ),
      );

      final result = await PdfHeadings.loadFromDatabase('בלי-line-index');

      expect(result, isNull, reason: 'אין כותרות עם lineIndex → null');
    });
  });

  group('PdfHeadings.buildHeadingsMapFromTocEntries', () {
    test('שומר את ה-lineIndex המינימלי כשיש כפילויות כותרת', () {
      final entries = <migration_models.TocEntry>[
        const migration_models.TocEntry(
          bookId: 1,
          text: 'כפול',
          level: 1,
          lineIndex: 20,
        ),
        const migration_models.TocEntry(
          bookId: 1,
          text: 'כפול',
          level: 1,
          lineIndex: 5,
        ),
        const migration_models.TocEntry(
          bookId: 1,
          text: 'יחיד',
          level: 1,
          lineIndex: 100,
        ),
      ];

      final map = PdfHeadings.buildHeadingsMapFromTocEntries(entries);

      expect(map, {'כפול': 5, 'יחיד': 100});
    });

    test('מסנן entries עם טקסט ריק או lineIndex חסר', () {
      final entries = <migration_models.TocEntry>[
        const migration_models.TocEntry(
          bookId: 1,
          text: '',
          level: 1,
          lineIndex: 0,
        ),
        const migration_models.TocEntry(bookId: 1, text: 'בלי שורה', level: 1),
        const migration_models.TocEntry(
          bookId: 1,
          text: 'תקין',
          level: 1,
          lineIndex: 7,
        ),
      ];

      final map = PdfHeadings.buildHeadingsMapFromTocEntries(entries);

      expect(map, {'תקין': 7});
    });
  });
}
