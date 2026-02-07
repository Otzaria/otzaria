import 'dart:convert';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:path/path.dart' as path;

import '../core/models/link.dart';
import '../dao/repository/seforim_repository.dart';

/// Data class for deserializing link data from JSON files
class LinkData {
  final String heRef2;
  final double lineIndex1;
  final String path2;
  final double lineIndex2;
  final String connectionType;

  const LinkData({
    required this.heRef2,
    required this.lineIndex1,
    required this.path2,
    required this.lineIndex2,
    this.connectionType = '',
  });

  factory LinkData.fromJson(Map<String, dynamic> json) {
    return LinkData(
      heRef2: json['heRef_2'] as String? ?? '',
      lineIndex1: (json['line_index_1'] as num?)?.toDouble() ?? 0,
      path2: json['path_2'] as String? ?? '',
      lineIndex2: (json['line_index_2'] as num?)?.toDouble() ?? 0,
      connectionType: json['Conection Type'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'heRef_2': heRef2,
      'line_index_1': lineIndex1,
      'path_2': path2,
      'line_index_2': lineIndex2,
      'Conection Type': connectionType,
    };
  }
}

/// Result of processing a link file
class LinkProcessResult {
  final int processedLinks;
  final int skippedLinks;
  final int totalLinks;
  final bool success;

  const LinkProcessResult({
    this.processedLinks = 0,
    this.skippedLinks = 0,
    this.totalLinks = 0,
    this.success = true,
  });

  @override
  String toString() =>
      'LinkProcessResult(processed: $processedLinks, skipped: $skippedLinks, total: $totalLinks, success: $success)';
}

/// Utility class for processing link files.
///
/// This class provides a unified way to process link JSON files
/// for both database generation and file sync operations.
class LinkProcessor {
  static final _log = Logger('LinkProcessor');

  /// Cache for book titles to IDs
  final Map<String, int> _bookTitleToId = {};

  /// Cache for book line indices to IDs
  final Map<int, List<int>> _bookLineIndexToId = {};

  /// The repository used to access the database
  final SeforimRepository _repository;

  /// Whether to use verbose logging
  final bool verboseLogging;

  LinkProcessor(this._repository, {this.verboseLogging = false});

  /// Loads all books into cache for faster link processing
  Future<void> loadBooksCache() async {
    if (_bookTitleToId.isNotEmpty) return; // Already loaded

    final books = await _repository.getAllBooks();
    for (final book in books) {
      if (book.fileType != 'txt') {
        continue;
      }
      _bookTitleToId[book.title] = book.id;
    }
  }

  /// Loads lines cache for a specific book
  Future<void> _loadBookLinesCache(int bookId) async {
    if (_bookLineIndexToId.containsKey(bookId)) return;

    // Use optimized query to fetch only IDs and indices
    final rows = await _repository.getLineIdsAndIndices(bookId);

    if (rows.isEmpty) {
      _bookLineIndexToId[bookId] = [];
      return;
    }

    // Find max index to size the array
    int maxIndex = 0;
    for (final row in rows) {
      final idx = row['lineIndex'] as int;
      if (idx > maxIndex) maxIndex = idx;
    }

    final arr = List<int>.filled(maxIndex + 1, 0);

    for (final row in rows) {
      final idx = row['lineIndex'] as int;
      final id = row['id'] as int;
      if (idx >= 0 && idx < arr.length) {
        arr[idx] = id;
      }
    }

    _bookLineIndexToId[bookId] = arr;

    if (verboseLogging) {
      _log.fine(
          'Loaded ${arr.length} line id/index pairs for book $bookId into memory');
    }
  }

  /// Finds a book ID by title from the cache
  /// Returns the first matching book ID or null if not found
  int? _findBookIdByTitle(String title) {
    return _bookTitleToId[title];
  }

  /// Processes a single link JSON file
  ///
  /// [linkFile] The path to the link file
  /// Returns a [LinkProcessResult] with the processing statistics
  Future<LinkProcessResult> processLinkFile(String linkFile) async {
    // Extract book title from filename
    final bookTitle = path
        .basenameWithoutExtension(path.basename(linkFile))
        .replaceAll('_links', '')
        .replaceAll(' links', '');

    // Find source book
    final sourceBookId = _findBookIdByTitle(bookTitle);

    if (sourceBookId == null) {
      _log.warning('Source book not found for links: $bookTitle');
      return const LinkProcessResult(success: false);
    }

    // Load lines cache for source book
    await _loadBookLinesCache(sourceBookId);

    try {
      final file = File(linkFile);
      final content = await file.readAsString();

      final jsonData = jsonDecode(content);

      // Handle different JSON structures
      List<dynamic> linksList;
      if (jsonData is List<dynamic>) {
        linksList = jsonData;
      } else if (jsonData is Map<String, dynamic>) {
        // If it's a map, try to find a list property or convert the map itself
        if (jsonData.containsKey('links')) {
          linksList = jsonData['links'] as List<dynamic>;
        } else if (jsonData.containsKey('data')) {
          linksList = jsonData['data'] as List<dynamic>;
        } else {
          // If it's a single object, wrap it in a list
          linksList = [jsonData];
        }
      } else {
        _log.warning(
            'Unexpected JSON structure in file: ${path.basename(linkFile)}');
        return const LinkProcessResult(success: false);
      }

      final linksData = linksList
          .map((item) => LinkData.fromJson(item as Map<String, dynamic>))
          .toList();

      // Prepare batch of links
      final linksToInsert = <Link>[];
      var skipped = 0;

      for (final linkData in linksData) {
        try {
          // Handle paths with backslashes
          final pathStr = linkData.path2;
          final targetTitle = pathStr.contains('\\')
              ? pathStr.split('\\').last.replaceAll(RegExp(r'\.[^.]*$'), '')
              : path.basenameWithoutExtension(pathStr);

          // Find target book
          final targetBookId = _findBookIdByTitle(targetTitle);

          if (targetBookId == null) {
            if (verboseLogging) {
              _log.fine('Target book not found: $targetTitle');
            }
            skipped++;
            continue;
          }

          // Load lines cache for target book
          await _loadBookLinesCache(targetBookId);

          // Adjust indices from 1-based to 0-based
          final sourceLineIndex = (linkData.lineIndex1.toInt() - 1)
              .clamp(0, double.infinity)
              .toInt();
          final targetLineIndex = (linkData.lineIndex2.toInt() - 1)
              .clamp(0, double.infinity)
              .toInt();

          // Get line IDs from cache
          final sourceLineArr = _bookLineIndexToId[sourceBookId];
          final targetLineArr = _bookLineIndexToId[targetBookId];

          final sourceLineId = (sourceLineArr != null &&
                  sourceLineIndex >= 0 &&
                  sourceLineIndex < sourceLineArr.length)
              ? (sourceLineArr[sourceLineIndex] != 0
                  ? sourceLineArr[sourceLineIndex]
                  : null)
              : null;

          final targetLineId = (targetLineArr != null &&
                  targetLineIndex >= 0 &&
                  targetLineIndex < targetLineArr.length)
              ? (targetLineArr[targetLineIndex] != 0
                  ? targetLineArr[targetLineIndex]
                  : null)
              : null;

          if (sourceLineId == null || targetLineId == null) {
            if (verboseLogging) {
              _log.fine(
                  'Line not found - source: $sourceLineIndex, target: $targetLineIndex');
            }
            skipped++;
            continue;
          }

          // קבל מזהה לינק שלילי חדש
          final negativeLinkId = await _repository.getNextNegativeLinkId();

          linksToInsert.add(Link(
            id: negativeLinkId,
            sourceBookId: sourceBookId,
            targetBookId: targetBookId,
            sourceLineId: sourceLineId,
            targetLineId: targetLineId,
            connectionType: ConnectionType.fromString(linkData.connectionType),
          ));

          // Insert in batches of 1000
          if (linksToInsert.length >= 1000) {
            await _repository.insertLinksBatch(linksToInsert);
            linksToInsert.clear();
          }
        } catch (e) {
          _log.warning('Error processing link: ${linkData.heRef2}', e);
          skipped++;
        }
      }

      // Insert remaining links
      if (linksToInsert.isNotEmpty) {
        await _repository.insertLinksBatch(linksToInsert);
      }

      final processed = linksData.length - skipped;
      return LinkProcessResult(
        processedLinks: processed,
        skippedLinks: skipped,
        totalLinks: linksData.length,
        success: true,
      );
    } catch (e, stackTrace) {
      _log.warning('Error processing link file: ${path.basename(linkFile)}', e,
          stackTrace);
      return const LinkProcessResult(success: false);
    }
  }

  /// Clears all caches
  void clearCaches() {
    _bookTitleToId.clear();
    _bookLineIndexToId.clear();
  }

  /// Clears only the line cache to free memory while keeping book titles
  void clearLineCache() {
    _bookLineIndexToId.clear();
  }

  /// Process all link files in a directory with transaction support.
  ///
  /// This is the unified method for processing links, combining the best
  /// practices from both generator and file sync operations:
  /// - Uses database transactions for atomicity and performance
  /// - Commits in batches to avoid memory issues
  /// - Clears line cache periodically to prevent memory explosion
  /// - Optionally updates the book_has_links table
  ///
  /// [linksPath] The path to the links directory
  /// [onProgress] Optional callback for progress updates (0.0 to 1.0)
  /// [updateBookHasLinks] Whether to update the book_has_links table after processing
  /// [batchCommitSize] Number of files to process before committing (default: 50)
  ///
  /// Returns a [LinkDirectoryResult] with processing statistics
  Future<LinkDirectoryResult> processLinksDirectory({
    required String linksPath,
    void Function(double progress, String message)? onProgress,
    bool updateBookHasLinks = true,
    int batchCommitSize = 50,
  }) async {
    final linksDir = Directory(linksPath);

    if (!await linksDir.exists()) {
      _log.info('Links directory does not exist: $linksPath');
      return const LinkDirectoryResult();
    }

    // Ensure books cache is loaded
    await loadBooksCache();

    // Collect all JSON link files (excluding _headings.json files)
    final linkFiles = <File>[];
    await for (final entity in linksDir.list()) {
      if (entity is File &&
          path.extension(entity.path) == '.json' &&
          !path.basename(entity.path).endsWith('_headings.json')) {
        linkFiles.add(entity);
      }
    }

    if (linkFiles.isEmpty) {
      _log.info('No JSON link files found in: $linksPath');
      return const LinkDirectoryResult();
    }

    final totalFiles = linkFiles.length;
    var processedFiles = 0;
    var totalLinks = 0;
    var skippedLinks = 0;
    var deletedFiles = 0;
    final errors = <String>[];

    _log.info('Found $totalFiles link files to process');
    onProgress?.call(0.0, 'מתחיל עיבוד קישורים (0/$totalFiles קבצים)');

    // Process all link files within a transaction for better performance
    await _repository.beginTransaction();

    // Track files to delete after successful commit
    final filesToDelete = <File>[];

    try {
      for (final file in linkFiles) {
        try {
          final result = await processLinkFile(file.path);
          totalLinks += result.processedLinks;
          skippedLinks += result.skippedLinks;
          processedFiles++;

          // Update progress
          final progress = totalFiles > 0 ? processedFiles / totalFiles : 0.0;
          final fileName = path.basename(file.path);
          onProgress?.call(progress,
              'מעבד קישורים: $fileName ($processedFiles/$totalFiles)');

          // Add to deletion list only if successful
          if (result.success && result.processedLinks > 0) {
            filesToDelete.add(file);
          }

          // Commit transaction every batchCommitSize files to avoid excessive memory usage
          if (processedFiles % batchCommitSize == 0) {
            await _repository.commitTransaction();

            // Delete files that were just committed
            for (final f in filesToDelete) {
              try {
                if (await f.exists()) {
                  await f.delete();
                  deletedFiles++;
                  _log.info('Deleted processed link file: ${f.path}');
                }
              } catch (e) {
                _log.warning('Failed to delete link file ${f.path}', e);
              }
            }
            filesToDelete.clear();

            // Clear line cache to prevent memory explosion
            clearLineCache();
            await _repository.beginTransaction();
          }
        } catch (e, stackTrace) {
          _log.warning(
              'Error processing link file: ${file.path}', e, stackTrace);
          errors.add('Error processing ${path.basename(file.path)}: $e');
        }
      }

      // Commit the final transaction
      await _repository.commitTransaction();

      // Delete remaining files
      for (final f in filesToDelete) {
        try {
          if (await f.exists()) {
            await f.delete();
            deletedFiles++;
            _log.info('Deleted processed link file: ${f.path}');
          }
        } catch (e) {
          _log.warning('Failed to delete link file ${f.path}', e);
        }
      }
      filesToDelete.clear();

      // Clear caches to free memory
      clearCaches();
    } catch (e) {
      // Rollback on error
      _log.severe('Error during link processing, rolling back transaction', e);
      await _repository.rollbackTransaction();
      rethrow;
    }

    // Optionally update the book_has_links table
    if (updateBookHasLinks && totalLinks > 0) {
      onProgress?.call(1.0, 'מעדכן טבלת קישורים לספרים...');
      await _updateBookHasLinksTable();
    }

    // Delete links directory if it became empty
    await _deleteIfEmpty(linksDir);

    final resultMessage = 'הושלם עיבוד $totalLinks קישורים מ-$totalFiles קבצים';
    onProgress?.call(1.0, resultMessage);
    _log.info(resultMessage);

    return LinkDirectoryResult(
      processedLinks: totalLinks,
      skippedLinks: skippedLinks,
      totalFiles: totalFiles,
      deletedFiles: deletedFiles,
      errors: errors,
    );
  }

  /// Updates the book_has_links table to indicate which books have source/target links.
  Future<void> _updateBookHasLinksTable() async {
    // Update book_has_links table using bulk SQL
    await _repository.executeRawQuery('''
      INSERT OR REPLACE INTO book_has_links (bookId, hasSourceLinks, hasTargetLinks)
      SELECT 
        b.id,
        CASE WHEN EXISTS (SELECT 1 FROM link WHERE sourceBookId = b.id) THEN 1 ELSE 0 END,
        CASE WHEN EXISTS (SELECT 1 FROM link WHERE targetBookId = b.id) THEN 1 ELSE 0 END
      FROM book b
      WHERE 
        EXISTS (SELECT 1 FROM link WHERE sourceBookId = b.id) 
        OR 
        EXISTS (SELECT 1 FROM link WHERE targetBookId = b.id)
    ''');

    // Update connection flags in book table
    await _repository.executeRawQuery('''
      WITH booctions AS (
        SELECT 
            book_id,
            MAX(CASE WHEN connectionTypeId = 2 THEN 1 ELSE 0 END) as has_targum,
            MAX(CASE WHEN connectionTypeId = 3 THEN 1 ELSE 0 END) as has_reference,
            MAX(CASE WHEN connectionTypeId = 1 THEN 1 ELSE 0 END) as has_commentary,
            MAX(CASE WHEN connectionTypeId = 4 THEN 1 ELSE 0 END) as has_other
        FROM (
            SELECT sourceBookId as book_id, connectionTypeId FROM link
            UNION ALL
            SELECT targetBookId as book_id, connectionTypeId FROM link
        ) all_connections
        GROUP BY book_id
      )
      UPDATE book 
      SET 
          hasTargumConnection = COALESCE(bc.has_targum, 0),
          hasReferenceConnection = COALESCE(bc.has_reference, 0),
          hasCommentaryConnection = COALESCE(bc.has_commentary, 0),
          hasOtherConnection = COALESCE(bc.has_other, 0)
      FROM book_connections bc
      WHERE book.id = bc.book_id
    ''');

    _log.info('Book_has_links table updated');
  }

  /// Deletes a directory if it is empty.
  Future<void> _deleteIfEmpty(Directory dir) async {
    try {
      if (!await dir.exists()) return;
      if (await dir.list().isEmpty) {
        await dir.delete();
        _log.info('Deleted empty directory: ${dir.path}');
      }
    } catch (e) {
      // Ignore deletion errors (e.g. permissions)
    }
  }
}

/// Result of processing a links directory
class LinkDirectoryResult {
  final int processedLinks;
  final int skippedLinks;
  final int totalFiles;
  final int deletedFiles;
  final List<String> errors;

  const LinkDirectoryResult({
    this.processedLinks = 0,
    this.skippedLinks = 0,
    this.totalFiles = 0,
    this.deletedFiles = 0,
    this.errors = const [],
  });

  @override
  String toString() =>
      'LinkDirectoryResult(processed: $processedLinks, skipped: $skippedLinks, '
      'files: $totalFiles, deleted: $deletedFiles, errors: ${errors.length})';
}
