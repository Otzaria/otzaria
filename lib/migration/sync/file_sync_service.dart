import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as path;

import '../core/models/book.dart';
import '../core/models/book_metadata.dart';
import '../core/models/category.dart';
import '../dao/repository/seforim_repository.dart';
import '../../settings/custom_folders/custom_folder.dart';
import '../../settings/settings_repository.dart';
import '../generator/generator.dart';
import '../shared/link_processor.dart';

/// Result of a file sync operation
class FileSyncResult {
  final int addedBooks;
  final int updatedBooks;
  final int addedCategories;
  final int addedLinks;
  final int deletedFiles;
  final int skippedFiles;
  final List<String> errors;
  final Duration duration;

  const FileSyncResult({
    this.addedBooks = 0,
    this.updatedBooks = 0,
    this.addedCategories = 0,
    this.addedLinks = 0,
    this.deletedFiles = 0,
    this.skippedFiles = 0,
    this.errors = const [],
    this.duration = Duration.zero,
  });

  @override
  String toString() {
    return 'FileSyncResult(added: $addedBooks, updated: $updatedBooks, '
        'categories: $addedCategories, links: $addedLinks, deleted: $deletedFiles, '
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
  static FileSyncService? _instance;

  final SeforimRepository _repository;
  bool _isSyncing = false;

  /// Progress callback for UI updates
  void Function(double progress, String message)? onProgress;

  /// Counter for IDs
  int _nextBookId = 0;
  int _nextLineId = 0;
  int _nextTocEntryId = 0;
  int _nextCategoryId = 0;

  FileSyncService._(this._repository);

  /// Get singleton instance
  static Future<FileSyncService?> getInstance(
      SeforimRepository? repository) async {
    if (repository == null) return null;
    _instance ??= FileSyncService._(repository);
    return _instance;
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
          'Successfully deleted book from DB: $title (id: ${existingBook.id})');
      return true;
    } catch (e, stackTrace) {
      _log.warning('Error deleting book from DB: $filePath', e, stackTrace);
      return false;
    }
  }

  /// Restore files from DB for a custom folder
  /// This exports books from the "ספרים אישיים" category back to files
  /// and then deletes them from the database.
  ///
  /// [folder] - The custom folder to restore
  /// [onProgress] - Progress callback for UI updates
  ///
  /// Returns the number of books restored
  Future<RestoreFolderResult> restoreFolderFromDatabase(
    CustomFolder folder, {
    void Function(double progress, String message)? onProgress,
  }) async {
    _log.info('Restoring folder from DB: ${folder.name}');
    int restoredBooks = 0;
    int restoredCategories = 0;
    final errors = <String>[];

    try {
      // Find the "ספרים אישיים" root category
      final rootCategories = await _repository.getRootCategories();
      Category? personalCategory;
      for (final cat in rootCategories) {
        if (cat.title == 'ספרים אישיים') {
          personalCategory = cat;
          break;
        }
      }

      if (personalCategory == null) {
        _log.info('No "ספרים אישיים" category found in DB');
        return RestoreFolderResult(
          restoredBooks: 0,
          restoredCategories: 0,
          errors: ['לא נמצאה קטגוריית "ספרים אישיים" במסד הנתונים'],
        );
      }

      // Find the folder's category under "ספרים אישיים"
      final folderCategories =
          await _repository.getCategoryChildren(personalCategory.id);
      Category? folderCategory;
      for (final cat in folderCategories) {
        if (cat.title == folder.name) {
          folderCategory = cat;
          break;
        }
      }

      if (folderCategory == null) {
        _log.info('Folder category not found in DB: ${folder.name}');
        return RestoreFolderResult(
          restoredBooks: 0,
          restoredCategories: 0,
          errors: ['התיקייה "${folder.name}" לא נמצאה במסד הנתונים'],
        );
      }

      onProgress?.call(0.1, 'מייצא ספרים מהמסד...');

      // Recursively restore all books and subcategories
      final result = await _restoreCategoryRecursive(
        folderCategory,
        folder.path,
        onProgress,
        0.1,
        0.8,
      );
      restoredBooks = result.books;
      restoredCategories = result.categories;
      errors.addAll(result.errors);

      onProgress?.call(0.9, 'מוחק נתונים מהמסד...');

      // Delete the folder category and all its contents from DB
      await _deleteCategoryRecursive(folderCategory.id);

      // Clean up empty parent categories up to "ספרים אישיים"
      await _cleanupEmptyParentCategories(personalCategory.id);

      onProgress?.call(1.0, 'השחזור הושלם');
      _log.info(
          'Restored $restoredBooks books and $restoredCategories categories from DB');
    } catch (e, stackTrace) {
      _log.severe('Error restoring folder from DB', e, stackTrace);
      errors.add('שגיאה בשחזור: $e');
    }

    return RestoreFolderResult(
      restoredBooks: restoredBooks,
      restoredCategories: restoredCategories,
      errors: errors,
    );
  }

  /// Recursively restore a category and its contents to files
  Future<_RestoreResult> _restoreCategoryRecursive(
    Category category,
    String targetPath,
    void Function(double progress, String message)? onProgress,
    double progressStart,
    double progressEnd,
  ) async {
    int books = 0;
    int categories = 0;
    final errors = <String>[];

    // Ensure the target directory exists
    final targetDir = Directory(targetPath);
    if (!await targetDir.exists()) {
      await targetDir.create(recursive: true);
      categories++;
    }

    // Get books in this category
    final categoryBooks = await _repository.getBooksByCategory(category.id);

    // Restore each book
    for (int i = 0; i < categoryBooks.length; i++) {
      final book = categoryBooks[i];
      try {
        await _restoreBookToFile(book, targetPath);
        books++;

        final progress = progressStart +
            (progressEnd - progressStart) * (i / categoryBooks.length) * 0.5;
        onProgress?.call(progress, 'משחזר: ${book.title}');
      } catch (e) {
        _log.warning('Error restoring book ${book.title}: $e');
        errors.add('שגיאה בשחזור "${book.title}": $e');
      }
    }

    // Get and restore subcategories
    final subCategories = await _repository.getCategoryChildren(category.id);
    for (int i = 0; i < subCategories.length; i++) {
      final subCat = subCategories[i];
      final subPath = path.join(targetPath, subCat.title);

      final subResult = await _restoreCategoryRecursive(
        subCat,
        subPath,
        onProgress,
        progressStart + (progressEnd - progressStart) * 0.5,
        progressEnd,
      );

      books += subResult.books;
      categories += subResult.categories + 1;
      errors.addAll(subResult.errors);
    }

    return _RestoreResult(books: books, categories: categories, errors: errors);
  }

  /// Restore a single book to a file
  Future<void> _restoreBookToFile(Book book, String targetPath) async {
    // Get all lines for the book
    final lines = await _repository.getLines(book.id, 0, book.totalLines - 1);

    // Sort lines by index
    lines.sort((a, b) => a.lineIndex.compareTo(b.lineIndex));

    // Build the file content
    final content = lines.map((line) => line.content).join('\n');

    // Write to file
    final filePath = path.join(targetPath, '${book.title}.txt');
    final file = File(filePath);
    await file.writeAsString(content, encoding: utf8);

    _log.info('Restored book to file: $filePath');
  }

  /// Recursively delete a category and all its contents from DB
  Future<void> _deleteCategoryRecursive(int categoryId) async {
    // First, delete all books in this category
    final books = await _repository.getBooksByCategory(categoryId);
    for (final book in books) {
      await _repository.deleteBookCompletely(book.id);
    }

    // Then, recursively delete subcategories
    final subCategories = await _repository.getCategoryChildren(categoryId);
    for (final subCat in subCategories) {
      await _deleteCategoryRecursive(subCat.id);
    }

    // Finally, delete this category
    await _repository.deleteCategory(categoryId);
  }

  /// Clean up empty parent categories recursively
  /// Starts from a category and checks if it's empty, if so deletes it
  /// and continues up the hierarchy
  Future<void> _cleanupEmptyParentCategories(int categoryId) async {
    // Get the category to check its parent
    final category = await _repository.getCategory(categoryId);
    if (category == null) return;

    // Check if this category has any children (books or subcategories)
    final books = await _repository.getBooksByCategory(categoryId);
    final subCategories = await _repository.getCategoryChildren(categoryId);

    // If category is empty, delete it and check parent
    if (books.isEmpty && subCategories.isEmpty) {
      final parentId = category.parentId;
      await _repository.deleteCategory(categoryId);
      _log.info('Deleted empty category: ${category.title}');

      // If there's a parent, check if it's now empty too
      if (parentId != null) {
        await _cleanupEmptyParentCategories(parentId);
      }
    }
  }

  /// Delete a folder from the database (without restoring files)
  /// Used when removing a folder from the app completely
  Future<void> deleteFolderFromDatabase(
      int folderCategoryId, int personalCategoryId) async {
    _log.info('Deleting folder category from DB: $folderCategoryId');

    // Delete the folder category and all its contents
    await _deleteCategoryRecursive(folderCategoryId);

    // Clean up empty parent categories
    await _cleanupEmptyParentCategories(personalCategoryId);

    _log.info('Folder deleted from DB');
  }

  /// Internal method to scan a single path and import files
  Future<FileSyncResult> _scanAndImportPath({
    required String rootPath,
    required List<String> categoryPrefix,
    required bool deleteOriginals,
    required DatabaseGenerator generator,
    Map<String, BookMetadata> metadata = const {},
  }) async {
    int addedBooks = 0;
    int updatedBooks = 0;
    int addedCategories = 0;
    int deletedFiles = 0;
    int skippedFiles = 0;
    final errors = <String>[];

    // Find new files
    final newFiles = await _findNewFiles(rootPath);

    if (newFiles.isEmpty) {
      _log.info('No files found in $rootPath');
      return const FileSyncResult();
    }

    _log.info('Found ${newFiles.length} files to process in $rootPath');

    for (final filePath in newFiles) {
      if (!_isSyncing) break;

      try {
        final result = await _processFileWithPrefix(
          filePath: filePath,
          basePath: rootPath,
          categoryPrefix: categoryPrefix,
          generator: generator,
          metadata: metadata,
        );

        if (result.wasAdded) {
          addedBooks++;
          addedCategories += result.categoriesCreated;
        } else if (result.wasUpdated) {
          updatedBooks++;
        } else {
          skippedFiles++;
        }

        // Delete the file after successful processing if requested
        // ONLY delete .txt files, as other files (PDF, DOCX) are referenced externally
        final isTxtFile = path.extension(filePath).toLowerCase() == '.txt';

        if (deleteOriginals &&
            isTxtFile &&
            (result.wasAdded || result.wasUpdated)) {
          try {
            await File(filePath).delete();
            deletedFiles++;
            _log.info('Deleted processed file: ${path.basename(filePath)}');
          } catch (e) {
            _log.warning('Failed to delete file $filePath: $e');
          }
        }

        // We don't report progress here to avoid spamming the main progress callback
        // or we could use a sub-progress callback if needed
      } catch (e, stackTrace) {
        _log.warning('Error processing file $filePath', e, stackTrace);
        errors.add('Error processing ${path.basename(filePath)}: $e');
      }
    }

    // Clean up empty directories after processing if we deleted files
    if (deleteOriginals) {
      await _removeEmptyDirectories(rootPath);
    }

    return FileSyncResult(
      addedBooks: addedBooks,
      updatedBooks: updatedBooks,
      addedCategories: addedCategories,
      deletedFiles: deletedFiles,
      skippedFiles: skippedFiles,
      errors: errors,
    );
  }

  /// Process a file with a specific category prefix
  Future<_FileProcessResult> _processFileWithPrefix({
    required String filePath,
    required String basePath,
    required List<String> categoryPrefix,
    required DatabaseGenerator generator,
    required Map<String, BookMetadata> metadata,
  }) async {
    final title = path.basenameWithoutExtension(filePath);
    final extension = path.extension(filePath).toLowerCase();

    // Build category path
    final relativeCategories = _parsePathToCategories(filePath, basePath);
    final categoryPath = [...categoryPrefix, ...relativeCategories];

    if (categoryPath.isEmpty && categoryPrefix.isEmpty) {
      _log.warning('Could not build category path for: $filePath');
      return const _FileProcessResult(wasAdded: false, wasUpdated: false);
    }

    // Find or create category chain
    final categoryResult = await _findOrCreateCategoryChain(categoryPath);
    final categoryId = categoryResult.categoryId;
    final categoriesCreated = categoryResult.categoriesCreated;

    // Extract file type from extension (remove the dot)
    final fileType = extension.replaceFirst('.', '').toLowerCase();

    // Check if book already exists in this category with the same file type
    // We do this check here to know if we are updating or adding for stats
    final existingBook = await _repository
        .checkBookExistsInCategoryWithFileType(title, categoryId, fileType);

    bool wasAdded = false;
    bool wasUpdated = false;

    if (existingBook != null) {
      wasUpdated = true;
      await generator.createAndProcessBook(
        filePath,
        categoryId,
        metadata,
        updateExisting: true,
        insertContent: true,
      );
    } else {
      wasAdded = true;
      await generator.createAndProcessBook(
        filePath,
        categoryId,
        metadata,
        updateExisting: false,
        insertContent: true,
      );
    }

    // Update local ID counters from generator
    final ids = generator.getIds();
    _nextBookId = ids.bookId;
    _nextLineId = ids.lineId;
    _nextTocEntryId = ids.tocId;

    return _FileProcessResult(
      wasAdded: wasAdded,
      wasUpdated: wasUpdated,
      categoriesCreated: categoriesCreated,
    );
  }

  /// Main sync function - scans אוצריא and links folders for new files
  Future<FileSyncResult> syncFiles({
    void Function(double progress, String message)? onProgress,
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
    int deletedFiles = 0;
    int skippedFiles = 0;
    final errors = <String>[];

    try {
      final libraryPath = Settings.getValue<String>('key-library-path');
      if (libraryPath == null || libraryPath.isEmpty) {
        _log.warning('Library path not set, skipping sync');
        return const FileSyncResult(errors: ['Library path not set']);
      }

      // Initialize ID counters from database
      await _initializeIdCounters();

      // Setup Generator
      final generator = DatabaseGenerator(libraryPath, _repository, onProgress: onProgress);
      generator.setIds(_nextBookId, _nextLineId, _nextTocEntryId);
      generator.initializeForSync(libraryRoot: path.join(libraryPath, 'אוצריא'));
      // Load metadata
      Map<String, BookMetadata> metadata = {};
      try {
         metadata = await generator.loadMetadata();
      } catch (e) {
          _log.warning('Failed to load metadata', e);
      }

      // Scan אוצריא folder for TXT files only
      final otzariaPath = path.join(libraryPath, 'אוצריא');
      final otzariaDir = Directory(otzariaPath);

      if (await otzariaDir.exists()) {
        _log.info('Scanning אוצריא folder: $otzariaPath');
        _reportProgress(0.1, 'סורק תיקיית אוצריא...');

        // Use the new internal method
        final otzariaResult = await _scanAndImportPath(
          rootPath: otzariaPath,
          categoryPrefix: [],
          deleteOriginals: true, // Keep existing behavior
          generator: generator,
          metadata: metadata,
        );

        addedBooks += otzariaResult.addedBooks;
        updatedBooks += otzariaResult.updatedBooks;
        addedCategories += otzariaResult.addedCategories;
        deletedFiles += otzariaResult.deletedFiles;
        skippedFiles += otzariaResult.skippedFiles;
        errors.addAll(otzariaResult.errors);
      }

      // Scan custom folders that are marked for DB sync
      _reportProgress(0.4, 'סורק תיקיות מותאמות אישית...');
      // Load custom folders from settings
      final customFoldersJson =
          Settings.getValue<String>(SettingsRepository.keyCustomFolders);
      final customFolders = CustomFoldersManager.loadFolders(customFoldersJson);

      // Filter only folders marked for DB sync
      final foldersToSync =
          customFolders.where((f) => f.addToDatabase).toList();

      if (foldersToSync.isNotEmpty) {
        _log.info('Found ${foldersToSync.length} custom folders to sync');

        for (final folder in foldersToSync) {
          final folderDir = Directory(folder.path);
          if (!await folderDir.exists()) {
            _log.warning('Custom folder does not exist: ${folder.path}');
            errors.add('תיקייה לא קיימת: ${folder.name}');
            continue;
          }

          _log.info('Scanning custom folder: ${folder.path}');

          // Use the new internal method
          final result = await _scanAndImportPath(
            rootPath: folder.path,
            categoryPrefix: ['ספרים אישיים', folder.name],
            deleteOriginals: true, // Keep existing behavior
            generator: generator,
            metadata: metadata,
          );

          addedBooks += result.addedBooks;
          updatedBooks += result.updatedBooks;
          addedCategories += result.addedCategories;
          deletedFiles += result.deletedFiles;
          skippedFiles += result.skippedFiles;
          errors.addAll(result.errors);
        }
      }
      // Scan links folder for JSON files only
      final linksPath = path.join(libraryPath, 'links');
      final linksDir = Directory(linksPath);

      if (await linksDir.exists()) {
        _log.info('Scanning links folder: $linksPath');
        _reportProgress(0.6, 'סורק תיקיית קישורים...');

        final linksResult = await _scanAndSyncLinkFiles(linksPath);
        addedLinks += linksResult.addedLinks;
        deletedFiles += linksResult.deletedFiles;
        skippedFiles += linksResult.skippedFiles;
        errors.addAll(linksResult.errors);
      }

      // Check for acronym.json file and update book_acronym table if found
      _reportProgress(0.85, 'בודק קובץ acronym.json...');
      final acronymResult = await _checkAndProcessAcronymFile(libraryPath);
      if (acronymResult.processed) {
        _log.info(
            'Processed acronym.json: ${acronymResult.updatedBooks} books updated, ${acronymResult.newTerms} new terms');
      }
      errors.addAll(acronymResult.errors);

      // Rebuild category closure if categories were added
      if (addedCategories > 0) {
        _reportProgress(0.95, 'מעדכן היררכיית קטגוריות...');
        await _repository.rebuildCategoryClosure();
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
      deletedFiles: deletedFiles,
      skippedFiles: skippedFiles,
      errors: errors,
      duration: stopwatch.elapsed,
    );

    _log.info('Sync completed: $result');
    return result;
  }

  /// Initialize ID counters from database
  Future<void> _initializeIdCounters() async {
    // Use repository extension method to get max IDs
    final maxIds = await _repository.getMaxIds();

    _nextBookId = maxIds.maxBookId + 1;
    _nextLineId = maxIds.maxLineId + 1;
    _nextTocEntryId = maxIds.maxTocId + 1;
    _nextCategoryId = maxIds.maxCategoryId + 1;

    _log.info('Initialized ID counters: book=$_nextBookId, line=$_nextLineId, '
        'toc=$_nextTocEntryId, category=$_nextCategoryId');
  }

  /// Scan links folder and sync JSON files to database
  Future<FileSyncResult> _scanAndSyncLinkFiles(String folderPath) async {
    int addedLinks = 0;
    int deletedFiles = 0;
    int skippedFiles = 0;
    final errors = <String>[];

    // Create link processor and load books cache
    final linkProcessor = LinkProcessor(_repository);
    await linkProcessor.loadBooksCache();

    // Find JSON files in links folder
    final linksDir = Directory(folderPath);
    final jsonFiles = <String>[];

    await for (final entity in linksDir.list()) {
      if (entity is File && path.extension(entity.path) == '.json') {
        jsonFiles.add(entity.path);
      }
    }

    if (jsonFiles.isEmpty) {
      _log.info('No JSON files found in links folder');
      return const FileSyncResult();
    }

    _log.info('Found ${jsonFiles.length} JSON link files to process');

    int processed = 0;
    for (final filePath in jsonFiles) {
      try {
        final result = await linkProcessor.processLinkFile(filePath);
        if (result.processedLinks > 0) {
          addedLinks += result.processedLinks;

          // Delete the JSON file after successful processing
          try {
            await File(filePath).delete();
            deletedFiles++;
            _log.info(
                'Deleted processed link file: ${path.basename(filePath)}');
          } catch (e) {
            _log.warning('Failed to delete link file $filePath: $e');
          }
        } else {
          skippedFiles++;
        }

        processed++;
        _reportProgress(
          0.6 + (0.3 * processed / jsonFiles.length),
          'מעבד קישורים ${path.basename(filePath)}...',
        );
      } catch (e, stackTrace) {
        _log.warning('Error processing link file $filePath', e, stackTrace);
        errors.add('Error processing ${path.basename(filePath)}: $e');
      }
    }

    return FileSyncResult(
      addedLinks: addedLinks,
      deletedFiles: deletedFiles,
      skippedFiles: skippedFiles,
      errors: errors,
    );
  }

  /// Find new or updated files to sync to the database
  /// Returns all supported files - the processing logic will determine if they should be added or updated
  Future<List<String>> _findNewFiles(String basePath) async {
    final newFiles = <String>[];
    final dir = Directory(basePath);
    final supportedExtensions = {'.txt', '.pdf', '.docx'};

    if (!await dir.exists()) return newFiles;

    await for (final entity in dir.list(recursive: true)) {
      if (entity is File) {
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

  /// Find or create a category chain and return the leaf category ID
  Future<_CategoryResult> _findOrCreateCategoryChain(
    List<String> categoryPath,
  ) async {
    int? currentParentId;
    int categoriesCreated = 0;

    for (int i = 0; i < categoryPath.length; i++) {
      final categoryName = categoryPath[i];
      final level = i;

      // Try to find existing category
      final existingCategory =
          await _findCategory(categoryName, currentParentId);

      if (existingCategory != null) {
        currentParentId = existingCategory.id;
      } else {
        // Create new category using repository method
        // Repository's insertCategory handles duplicates and returns existing ID if found
        final category = Category(
          id: _nextCategoryId++,
          parentId: currentParentId,
          title: categoryName,
          level: level,
        );

        final insertedId = await _repository.insertCategory(category);
        currentParentId = insertedId;
        categoriesCreated++;

        _log.info('Created new category: $categoryName (id: $insertedId)');
      }
    }

    return _CategoryResult(
      categoryId: currentParentId!,
      categoriesCreated: categoriesCreated,
    );
  }

  /// Find a category by name and parent ID
  Future<Category?> _findCategory(String name, int? parentId) async {
    // Use repository methods to get categories by parent
    final categories = parentId == null
        ? await _repository.getRootCategories()
        : await _repository.getCategoryChildren(parentId);

    // Find category with matching name
    for (final cat in categories) {
      if (cat.title == name) {
        return cat;
      }
    }
    return null;
  }


  Future<void> _removeEmptyDirectories(String basePath) async {
    final dir = Directory(basePath);
    final entities = await dir.list(recursive: true).toList();

    // Sort from deepest to shallowest
    entities.sort((a, b) => b.path.length.compareTo(a.path.length));

    for (final entity in entities) {
      if (entity is Directory) {
        try {
          final contents = await entity.list().toList();
          if (contents.isEmpty) {
            await entity.delete();
            _log.fine('Deleted empty directory: ${entity.path}');
          }
        } catch (e) {
          // Ignore errors when deleting directories
        }
      }
    }
  }

  /// Report progress to callback
  void _reportProgress(double progress, String message) {
    onProgress?.call(progress, message);
    _log.fine('Progress: ${(progress * 100).toStringAsFixed(1)}% - $message');
  }

  /// Check for acronym.json file in "אודות התוכנה" folder and update book_acronym table
  /// Updates existing books by matching book_title to book.title in the database
  /// After processing, deletes the acronym.json file
  Future<_AcronymProcessResult> _checkAndProcessAcronymFile(
      String libraryPath) async {
    final errors = <String>[];
    int updatedBooks = 0;
    int newTerms = 0;

    try {
      final acronymPath =
          path.join(libraryPath, 'אוצריא', 'אודות התוכנה', 'acronym.json');
      final acronymFile = File(acronymPath);

      if (!await acronymFile.exists()) {
        _log.fine('No acronym.json file found at $acronymPath');
        return const _AcronymProcessResult(processed: false);
      }

      _log.info('Found acronym.json file, processing...');

      // Read and parse the file
      final content = await acronymFile.readAsString();
      final decoded = jsonDecode(content);

      // Convert to list format (handle both Map and List)
      List<Map<String, dynamic>> acronymEntries = [];
      if (decoded is List) {
        acronymEntries = decoded.cast<Map<String, dynamic>>();
      } else if (decoded is Map<String, dynamic>) {
        // Convert map to list format
        decoded.forEach((key, value) {
          if (value is Map<String, dynamic>) {
            acronymEntries.add(value);
          }
        });
      }

      _log.info('Loaded ${acronymEntries.length} acronym entries from file');

      // Process each entry - match by book_title to find the book in DB
      for (final entry in acronymEntries) {
        final bookTitle = entry['book_title'] as String?;
        final termsRaw = entry['terms'] as String?;

        if (bookTitle == null || bookTitle.isEmpty) {
          continue;
        }

        // Find the book by title in the database
        final existingBook = await _repository.checkBookExists(bookTitle);
        if (existingBook == null) {
          _log.fine('Book not found in DB for acronym update: $bookTitle');
          continue;
        }

        final bookId = existingBook.id;

        // Parse terms (comma-separated)
        final terms = (termsRaw == null || termsRaw.isEmpty)
            ? <String>[]
            : termsRaw
                .split(',')
                .map((t) => DatabaseGenerator.sanitizeAcronymTerm(t))
                .where((t) => t.isNotEmpty)
                .toList();

        // Full replacement: delete all existing terms and insert new ones
        // This handles additions, removals, and updates
        await _repository.deleteBookAcronyms(bookId);

        if (terms.isNotEmpty) {
          await _repository.bulkInsertBookAcronyms(bookId, terms);
          newTerms += terms.length;
        }

        updatedBooks++;
        _log.fine(
            'Replaced acronym terms for book: $bookTitle (id: $bookId) with ${terms.length} terms');
      }

      // Delete the acronym.json file after successful processing
      try {
        await acronymFile.delete();
        _log.info('Deleted acronym.json file after processing');
      } catch (e) {
        _log.warning('Failed to delete acronym.json file: $e');
        errors.add('Failed to delete acronym.json: $e');
      }

      _log.info(
          'Acronym processing complete: $updatedBooks books updated, $newTerms new terms added');

      return _AcronymProcessResult(
        processed: true,
        updatedBooks: updatedBooks,
        newTerms: newTerms,
        errors: errors,
      );
    } catch (e, stackTrace) {
      _log.warning('Error processing acronym.json', e, stackTrace);
      errors.add('Error processing acronym.json: $e');
      return _AcronymProcessResult(
        processed: false,
        errors: errors,
      );
    }
  }


}

/// Result of processing a single file
class _FileProcessResult {
  final bool wasAdded;
  final bool wasUpdated;
  final int categoriesCreated;

  const _FileProcessResult({
    required this.wasAdded,
    required this.wasUpdated,
    this.categoriesCreated = 0,
  });
}

/// Result of finding/creating category chain
class _CategoryResult {
  final int categoryId;
  final int categoriesCreated;

  const _CategoryResult({
    required this.categoryId,
    required this.categoriesCreated,
  });
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

/// Internal result for recursive restore
class _RestoreResult {
  final int books;
  final int categories;
  final List<String> errors;

  const _RestoreResult({
    this.books = 0,
    this.categories = 0,
    this.errors = const [],
  });
}


/// Result of processing acronym.json file
class _AcronymProcessResult {
  final bool processed;
  final int updatedBooks;
  final int newTerms;
  final List<String> errors;

  const _AcronymProcessResult({
    this.processed = false,
    this.updatedBooks = 0,
    this.newTerms = 0,
    this.errors = const [],
  });
}
