import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../config/built_in_books_config.dart';
import '../models/book_model.dart';
import '../models/error_model.dart';
import '../models/tracked_book_model.dart';
import 'book_scanner_service.dart';
import 'custom_books_service.dart';

/// Service for loading book data without scanning built-in content on startup.
///
/// Built-in books are distributed as a pre-generated JSON asset and are loaded
/// directly from disk. Custom books that users add are still scanned once at
/// the moment of addition and stored in SharedPreferences.
class DynamicDataLoaderService {
  static final Logger _logger = Logger('DynamicDataLoaderService');

  static const String _builtInAssetPath =
      'packages/shamor_zachor/assets/data/built_in_tracked_books.json';

  final BookScannerService _scannerService;
  final CustomBooksService _customBooksService;

  Map<String, BookCategory>? _cachedData;
  bool _isInitialized = false;
  List<TrackedBook> _builtInTrackedBooks = const [];
  Map<String, TrackedBook> _builtInBookMap = const {};
  Future<void>? _builtInLoadFuture;
  bool _builtInLoadFailed = false;

  DynamicDataLoaderService({
    required BookScannerService scannerService,
    required CustomBooksService customBooksService,
    required SharedPreferences prefs,
  })  : _scannerService = scannerService,
        _customBooksService = customBooksService;

  /// Initialize the service and load built-in books from the static asset.
  Future<void> initialize() async {
    if (_isInitialized) {
      _logger.fine('Already initialized, skipping');
      return;
    }

    try {
      _logger.info('Starting DynamicDataLoaderService initialization');

      await _customBooksService.init();
      _scheduleBuiltInBooksLoad();

      _isInitialized = true;
      _logger.info(
          'DynamicDataLoaderService initialized (custom: ${_customBooksService.getCustomBooks().length})');
    } catch (e, stackTrace) {
      _logger.severe('Failed to initialize', e, stackTrace);
      rethrow;
    }
  }

  Future<void> _loadBuiltInBooksFromAsset() async {
    if (_builtInTrackedBooks.isNotEmpty) {
      return;
    }

    try {
      final jsonString = await rootBundle.loadString(_builtInAssetPath);
      final Map<String, dynamic> jsonData = jsonDecode(jsonString);
      final List<dynamic> booksJson =
          jsonData['books'] as List<dynamic>? ?? const [];

      final List<TrackedBook> parsed = [];
      final Map<String, TrackedBook> mapById = {};

      for (final dynamic rawEntry in booksJson) {
        if (rawEntry is! Map<String, dynamic>) {
          continue;
        }

        final entry = Map<String, dynamic>.from(rawEntry);
        final bookId = entry['bookId'] as String? ?? '';
        final bookName = entry['bookName'] as String? ?? '';
        final categoryName = entry['categoryName'] as String? ?? '';

        if (bookId.isEmpty || bookName.isEmpty || categoryName.isEmpty) {
          _logger
              .warning('Skipping malformed built-in book entry: ${entry.keys}');
          continue;
        }

        final Map<String, dynamic> detailsJson = Map<String, dynamic>.from(
            entry['bookDetails'] as Map<String, dynamic>? ?? const {});
        final contentType = detailsJson['contentType'] as String? ?? 'פרק';
        final bookDetails = BookDetails.fromJson(
          detailsJson,
          contentType: contentType,
          isCustom: false,
          id: detailsJson['id'] as String?,
        );

        final relativePath = _resolveRelativePath(
          categoryName,
          bookName,
          entry['relativePath'] as String? ?? '',
        );
        final fullPath = _buildFullPath(relativePath);

        final dateAddedStr = entry['dateAdded'] as String?;
        final lastScannedStr = entry['lastScanned'] as String?;
        final dateAdded = dateAddedStr != null
            ? DateTime.tryParse(dateAddedStr) ??
                DateTime.fromMillisecondsSinceEpoch(0)
            : DateTime.fromMillisecondsSinceEpoch(0);
        final lastScanned =
            lastScannedStr != null ? DateTime.tryParse(lastScannedStr) : null;

        final trackedBook = TrackedBook(
          bookId: bookId,
          bookName: bookName,
          categoryName: categoryName,
          isBuiltIn: true,
          bookPath: fullPath,
          bookDetails: bookDetails,
          sourceFile:
              entry['sourceFile'] as String? ?? 'built_in_tracked_books.json',
          dateAdded: dateAdded,
          lastScanned: lastScanned,
        );

        parsed.add(trackedBook);
        mapById[bookId] = trackedBook;
      }

      _builtInTrackedBooks = List.unmodifiable(parsed);
      _builtInBookMap = Map.unmodifiable(mapById);
      _builtInLoadFailed = false;

      _logger.info(
          'Loaded ${_builtInTrackedBooks.length} built-in books from static asset');
    } catch (e, stackTrace) {
      _builtInLoadFailed = true;
      _logger.severe('Failed to load built-in books from asset', e, stackTrace);
      rethrow;
    }
  }

  void _scheduleBuiltInBooksLoad() {
    if (_builtInLoadFuture != null || _builtInTrackedBooks.isNotEmpty) {
      return;
    }

    final completer = Completer<void>();
    _builtInLoadFuture = completer.future;

    Future<void>(() async {
      try {
        await _loadBuiltInBooksFromAsset();
        completer.complete();
      } catch (e, stackTrace) {
        _builtInLoadFailed = true;
        _logger.severe(
            'Background load of built-in books failed', e, stackTrace);
        if (!completer.isCompleted) {
          completer.completeError(e, stackTrace);
        }
      }
    });
  }

  Future<void> _ensureBuiltInBooksLoaded() async {
    if (_builtInTrackedBooks.isNotEmpty) {
      return;
    }

    _builtInLoadFuture ??= _loadBuiltInBooksFromAsset();
    try {
      await _builtInLoadFuture;
    } catch (e) {
      _builtInLoadFuture = null;
      _builtInLoadFailed = true;
      rethrow;
    }
  }

  String _resolveRelativePath(
    String categoryName,
    String bookName,
    String storedRelativePath,
  ) {
    if (storedRelativePath.isNotEmpty) {
      return storedRelativePath;
    }

    final categoryMap = BuiltInBooksConfig.builtInBookPaths[categoryName];
    if (categoryMap != null) {
      final direct = categoryMap[bookName];
      if (direct != null && direct.isNotEmpty) {
        return direct;
      }
    }

    _logger.warning(
      'Unable to resolve path for built-in book "$categoryName:$bookName" - using book name as fallback',
    );
    return bookName;
  }

  String _buildFullPath(String relativePath) {
    final parts = relativePath
        .split(RegExp(r'[\\/]+'))
        .where((segment) => segment.isNotEmpty)
        .toList();

    if (parts.isEmpty) {
      return _scannerService.libraryBasePath;
    }

    return p.joinAll([_scannerService.libraryBasePath, ...parts]);
  }

  /// Load all book categories (built-in + custom).
  Future<Map<String, BookCategory>> loadData() async {
    if (!_isInitialized) {
      await initialize();
    }

    await _ensureBuiltInBooksLoaded();

    if (_cachedData != null) {
      return _cachedData!;
    }

    try {
      final customBooks = _customBooksService.getCustomBooks();
      final combined = <TrackedBook>[
        ..._builtInTrackedBooks,
        ...customBooks,
      ];

      final Map<String, BookCategory> categories = {};

      for (final book in combined) {
        final category = categories.putIfAbsent(
          book.categoryName,
          () => BookCategory(
            name: book.categoryName,
            contentType: book.bookDetails.contentType,
            books: {},
            defaultStartPage: book.bookDetails.contentType == "דף" ? 2 : 1,
            isCustom: false,
            sourceFile: book.sourceFile,
          ),
        );

        category.books[book.bookName] = book.bookDetails;
      }

      _cachedData = categories;
      _logger.info(
        'Loaded ${categories.length} categories (custom: ${customBooks.length})',
      );
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

  /// Add a custom book to tracking (still scanned exactly once).
  Future<void> addCustomBook({
    required String bookName,
    required String categoryName,
    required String bookPath,
    required String contentType,
  }) async {
    try {
      _logger.info('Adding custom book: $categoryName - $bookName');

      final bookId = '$categoryName:$bookName';

      final existingBook = await _scannerService.loadScanCache(bookId);
      if (existingBook != null) {
        _logger.info('Book already exists in cache: $bookId');
        await _customBooksService.addBook(existingBook);
        clearCache();
        return;
      }

      final trackedBook = await _scannerService.createTrackedBook(
        bookName: bookName,
        categoryName: categoryName,
        bookPath: bookPath,
        contentType: contentType,
        isBuiltIn: false,
      );

      await _scannerService.saveScanCache(trackedBook);
      await _customBooksService.addBook(trackedBook);
      clearCache();

      _logger.info('Successfully added custom book: ${trackedBook.bookId}');
    } catch (e, stackTrace) {
      _logger.severe('Failed to add custom book', e, stackTrace);
      throw ShamorZachorError.fromException(
        e,
        stackTrace: stackTrace,
        customMessage: 'Failed to add custom book',
      );
    }
  }

  /// Remove a custom book from tracking.
  Future<void> removeBook(String bookId) async {
    if (_builtInBookMap.containsKey(bookId)) {
      throw ShamorZachorError(
        type: ShamorZachorErrorType.permissionDenied,
        message: 'Cannot remove built-in book: $bookId',
      );
    }

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

  /// Check if a book is tracked (built-in or custom).
  bool isBookTracked(String categoryName, String bookName) {
    _scheduleBuiltInBooksLoad();

    if (_builtInTrackedBooks.isEmpty) {
      _builtInLoadFuture ??= _loadBuiltInBooksFromAsset();
    }

    if (_builtInLoadFailed) {
      _logger.warning(
        'Built-in books failed to load previously; treating $categoryName:$bookName as custom-only',
      );
    }

    if (BuiltInBooksConfig.isBuiltInBook(categoryName, bookName)) {
      return true;
    }

    return _customBooksService.isBookTrackedByName(categoryName, bookName);
  }

  /// Check if a book is built-in.
  bool isBuiltInBook(String categoryName, String bookName) {
    return BuiltInBooksConfig.isBuiltInBook(categoryName, bookName);
  }

  /// Get all tracked books (built-in + custom).
  ///
  /// The first call awaits the built-in cache so that the returned list
  /// is always complete.
  Future<List<TrackedBook>> getAllTrackedBooks() async {
    _scheduleBuiltInBooksLoad();
    await _ensureBuiltInBooksLoaded();

    final customTracked = await _customBooksService.getAllTrackedBooks();

    return [
      ..._builtInTrackedBooks,
      ...customTracked,
    ];
  }

  /// Load a specific category by name.
  Future<BookCategory?> loadCategory(String categoryName) async {
    final allData = await loadData();
    return allData[categoryName];
  }

  /// Get list of available category names.
  Future<List<String>> getAvailableCategories() async {
    final allData = await loadData();
    return allData.keys.toList();
  }

  void clearCache() {
    _cachedData = null;
  }

  bool get isDataCached => _cachedData != null;

  int get cacheSize => _cachedData?.length ?? 0;

  Future<void> rescanBuiltInBooks() async {
    _logger.warning('rescanBuiltInBooks() is not supported in static mode');
  }

  Map<String, dynamic> getStatistics() {
    final customStats = _customBooksService.getStatistics();
    return {
      'initialized': _isInitialized,
      'cached': isDataCached,
      'cacheSize': cacheSize,
      'builtInBooks': _builtInTrackedBooks.length,
      ...customStats,
    };
  }
}
