import 'dart:io';

import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/migration/models/book.dart';
import 'package:otzaria/migration/models/category.dart';
import 'package:otzaria/migration/database/daos/database.dart';
import 'package:otzaria/migration/database/repository/seforim_repository.dart';
import 'package:otzaria/migration/sync/file_sync_service.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/settings/services/custom_folders/custom_folder.dart';
import 'package:path/path.dart' as path;

String _sourceNameForFolder(String folderPath) {
  final normalized = path.normalize(folderPath);
  final key = Platform.isWindows ? normalized.toLowerCase() : normalized;
  return 'Personal::$key';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late MyDatabase database;
  late SeforimRepository repository;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp(
      'otzaria-file-sync-prune-test-',
    );
    await Settings.init(cacheProvider: _MemoryCacheProvider());
    // מאפסים את הסינגלטון של FileSyncService כדי שלא יחזיק repository
    // מ-tempDir של טסט קודם (שכבר נסגר).
    FileSyncService.resetSingletonForTesting();
    database = MyDatabase.withPath(path.join(tempDir.path, 'test.db'));
    repository = SeforimRepository(database);
    await repository.ensureInitialized();
    // הטסט בודק לוגיקת prune של תיקיות מותאמות בלבד, ולכן אותו DB משמש גם
    // כ-seforim (dedup) וגם כ-user_books (יעד הכתיבה) — בפרודקשן הם נפרדים.
  });

  tearDown(() async {
    database.close();
    FileSyncService.resetSingletonForTesting();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('syncFiles לא מוחק תיקייה מותאמת חדשה עם ספר ברמת השורש', () async {
    final libraryPath = path.join(tempDir.path, 'library');
    final customFolderPath = path.join(tempDir.path, 'היברו');
    await Directory(libraryPath).create(recursive: true);
    await Directory(path.join(libraryPath, 'אוצריא')).create(recursive: true);
    await Directory(customFolderPath).create(recursive: true);
    await File(
      path.join(customFolderPath, 'ספר חדש.txt'),
    ).writeAsString('תוכן');

    await Settings.setValue<String>(
      SettingsRepository.keyLibraryPath,
      libraryPath,
    );
    await Settings.setValue<String>(
      SettingsRepository.keyCustomFolders,
      CustomFoldersManager.saveFolders([
        CustomFolder(
          path: customFolderPath,
          addToDatabase: true,
          addedAt: DateTime(2026, 4, 13),
        ),
      ]),
    );

    final service = await FileSyncService.getInstance(
      repository,
      userBooksRepository: repository,
    );
    final result = await service!.syncFiles();

    final personalCategory = (await repository.getRootCategories())
        .where((category) => category.title == 'ספרים אישיים')
        .firstOrNull;
    expect(personalCategory, isNotNull);

    final customCategory = await repository.getCategoryByTitleAndParent(
      'היברו',
      personalCategory!.id,
    );
    expect(customCategory, isNotNull);

    final books = await repository.getBooksByCategory(customCategory!.id);
    expect(books.map((book) => book.title), ['ספר חדש']);
    expect(result.errors, isEmpty);
  });

  test(
    'רענון מוחק ספר "קריאה מהקבצים" שקובצו נמחק, ומשאיר "עותק עצמאי"',
    () async {
      final libraryPath = path.join(tempDir.path, 'library');
      // שתי תיקיות: אחת file-backed (קריאה מהקבצים) ואחת content-in-db
      // (עותק עצמאי), כדי לבדוק את שתי ההתנהגויות הנגדיות באותו רענון.
      final fileBackedDir = path.join(tempDir.path, 'מהקבצים');
      final inDbDir = path.join(tempDir.path, 'בתוכנה');
      await Directory(path.join(libraryPath, 'אוצריא')).create(recursive: true);
      await Directory(fileBackedDir).create(recursive: true);
      await Directory(inDbDir).create(recursive: true);
      final fileBackedFile = File(path.join(fileBackedDir, 'ספר מקובץ.txt'));
      final inDbFile = File(path.join(inDbDir, 'ספר עצמאי.txt'));
      await fileBackedFile.writeAsString('תוכן מקובץ');
      await inDbFile.writeAsString('תוכן עצמאי');

      await Settings.setValue<String>(
        SettingsRepository.keyLibraryPath,
        libraryPath,
      );
      await Settings.setValue<String>(
        SettingsRepository.keyCustomFolders,
        CustomFoldersManager.saveFolders([
          CustomFolder(
            path: fileBackedDir,
            addToDatabase: false, // קריאה מהקבצים — תלוי בקובץ
            addedAt: DateTime(2026, 4, 13),
          ),
          CustomFolder(
            path: inDbDir,
            addToDatabase: true, // עותק עצמאי — שורד מחיקת קובץ
            addedAt: DateTime(2026, 4, 13),
          ),
        ]),
      );

      final service = await FileSyncService.getInstance(
        repository,
        userBooksRepository: repository,
      );

      // סריקה ראשונה — שני הספרים נכנסים ל-DB.
      await service!.syncFiles();

      final personalCategory = (await repository.getRootCategories())
          .where((category) => category.title == 'ספרים אישיים')
          .first;
      final fileBackedCat = await repository.getCategoryByTitleAndParent(
        'מהקבצים',
        personalCategory.id,
      );
      final inDbCat = await repository.getCategoryByTitleAndParent(
        'בתוכנה',
        personalCategory.id,
      );
      expect(
        await repository.getBooksByCategory(fileBackedCat!.id),
        isNotEmpty,
      );
      expect(await repository.getBooksByCategory(inDbCat!.id), isNotEmpty);

      // מוחקים את שני הקבצים מהדיסק וסורקים מחדש.
      await fileBackedFile.delete();
      await inDbFile.delete();
      await service.syncFiles();

      expect(
        await repository.getBooksByCategory(fileBackedCat.id),
        isEmpty,
        reason: 'ספר "קריאה מהקבצים" תלוי בקובץ — נמחק כשהקובץ נעלם',
      );
      expect(
        (await repository.getBooksByCategory(
          inDbCat.id,
        )).map((book) => book.title),
        ['ספר עצמאי'],
        reason: 'ספר "עותק עצמאי" שורד מחיקת קובץ — נמחק רק דרך הספרייה',
      );
    },
  );

  test(
    'רענון לא פוגע בספרי תיקייה אחרת בעלת אותו basename (זיהוי לפי source)',
    () async {
      final libraryPath = path.join(tempDir.path, 'library');
      // שתי תיקיות שונות עם אותו basename "shared" — ממוזגות לאותה קטגוריה.
      final alphaShared = path.join(tempDir.path, 'alpha', 'shared');
      final betaShared = path.join(tempDir.path, 'beta', 'shared');
      await Directory(path.join(libraryPath, 'אוצריא')).create(recursive: true);
      await Directory(alphaShared).create(recursive: true);
      await Directory(betaShared).create(recursive: true);
      final alphaFile = File(path.join(alphaShared, 'ספר אלפא.txt'));
      await alphaFile.writeAsString('תוכן אלפא');
      await File(
        path.join(betaShared, 'ספר בטא.txt'),
      ).writeAsString('תוכן בטא');

      await Settings.setValue<String>(
        SettingsRepository.keyLibraryPath,
        libraryPath,
      );
      await Settings.setValue<String>(
        SettingsRepository.keyCustomFolders,
        CustomFoldersManager.saveFolders([
          // file-backed (קריאה מהקבצים) — כדי שמחיקת הקובץ תפעיל prune.
          CustomFolder(
            path: alphaShared,
            addToDatabase: false,
            addedAt: DateTime(2026, 4, 13),
          ),
          CustomFolder(
            path: betaShared,
            addToDatabase: false,
            addedAt: DateTime(2026, 4, 13),
          ),
        ]),
      );

      final service = await FileSyncService.getInstance(
        repository,
        userBooksRepository: repository,
      );
      await service!.syncFiles();

      final personalCategory = (await repository.getRootCategories())
          .where((category) => category.title == 'ספרים אישיים')
          .first;
      final sharedCategory = await repository.getCategoryByTitleAndParent(
        'shared',
        personalCategory.id,
      );
      // שני הספרים יושבים תחת אותה קטגוריה "shared".
      var books = await repository.getBooksByCategory(sharedCategory!.id);
      expect(books.map((book) => book.title).toSet(), {'ספר אלפא', 'ספר בטא'});

      // מוחקים את הקובץ של alpha בלבד וסורקים מחדש.
      await alphaFile.delete();
      await service.syncFiles();

      books = await repository.getBooksByCategory(sharedCategory.id);
      expect(
        books.map((book) => book.title),
        ['ספר בטא'],
        reason:
            'prune של alpha הסיר רק את ספרו, ולא פגע בספר של beta '
            'למרות אותו basename',
      );
    },
  );

  test('snapshot ישן לא מוחק ספר ששויך מחדש במהלך אותה סריקה', () async {
    final libraryPath = path.join(tempDir.path, 'library');
    final alphaShared = path.join(tempDir.path, 'alpha', 'shared');
    final betaShared = path.join(tempDir.path, 'beta', 'shared');
    await Directory(path.join(libraryPath, 'אוצריא')).create(recursive: true);
    await Directory(alphaShared).create(recursive: true);
    await Directory(betaShared).create(recursive: true);
    final alphaFile = File(path.join(alphaShared, 'ספר זהה.txt'));
    final betaFile = File(path.join(betaShared, 'ספר זהה.txt'));
    await alphaFile.writeAsString('תוכן אלפא');
    await betaFile.writeAsString('תוכן בטא');

    final folders = [
      CustomFolder(
        path: alphaShared,
        addToDatabase: false,
        addedAt: DateTime(2026, 4, 13),
      ),
      CustomFolder(
        path: betaShared,
        addToDatabase: false,
        addedAt: DateTime(2026, 4, 13),
      ),
    ];
    await Settings.setValue<String>(
      SettingsRepository.keyLibraryPath,
      libraryPath,
    );
    await Settings.setValue<String>(
      SettingsRepository.keyCustomFolders,
      CustomFoldersManager.saveFolders(folders),
    );

    final service = await FileSyncService.getInstance(
      repository,
      userBooksRepository: repository,
    );
    await service!.syncFiles();

    // בסריקה הראשונה הרשומה המשותפת שויכה לתיקייה השנייה. לאחר שקובץ beta
    // נעלם, סריקת alpha משייכת אותה מחדש ל-alpha; ה-prune של beta חייב לקרוא
    // את ה-source העדכני ולא למחוק לפי ה-snapshot שנבנה בתחילת הסריקה.
    await betaFile.delete();
    await service.syncFiles();

    final personalCategory = (await repository.getRootCategories())
        .where((category) => category.title == 'ספרים אישיים')
        .first;
    final sharedCategory = await repository.getCategoryByTitleAndParent(
      'shared',
      personalCategory.id,
    );
    final books = await repository.getBooksByCategory(sharedCategory!.id);
    expect(books.map((book) => book.title), ['ספר זהה']);
    expect(books.single.filePath, alphaFile.path);
    expect(
      (await repository.getSourceById(books.single.sourceId))?.name,
      _sourceNameForFolder(alphaShared),
    );
  });

  test(
    'pruneRemovedCustomFoldersFromDatabase משאיר תיקייה פעילה בלי filePath ומוחק ישנה',
    () async {
      final activeFolderPath = path.join(tempDir.path, 'active-folder');
      final removedFolderPath = path.join(tempDir.path, 'removed-folder');
      final personalCategoryId = await repository.insertCategory(
        const Category(title: 'ספרים אישיים'),
      );
      final activeCategoryId = await repository.insertCategory(
        Category(
          title: 'active-folder',
          parentId: personalCategoryId,
          level: 1,
        ),
      );
      final staleCategoryId = await repository.insertCategory(
        Category(
          title: 'removed-folder',
          parentId: personalCategoryId,
          level: 1,
        ),
      );
      final activeSourceId = await repository.insertSource(
        _sourceNameForFolder(activeFolderPath),
        -1,
      );
      final staleSourceId = await repository.insertSource(
        _sourceNameForFolder(removedFolderPath),
        -1,
      );

      await repository.insertBook(
        Book(
          id: 0,
          categoryId: activeCategoryId,
          sourceId: activeSourceId,
          title: 'ספר פעיל',
          isPersonal: true,
          fileType: 'txt',
          filePath: null,
        ),
      );
      await repository.insertBook(
        Book(
          id: 0,
          categoryId: staleCategoryId,
          sourceId: staleSourceId,
          title: 'ספר ישן',
          isPersonal: true,
          fileType: 'txt',
          filePath: null,
        ),
      );
      await repository.rebuildCategoryClosure();

      final service = await FileSyncService.getInstance(
        repository,
        userBooksRepository: repository,
      );

      await service!.pruneRemovedCustomFoldersFromDatabase([
        CustomFolder(
          path: activeFolderPath,
          addToDatabase: true,
          addedAt: DateTime(2026, 4, 13),
        ),
      ]);

      final personalChildren = await repository.getCategoryChildren(
        personalCategoryId,
      );
      final remainingTitles = personalChildren
          .map((category) => category.title)
          .toList();

      expect(remainingTitles, ['active-folder']);
      expect(await repository.getCategory(staleCategoryId), isNull);
      expect(await repository.getCategory(activeCategoryId), isNotNull);
    },
  );

  // Regression test for bug introduced in commit 72ca3b4aa:
  // When a folder was added via UI (custom_folders_panel.dart → _scanAndAddExternalBooks),
  // insertCategory was called without rebuildCategoryClosure.
  // Then RefreshLibrary → _pruneRemovedCustomFoldersIfNeeded ran immediately,
  // and _categoryBelongsToAnyConfiguredFolder returned false (empty closure table),
  // so the newly-added folder was deleted right away.
  // Fix: refreshSourcesAndPruneRemovedCustomFolders now calls rebuildCategoryClosure
  // before pruneRemovedCustomFoldersFromDatabase.
  test(
    'regression: refreshSourcesAndPruneRemovedCustomFolders לא מוחק תיקייה שנוספה דרך UI ללא rebuildCategoryClosure',
    () async {
      final activeFolderPath = path.join(tempDir.path, 'my-books');

      // מדמה את _getOrCreateCategoryInDb ב-database_library_provider.dart:
      // מוסיף קטגוריות עם insertCategory בלי לקרוא ל-rebuildCategoryClosure.
      final personalCategoryId = await repository.insertCategory(
        const Category(title: 'ספרים אישיים'),
      );
      final newCategoryId = await repository.insertCategory(
        Category(
          title: 'my-books',
          parentId: personalCategoryId,
          level: 1,
        ),
      );
      final sourceId = await repository.insertSource(
        _sourceNameForFolder(activeFolderPath),
        -1,
      );
      await repository.insertBook(
        Book(
          id: 0,
          categoryId: newCategoryId,
          sourceId: sourceId,
          title: 'ספר חדש',
          isPersonal: true,
          fileType: 'txt',
          filePath: path.join(activeFolderPath, 'ספר חדש.txt'),
        ),
      );

      // בכוונה לא קוראים ל-rebuildCategoryClosure לפני refreshSources,
      // בדיוק כמו שה-UI עושה: הוסיף תיקייה ואז מיד שלח RefreshLibrary.
      // לפני התיקון, prune היה מוחק את הקטגוריה כי category_closure ריק.

      final service = await FileSyncService.getInstance(
        repository,
        userBooksRepository: repository,
      );

      await service!.refreshSourcesAndPruneRemovedCustomFolders([
        CustomFolder(
          path: activeFolderPath,
          addToDatabase: true,
          addedAt: DateTime(2026, 4, 17),
        ),
      ]);

      expect(
        await repository.getCategory(newCategoryId),
        isNotNull,
        reason:
            'תיקייה שנוספה דרך UI לא צריכה להימחק על ידי prune כי category_closure לא עודכן עדיין',
      );
      final books = await repository.getBooksByCategory(newCategoryId);
      expect(
        books,
        isNotEmpty,
        reason: 'ספרים בתיקייה שנוספה לא צריכים להימחק',
      );
    },
  );

  test(
    'regression: רענון מוחק ספר file-backed שתויג source="external" (מסלול ההוספה) לפי נתיב',
    () async {
      final libraryPath = path.join(tempDir.path, 'library');
      final folderPath = path.join(tempDir.path, 'תיקיית-הוספה');
      await Directory(path.join(libraryPath, 'אוצריא')).create(recursive: true);
      // התיקייה עדיין קיימת, אבל הקובץ נמחק — בדיוק כמו בדיווח.
      await Directory(folderPath).create(recursive: true);

      await Settings.setValue<String>(
        SettingsRepository.keyLibraryPath,
        libraryPath,
      );
      await Settings.setValue<String>(
        SettingsRepository.keyCustomFolders,
        CustomFoldersManager.saveFolders([
          CustomFolder(
            path: folderPath,
            addToDatabase: false,
            addedAt: DateTime(2026, 4, 13),
          ),
        ]),
      );

      // מדמה את מסלול ההוספה (scanAndAddExternalBooksFromFolder): ספר
      // file-backed המתויג בקטגוריה 'ספרים אישיים' > <שם התיקייה>, עם
      // source='external' (ולא 'Personal::<path>') ו-filePath בתוך התיקייה.
      final personalCategoryId = await repository.insertCategory(
        const Category(title: 'ספרים אישיים'),
      );
      final folderCategoryId = await repository.insertCategory(
        Category(
          title: path.basename(folderPath),
          parentId: personalCategoryId,
          level: 1,
        ),
      );
      final externalSourceId = await repository.insertSource('external', -1);
      await repository.insertBook(
        Book(
          id: 0,
          categoryId: folderCategoryId,
          sourceId: externalSourceId,
          title: 'ספר שקובצו נמחק',
          isPersonal: true,
          fileType: 'txt',
          filePath: path.join(folderPath, 'ספר שקובצו נמחק.txt'),
        ),
      );
      await repository.rebuildCategoryClosure();

      final service = await FileSyncService.getInstance(
        repository,
        userBooksRepository: repository,
      );
      await service!.syncFiles();

      expect(
        await repository.getBooksByCategory(folderCategoryId),
        isEmpty,
        reason:
            'ספר file-backed שתויג "external" וקובצו נמחק חייב להיות מוסר '
            'ברענון — הזיהוי לפי נתיב תופס אותו למרות ה-source השונה',
      );
    },
  );

  test(
    'regression: הסרת תיקיית-אב לא מוחקת ספרי תיקיית-בן מקוננת הרשומה בנפרד',
    () async {
      final parentPath = path.join(tempDir.path, 'אב');
      final childPath = path.join(parentPath, 'בן');

      final personalCategoryId = await repository.insertCategory(
        const Category(title: 'ספרים אישיים'),
      );
      final parentCategoryId = await repository.insertCategory(
        Category(title: 'אב', parentId: personalCategoryId, level: 1),
      );
      // הבן רשום בנפרד — קטגוריה אחות תחת "ספרים אישיים", לא תחת האב.
      final childCategoryId = await repository.insertCategory(
        Category(title: 'בן', parentId: personalCategoryId, level: 1),
      );
      final parentSourceId = await repository.insertSource(
        _sourceNameForFolder(parentPath),
        -1,
      );
      final childSourceId = await repository.insertSource(
        _sourceNameForFolder(childPath),
        -1,
      );

      await repository.insertBook(
        Book(
          id: 0,
          categoryId: parentCategoryId,
          sourceId: parentSourceId,
          title: 'ספר האב',
          isPersonal: true,
          fileType: 'txt',
          filePath: path.join(parentPath, 'ספר האב.txt'),
        ),
      );
      // נתיב הקובץ של הבן נמצא *בתוך* תיקיית האב — לכן זיהוי לפי נתיב לבדו
      // היה מוחק אותו בהסרת האב.
      await repository.insertBook(
        Book(
          id: 0,
          categoryId: childCategoryId,
          sourceId: childSourceId,
          title: 'ספר הבן',
          isPersonal: true,
          fileType: 'txt',
          filePath: path.join(childPath, 'ספר הבן.txt'),
        ),
      );
      await repository.rebuildCategoryClosure();

      final service = await FileSyncService.getInstance(
        repository,
        userBooksRepository: repository,
      );
      await service!.deleteFolderFromDatabase(parentPath);

      expect(
        await repository.getBooksByCategory(parentCategoryId),
        isEmpty,
        reason: 'ספר האב הוסר עם הסרת תיקיית האב',
      );
      expect(
        (await repository.getBooksByCategory(
          childCategoryId,
        )).map((book) => book.title),
        ['ספר הבן'],
        reason: 'ספר הבן מתויג ל-source של הבן — הסרת האב לא נוגעת בו',
      );
    },
  );

  test(
    'regression: הסרת תיקיית-אב legacy לא מוחקת ספרי תיקיית-בן שגם היא legacy',
    () async {
      final parentPath = path.join(tempDir.path, 'אב');
      final childPath = path.join(parentPath, 'בן');

      final personalCategoryId = await repository.insertCategory(
        const Category(title: 'ספרים אישיים'),
      );
      final parentCategoryId = await repository.insertCategory(
        Category(title: 'אב', parentId: personalCategoryId, level: 1),
      );
      final childCategoryId = await repository.insertCategory(
        Category(title: 'בן', parentId: personalCategoryId, level: 1),
      );
      // שתי התיקיות נוצרו לפני המעבר ל-Personal::<path> — כל ספריהן 'external',
      // כך שהשיוך לתיקייה נופל לזיהוי לפי נתיב בלבד.
      final externalSourceId = await repository.insertSource('external', -1);

      await repository.insertBook(
        Book(
          id: 0,
          categoryId: parentCategoryId,
          sourceId: externalSourceId,
          title: 'ספר האב',
          isPersonal: true,
          fileType: 'txt',
          filePath: path.join(parentPath, 'ספר האב.txt'),
        ),
      );
      await repository.insertBook(
        Book(
          id: 0,
          categoryId: childCategoryId,
          sourceId: externalSourceId,
          title: 'ספר הבן',
          isPersonal: true,
          fileType: 'txt',
          filePath: path.join(childPath, 'ספר הבן.txt'),
        ),
      );
      await repository.rebuildCategoryClosure();

      final service = await FileSyncService.getInstance(
        repository,
        userBooksRepository: repository,
      );
      await service!.deleteFolderFromDatabase(
        parentPath,
        otherConfiguredFolderPaths: [childPath],
      );

      expect(
        await repository.getBooksByCategory(parentCategoryId),
        isEmpty,
        reason: 'ספר האב legacy הוסר עם הסרת תיקיית האב',
      );
      expect(
        (await repository.getBooksByCategory(
          childCategoryId,
        )).map((book) => book.title),
        ['ספר הבן'],
        reason:
            'ספר הבן שייך לתיקייה המוגדרת העמוקה יותר — הסרת האב לא נוגעת בו',
      );
    },
  );

  test(
    'pruneRemovedCustomFoldersFromDatabase מוחק קטגוריה עמומה בלי הוכחת source או path',
    () async {
      final personalCategoryId = await repository.insertCategory(
        const Category(title: 'ספרים אישיים'),
      );
      final ambiguousCategoryId = await repository.insertCategory(
        Category(
          title: 'shared',
          parentId: personalCategoryId,
          level: 1,
        ),
      );
      final legacySourceId = await repository.insertSource('Personal', -1);

      await repository.insertBook(
        Book(
          id: 0,
          categoryId: ambiguousCategoryId,
          sourceId: legacySourceId,
          title: 'ספר עמום',
          isPersonal: true,
          fileType: 'txt',
          filePath: null,
        ),
      );
      await repository.rebuildCategoryClosure();

      final service = await FileSyncService.getInstance(
        repository,
        userBooksRepository: repository,
      );

      await service!.pruneRemovedCustomFoldersFromDatabase([
        CustomFolder(
          path: path.join(tempDir.path, 'alpha', 'shared'),
          addToDatabase: true,
          addedAt: DateTime(2026, 4, 13),
        ),
        CustomFolder(
          path: path.join(tempDir.path, 'beta', 'shared'),
          addToDatabase: true,
          addedAt: DateTime(2026, 4, 13),
        ),
      ]);

      expect(await repository.getCategory(ambiguousCategoryId), isNull);
    },
  );
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
