import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as path;

import '../dao/repository/seforim_repository.dart';
import '../../settings/services/custom_folders/custom_folder.dart';
import '../../settings/engine/settings_repository.dart';
import '../generator/generator.dart';
import '../shared/link_processor.dart';

/// Result of a file sync operation
class FileSyncResult {
  final int addedBooks;
  final int updatedBooks;
  final int addedCategories;
  final int addedLinks;
  final int skippedFiles;
  final List<String> errors;
  final Duration duration;

  const FileSyncResult({
    this.addedBooks = 0,
    this.updatedBooks = 0,
    this.addedCategories = 0,
    this.addedLinks = 0,
    this.skippedFiles = 0,
    this.errors = const [],
    this.duration = Duration.zero,
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
  static FileSyncService? _instance;

  final SeforimRepository _repository;
  bool _isSyncing = false;

  /// Progress callback for UI updates
  void Function(double progress, String message)? onProgress;

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

  /// Recursively delete a category and all its contents from DB
  Future<void> _deleteCategoryRecursive(int categoryId) async {
    // First, delete all books in this category
    final books = await _repository.getBooksByCategory(categoryId);
    debugPrint(
        '[FileSyncService] _deleteCategoryRecursive: categoryId=$categoryId, found ${books.length} books');
    for (final book in books) {
      debugPrint(
          '[FileSyncService]   deleting book: id=${book.id}, title="${book.title}"');
      try {
        await _repository.deleteBookCompletely(book.id);
      } catch (e, st) {
        _log.warning(
            'Failed to delete book ${book.id} ("${book.title}"), continuing',
            e,
            st);
      }
    }

    // Then, recursively delete subcategories
    final subCategories = await _repository.getCategoryChildren(categoryId);
    debugPrint(
        '[FileSyncService] _deleteCategoryRecursive: categoryId=$categoryId, found ${subCategories.length} subcategories');
    for (final subCat in subCategories) {
      debugPrint(
          '[FileSyncService]   recursing into subcategory: id=${subCat.id}, title="${subCat.title}"');
      try {
        await _deleteCategoryRecursive(subCat.id);
      } catch (e, st) {
        _log.warning(
            'Failed to delete subcategory ${subCat.id} ("${subCat.title}"), continuing',
            e,
            st);
      }
    }

    // Finally, delete this category
    debugPrint('[FileSyncService]   deleting category itself: id=$categoryId');
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
    debugPrint(
        '[FileSyncService] deleteFolderFromDatabase START: folderCategoryId=$folderCategoryId, personalCategoryId=$personalCategoryId');

    // Delete the folder category and all its contents
    await _deleteCategoryRecursive(folderCategoryId);
    debugPrint(
        '[FileSyncService] deleteFolderFromDatabase: recursive delete done, cleaning up empty parents...');

    // Clean up empty parent categories
    await _cleanupEmptyParentCategories(personalCategoryId);

    // Clean up orphaned tocText entries (shared lookup table, not deleted per-book)
    await _repository.deleteOrphanedTocTexts();
    debugPrint(
        '[FileSyncService] deleteFolderFromDatabase: orphaned tocText cleaned up');

    // Clean up any orphaned line_toc rows (e.g. (-1,-1) artifact from prior bugs)
    await _repository.deleteOrphanedLineToc();
    debugPrint(
        '[FileSyncService] deleteFolderFromDatabase: orphaned line_toc cleaned up');

    debugPrint('[FileSyncService] deleteFolderFromDatabase END');
    _log.info('Folder deleted from DB');
  }

  /// Internal method to scan a single path and import files
  Future<FileSyncResult> _scanAndImportPath(
      {required String rootPath,
      required List<String> categoryPrefix,
      required bool insertContent,
      required DatabaseGenerator generator}) async {
    int addedBooks = 0;
    int updatedBooks = 0;
    int addedCategories = 0;
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
          insertContent: insertContent,
          generator: generator,
        );

        if (result.wasAdded) {
          addedBooks++;
          addedCategories += result.categoriesCreated;
        } else if (result.wasUpdated) {
          updatedBooks++;
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
    );
  }

  /// Process a file with a specific category prefix
  Future<_FileProcessResult> _processFileWithPrefix({
    required String filePath,
    required String basePath,
    required List<String> categoryPrefix,
    required bool insertContent,
    required DatabaseGenerator generator,
  }) async {
    final title = path.basenameWithoutExtension(filePath);
    final extension = path.extension(filePath).toLowerCase();

    // PDF and DOCX files always act as external (content never in DB)
    final isPdfOrDocx = extension == '.pdf' || extension == '.docx';
    final effectiveInsertContent = isPdfOrDocx ? false : insertContent;

    // Build category path
    final relativeCategories = _parsePathToCategories(filePath, basePath);
    final categoryPath = [...categoryPrefix, ...relativeCategories];

    if (categoryPath.isEmpty && categoryPrefix.isEmpty) {
      _log.warning('Could not build category path for: $filePath');
      return const _FileProcessResult(wasAdded: false, wasUpdated: false);
    }

    // Find or create category chain using generator's unified method
    final categoryResult =
        await generator.findOrCreateCategoryChain(categoryPath);
    final categoryId = categoryResult.categoryId;
    final categoriesCreated = categoryResult.categoriesCreated;

    // Extract file type from extension (remove the dot)
    final fileType = extension.replaceFirst('.', '').toLowerCase();

    // Check if book already exists in this category with the same file type
    final existingBook = await _repository
        .checkBookExistsInCategoryWithFileType(title, categoryId, fileType);

    bool wasAdded = false;
    bool wasUpdated = false;

    if (existingBook != null) {
      debugPrint(
          '[FileSyncService] Found existing book: title=$title, id=${existingBook.id}, filePath=${existingBook.filePath}, isFileBacked=${existingBook.isFileBacked}, totalLines=${existingBook.totalLines}');

      // Book exists - check if file has changed
      final file = File(filePath);
      final fileStat = await file.stat();
      final fileSize = fileStat.size;
      final lastModified = fileStat.modified.millisecondsSinceEpoch;

      // Only update if file has actually changed
      final fileChanged = existingBook.fileSize != fileSize ||
          existingBook.lastModified != lastModified;

      // Also update if the storage preference changed (e.g. user toggled addToDatabase)
      final expectedIsContentExternal = !effectiveInsertContent;
      final storageChanged =
          existingBook.isFileBacked != expectedIsContentExternal;

      if (fileChanged || storageChanged) {
        if (storageChanged) {
          debugPrint(
              '[FileSyncService] Storage preference changed for ${existingBook.title}: isFileBacked=${existingBook.isFileBacked} -> $expectedIsContentExternal');
        }
        wasUpdated = true;
        await generator.createAndProcessBook(
          filePath,
          categoryId,
          insertContent: effectiveInsertContent,
        );
      }
    } else {
      wasAdded = true;
      await generator.createAndProcessBook(
        filePath,
        categoryId,
        insertContent: effectiveInsertContent,
      );
    }

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
    int skippedFiles = 0;
    final errors = <String>[];

    try {
      final libraryPath = Settings.getValue<String>('key-library-path');
      if (libraryPath == null || libraryPath.isEmpty) {
        _log.warning('Library path not set, skipping sync');
        return const FileSyncResult(errors: ['Library path not set']);
      }

      // Setup Generator
      final generator =
          DatabaseGenerator(libraryPath, _repository, onProgress: onProgress);
      generator.initializeForSync(
          libraryRoot: path.join(libraryPath, 'אוצריא'));
      // Load metadata

      // Skip scanning אוצריא folder - it only contains the DB file now
      // All books are already in the database
      _log.info('Skipping אוצריא folder scan - books are in database');

      // Scan ALL custom folders (DB is single source of truth)
      _reportProgress(0.4, 'סורק תיקיות מותאמות אישית...');
      // Load custom folders from settings
      final customFoldersJson =
          Settings.getValue<String>(SettingsRepository.keyCustomFolders);
      final customFolders = CustomFoldersManager.loadFolders(customFoldersJson);

      if (customFolders.isNotEmpty) {
        _log.info('Found ${customFolders.length} custom folders to sync');

        for (final folder in customFolders) {
          final folderDir = Directory(folder.path);
          if (!await folderDir.exists()) {
            _log.warning('Custom folder does not exist: ${folder.path}');
            errors.add('תיקייה לא קיימת: ${folder.name}');
            continue;
          }

          _log.info(
              'Scanning custom folder: ${folder.path} (addToDatabase: ${folder.addToDatabase})');

          // insertContent depends on the addToDatabase flag:
          // true = content lines go into DB
          // false = only metadata/TOC saved, content read on-the-fly from file
          final result = await _scanAndImportPath(
              rootPath: folder.path,
              categoryPrefix: ['ספרים אישיים', folder.name],
              insertContent: folder.addToDatabase,
              generator: generator);

          addedBooks += result.addedBooks;
          updatedBooks += result.updatedBooks;
          addedCategories += result.addedCategories;
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

        // Use unified link processor method
        final linkProcessor = LinkProcessor(_repository);
        final linksResult = await linkProcessor.processLinksDirectory(
          linksPath: linksPath,
          onProgress: (progress, message) {
            // Map progress from 0-1 to 0.6-0.9 range
            _reportProgress(0.6 + (progress * 0.3), message);
          },
          updateBookHasLinks: true,
        );
        addedLinks += linksResult.processedLinks;
        errors.addAll(linksResult.errors);
      }

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
      skippedFiles: skippedFiles,
      errors: errors,
      duration: stopwatch.elapsed,
    );

    _log.info('Sync completed: $result');
    return result;
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

  /// Delete the physical files/directory of a custom folder
  /// Used when the user explicitly confirms file deletion
  Future<bool> deletePhysicalFolder(String folderPath) async {
    try {
      final dir = Directory(folderPath);
      if (await dir.exists()) {
        await dir.delete(recursive: true);
        _log.info('Deleted physical folder: $folderPath');
        return true;
      }
      return false;
    } catch (e, stackTrace) {
      _log.warning(
          'Error deleting physical folder: $folderPath', e, stackTrace);
      return false;
    }
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

  const _FileProcessResult({
    required this.wasAdded,
    required this.wasUpdated,
    this.categoriesCreated = 0,
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
