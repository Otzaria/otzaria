import 'dart:async';
import 'dart:isolate';

import 'package:logging/logging.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/book_model.dart';
import '../models/error_model.dart';
import '../models/tracked_book_model.dart';
import '../config/built_in_books_config.dart';
import 'book_scanner_service.dart';
import 'custom_books_service.dart';
import '../utils/category_aliases.dart';

/// Service for loading book data dynamically
///
/// IMPORTANT: Books are scanned ONLY ONCE:
/// - Built-in books: Scanned on first app launch and cached permanently
/// - Custom books: Scanned when user adds them and cached permanently
/// - After scanning, all data is loaded from cache (no re-scanning)
///
/// This new implementation:
/// - Loads built-in books by scanning them on first run ONLY
/// - Supports user-added custom books (scanned once when added)
/// - Caches scanned data permanently for performance
/// - All subsequent loads use cached data exclusively
class DynamicDataLoaderService {
  static final Logger _logger = Logger('DynamicDataLoaderService');

  final BookScannerService _scannerService;
  final CustomBooksService _customBooksService;
  final SharedPreferences _prefs;

  Map<String, BookCategory>? _cachedData;
  bool _isInitialized = false;
  Future<void>? _initialScanFuture;

  static const String _initKey = 'shamor_zachor_initialized';

  DynamicDataLoaderService({
    required BookScannerService scannerService,
    required CustomBooksService customBooksService,
    required SharedPreferences prefs,
  })  : _scannerService = scannerService,
        _customBooksService = customBooksService,
        _prefs = prefs;

  /// Initialize the service and load/scan books
  Future<void> initialize() async {
    if (_isInitialized) {
      return;
    }

    try {
      // Initialize custom books service first
      await _customBooksService.init();

      // Check if this is the first run (built-in books not yet scanned)
      final isFirstRun = !_prefs.containsKey(_initKey);

      if (isFirstRun) {
        _logger.info(
            'First run detected - scheduling one-time scan of built-in books');
        _initialScanFuture ??= _scheduleInitialScan();
      } else {
        // NOT first run - load ALL books from cache (no scanning!)
        _logger.info('Loading built-in books from cache');
        await _loadBuiltInBooksFromCache();
      }

      _isInitialized = true;
      _logger.info('DynamicDataLoaderService initialized');
    } catch (e, stackTrace) {
      _logger.severe('Failed to initialize', e, stackTrace);
      rethrow;
    }
  }

  Future<void> _scheduleInitialScan() {
    final completer = Completer<void>();
    Future<void>(() async {
      try {
        await _scanAndCacheBuiltInBooks();
        await _prefs.setBool(_initKey, true);
        if (!completer.isCompleted) {
          completer.complete();
        }
      } catch (e, stackTrace) {
        _logger.severe('Failed during initial scan', e, stackTrace);
        if (!completer.isCompleted) {
          completer.completeError(e, stackTrace);
        }
      }
    });
    return completer.future;
  }

  /// Load all built-in books from cache (no scanning)
  Future<void> _loadBuiltInBooksFromCache() async {
    final categories = BuiltInBooksConfig.builtInBookPaths;

    for (final categoryEntry in categories.entries) {
      final categoryName = categoryEntry.key;
      final books = categoryEntry.value;

      for (final bookEntry in books.entries) {
        final bookName = bookEntry.key;
        final relativePath = bookEntry.value; // path relative to library base
        final bookId = '$categoryName:$bookName';

        try {
          // Load from cache
          TrackedBook? cachedBook = await _scannerService.loadScanCache(bookId);

          // If not found, try legacy aliases (migration path)
          if (cachedBook == null) {
            final legacyNames = CategoryAliases.legacyAliasesForNew(categoryName);
            for (final legacy in legacyNames) {
              final legacyId = '$legacy:$bookName';
              final legacyBook = await _scannerService.loadScanCache(legacyId);
              if (legacyBook != null) {
                // Migrate to new category key and new bookId
                final migrated = legacyBook.copyWith(
                  categoryName: categoryName,
                  bookId: bookId,
                );
                // Save under the new id for future loads
                await _scannerService.saveScanCache(migrated);
                cachedBook = migrated;
                _logger.info('Migrated cached book ID from "$legacyId" to "$bookId"');
                break;
              }
            }
          }

          if (cachedBook != null) {
            // Add to custom books service (in memory)
            await _customBooksService.addBook(cachedBook);
            _logger.fine('Loaded cached book: $bookId');
          } else {
            _logger.warning('Cache missing for built-in book: $bookId - attempting self-heal re-scan');
            // Optional self-healing: re-scan this built-in book if cache is missing
            try {
              final contentType = _getContentTypeForCategory(categoryName);
              final fullPath = '${_scannerService.libraryBasePath}/$relativePath';
              final trackedBook = await _scannerService.createTrackedBook(
                bookName: bookName,
                categoryName: categoryName,
                bookPath: fullPath,
                contentType: contentType,
                isBuiltIn: true,
              );
              await _scannerService.saveScanCache(trackedBook);
              await _customBooksService.addBook(trackedBook);
              _logger.info('Re-scanned and cached missing built-in book: $bookId');
            } catch (e, st) {
              _logger.warning('Self-heal re-scan failed for $bookId', e, st);
            }
          }
        } catch (e, stackTrace) {
          _logger.warning(
            'Failed to load cached book: $bookId',
            e,
            stackTrace,
          );
        }
      }
    }
  }

  // Legacy alias mapping moved to utils/category_aliases.dart

  /// Scan all built-in books and cache them (ONE TIME ONLY)
  /// This runs only on first initialization and saves all data to cache
  Future<void> _scanAndCacheBuiltInBooks() async {
    final categories = BuiltInBooksConfig.builtInBookPaths;
    final List<Map<String, dynamic>> pendingScans = [];

    _logger.info('Starting one-time scan of built-in books');

    for (final categoryEntry in categories.entries) {
      final categoryName = categoryEntry.key;
      final books = categoryEntry.value;

      for (final bookEntry in books.entries) {
        final bookName = bookEntry.key;
        final relativePath = bookEntry.value;
        final bookId = '$categoryName:$bookName';

        try {
          final existing = await _scannerService.loadScanCache(bookId);
          if (existing != null) {
            _logger.fine('Cache already exists for $bookId, skipping scan');
            await _customBooksService.addBook(existing);
            continue;
          }

          final contentType = _getContentTypeForCategory(categoryName);
          final fullPath = '${_scannerService.libraryBasePath}/$relativePath';

          pendingScans.add({
            'bookId': bookId,
            'bookName': bookName,
            'categoryName': categoryName,
            'bookPath': fullPath,
            'contentType': contentType,
            'isBuiltIn': true,
          });
        } catch (e, stackTrace) {
          _logger.warning(
            'Failed preparing scan for built-in book: $categoryName - $bookName',
            e,
            stackTrace,
          );
        }
      }
    }

    if (pendingScans.isEmpty) {
      _logger.info('Completed one-time scan of built-in books (all cached)');
      return;
    }

    try {
      final results = await _runBuiltInScanIsolate(
        libraryBasePath: _scannerService.libraryBasePath,
        getTocFromFile: _scannerService.getTocFromFile,
        booksToScan: pendingScans,
      );

      for (final result in results) {
        final success = result['success'] as bool? ?? false;
        final bookId = result['bookId'] as String? ?? 'unknown';

        if (!success) {
          _logger.warning(
            'Isolate scan failed for built-in book: $bookId',
            result['error'],
            result['stackTrace'],
          );
          continue;
        }

        final bookJson =
            Map<String, dynamic>.from(result['book'] as Map<String, dynamic>);
        final trackedBook = TrackedBook.fromJson(bookJson);

        await _scannerService.saveScanCache(trackedBook);
        await _customBooksService.addBook(trackedBook);

        _logger.info('Successfully scanned and cached $bookId');
      }

      _logger.info('Completed one-time scan of built-in books');
    } on UnsupportedError catch (e, stackTrace) {
      _logger.warning(
        'Background isolate unsupported; falling back to sequential scan',
        e,
        stackTrace,
      );
      await _scanBuiltInBooksSequentially(pendingScans);
      _logger.info('Completed one-time scan of built-in books (sequential fallback)');
    } on IsolateSpawnException catch (e, stackTrace) {
      _logger.warning(
        'Isolate spawn failed; falling back to sequential scan',
        e,
        stackTrace,
      );
      await _scanBuiltInBooksSequentially(pendingScans);
      _logger.info('Completed one-time scan of built-in books (sequential fallback)');
    } catch (e, stackTrace) {
      _logger.severe('Failed to complete isolate scan of built-in books', e, stackTrace);
      rethrow;
    }
  }

  Future<void> _scanBuiltInBooksSequentially(
    List<Map<String, dynamic>> pendingScans,
  ) async {
    for (final job in pendingScans) {
      final bookId = job['bookId'] as String? ?? 'unknown';

      try {
        final trackedBook = await _scannerService.createTrackedBook(
          bookName: job['bookName'] as String? ?? 'unknown',
          categoryName: job['categoryName'] as String? ?? 'לא ידוע',
          bookPath: job['bookPath'] as String? ?? '',
          contentType: job['contentType'] as String? ?? 'פרק',
          isBuiltIn: job['isBuiltIn'] as bool? ?? true,
        );

        await _scannerService.saveScanCache(trackedBook);
        await _customBooksService.addBook(trackedBook);

        _logger.info('Successfully scanned and cached $bookId (sequential)');
      } catch (e, stackTrace) {
        _logger.warning(
          'Sequential scan failed for built-in book: $bookId',
          e,
          stackTrace,
        );
      }
    }
  }

  /// Get content type based on category name
  String _getContentTypeForCategory(String categoryName) {
    switch (categoryName) {
      case 'תנ"ך':
        return 'פרק';
      case 'משנה':
        return 'משנה';
      case 'תלמוד בבלי':
      case 'תלמוד ירושלמי':
      // תמיכה לאחור
      case 'ש"ס':
      case 'ירושלמי':
        return 'דף';
      case 'רמב"ם':
        return 'הלכה';
      case 'הלכה':
        return 'הלכה';
      default:
        return 'פרק';
    }
  }

  /// Load all book categories (from tracked books)
  Future<Map<String, BookCategory>> loadData() async {
    if (!_isInitialized) {
      await initialize();
    }

    if (_initialScanFuture != null) {
      try {
        await _initialScanFuture;
      } catch (e, stackTrace) {
        _logger.severe('Initial scan failed', e, stackTrace);
      }
    }

    if (_cachedData != null) {
      return _cachedData!;
    }

    try {
      final trackedBooks = _customBooksService.getAllTrackedBooks();
      final Map<String, BookCategory> categories = {};

      // Group books by category
      for (final book in trackedBooks) {
        if (!categories.containsKey(book.categoryName)) {
          categories[book.categoryName] = BookCategory(
            name: book.categoryName,
            contentType: book.bookDetails.contentType,
            books: {},
            defaultStartPage:
                book.bookDetails.contentType == "דף" ? 2 : 1,
            isCustom: false,
            sourceFile: book.sourceFile,
          );
        }

        // Add book to category
        final category = categories[book.categoryName]!;
        category.books[book.bookName] = book.bookDetails;
      }

      _cachedData = categories;
      _logger.info('Loaded ${categories.length} categories with ${trackedBooks.length} books');
      return categories;
    } catch (e, stackTrace) {
      _logger.severe('Failed to load data', e, stackTrace);
      throw ShamorZachorError.fromException(
        e,
        stackTrace: stackTrace,
        customMessage: 'Failed to load book data',
      );
    }
  }

  /// Add a custom book to tracking
  /// This will scan the book ONE TIME and save to cache
  Future<void> addCustomBook({
    required String bookName,
    required String categoryName,
    required String bookPath,
    required String contentType,
  }) async {
    try {
      _logger.info('Adding custom book: $categoryName - $bookName');

      final bookId = '$categoryName:$bookName';

      // Check if already exists in cache
      final existingBook = await _scannerService.loadScanCache(bookId);
      if (existingBook != null) {
        _logger.info('Book already exists in cache: $bookId');
        // Just add to custom books service
        await _customBooksService.addBook(existingBook);
        clearCache();
        return;
      }

      // Scan the book (ONE TIME ONLY - when user adds it)
      _logger.info('Performing one-time scan of custom book: $bookId');
      final trackedBook = await _scannerService.createTrackedBook(
        bookName: bookName,
        categoryName: categoryName,
        bookPath: bookPath,
        contentType: contentType,
        isBuiltIn: false,
      );

      // Save to cache (permanent storage - will not be scanned again)
      await _scannerService.saveScanCache(trackedBook);

      // Add to custom books service
      await _customBooksService.addBook(trackedBook);

      // Clear cached data to force reload
      clearCache();

      _logger.info('Successfully added and cached custom book: ${trackedBook.bookId}');
    } catch (e, stackTrace) {
      _logger.severe('Failed to add custom book', e, stackTrace);
      rethrow;
    }
  }

  /// Remove a book from tracking
  Future<void> removeBook(String bookId) async {
    try {
      await _customBooksService.removeBook(bookId);
      await _scannerService.clearBookCache(bookId);
      clearCache();
      _logger.info('Removed book: $bookId');
    } catch (e, stackTrace) {
      _logger.severe('Failed to remove book: $bookId', e, stackTrace);
      rethrow;
    }
  }

  /// Check if a book is tracked
  bool isBookTracked(String categoryName, String bookName) {
    return _customBooksService.isBookTrackedByName(categoryName, bookName);
  }

  /// Check if a book is built-in
  bool isBuiltInBook(String categoryName, String bookName) {
    return BuiltInBooksConfig.isBuiltInBook(categoryName, bookName);
  }

  /// Get all tracked books (both built-in and custom)
  List<TrackedBook> getAllTrackedBooks() {
    return _customBooksService.getAllTrackedBooks();
  }

  /// Load a specific category by name
  Future<BookCategory?> loadCategory(String categoryName) async {
    try {
      final allData = await loadData();
      return allData[categoryName];
    } catch (e) {
      _logger.severe('Failed to load category $categoryName: $e');
      rethrow;
    }
  }

  /// Get list of available category names
  Future<List<String>> getAvailableCategories() async {
    try {
      final allData = await loadData();
      return allData.keys.toList();
    } catch (e) {
      _logger.severe('Failed to get available categories: $e');
      rethrow;
    }
  }

  /// Clear the cached data
  void clearCache() {
    _cachedData = null;
  }

  /// Check if data is cached
  bool get isDataCached => _cachedData != null;

  /// Get cache size (number of categories)
  int get cacheSize => _cachedData?.length ?? 0;

  /// Force re-scan of all built-in books
  Future<void> rescanBuiltInBooks() async {
    _logger.info('Re-scanning all built-in books');
    await _scanAndCacheBuiltInBooks();
    clearCache();
  }

  /// Get statistics
  Map<String, dynamic> getStatistics() {
    return {
      'initialized': _isInitialized,
      'cached': isDataCached,
      'cacheSize': cacheSize,
      ..._customBooksService.getStatistics(),
    };
  }
}

Future<List<Map<String, dynamic>>> _runBuiltInScanIsolate({
  required String libraryBasePath,
  required Future<List<Map<String, dynamic>>> Function(String bookPath)
      getTocFromFile,
  required List<Map<String, dynamic>> booksToScan,
}) async {
  if (booksToScan.isEmpty) {
    return const [];
  }

  return Isolate.run(() async {
    final scanner = BookScannerService(
      libraryBasePath: libraryBasePath,
      getTocFromFile: getTocFromFile,
    );

    final Logger logger = Logger('DynamicDataLoaderService.Isolate');
    final List<Map<String, dynamic>> results = [];

    for (final job in booksToScan) {
      final bookId = job['bookId'] as String? ?? 'unknown';

      try {
        final trackedBook = await scanner.createTrackedBook(
          bookName: job['bookName'] as String? ?? 'unknown',
          categoryName: job['categoryName'] as String? ?? 'לא ידוע',
          bookPath: job['bookPath'] as String? ?? '',
          contentType: job['contentType'] as String? ?? 'פרק',
          isBuiltIn: job['isBuiltIn'] as bool? ?? true,
        );

        results.add({
          'success': true,
          'bookId': bookId,
          'book': trackedBook.toJson(),
        });
      } catch (e, stackTrace) {
        logger.warning(
          'Failed to scan built-in book in isolate: $bookId',
          e,
          stackTrace,
        );

        results.add({
          'success': false,
          'bookId': bookId,
          'error': e.toString(),
          'stackTrace': stackTrace.toString(),
        });
      }
    }

    return results;
  });
}
