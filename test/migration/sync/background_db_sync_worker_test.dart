import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/data_providers/database_library_provider.dart';
import 'package:otzaria/migration/models/book.dart';
import 'package:otzaria/migration/models/category.dart';
import 'package:otzaria/migration/database/daos/database.dart';
import 'package:otzaria/migration/database/repository/seforim_repository.dart';
import 'package:otzaria/migration/sync/background_db_sync_worker.dart';
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
      expect(books.first.filePath, isNull,
          reason: 'addToDatabase=true עבור txt → filePath חייב להיות null');
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
      expect(books.first.isFileBacked, isTrue,
          reason: 'addToDatabase=false → ספר חיצוני');
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
              path: f1, addToDatabase: false, addedAt: DateTime(2026, 1, 1)),
          CustomFolder(
              path: f2, addToDatabase: false, addedAt: DateTime(2026, 1, 1)),
        ],
      );

      expect(result.errors, isEmpty);
      expect(result.addedBooks, equals(2));
    });

    test(
        'יש קבצי links: prepareForWrite/restoreAfterWrite נקראים *בתוך* יחידת '
        'התור, סביב הכתיבה (תיקון מסך עיון/תצוגה מקדימה ריקים)', () async {
      final folderPath = await makeFolder('תיקייה-hooks', 'ספר-hooks');
      // קובץ links כלשהו מפעיל את שלב הכתיבה ל-seforim.db (ולכן את ה-hooks).
      await File(p.join(libPath(), 'links', 'ספר-hooks_links.json'))
          .create(recursive: true)
          .then((f) => f.writeAsString('[]', flush: true));
      final events = <String>[];

      final result = await runCustomFoldersDbSyncInIsolate(
        dbPath: dbPath,
        userBooksDbPath: userBooksDbPath,
        libraryPath: libPath(),
        customFolders: [
          CustomFolder(
              path: folderPath,
              addToDatabase: false,
              addedAt: DateTime(2026, 1, 1)),
        ],
        prepareForWrite: () async => events.add('prepare'),
        restoreAfterWrite: () async => events.add('restore'),
      );

      expect(result.errors, isEmpty);
      // prepare לפני הכתיבה, restore אחריה (ב-finally) — שניהם רצים, בסדר הזה.
      // כך ה-RO נסגר רק למשך הכתיבה ותמיד נפתח מחדש (גם בכשל).
      expect(events, equals(['prepare', 'restore']));
    });

    test(
        'אין קבצי links: שלב הכתיבה ל-seforim.db מדולג וה-hooks לא נקראים '
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
              addedAt: DateTime(2026, 1, 1)),
        ],
        prepareForWrite: () async => events.add('prepare'),
        restoreAfterWrite: () async => events.add('restore'),
      );

      expect(result.errors, isEmpty);
      expect(events, isEmpty,
          reason: 'בלי קבצי links אין כתיבה ל-seforim.db → ה-RO לא נסגר');
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
          userBooksDbPath:
              p.join(tempDir.path, 'nonexistent-dir', 'broken_user.db'),
          libraryPath: libPath(),
          customFolders: const [],
          prepareForWrite: () async => events.add('prepare'),
          restoreAfterWrite: () async => events.add('restore'),
        ),
        throwsA(anything),
      );

      expect(events, isEmpty,
          reason: 'שלב הספרים-האישיים לא סוגר RO — הכשל לא מפעיל את ה-hooks');
    });
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
      final sourceId =
          await userBooksRepository.insertSource('Personal::test', -1);
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

      expect(await userBooksRepository.getCategory(folderCatId), isNull,
          reason: 'קטגוריית התיקייה נמחקה');
      expect(await userBooksRepository.getBooksByCategory(folderCatId), isEmpty,
          reason: 'ספרי התיקייה נמחקו');
    });

    test('מנקה קטגוריית-אב ריקה לאחר המחיקה', () async {
      final personalCatId = await userBooksRepository.insertCategory(
        const Category(title: 'ספרים אישיים'),
      );
      final folderCatId = await userBooksRepository.insertCategory(
        Category(title: 'תיקייה-יחידה', parentId: personalCatId, level: 1),
      );
      // שם ה-source חייב להתאים ל-_buildCustomFolderSourceName('sole').
      final sourceId =
          await userBooksRepository.insertSource('Personal::sole', -1);
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

      expect(await userBooksRepository.getCategory(personalCatId), isNull,
          reason: '"ספרים אישיים" ריקה — חייבת להינקות');
    });
  });

  // ── serialization ─────────────────────────────────────────────────────────

  group('סריאליזציה דרך operationQueue', () {
    test('busyCount עולה מיד ויורד לאחר סיום', () async {
      final folderPath = await makeFolder('תיקייה-ס', 'ספר-ס');

      expect(DatabaseLibraryProvider.operationQueue.busyCount.value, 0,
          reason: 'queue פנוי לפני הקריאה');

      final future = runCustomFoldersDbSyncInIsolate(
        dbPath: dbPath,
        userBooksDbPath: userBooksDbPath,
        libraryPath: libPath(),
        customFolders: [
          CustomFolder(
              path: folderPath,
              addToDatabase: false,
              addedAt: DateTime(2026, 1, 1)),
        ],
      );

      // enqueue increments busyCount synchronously before any await
      expect(
        DatabaseLibraryProvider.operationQueue.busyCount.value,
        greaterThan(0),
        reason: 'busyCount עולה מיד עם ה-enqueue',
      );

      await future;

      expect(DatabaseLibraryProvider.operationQueue.busyCount.value, 0,
          reason: 'busyCount חוזר ל-0 לאחר סיום');
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
              path: f1, addToDatabase: false, addedAt: DateTime(2026, 1, 1)),
        ],
      );
      final future2 = runCustomFoldersDbSyncInIsolate(
        dbPath: dbPath,
        userBooksDbPath: userBooksDbPath,
        libraryPath: libPath(),
        customFolders: [
          CustomFolder(
              path: f2, addToDatabase: false, addedAt: DateTime(2026, 1, 1)),
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
