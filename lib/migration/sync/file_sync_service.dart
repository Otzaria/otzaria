import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as path;

import '../database/repository/seforim_repository.dart';
import '../../settings/services/custom_folders/custom_folder.dart';
import '../../settings/engine/settings_repository.dart';
import '../generator/generator.dart';
import '../generator/link_processor.dart';
import '../models/book.dart';
import '../models/category.dart';
import '../../utils/file/file_hidden_utils.dart';

/// Result of a file sync operation
class FileSyncResult {
  final int addedBooks;
  final int updatedBooks;
  final int addedCategories;
  final int addedLinks;
  final int skippedFiles;
  final List<String> errors;
  final Duration duration;

  /// מזהי ספרים (ב-user_books.db) שקובצם השתנה ועודכנו — דורשים אינדוקס
  /// מחדש בחיפוש.
  final List<int> updatedBookIds;

  const FileSyncResult({
    this.addedBooks = 0,
    this.updatedBooks = 0,
    this.addedCategories = 0,
    this.addedLinks = 0,
    this.skippedFiles = 0,
    this.errors = const [],
    this.duration = Duration.zero,
    this.updatedBookIds = const [],
  });

  @override
  String toString() {
    return 'FileSyncResult(added: $addedBooks, updated: $updatedBooks, '
        'categories: $addedCategories, links: $addedLinks, '
        'skipped: $skippedFiles, errors: ${errors.length}, '
        'duration: ${duration.inSeconds}s)';
  }
}

/// Service for syncing files from אוצריא and links folders to the database.
///
/// This service scans for new TXT files in the library path and adds them
/// to the database automatically. It runs in the background after app startup.
class FileSyncService {
  static final _log = Logger('FileSyncService');
  static const String _customFolderSourcePrefix = CustomFolderSource.prefix;
  static FileSyncService? _instance;

  /// Repository של `seforim.db` — לתוכן הרשמי (אוצריא, links).
  final SeforimRepository _repository;

  /// Repository של `user_books.db` — לתיקיות מותאמות אישית בלבד.
  /// כש-null, זרימות תיקיות מותאמות אישית משתמשות ב-`_repository` (legacy).
  final SeforimRepository? _userBooksRepository;

  /// ה-repository האפקטיבי לזרימת תיקיות מותאמות אישית.
  SeforimRepository get _customFoldersRepo =>
      _userBooksRepository ?? _repository;

  bool _isSyncing = false;

  /// Progress callback for UI updates
  void Function(double progress, String message)? onProgress;

  FileSyncService._(this._repository, this._userBooksRepository);

  /// Get singleton instance.
  ///
  /// [repository] — `seforim.db` repository (לתוכן רשמי).
  /// [userBooksRepository] — `user_books.db` repository (לתיקיות מותאמות
  /// אישית). כש-null, הזרימה הישנה בה הכל ב-`seforim.db` נשמרת.
  static Future<FileSyncService?> getInstance(
    SeforimRepository? repository, {
    SeforimRepository? userBooksRepository,
  }) async {
    if (repository == null) return null;
    _instance ??= FileSyncService._(repository, userBooksRepository);
    return _instance;
  }

  /// Creates a fresh instance for use inside a background worker isolate.
  /// Must NOT be used from the main isolate — use [getInstance] instead.
  factory FileSyncService.createForWorker(
    SeforimRepository repository, {
    SeforimRepository? userBooksRepository,
  }) {
    return FileSyncService._(repository, userBooksRepository);
  }

  /// מאפס את הסינגלטון. שימושי בעיקר בטסטים שיוצרים DB חדש בכל setUp
  /// ולא רוצים שה-singleton ישמור התייחסות ל-DB ישן/סגור.
  @visibleForTesting
  static void resetSingletonForTesting() {
    _instance = null;
  }

  /// Check if sync is currently running
  bool get isSyncing => _isSyncing;

  /// Get the repository for external access
  SeforimRepository get repository => _repository;

  /// Delete a book from the database by its file path
  /// This is used when a file is removed from GitHub sync
  Future<bool> deleteBookByFilePath(String filePath) async {
    try {
      // Extract the book title from the file path
      final title = path.basenameWithoutExtension(filePath);
      _log.info('Attempting to delete book from DB: $title');

      // Find the book by title
      final existingBook = await _repository.checkBookExists(title);
      if (existingBook == null) {
        _log.info('Book not found in DB, nothing to delete: $title');
        return false;
      }

      // Delete the book completely (including lines, TOC, links, etc.)
      await _repository.deleteBookCompletely(existingBook.id);
      _log.info(
        'Successfully deleted book from DB: $title (id: ${existingBook.id})',
      );
      return true;
    } catch (e, stackTrace) {
      _log.warning('Error deleting book from DB: $filePath', e, stackTrace);
      return false;
    }
  }

  /// Recursively delete a category and all its contents from the
  /// custom-folders DB (`user_books.db` or fallback to `_repository`).
  Future<void> _deleteCategoryRecursive(int categoryId) async {
    final repo = _customFoldersRepo;
    // First, delete all books in this category
    final books = await repo.getBooksByCategory(categoryId);
    debugPrint(
      '[FileSyncService] _deleteCategoryRecursive: categoryId=$categoryId, found ${books.length} books',
    );
    for (final book in books) {
      debugPrint(
        '[FileSyncService]   deleting book: id=${book.id}, title="${book.title}"',
      );
      try {
        await repo.deleteBookCompletely(book.id);
      } catch (e, st) {
        _log.warning(
          'Failed to delete book ${book.id} ("${book.title}"), continuing',
          e,
          st,
        );
      }
    }

    // Then, recursively delete subcategories
    final subCategories = await repo.getCategoryChildren(categoryId);
    debugPrint(
      '[FileSyncService] _deleteCategoryRecursive: categoryId=$categoryId, found ${subCategories.length} subcategories',
    );
    for (final subCat in subCategories) {
      debugPrint(
        '[FileSyncService]   recursing into subcategory: id=${subCat.id}, title="${subCat.title}"',
      );
      try {
        await _deleteCategoryRecursive(subCat.id);
      } catch (e, st) {
        _log.warning(
          'Failed to delete subcategory ${subCat.id} ("${subCat.title}"), continuing',
          e,
          st,
        );
      }
    }

    // Finally, delete this category
    debugPrint('[FileSyncService]   deleting category itself: id=$categoryId');
    await repo.deleteCategory(categoryId);
  }

  /// Clean up empty parent categories recursively
  /// Starts from a category and checks if it's empty, if so deletes it
  /// and continues up the hierarchy.
  /// פועל על ה-DB של תיקיות מותאמות אישית.
  Future<void> _cleanupEmptyParentCategories(int categoryId) async {
    final repo = _customFoldersRepo;
    // Get the category to check its parent
    final category = await repo.getCategory(categoryId);
    if (category == null) return;

    // Check if this category has any children (books or subcategories)
    final books = await repo.getBooksByCategory(categoryId);
    final subCategories = await repo.getCategoryChildren(categoryId);

    // If category is empty, delete it and check parent
    if (books.isEmpty && subCategories.isEmpty) {
      final parentId = category.parentId;
      await repo.deleteCategory(categoryId);
      _log.info('Deleted empty category: ${category.title}');

      // If there's a parent, check if it's now empty too
      if (parentId != null) {
        await _cleanupEmptyParentCategories(parentId);
      }
    }
  }

  /// Delete a folder from the database (without restoring files)
  /// Used when removing a folder from the app completely.
  /// פועל על ה-DB של תיקיות מותאמות אישית.
  ///
  /// הזיהוי הוא לפי [folderPath] (שם ה-source הייחודי), ולא לפי שם
  /// הקטגוריה — כך הסרת תיקייה לא תפגע בספרי תיקייה אחרת בעלת אותו
  /// basename שממוזגת לאותה קטגוריה. קטגוריות שהתרוקנו נמחקות, אך קטגוריה
  /// שעדיין מכילה ספרים של תיקייה אחרת נשמרת.
  ///
  /// [otherConfiguredFolderPaths] — נתיבי שאר התיקיות המוגדרות: ספר legacy
  /// ('external') המשויך לפי נתיב לא יימחק אם תיקייה מוגדרת עמוקה יותר
  /// מכילה אותו (תיקיית-בן מקוננת שנשארת רשומה).
  Future<void> deleteFolderFromDatabase(
    String folderPath, {
    List<String> otherConfiguredFolderPaths = const [],
  }) async {
    _log.info('Deleting folder books from DB by source: $folderPath');
    final removed = await _removeFolderBooksBySource(
      folderPath,
      otherConfiguredFolderPaths: otherConfiguredFolderPaths,
    );
    _log.info('Folder deleted from DB ($removed books removed)');
  }

  String _normalizeFolderPath(String folderPath) =>
      CustomFolderSource.normalizePath(folderPath);

  String _buildCustomFolderSourceName(String folderPath) =>
      CustomFolderSource.nameForFolder(folderPath);

  String? _extractCustomFolderPathFromSourceName(String? sourceName) {
    if (sourceName == null ||
        !sourceName.startsWith(_customFolderSourcePrefix)) {
      return null;
    }

    return sourceName.substring(_customFolderSourcePrefix.length);
  }

  bool _isPathInsideFolder(String bookPath, String folderPath) {
    final normalizedBookPath = _normalizeFolderPath(bookPath);
    final normalizedFolderPath = _normalizeFolderPath(folderPath);

    if (normalizedBookPath == normalizedFolderPath) {
      return true;
    }

    final folderWithSeparator = normalizedFolderPath.endsWith(path.separator)
        ? normalizedFolderPath
        : '$normalizedFolderPath${path.separator}';
    return normalizedBookPath.startsWith(folderWithSeparator);
  }

  /// האם אחת מ-[otherFolderPaths] מכילה את [bookPath] ועמוקה יותר
  /// מ-[folderPath] — כלומר הספר שייך לתיקייה מוגדרת מקוננת ולא לזו הנוכחית.
  bool _belongsToDeeperFolder(
    String bookPath,
    String folderPath,
    List<String> otherFolderPaths,
  ) {
    final folderDepth = _normalizeFolderPath(folderPath).length;
    return otherFolderPaths.any(
      (other) =>
          _normalizeFolderPath(other).length > folderDepth &&
          _isPathInsideFolder(bookPath, other),
    );
  }

  Future<bool> _categoryBelongsToAnyConfiguredFolder(
    int categoryId,
    List<CustomFolder> customFolders,
  ) async {
    final repo = _customFoldersRepo;
    final descendantIds = await repo.getDescendantCategoryIds(categoryId);
    final sourceNameCache = <int, String?>{};

    for (final descendantId in descendantIds) {
      final books = await repo.getBooksByCategory(descendantId);
      for (final book in books) {
        final sourceName = sourceNameCache.containsKey(book.sourceId)
            ? sourceNameCache[book.sourceId]
            : (sourceNameCache[book.sourceId] = (await repo.getSourceById(
                book.sourceId,
              ))?.name);
        final sourceFolderPath = _extractCustomFolderPathFromSourceName(
          sourceName,
        );
        if (sourceFolderPath != null &&
            customFolders.any(
              (folder) => _normalizeFolderPath(folder.path) == sourceFolderPath,
            )) {
          return true;
        }

        final bookPath = book.filePath;
        if (bookPath == null || bookPath.isEmpty) {
          continue;
        }
        if (customFolders.any(
          (folder) => _isPathInsideFolder(bookPath, folder.path),
        )) {
          return true;
        }
      }
    }

    return false;
  }

  /// מוחק מה-DB של תיקיות מותאמות אישית את התיקיות שכבר לא מוגדרות
  /// בהגדרות. פועל על user_books.db (דרך `_customFoldersRepo`).
  Future<void> pruneRemovedCustomFoldersFromDatabase(
    List<CustomFolder> customFolders,
  ) async {
    final repo = _customFoldersRepo;
    final rootCategories = await repo.getRootCategories();
    final personalCategory = rootCategories
        .where((category) => category.title == 'ספרים אישיים')
        .firstOrNull;
    if (personalCategory == null) {
      return;
    }

    final personalSubCategories = await repo.getCategoryChildren(
      personalCategory.id,
    );

    final staleFolderCategories = <Category>[];
    for (final category in personalSubCategories) {
      final belongsToConfiguredFolder =
          await _categoryBelongsToAnyConfiguredFolder(
            category.id,
            customFolders,
          );
      if (!belongsToConfiguredFolder) {
        staleFolderCategories.add(category);
      }
    }

    if (staleFolderCategories.isEmpty) {
      return;
    }

    for (final staleCategory in staleFolderCategories) {
      _log.info(
        'Removing stale custom folder from DB: ${staleCategory.title} (${staleCategory.id})',
      );
      await _deleteCategoryRecursive(staleCategory.id);
    }

    await _cleanupEmptyParentCategories(personalCategory.id);
    await repo.deleteOrphanedTocTexts();
    await repo.deleteOrphanedLineToc();
  }

  /// מוחק מ-`user_books.db` ספרים שקובצם הפיזי כבר לא קיים בתיקייה.
  ///
  /// [validBookKeys] הם המפתחות (`categoryId|title|fileType`) של הקבצים
  /// שנמצאו בסריקת [folder]; ספר השייך לתיקייה שמפתחו אינו ביניהם — קובצו
  /// נמחק, ולכן הוא מוסר. שיוך ספר לתיקייה נקבע לפי שם ה-`source` (הנתיב
  /// המלא), כך ש-basename כפול לא יפגע בתיקייה השנייה.
  Future<int> _pruneDeletedBooksInFolder(
    CustomFolder folder,
    Set<String> validBookKeys, {
    List<String> otherConfiguredFolderPaths = const [],
  }) => _removeFolderBooksBySource(
    folder.path,
    keepKeys: validBookKeys,
    otherConfiguredFolderPaths: otherConfiguredFolderPaths,
  );

  /// מסיר מ-`user_books.db` את ספרי התיקייה [folderPath], לפי שם ה-`source`
  /// הייחודי (הנתיב המלא) — לא לפי שם הקטגוריה. כך שתי תיקיות שונות בעלות
  /// אותו basename (למשל `C:\alpha\shared` ו-`D:\beta\shared`), שממוזגות
  /// לאותה קטגוריה `shared`, לא יפגעו זו בספרים של זו.
  ///
  /// אם [keepKeys] מסופק (זרימת prune) — ספרים שמפתחם
  /// (`categoryId|title|fileType`) נמצא בו נשמרים, והשאר מוסרים. אם null
  /// (זרימת מחיקת תיקייה) — כל ספרי התיקייה מוסרים.
  ///
  /// קטגוריות שהתרוקנו נמחקות; קטגוריה שעדיין מכילה ספרים (של תיקייה אחרת)
  /// נשמרת. מחזיר את מספר הספרים שהוסרו.
  Future<int> _removeFolderBooksBySource(
    String folderPath, {
    Set<String>? keepKeys,
    List<String> otherConfiguredFolderPaths = const [],
  }) async {
    final repo = _customFoldersRepo;
    final rootCategories = await repo.getRootCategories();
    final personalCategory = rootCategories
        .where((category) => category.title == 'ספרים אישיים')
        .firstOrNull;
    if (personalCategory == null) return 0;

    final folderSourceName = _buildCustomFolderSourceName(folderPath);

    final categoryIds = <int>{
      personalCategory.id,
      ...await repo.getDescendantCategoryIds(personalCategory.id),
    };

    final sourceNameCache = <int, String?>{};
    final affectedCategoryIds = <int>{};
    var removed = 0;
    for (final categoryId in categoryIds) {
      final books = await repo.getBooksByCategory(categoryId);
      for (final book in books) {
        final sourceName = sourceNameCache.containsKey(book.sourceId)
            ? sourceNameCache[book.sourceId]
            : (sourceNameCache[book.sourceId] = (await repo.getSourceById(
                book.sourceId,
              ))?.name);
        // שיוך לתיקייה לפי שם ה-source. נפילה-חזרה לפי נתיב הקובץ מוגבלת
        // *אך ורק* למקור ה-legacy המדויק שמסלול ההוספה הישן ייצר
        // ('external'), כדי לזהות נתונים ישנים בלי לגעת בספרים ממקור אחר
        // (תיקייה אחרת, ייבוא) שקובצם במקרה יושב בתוך התיקייה.
        // ספר legacy משויך רק לתיקייה המוגדרת *העמוקה ביותר* שמכילה אותו —
        // אחרת מחיקת תיקיית-אב הייתה גוררת גם ספרי תיקיית-בן מקוננת.
        final bookPath = book.filePath;
        final belongsToFolder =
            sourceName == folderSourceName ||
            (sourceName == CustomFolderSource.legacyExternalSourceName &&
                bookPath != null &&
                bookPath.isNotEmpty &&
                _isPathInsideFolder(bookPath, folderPath) &&
                !_belongsToDeeperFolder(
                  bookPath,
                  folderPath,
                  otherConfiguredFolderPaths,
                ));
        if (!belongsToFolder) continue;
        if (keepKeys != null) {
          // זרימת prune (רענון): ספר "עותק עצמאי" (התוכן נשמר בתוכנה,
          // filePath=null) נועד לשרוד גם אם הקובץ נמחק מהדיסק — זה כל
          // הרעיון של ההכנסה לתוכנה. לכן מוחקים רק ספרי "קריאה מהקבצים"
          // (file-backed) שקובצם נעלם; עותק עצמאי נמחק רק דרך הספרייה.
          if (!book.isFileBacked) continue;
          final key =
              '${book.categoryId}|${book.title}|'
              '${(book.fileType ?? '').toLowerCase()}';
          if (keepKeys.contains(key)) continue;
        }
        _log.info('Removing book from DB: "${book.title}" (id=${book.id})');
        try {
          await repo.deleteBookCompletely(book.id);
          removed++;
          affectedCategoryIds.add(categoryId);
        } catch (e, st) {
          _log.warning('Failed to remove book ${book.id}, continuing', e, st);
        }
      }
    }

    if (removed > 0) {
      for (final categoryId in affectedCategoryIds) {
        await _cleanupEmptyParentCategories(categoryId);
      }
      await repo.deleteOrphanedTocTexts();
      await repo.deleteOrphanedLineToc();
    }
    return removed;
  }

  Future<void> refreshSourcesAndPruneRemovedCustomFolders(
    List<CustomFolder> customFolders,
  ) async {
    // הערה: בעבר היה כאן rebuildCategoryClosure בלתי-מותנה שגרם להמון כתיבות
    // לדיסק בכל עלייה. כיום insertCategory מתחזק את category_closure
    // אינקרמנטלית, כך שה-rebuild המלא הזה כבר לא נחוץ כאן.
    await pruneRemovedCustomFoldersFromDatabase(customFolders);
  }

  /// Internal method to scan a single path and import files
  Future<FileSyncResult> _scanAndImportPath({
    required String rootPath,
    required List<String> categoryPrefix,
    required bool insertContent,
    String? customSourceName,
    required DatabaseGenerator generator,
    Set<String>? validBookKeys,
    _FolderScanCaches? caches,
  }) async {
    int addedBooks = 0;
    int updatedBooks = 0;
    int addedCategories = 0;
    int skippedFiles = 0;
    final errors = <String>[];
    final updatedBookIds = <int>[];

    // Find new files
    final newFiles = await _findNewFiles(rootPath);

    if (newFiles.isEmpty) {
      _log.info('No files found in $rootPath');
      return const FileSyncResult();
    }

    _log.info('Found ${newFiles.length} files to process in $rootPath');

    // תמונת-מצב אחת של ה-DB — במקום כמה שאילתות פר-קובץ, קובץ ללא שינוי
    // עולה stat בלבד. הקאש משותף לכל התיקיות בפעולת סנכרון אחת.
    caches ??= _FolderScanCaches(await _customFoldersRepo.getAllBooks());

    for (final filePath in newFiles) {
      if (!_isSyncing) break;

      try {
        final result = await _processFileWithPrefix(
          filePath: filePath,
          basePath: rootPath,
          categoryPrefix: categoryPrefix,
          insertContent: insertContent,
          customSourceName: customSourceName,
          generator: generator,
          validBookKeys: validBookKeys,
          caches: caches,
        );

        if (result.wasAdded) {
          addedBooks++;
          addedCategories += result.categoriesCreated;
        } else if (result.wasUpdated) {
          updatedBooks++;
          if (result.updatedBookId != null) {
            updatedBookIds.add(result.updatedBookId!);
          }
        } else {
          skippedFiles++;
        }

        // NOTE: Original files are never deleted. The DB is the single source
        // of truth but original files are always preserved on disk.
      } catch (e, stackTrace) {
        final errorMsg = 'Error processing file $filePath: $e';
        _log.warning(errorMsg, e, stackTrace);
        errors.add('Error processing ${path.basename(filePath)}: $e');
        debugPrint('❌ $errorMsg');
        debugPrint('Stack trace: $stackTrace');
      }
    }

    return FileSyncResult(
      addedBooks: addedBooks,
      updatedBooks: updatedBooks,
      addedCategories: addedCategories,
      skippedFiles: skippedFiles,
      errors: errors,
      updatedBookIds: updatedBookIds,
    );
  }

  /// Process a file with a specific category prefix
  Future<_FileProcessResult> _processFileWithPrefix({
    required String filePath,
    required String basePath,
    required List<String> categoryPrefix,
    required bool insertContent,
    String? customSourceName,
    required DatabaseGenerator generator,
    Set<String>? validBookKeys,
    required _FolderScanCaches caches,
  }) async {
    final title = path.basenameWithoutExtension(filePath);
    final extension = path.extension(filePath).toLowerCase();

    // PDF, DOCX and EPUB files always act as external (content never in DB)
    final isBinaryFormat =
        extension == '.pdf' || extension == '.docx' || extension == '.epub';
    final effectiveInsertContent = isBinaryFormat ? false : insertContent;

    // Build category path
    final relativeCategories = _parsePathToCategories(filePath, basePath);
    final categoryPath = [...categoryPrefix, ...relativeCategories];

    if (categoryPath.isEmpty && categoryPrefix.isEmpty) {
      _log.warning('Could not build category path for: $filePath');
      return const _FileProcessResult(wasAdded: false, wasUpdated: false);
    }

    // Find or create category chain (memoized per directory for this scan)
    final chainKey = categoryPath.join('\u0000');
    var categoryResult = caches.categoryChains[chainKey];
    final isFirstChainResolution = categoryResult == null;
    categoryResult ??= caches.categoryChains[chainKey] = await generator
        .findOrCreateCategoryChain(categoryPath);
    final categoryId = categoryResult.categoryId;
    // הקטגוריות נוצרו רק בפתרון הראשון של השרשרת; קבצים נוספים באותה
    // תיקייה לא סופרים אותן שוב.
    final categoriesCreated = isFirstChainResolution
        ? categoryResult.categoriesCreated
        : 0;

    // Extract file type from extension (remove the dot)
    final fileType = extension.replaceFirst('.', '').toLowerCase();

    // רישום מפתח הספר — הקובץ קיים בדיסק, ולכן ה-prune של קבצים שנמחקו
    // לא יסיר אותו מה-DB. המפתח אינו תלוי ב-filePath, כדי לכסות גם ספרים
    // ששמורים כעותק עצמאי (txt עם content בתוך ה-DB, filePath=null).
    validBookKeys?.add('$categoryId|$title|$fileType');

    // ספרי תיקיות מותאמות חיים ב-user_books.db; תמונת-המצב נטענה משם —
    // ל-seforim.db v3 אין עמודת fileType (וגם הוא read-only).
    final existingBook = caches.booksByKey['$categoryId|$title|$fileType'];

    bool wasAdded = false;
    bool wasUpdated = false;

    if (existingBook != null) {
      debugPrint(
        '[FileSyncService] Found existing book: title=$title, id=${existingBook.id}, filePath=${existingBook.filePath}, isFileBacked=${existingBook.isFileBacked}, totalLines=${existingBook.totalLines}',
      );

      final existingSourceName = await caches.sourceNameById(
        existingBook.sourceId,
        _customFoldersRepo,
      );

      // Book exists - check if file has changed
      final file = File(filePath);
      final fileStat = await file.stat();
      final fileSize = fileStat.size;
      final lastModified = fileStat.modified.millisecondsSinceEpoch;

      // Only update if file has actually changed
      final fileChanged =
          existingBook.fileSize != fileSize ||
          existingBook.lastModified != lastModified;

      // Also update if the storage preference changed (e.g. user toggled addToDatabase)
      final expectedIsContentExternal = !effectiveInsertContent;
      final storageChanged =
          existingBook.isFileBacked != expectedIsContentExternal;
      final sourceChanged = existingSourceName != customSourceName;

      if (fileChanged || storageChanged || sourceChanged) {
        if (storageChanged) {
          debugPrint(
            '[FileSyncService] Storage preference changed for ${existingBook.title}: isFileBacked=${existingBook.isFileBacked} -> $expectedIsContentExternal',
          );
        }
        if (sourceChanged) {
          debugPrint(
            '[FileSyncService] Source changed for ${existingBook.title}: $existingSourceName -> $customSourceName',
          );
        }
        wasUpdated = true;
        await generator.createAndProcessBook(
          filePath,
          categoryId,
          insertContent: effectiveInsertContent,
          sourceName: customSourceName,
        );
      }
    } else {
      wasAdded = true;
      await generator.createAndProcessBook(
        filePath,
        categoryId,
        insertContent: effectiveInsertContent,
        sourceName: customSourceName,
      );
    }

    if (wasAdded || wasUpdated) {
      // רענון נקודתי של תמונת-המצב — הקאש משותף בין תיקיות, ותיקייה שנסרקת
      // אחר-כך חייבת לראות את הספר שנכתב כרגע (קטגוריות ממוזגות).
      final refreshed = await _customFoldersRepo
          .checkBookExistsInCategoryWithFileType(title, categoryId, fileType);
      if (refreshed != null) {
        caches.booksByKey['$categoryId|$title|$fileType'] = refreshed;
      }
    }

    return _FileProcessResult(
      wasAdded: wasAdded,
      wasUpdated: wasUpdated,
      categoriesCreated: categoriesCreated,
      updatedBookId: wasUpdated ? existingBook?.id : null,
    );
  }

  /// Pure sync logic — receives all inputs, touches no Settings.
  /// Suitable for running inside a background worker isolate.
  /// [syncFolders] — לעבד את התיקיות המותאמות (כתיבה ל-user_books.db).
  /// [syncLinks] — לעבד את תיקיית ה-`links` (כתיבה ל-seforim.db).
  ///
  /// השניים מופרדים כדי שניתן יהיה להריץ את כתיבת הספרים האישיים (שצריכה רק
  /// *קריאה* מ-seforim.db) בלי לסגור את חיבור ה-RO הראשי, ולסגור אותו רק
  /// סביב שלב ה-links (שכותב ל-seforim.db). ברירת המחדל — שניהם, לשמירת
  /// תאימות עם קוראים קיימים.
  /// [onlyFolderPath] — כשמסופק, נסרקת רק התיקייה בעלת נתיב זה (למשל אחרי
  /// ייבוא לתיקיית הספרים האישיים). ה-prune של תיקיות שהוסרו עדיין רץ מול
  /// הרשימה המלאה, כך שספרי תיקיות אחרות לא נפגעים.
  Future<FileSyncResult> syncCustomFoldersWithInputs({
    required String libraryPath,
    required List<CustomFolder> customFolders,
    String folderName = '',
    void Function(double progress, String message)? onProgress,
    bool syncFolders = true,
    bool syncLinks = true,
    String? onlyFolderPath,
  }) async {
    if (_isSyncing) {
      _log.warning('Sync already in progress, skipping');
      return const FileSyncResult(errors: ['Sync already in progress']);
    }

    _isSyncing = true;
    this.onProgress = onProgress;
    final stopwatch = Stopwatch()..start();

    int addedBooks = 0;
    int updatedBooks = 0;
    int addedCategories = 0;
    int addedLinks = 0;
    int skippedFiles = 0;
    final errors = <String>[];
    final updatedBookIds = <int>[];

    try {
      if (syncFolders) {
        // Generator לתיקיות מותאמות אישית — כותב ל-user_books.db.
        final customFoldersGenerator = DatabaseGenerator(
          libraryPath,
          _customFoldersRepo,
          onProgress: onProgress,
        );
        final libraryRoot = folderName.isNotEmpty
            ? path.join(libraryPath, folderName)
            : libraryPath;
        customFoldersGenerator.initializeForSync(libraryRoot: libraryRoot);

        _reportProgress(0.4, 'סורק תיקיות מותאמות אישית...');

        if (customFolders.isNotEmpty) {
          _log.info('Found ${customFolders.length} custom folders to sync');

          // תמונת-מצב אחת של ה-DB לכל התיקיות — נטענת פעם אחת, מתעדכנת
          // נקודתית אחרי כל כתיבה, ונבנית מחדש רק אם prune מחק ספרים.
          _FolderScanCaches? sharedCaches;

          for (final folder in customFolders) {
            if (onlyFolderPath != null &&
                _normalizeFolderPath(folder.path) !=
                    _normalizeFolderPath(onlyFolderPath)) {
              continue;
            }
            final folderDir = Directory(folder.path);
            if (!await folderDir.exists()) {
              _log.warning('Custom folder does not exist: ${folder.path}');
              errors.add('תיקייה לא קיימת: ${folder.name}');
              continue;
            }

            _log.info(
              'Scanning custom folder: ${folder.path} (addToDatabase: ${folder.addToDatabase})',
            );

            sharedCaches ??= _FolderScanCaches(
              await _customFoldersRepo.getAllBooks(),
            );

            final folderValidKeys = <String>{};
            final result = await _scanAndImportPath(
              rootPath: folder.path,
              categoryPrefix: ['ספרים אישיים', folder.name],
              insertContent: folder.addToDatabase,
              customSourceName: _buildCustomFolderSourceName(folder.path),
              generator: customFoldersGenerator,
              validBookKeys: folderValidKeys,
              caches: sharedCaches,
            );

            addedBooks += result.addedBooks;
            updatedBooks += result.updatedBooks;
            addedCategories += result.addedCategories;
            skippedFiles += result.skippedFiles;
            errors.addAll(result.errors);
            updatedBookIds.addAll(result.updatedBookIds);

            // הסרת ספרים מה-DB שקובצם נמחק מהתיקייה. רץ רק אם הסריקה
            // הושלמה (לא בוטלה) — אחרת folderValidKeys חלקי והיינו עלולים
            // למחוק ספרים שקבציהם עדיין קיימים.
            if (_isSyncing) {
              final removed = await _pruneDeletedBooksInFolder(
                folder,
                folderValidKeys,
                otherConfiguredFolderPaths: [
                  for (final other in customFolders)
                    if (!identical(other, folder)) other.path,
                ],
              );
              if (removed > 0) sharedCaches = null;
            }
          }
        }

        // category_closure מתעדכן אינקרמנטלית בכל insertCategory, אז אין צורך
        // ב-rebuild גלובלי כאן גם כשהוספו קטגוריות חדשות.

        // בסריקה ממוקדת רשימת התיקיות לא השתנתה — אין תיקיות שהוסרו לנקות.
        if (onlyFolderPath == null) {
          await pruneRemovedCustomFoldersFromDatabase(customFolders);
        }
      }

      final linksPath = path.join(libraryPath, 'links');
      final linksDir = Directory(linksPath);

      if (syncLinks && await linksDir.exists()) {
        _log.info('Scanning links folder: $linksPath');
        _reportProgress(0.6, 'סורק תיקיית קישורים...');

        // Links תמיד שייכים ל-seforim.db — ה-LinkProcessor מקבל את
        // ה-repository הראשי (לא user_books).
        final linkProcessor = LinkProcessor(_repository);
        final linksResult = await linkProcessor.processLinksDirectory(
          linksPath: linksPath,
          onProgress: (progress, message) {
            _reportProgress(0.6 + (progress * 0.3), message);
          },
          updateBookHasLinks: true,
        );
        addedLinks += linksResult.processedLinks;
        errors.addAll(linksResult.errors);
      }

      _reportProgress(1.0, 'הסנכרון הושלם');
    } catch (e, stackTrace) {
      _log.severe('Error during sync', e, stackTrace);
      errors.add('Sync error: $e');
    } finally {
      _isSyncing = false;
      stopwatch.stop();
    }

    final result = FileSyncResult(
      addedBooks: addedBooks,
      updatedBooks: updatedBooks,
      addedCategories: addedCategories,
      addedLinks: addedLinks,
      skippedFiles: skippedFiles,
      errors: errors,
      duration: stopwatch.elapsed,
      updatedBookIds: updatedBookIds,
    );

    _log.info('Sync completed: $result');
    return result;
  }

  /// Legacy wrapper — reads Settings and delegates to [syncCustomFoldersWithInputs].
  /// Prefer calling [syncCustomFoldersWithInputs] via a worker isolate instead.
  Future<FileSyncResult> syncFiles({
    void Function(double progress, String message)? onProgress,
  }) async {
    if (_isSyncing) {
      _log.warning('Sync already in progress, skipping');
      return const FileSyncResult(errors: ['Sync already in progress']);
    }

    final libraryPath = Settings.getValue<String>(
      SettingsRepository.keyLibraryPath,
    );
    if (libraryPath == null || libraryPath.isEmpty) {
      _log.warning('Library path not set, skipping sync');
      return const FileSyncResult(errors: ['Library path not set']);
    }

    final customFoldersJson = Settings.getValue<String>(
      SettingsRepository.keyCustomFolders,
    );
    final customFolders = CustomFoldersManager.loadFolders(customFoldersJson);

    final libraryFolderName =
        Settings.getValue<String>(SettingsRepository.keyLibraryFolderName) ??
        '';
    final result = await syncCustomFoldersWithInputs(
      libraryPath: libraryPath,
      customFolders: customFolders,
      folderName: libraryFolderName,
      onProgress: onProgress,
    );

    return result;
  }

  /// Find new or updated files to sync to the database
  /// Returns all supported files - the processing logic will determine if they should be added or updated
  Future<List<String>> _findNewFiles(String basePath) async {
    final newFiles = <String>[];
    final dir = Directory(basePath);
    final supportedExtensions = {'.txt', '.pdf', '.docx', '.epub'};

    if (!await dir.exists()) return newFiles;

    await for (final entity in dir.list(recursive: true)) {
      if (entity is File) {
        if (isHiddenOrSystem(entity.path)) continue;
        final ext = path.extension(entity.path).toLowerCase();
        if (supportedExtensions.contains(ext)) {
          final title = path.basenameWithoutExtension(entity.path);
          newFiles.add(entity.path);
          _log.fine('Found file to process: $title ($ext)');
        }
      }
    }

    return newFiles;
  }

  /// Parse file path to extract category hierarchy
  List<String> _parsePathToCategories(String filePath, String basePath) {
    // Normalize paths
    final normalizedFile = path.normalize(filePath);
    final normalizedBase = path.normalize(basePath);

    // Get relative path
    String relativePath;
    if (normalizedFile.startsWith(normalizedBase)) {
      relativePath = normalizedFile.substring(normalizedBase.length);
      if (relativePath.startsWith(path.separator)) {
        relativePath = relativePath.substring(1);
      }
    } else {
      return [];
    }

    // Split into parts and remove the filename
    final parts = path.split(relativePath);
    if (parts.isEmpty) return [];

    // Remove the filename (last part)
    return parts.sublist(0, parts.length - 1);
  }

  /// Report progress to callback
  void _reportProgress(double progress, String message) {
    onProgress?.call(progress, message);
    _log.fine('Progress: ${(progress * 100).toStringAsFixed(1)}% - $message');
  }
}

/// Result of processing a single file
class _FileProcessResult {
  final bool wasAdded;
  final bool wasUpdated;
  final int categoriesCreated;

  /// מזהה הספר הקיים שעודכן (כאשר [wasUpdated] פעיל).
  final int? updatedBookId;

  const _FileProcessResult({
    required this.wasAdded,
    required this.wasUpdated,
    this.categoriesCreated = 0,
    this.updatedBookId,
  });
}

/// קאשים לסריקת תיקייה אחת: תמונת-מצב של הספרים מה-DB, שמות source ופתרונות
/// שרשרת קטגוריות — במקום כמה שאילתות DB לכל קובץ.
class _FolderScanCaches {
  _FolderScanCaches(List<Book> books)
    : booksByKey = {
        for (final book in books)
          '${book.categoryId}|${book.title}|'
                  '${(book.fileType ?? '').toLowerCase()}':
              book,
      };

  /// מפתח: `categoryId|title|fileType` — זהה לבדיקת הקיום המקורית.
  final Map<String, Book> booksByKey;

  final Map<int, String?> _sourceNamesById = {};

  final Map<String, ({int categoryId, int categoriesCreated})> categoryChains =
      {};

  Future<String?> sourceNameById(int sourceId, SeforimRepository repo) async {
    if (_sourceNamesById.containsKey(sourceId)) {
      return _sourceNamesById[sourceId];
    }
    return _sourceNamesById[sourceId] = (await repo.getSourceById(
      sourceId,
    ))?.name;
  }
}

/// Result of restoring a folder from DB
class RestoreFolderResult {
  final int restoredBooks;
  final int restoredCategories;
  final List<String> errors;

  const RestoreFolderResult({
    this.restoredBooks = 0,
    this.restoredCategories = 0,
    this.errors = const [],
  });
}
