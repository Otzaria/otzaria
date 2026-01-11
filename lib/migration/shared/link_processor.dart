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
      if(book.fileType != 'txt') {
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
      _log.fine('Loaded ${arr.length} line id/index pairs for book $bookId into memory');
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
        _log.warning('Unexpected JSON structure in file: ${path.basename(linkFile)}');
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
              _log.fine('Line not found - source: $sourceLineIndex, target: $targetLineIndex');
            }
            skipped++;
            continue;
          }

          linksToInsert.add(Link(
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
      _log.warning('Error processing link file: ${path.basename(linkFile)}', e, stackTrace);
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
}
