import 'dart:convert';
import 'dart:io';
import 'package:logging/logging.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import '../models/book_model.dart';
import '../models/tracked_book_model.dart';

/// Service for scanning books and generating their structure data
///
/// IMPORTANT: Each book is scanned ONLY ONCE and then cached permanently.
/// The cache is used for all subsequent loads - no re-scanning occurs.
///
/// This service provides functionality to:
/// - Scan a book file and extract its table of contents (ONE TIME ONLY)
/// - Convert TOC to BookCategory/BookDetails format
/// - Cache scanned book data permanently for performance
/// - Load cached data on subsequent runs (no re-scanning)
class BookScannerService {
  static final Logger _logger = Logger('BookScannerService');

  final String libraryBasePath;

  /// Function to get TOC from a book file
  /// This should be provided by the main app
  final Future<List<Map<String, dynamic>>> Function(String bookPath) getTocFromFile;

  BookScannerService({
    required this.libraryBasePath,
    required this.getTocFromFile,
  });

  /// Scan a book and create its BookDetails structure
  ///
  /// [bookPath] - Full path to the book file
  /// [contentType] - Type of content ("פרק", "דף", etc.)
  Future<BookDetails> scanBook(String bookPath, String contentType) async {
    try {
      _logger.info('Scanning book: $bookPath');

      // Get TOC from the book
      final toc = await getTocFromFile(bookPath);

      if (toc.isEmpty) {
        _logger.warning('No TOC found for book: $bookPath');
        // Return a simple single-part book
        return BookDetails(
          contentType: contentType,
          parts: [
            BookPart(
              name: 'ראשי',
              startPage: contentType == "דף" ? 2 : 1,
              endPage: contentType == "דף" ? 2 : 1,
            ),
          ],
          isCustom: true,
        );
      }

      // Convert TOC to BookParts
      final parts = _convertTocToParts(toc, contentType);

      return BookDetails(
        contentType: contentType,
        parts: parts,
        isCustom: true,
      );
    } catch (e, stackTrace) {
      _logger.severe('Failed to scan book: $bookPath', e, stackTrace);
      rethrow;
    }
  }

  /// Convert TOC entries to BookParts
  List<BookPart> _convertTocToParts(
    List<Map<String, dynamic>> toc,
    String contentType,
  ) {
    if (toc.isEmpty) {
      return [
        BookPart(
          name: 'ראשי',
          startPage: contentType == "דף" ? 2 : 1,
          endPage: contentType == "דף" ? 2 : 1,
        ),
      ];
    }

    // Group TOC entries by level 1 (top-level parts)
    final List<BookPart> parts = [];
    final topLevelEntries = toc.where((entry) => entry['level'] == 1).toList();

    if (topLevelEntries.isEmpty) {
      // If no level 1 entries, treat the whole book as one part
      final lastIndex = toc.last['index'] as int;
      return [
        BookPart(
          name: 'ראשי',
          startPage: contentType == "דף" ? 2 : 1,
          endPage: _indexToPage(lastIndex, contentType),
        ),
      ];
    }

    for (int i = 0; i < topLevelEntries.length; i++) {
      final entry = topLevelEntries[i];
      final startIndex = entry['index'] as int;
      final text = entry['text'] as String;

      // Find end index (start of next part or end of book)
      final endIndex = i < topLevelEntries.length - 1
          ? (topLevelEntries[i + 1]['index'] as int) - 1
          : (toc.last['index'] as int);

      parts.add(BookPart(
        name: text,
        startPage: _indexToPage(startIndex, contentType),
        endPage: _indexToPage(endIndex, contentType),
      ));
    }

    return parts;
  }

  /// Convert line index to page number
  int _indexToPage(int index, String contentType) {
    // For "דף" type, pages start at 2
    // For other types, pages start at 1
    // This is a simplified conversion - may need adjustment based on actual data
    if (contentType == "דף") {
      return (index ~/ 2) + 2;
    } else {
      return index + 1;
    }
  }

  /// Create a TrackedBook from a scanned book
  Future<TrackedBook> createTrackedBook({
    required String bookName,
    required String categoryName,
    required String bookPath,
    required String contentType,
    required bool isBuiltIn,
  }) async {
    final bookDetails = await scanBook(bookPath, contentType);

    return TrackedBook(
      bookId: '$categoryName:$bookName',
      bookName: bookName,
      categoryName: categoryName,
      isBuiltIn: isBuiltIn,
      bookPath: bookPath,
      bookDetails: bookDetails,
      sourceFile: isBuiltIn ? '${categoryName.toLowerCase()}.json' : 'custom',
      dateAdded: DateTime.now(),
      lastScanned: DateTime.now(),
    );
  }

  /// Save scanned book data to cache
  Future<void> saveScanCache(TrackedBook trackedBook) async {
    try {
      final cacheDir = await _getCacheDirectory();
      final cacheFile = File(p.join(
        cacheDir.path,
        '${trackedBook.bookId.replaceAll(':', '_')}.json',
      ));

      await cacheFile.writeAsString(
        jsonEncode(trackedBook.toJson()),
        flush: true,
      );

      _logger.info('Saved scan cache for: ${trackedBook.bookId}');
    } catch (e, stackTrace) {
      _logger.warning('Failed to save scan cache', e, stackTrace);
      // Non-critical error, don't rethrow
    }
  }

  /// Load scanned book data from cache
  Future<TrackedBook?> loadScanCache(String bookId) async {
    try {
      final cacheDir = await _getCacheDirectory();
      final cacheFile = File(p.join(
        cacheDir.path,
        '${bookId.replaceAll(':', '_')}.json',
      ));

      if (!await cacheFile.exists()) {
        return null;
      }

      final jsonString = await cacheFile.readAsString();
      final jsonData = jsonDecode(jsonString) as Map<String, dynamic>;

      return TrackedBook.fromJson(jsonData);
    } catch (e, stackTrace) {
      _logger.warning('Failed to load scan cache for $bookId', e, stackTrace);
      return null;
    }
  }

  /// Get cache directory for scanned books
  Future<Directory> _getCacheDirectory() async {
    final appDir = await getApplicationSupportDirectory();
    final cacheDir = Directory(p.join(appDir.path, 'shamor_zachor', 'scanned_books'));

    if (!await cacheDir.exists()) {
      await cacheDir.create(recursive: true);
    }

    return cacheDir;
  }

  /// Clear all scan cache
  Future<void> clearAllCache() async {
    try {
      final cacheDir = await _getCacheDirectory();
      if (await cacheDir.exists()) {
        await cacheDir.delete(recursive: true);
      }
      _logger.info('Cleared all scan cache');
    } catch (e, stackTrace) {
      _logger.warning('Failed to clear scan cache', e, stackTrace);
    }
  }

  /// Clear cache for a specific book
  Future<void> clearBookCache(String bookId) async {
    try {
      final cacheDir = await _getCacheDirectory();
      final cacheFile = File(p.join(
        cacheDir.path,
        '${bookId.replaceAll(':', '_')}.json',
      ));

      if (await cacheFile.exists()) {
        await cacheFile.delete();
      }
      _logger.info('Cleared cache for: $bookId');
    } catch (e, stackTrace) {
      _logger.warning('Failed to clear cache for $bookId', e, stackTrace);
    }
  }
}
