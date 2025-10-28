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
        _logger.info('First run detected - performing one-time scan of built-in books');
        await _scanAndCacheBuiltInBooks();
        await _prefs.setBool(_initKey, true);
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

    _logger.info('Starting one-time scan of built-in books');

    for (final categoryEntry in categories.entries) {
      final categoryName = categoryEntry.key;
      final books = categoryEntry.value;

      for (final bookEntry in books.entries) {
        final bookName = bookEntry.key;
        final bookPath = bookEntry.value;

        try {
          _logger.info('Scanning built-in book: $categoryName - $bookName');

          // Determine content type based on category
          final contentType = _getContentTypeForCategory(categoryName);

          final bookId = '$categoryName:$bookName';

          // Create the full path
          final fullPath =
              '${_scannerService.libraryBasePath}/$bookPath';

          // Scan the book (ONE TIME ONLY)
          final trackedBook = await _scannerService.createTrackedBook(
            bookName: bookName,
            categoryName: categoryName,
            bookPath: fullPath,
            contentType: contentType,
            isBuiltIn: true,
          );

          // Save to cache (this is the permanent storage)
          await _scannerService.saveScanCache(trackedBook);

          // Add to custom books service
          await _customBooksService.addBook(trackedBook);

          _logger.info('Successfully scanned and cached $bookId');
        } catch (e, stackTrace) {
          _logger.warning(
            'Failed to scan built-in book: $categoryName - $bookName',
            e,
            stackTrace,
          );
          // Continue with other books
        }
      }
    }

    _logger.info('Completed one-time scan of built-in books');
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
