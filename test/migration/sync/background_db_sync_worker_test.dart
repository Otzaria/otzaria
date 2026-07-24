import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/data_providers/database_library_provider.dart';
import 'package:otzaria/migration/models/book.dart';
import 'package:otzaria/migration/models/category.dart';
import 'package:otzaria/migration/database/daos/database.dart';
import 'package:otzaria/migration/database/repository/seforim_repository.dart';
import 'package:otzaria/migration/sync/background_db_sync_worker.dart';
import 'package:otzaria/migration/sync/file_sync_service.dart';
import 'package:otzaria/settings/services/custom_folders/custom_folder.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late String dbPath;
  late String userBooksDbPath;
  late MyDatabase database;
  late MyDatabase userBooksDatabase;
  late SeforimRepository repository;
  late SeforimRepository userBooksRepository;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('otzaria-worker-test-');
    dbPath = p.join(tempDir.path, 'test.db');
    userBooksDbPath = p.join(tempDir.path, 'user_books.db');

    database = MyDatabase.withPath(dbPath);
    repository = SeforimRepository(database);
    await repository.ensureInitialized();

    userBooksDatabase = MyDatabase.withPath(userBooksDbPath);
    userBooksRepository = SeforimRepository(userBooksDatabase);
    await userBooksRepository.ensureInitialized();
  });

  tearDown(() async {
    database.close();
    userBooksDatabase.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  // ── helpers ───────────────────────────────────────────────────────────────

  /// Returns the library path used in all sync calls.
  String libPath() => p.join(tempDir.path, 'library');

  /// Creates library/אוצריא and a custom folder containing one txt file.
  /// Returns the folder path.
  Future<String> makeFolder(String folderName, String bookTitle) async {
    final folderPath = p.join(tempDir.path, folderName);
    await Directory(p.join(libPath(), 'אוצריא')).create(recursive: true);
    await Directory(folderPath).create(recursive: true);
    await File(p.join(folderPath, '$bookTitle.txt')).writeAsString(
      '\n<h1>פרק א</h1>\nשורת תוכן ראשונה\n',
      flush: true,
    );
    return folderPath;
  }

  // ── sync worker ───────────────────────────────────────────────────────────

  group('runCustomFoldersDbSyncInIsolate', () {
    test('addToDatabase=true: ספר נוצר ב-DB עם filePath=null', () async {
      final folderPath = await makeFolder('תיקייה-א', 'ספר-א');

      final result = await runCustomFoldersDbSyncInIsolate(
        dbPath: dbPath,
        userBooksDbPath: userBooksDbPath,
        libraryPath: libPath(),
        customFolders: [
          CustomFolder(
            path: folderPath,
            addToDatabase: true,
            addedAt: DateTime(2026, 1, 1),
          ),
        ],
      );

      expect(result.errors, isEmpty, reason: 'אין שגיאות');
      expect(result.addedBooks, greaterThan(0), reason: 'ספר נוסף');

      final personalCat = (await userBooksRepository.getRootCategories())
          .where((c) => c.title == 'ספרים אישיים')
          .firstOrNull;
      expect(personalCat, isNotNull);

      final folderCat = await userBooksRepository.getCategoryByTitleAndParent(
        p.basename(folderPath),
        personalCat!.id,
      );
      expect(folderCat, isNotNull);

      final books = await userBooksRepository.getBooksByCategory(folderCat!.id);
      expect(books, hasLength(1));
      expect(books.first.title, 'ספר-א');
      // txt + addToDatabase=true → content stored in DB → generator nulls filePath
      expect(
        books.first.filePath,
        isNull,
        reason: 'addToDatabase=true עבור txt → filePath חייב להיות null',
      );
    });

    test('addToDatabase=false: ספר נשמר כ-file-backed', () async {
      final folderPath = await makeFolder('תיקייה-ב', 'ספר-ב');

      final result = await runCustomFoldersDbSyncInIsolate(
        dbPath: dbPath,
        userBooksDbPath: userBooksDbPath,
        libraryPath: libPath(),
        customFolders: [
          CustomFolder(
            path: folderPath,
            addToDatabase: false,
            addedAt: DateTime(2026, 1, 1),
          ),
        ],
      );

      expect(result.errors, isEmpty);

      final personalCat = (await userBooksRepository.getRootCategories())
          .where((c) => c.title == 'ספרים אישיים')
          .firstOrNull;
      final folderCat = await userBooksRepository.getCategoryByTitleAndParent(
        p.basename(folderPath),
        personalCat!.id,
      );
      final books = await userBooksRepository.getBooksByCategory(folderCat!.id);
      expect(
        books.first.isFileBacked,
        isTrue,
        reason: 'addToDatabase=false → ספר חיצוני',
      );
    });

    test('סנכרון תיקייה פעמיים אינו מכפיל ספר '
        '(existence check מול user_books, לא seforim)', () async {
      final folderPath = await makeFolder('תיקייה-dup', 'ספר-dup');
      final folders = [
        CustomFolder(
          path: folderPath,
          addToDatabase: true,
          addedAt: DateTime(2026, 1, 1),
        ),
      ];

      await runCustomFoldersDbSyncInIsolate(
        dbPath: dbPath,
        userBooksDbPath: userBooksDbPath,
        libraryPath: libPath(),
        customFolders: folders,
      );
      // סנכרון שני: ה-existence check חייב למצוא את הספר ב-user_books ולא
      // להוסיף כפיל (לפני התיקון הבדיקה פנתה ל-seforim ולא מצאה אותו).
      await runCustomFoldersDbSyncInIsolate(
        dbPath: dbPath,
        userBooksDbPath: userBooksDbPath,
        libraryPath: libPath(),
        customFolders: folders,
      );

      final personalCat = (await userBooksRepository.getRootCategories())
          .firstWhere((c) => c.title == 'ספרים אישיים');
      final folderCat = await userBooksRepository.getCategoryByTitleAndParent(
        p.basename(folderPath),
        personalCat.id,
      );
      final books = await userBooksRepository.getBooksByCategory(folderCat!.id);
      expect(
        books,
        hasLength(1),
        reason: 'סנכרון חוזר לא מכפיל — הספר נמצא דרך user_books',
      );
    });

    test('שתי תיקיות באותו worker: שני ספרים נוצרים', () async {
      final f1 = await makeFolder('תיקייה-c1', 'ספר-c1');
      final f2 = await makeFolder('תיקייה-c2', 'ספר-c2');

      final result = await runCustomFoldersDbSyncInIsolate(
        dbPath: dbPath,
        userBooksDbPath: userBooksDbPath,
        libraryPath: libPath(),
        customFolders: [
          CustomFolder(
            path: f1,
            addToDatabase: false,
            addedAt: DateTime(2026, 1, 1),
          ),
          CustomFolder(
            path: f2,
            addToDatabase: false,
            addedAt: DateTime(2026, 1, 1),
          ),
        ],
      );

      expect(result.errors, isEmpty);
      expect(result.addedBooks, equals(2));
    });

    test('onlyFolderPath: רק התיקייה הממוקדת נסרקת, וספרי תיקייה אחרת '
        'שכבר ב-DB אינם נמחקים', () async {
      final f1 = await makeFolder('ממוקדת-א', 'ספר-א');
      final f2 = await makeFolder('ממוקדת-ב', 'ספר-ב');
      final folders = [
        CustomFolder(
          path: f1,
          addToDatabase: false,
          addedAt: DateTime(2026, 1, 1),
        ),
        CustomFolder(
          path: f2,
          addToDatabase: false,
          addedAt: DateTime(2026, 1, 1),
        ),
      ];

      // סנכרון מלא ראשון — שתי התיקיות נכנסות ל-DB.
      await runCustomFoldersDbSyncInIsolate(
        dbPath: dbPath,
        userBooksDbPath: userBooksDbPath,
        libraryPath: libPath(),
        customFolders: folders,
      );

      // ספר חדש בשתי התיקיות; סריקה ממוקדת של f1 בלבד.
      await File(p.join(f1, 'ספר-א2.txt')).writeAsString('תוכן', flush: true);
      await File(p.join(f2, 'ספר-ב2.txt')).writeAsString('תוכן', flush: true);

      final scoped = await runCustomFoldersDbSyncInIsolate(
        dbPath: dbPath,
        userBooksDbPath: userBooksDbPath,
        libraryPath: libPath(),
        customFolders: folders,
        onlyFolderPath: f1,
      );

      expect(scoped.errors, isEmpty);
      expect(
        scoped.addedBooks,
        equals(1),
        reason: 'רק הספר החדש בתיקייה הממוקדת נוסף',
      );

      // ספרי התיקייה השנייה נשארו ב-DB (לא נמחקו כ"תיקייה שהוסרה").
      final personalCat = (await userBooksRepository.getRootCategories())
          .firstWhere((c) => c.title == 'ספרים אישיים');
      final f2Cat = await userBooksRepository.getCategoryByTitleAndParent(
        p.basename(f2),
        personalCat.id,
      );
      expect(f2Cat, isNotNull);
      final f2Books = await userBooksRepository.getBooksByCategory(f2Cat!.id);
      expect(f2Books, hasLength(1), reason: 'ספרי התיקייה השנייה שרדו');
    });

    test('יש קבצי links: prepareForWrite/restoreAfterWrite נקראים *בתוך* יחידת '
        'התור, סביב הכתיבה (תיקון מסך עיון/תצוגה מקדימה ריקים)', () async {
      final folderPath = await makeFolder('תיקייה-hooks', 'ספר-hooks');
      // קובץ links כלשהו מפעיל את שלב הכתיבה ל-seforim.db (ולכן את ה-hooks).
      await File(
        p.join(libPath(), 'links', 'ספר-hooks_links.json'),
      ).create(recursive: true).then((f) => f.writeAsString('[]', flush: true));
      final events = <String>[];

      final result = await runCustomFoldersDbSyncInIsolate(
        dbPath: dbPath,
        userBooksDbPath: userBooksDbPath,
        libraryPath: libPath(),
        customFolders: [
          CustomFolder(
            path: folderPath,
            addToDatabase: false,
            addedAt: DateTime(2026, 1, 1),
          ),
        ],
        prepareForWrite: () async => events.add('prepare'),
        restoreAfterWrite: () async => events.add('restore'),
      );

      expect(result.errors, isEmpty);
      // prepare לפני הכתיבה, restore אחריה (ב-finally) — שניהם רצים, בסדר הזה.
      // כך ה-RO נסגר רק למשך הכתיבה ותמיד נפתח מחדש (גם בכשל).
      expect(events, equals(['prepare', 'restore']));
    });

    test('אין קבצי links: שלב הכתיבה ל-seforim.db מדולג וה-hooks לא נקראים '
        '(ה-RO לא נסגר בעלייה רגילה)', () async {
      final folderPath = await makeFolder('תיקייה-no-links', 'ספר-no-links');
      final events = <String>[];

      final result = await runCustomFoldersDbSyncInIsolate(
        dbPath: dbPath,
        userBooksDbPath: userBooksDbPath,
        libraryPath: libPath(),
        customFolders: [
          CustomFolder(
            path: folderPath,
            addToDatabase: false,
            addedAt: DateTime(2026, 1, 1),
          ),
        ],
        prepareForWrite: () async => events.add('prepare'),
        restoreAfterWrite: () async => events.add('restore'),
      );

      expect(result.errors, isEmpty);
      expect(
        events,
        isEmpty,
        reason: 'בלי קבצי links אין כתיבה ל-seforim.db → ה-RO לא נסגר',
      );
    });

    test(
      'כשל בשלב הספרים-האישיים אינו סוגר את ה-RO (ה-hooks לא נקראים — אין דליפה)',
      () async {
        final events = <String>[];

        // נתיב DB לא תקין מפיל את שלב הספרים-האישיים (פתיחת seforim.db נכשלת).
        // שלב זה רץ עם seforim.db RO וללא prepare/restore — ולכן כשל בו *לא*
        // סוגר את ה-RO הראשי: ה-hooks לא נקראים כלל. כך אין דליפת write-session
        // גם כשהשלב הכבד נכשל.
        await expectLater(
          runCustomFoldersDbSyncInIsolate(
            dbPath: p.join(tempDir.path, 'nonexistent-dir', 'broken.db'),
            userBooksDbPath: p.join(
              tempDir.path,
              'nonexistent-dir',
              'broken_user.db',
            ),
            libraryPath: libPath(),
            customFolders: const [],
            prepareForWrite: () async => events.add('prepare'),
            restoreAfterWrite: () async => events.add('restore'),
          ),
          throwsA(anything),
        );

        expect(
          events,
          isEmpty,
          reason: 'שלב הספרים-האישיים לא סוגר RO — הכשל לא מפעיל את ה-hooks',
        );
      },
    );
  });

  // ── delete worker ─────────────────────────────────────────────────────────

  group('runDeleteFolderFromDbInIsolate', () {
    test('מוחק קטגוריית תיקייה וספריה', () async {
      final personalCatId = await userBooksRepository.insertCategory(
        const Category(title: 'ספרים אישיים'),
      );
      final folderCatId = await userBooksRepository.insertCategory(
        Category(title: 'תיקיית-מחיקה', parentId: personalCatId, level: 1),
      );
      // שם ה-source חייב להתאים ל-_buildCustomFolderSourceName('test').
      final sourceId = await userBooksRepository.insertSource(
        'Personal::test',
        -1,
      );
      await userBooksRepository.insertBook(
        Book(
          id: 0, // SQLite מקצה דרך AUTOINCREMENT
          categoryId: folderCatId,
          sourceId: sourceId,
          title: 'ספר למחיקה',
          isPersonal: true,
          fileType: 'txt',
        ),
      );
      await userBooksRepository.rebuildCategoryClosure();

      await runDeleteFolderFromDbInIsolate(
        dbPath: dbPath,
        userBooksDbPath: userBooksDbPath,
        folderPath: 'test',
      );

      expect(
        await userBooksRepository.getCategory(folderCatId),
        isNull,
        reason: 'קטגוריית התיקייה נמחקה',
      );
      expect(
        await userBooksRepository.getBooksByCategory(folderCatId),
        isEmpty,
        reason: 'ספרי התיקייה נמחקו',
      );
    });

    test('מנקה קטגוריית-אב ריקה לאחר המחיקה', () async {
      final personalCatId = await userBooksRepository.insertCategory(
        const Category(title: 'ספרים אישיים'),
      );
      final folderCatId = await userBooksRepository.insertCategory(
        Category(title: 'תיקייה-יחידה', parentId: personalCatId, level: 1),
      );
      // שם ה-source חייב להתאים ל-_buildCustomFolderSourceName('sole').
      final sourceId = await userBooksRepository.insertSource(
        'Personal::sole',
        -1,
      );
      await userBooksRepository.insertBook(
        Book(
          id: 0, // SQLite מקצה דרך AUTOINCREMENT
          categoryId: folderCatId,
          sourceId: sourceId,
          title: 'ספר יחיד',
          isPersonal: true,
          fileType: 'txt',
        ),
      );
      await userBooksRepository.rebuildCategoryClosure();

      await runDeleteFolderFromDbInIsolate(
        dbPath: dbPath,
        userBooksDbPath: userBooksDbPath,
        folderPath: 'sole',
      );

      expect(
        await userBooksRepository.getCategory(personalCatId),
        isNull,
        reason: '"ספרים אישיים" ריקה — חייבת להינקות',
      );
    });

    test('מחיקת תיקייה מצליחה גם כש-seforim.db פתוח read-only '
        '(חוזה: המחיקה לא כותבת ל-DB הרשמי)', () async {
      // seforim.db read-only: יוצרים סכמה, ממירים ל-DELETE (תנאי לפתיחת RO),
      // וסוגרים. אם המחיקה תנסה לכתוב לשם — החיבור ה-RO יזרוק.
      final roPath = p.join(tempDir.path, 'seforim_ro.db');
      final tmpDb = MyDatabase.withPath(roPath);
      final tmpRepo = SeforimRepository(tmpDb);
      await tmpRepo.ensureInitialized();
      await tmpRepo.setJournalMode('DELETE');
      tmpDb.close();

      final roDb = MyDatabase.withPath(roPath, readOnly: true);
      final roRepo = SeforimRepository(roDb);
      await roRepo.ensureInitialized();

      // ספר אישי לתיקייה 'ro' ב-user_books (כתיב).
      final personalCatId = await userBooksRepository.insertCategory(
        const Category(title: 'ספרים אישיים'),
      );
      final folderCatId = await userBooksRepository.insertCategory(
        Category(title: 'תיקיית-ro', parentId: personalCatId, level: 1),
      );
      final sourceId = await userBooksRepository.insertSource(
        'Personal::ro',
        -1,
      );
      await userBooksRepository.insertBook(
        Book(
          id: 0,
          categoryId: folderCatId,
          sourceId: sourceId,
          title: 'ספר ro',
          isPersonal: true,
          fileType: 'txt',
        ),
      );
      await userBooksRepository.rebuildCategoryClosure();

      final service = FileSyncService.createForWorker(
        roRepo,
        userBooksRepository: userBooksRepository,
      );

      try {
        // לא אמור לזרוק — כל הכתיבה ל-user_books בלבד.
        await service.deleteFolderFromDatabase('ro');

        expect(
          await userBooksRepository.getCategory(folderCatId),
          isNull,
          reason: 'ספרי התיקייה נמחקו מ-user_books',
        );
      } finally {
        roDb.close();
      }
    });
  });

  // ── serialization ─────────────────────────────────────────────────────────

  group('סריאליזציה דרך operationQueue', () {
    test('busyCount עולה מיד ויורד לאחר סיום', () async {
      final folderPath = await makeFolder('תיקייה-ס', 'ספר-ס');

      expect(
        DatabaseLibraryProvider.operationQueue.busyCount.value,
        0,
        reason: 'queue פנוי לפני הקריאה',
      );

      final future = runCustomFoldersDbSyncInIsolate(
        dbPath: dbPath,
        userBooksDbPath: userBooksDbPath,
        libraryPath: libPath(),
        customFolders: [
          CustomFolder(
            path: folderPath,
            addToDatabase: false,
            addedAt: DateTime(2026, 1, 1),
          ),
        ],
      );

      // enqueue increments busyCount synchronously before any await
      expect(
        DatabaseLibraryProvider.operationQueue.busyCount.value,
        greaterThan(0),
        reason: 'busyCount עולה מיד עם ה-enqueue',
      );

      await future;

      expect(
        DatabaseLibraryProvider.operationQueue.busyCount.value,
        0,
        reason: 'busyCount חוזר ל-0 לאחר סיום',
      );
    });

    test('שתי קריאות מקבילות: אין שגיאות DB ושני ספרים נוצרים', () async {
      final f1 = await makeFolder('ס-1', 'ספר-ס1');
      final f2 = await makeFolder('ס-2', 'ספר-ס2');

      // Fire both without awaiting — queue serialises them automatically.
      final future1 = runCustomFoldersDbSyncInIsolate(
        dbPath: dbPath,
        userBooksDbPath: userBooksDbPath,
        libraryPath: libPath(),
        customFolders: [
          CustomFolder(
            path: f1,
            addToDatabase: false,
            addedAt: DateTime(2026, 1, 1),
          ),
        ],
      );
      final future2 = runCustomFoldersDbSyncInIsolate(
        dbPath: dbPath,
        userBooksDbPath: userBooksDbPath,
        libraryPath: libPath(),
        customFolders: [
          CustomFolder(
            path: f2,
            addToDatabase: false,
            addedAt: DateTime(2026, 1, 1),
          ),
        ],
      );

      final results = await Future.wait([future1, future2]);

      for (final r in results) {
        expect(
          r.errors.where((e) => e.contains('Sync already in progress')),
          isEmpty,
          reason: '"Sync already in progress" מוכיח שה-queue לא עובד',
        );
      }

      final total = results.fold<int>(0, (sum, r) => sum + r.addedBooks);
      expect(total, equals(2), reason: 'כל worker הוסיף ספר אחד');
    });
  });
}
