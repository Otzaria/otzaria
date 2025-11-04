import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';

import '../models/book_model.dart';
import '../models/error_model.dart';
import '../models/tracked_book_model.dart';
import '../services/data_loader_service.dart';
import '../services/dynamic_data_loader_service.dart';

/// Provider for managing book data in Shamor Zachor
/// This provider is scoped locally within the ShamorZachorWidget
///
/// Supports both legacy DataLoaderService (static JSON) and new
/// DynamicDataLoaderService (dynamic scanning with cache)
class ShamorZachorDataProvider with ChangeNotifier {
  static final Logger _logger = Logger('ShamorZachorDataProvider');

  final DataLoaderService? _dataLoaderService;
  final DynamicDataLoaderService? _dynamicDataLoaderService;
  Map<String, BookCategory> _allBookData = {};
  bool _isLoading = false;
  ShamorZachorError? _error;
  List<TrackedBook> _trackedBooksCache = const [];
  bool _trackedBooksReady = false;

  /// Get all book data
  Map<String, BookCategory> get allBookData => _allBookData;

  /// Check if data is currently loading
  bool get isLoading => _isLoading;

  /// Get current error, if any
  ShamorZachorError? get error => _error;

  /// Check if data has been loaded
  bool get hasData => _allBookData.isNotEmpty;

  /// Check if using dynamic loader (new architecture)
  bool get useDynamicLoader => _dynamicDataLoaderService != null;

  /// Legacy constructor with DataLoaderService (static JSON)
  ShamorZachorDataProvider({DataLoaderService? dataLoaderService})
      : _dataLoaderService = dataLoaderService ??
            DataLoaderService(
                assetsBasePath: 'packages/shamor_zachor/assets/data/'),
        _dynamicDataLoaderService = null {
    _loadInitialData();
  }

  /// New constructor with DynamicDataLoaderService (dynamic scanning)
  ShamorZachorDataProvider.dynamic(DynamicDataLoaderService dynamicService)
      : _dynamicDataLoaderService = dynamicService,
        _dataLoaderService = null {
    _loadInitialData();
  }

  /// Load initial data on provider creation
  Future<void> _loadInitialData() async {
    await loadAllData();
  }

  /// Load all book categories and data
  Future<void> loadAllData() async {
    // Wait for any pending load to complete (with timeout)
    int waitCount = 0;
    while (_isLoading && waitCount < 100) {
      // Max 10 seconds
      _logger.fine('Waiting for pending load to complete... ($waitCount)');
      await Future.delayed(const Duration(milliseconds: 100));
      waitCount++;
    }

    if (_isLoading) {
      _logger.warning('Load timeout - forcing reload anyway');
      // Don't return, continue with reload
    }

    _logger.info('Starting to load all data...');

    // Clear cache based on service type
    if (_dynamicDataLoaderService != null) {
      _dynamicDataLoaderService.clearCache();
    } else {
      _dataLoaderService?.clearCache();
    }

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _logger.info('Calling dataLoaderService.loadData()...');

      // Load data from appropriate service
      if (_dynamicDataLoaderService != null) {
        _allBookData = await _dynamicDataLoaderService.loadData();
        _trackedBooksCache =
            await _dynamicDataLoaderService.getAllTrackedBooks();
        _trackedBooksReady = true;
        _logger.info('Data loaded from DynamicDataLoaderService');
      } else {
        _allBookData = await _dataLoaderService!.loadData();
        _logger.info('Data loaded from legacy DataLoaderService');
      }

      _logger.info(
          'Data loaded successfully. Categories: ${_allBookData.keys.toList()}');
      _logger.info('Successfully loaded ${_allBookData.length} categories');

      // Log category structure for debugging
      if (kDebugMode) {
        _allBookData.forEach((key, category) {
          _logger.fine('Category: ${category.name}');
          _logger.fine(
              '  Has subcategories: ${category.subcategories?.isNotEmpty ?? false}');
          _logger.fine('  Direct books count: ${category.books.length}');

          if (category.subcategories != null &&
              category.subcategories!.isNotEmpty) {
            for (var subCat in category.subcategories!) {
              _logger.fine(
                  '    SubCategory: ${subCat.name}, Books: ${subCat.books.length}');
              if (subCat.subcategories != null &&
                  subCat.subcategories!.isNotEmpty) {
                for (var deepSubCat in subCat.subcategories!) {
                  _logger.fine(
                      '      DeepSubCategory: ${deepSubCat.name}, Books: ${deepSubCat.books.length}');
                }
              }
            }
          }
        });
      }
    } catch (e, stackTrace) {
      if (e is ShamorZachorError) {
        _error = e;
      } else {
        _error = ShamorZachorError.fromException(
          e,
          stackTrace: stackTrace,
          customMessage: 'Failed to load book data',
        );
      }
      _logger.severe('Error loading data: ${_error!.message}', e, stackTrace);
    }

    _isLoading = false;
    notifyListeners();
  }

  /// Get a specific category by name
  BookCategory? getCategory(String categoryName) {
    return _allBookData[categoryName];
  }

  /// Get book details for a specific book
  BookDetails? getBookDetails(String categoryName, String bookName) {
    final category = _allBookData[categoryName];
    if (category == null) return null;

    // First check direct books
    if (category.books.containsKey(bookName)) {
      return category.books[bookName];
    }

    // Then search in subcategories
    final searchResult = category.findBookRecursive(bookName);
    return searchResult?.bookDetails;
  }

  /// Search for books across all categories
  List<BookSearchResult> searchBooks(String query) {
    if (query.isEmpty) return [];

    final results = <BookSearchResult>[];
    final queryLower = query.toLowerCase();

    _allBookData.forEach((topLevelName, category) {
      // Search in direct books
      for (final entry in category.books.entries) {
        if (entry.key.toLowerCase().contains(queryLower)) {
          results.add(BookSearchResult(
              entry.value, category.name, category, entry.key, topLevelName));
        }
      }

      // Search in subcategories
      if (category.subcategories != null) {
        for (final subCategory in category.subcategories!) {
          _searchInSubCategory(subCategory, queryLower, results, topLevelName);
        }
      }
    });

    return results;
  }

  /// Helper method to search recursively in subcategories
  void _searchInSubCategory(BookCategory category, String queryLower,
      List<BookSearchResult> results, String topLevelCategoryName) {
    // Search in direct books
    for (final entry in category.books.entries) {
      if (entry.key.toLowerCase().contains(queryLower)) {
        results.add(BookSearchResult(entry.value, category.name, category,
            entry.key, topLevelCategoryName));
      }
    }

    // Search in subcategories
    if (category.subcategories != null) {
      for (final subCategory in category.subcategories!) {
        _searchInSubCategory(
            subCategory, queryLower, results, topLevelCategoryName);
      }
    }
  }

  /// Get all available category names
  List<String> getCategoryNames() {
    return _allBookData.keys.toList();
  }

  /// Get all books from a category (including subcategories)
  Map<String, BookDetails> getAllBooksFromCategory(String categoryName) {
    final category = _allBookData[categoryName];
    if (category == null) return {};

    return category.getAllBooksRecursive();
  }

  /// Retry loading data after an error
  Future<void> retry() async {
    if (_error != null && _error!.isRecoverable) {
      await loadAllData();
    }
  }

  /// Clear error state
  void clearError() {
    _error = null;
    notifyListeners();
  }

  /// Get statistics about loaded data
  Map<String, int> getDataStatistics() {
    int totalCategories = _allBookData.length;
    int totalBooks = 0;
    int totalSubcategories = 0;

    for (final category in _allBookData.values) {
      totalBooks += category.books.length;
      if (category.subcategories != null) {
        totalSubcategories += category.subcategories!.length;
        for (final subCategory in category.subcategories!) {
          totalBooks += subCategory.getAllBooksRecursive().length;
        }
      }
    }

    return {
      'categories': totalCategories,
      'subcategories': totalSubcategories,
      'books': totalBooks,
    };
  }

  /// Check if a specific category exists
  bool hasCategory(String categoryName) {
    return _allBookData.containsKey(categoryName);
  }

  /// Check if a specific book exists in a category
  bool hasBook(String categoryName, String bookName) {
    return getBookDetails(categoryName, bookName) != null;
  }

  /// Reload data from service (useful after adding custom books)
  Future<void> reload() async {
    await loadAllData();
  }

  /// Add a custom book to tracking (only for DynamicDataLoaderService)
  Future<void> addCustomBook({
    required String bookName,
    required String categoryName,
    required String bookPath,
    required String contentType,
  }) async {
    if (_dynamicDataLoaderService == null) {
      throw UnsupportedError(
          'Adding custom books is only supported with DynamicDataLoaderService');
    }

    _logger.info('Provider: Adding custom book: $categoryName - $bookName');

    await _dynamicDataLoaderService.addCustomBook(
      bookName: bookName,
      categoryName: categoryName,
      bookPath: bookPath,
      contentType: contentType,
    );

    _logger.info('Provider: Book added to service, now reloading...');

    // Reload data to reflect the new book
    await reload();

    _logger.info(
        'Provider: Reload complete. Categories: ${_allBookData.keys.toList()}');
    _logger.info(
        'Provider: Category "$categoryName" exists: ${_allBookData.containsKey(categoryName)}');
    if (_allBookData.containsKey(categoryName)) {
      final category = _allBookData[categoryName]!;
      _logger.info(
          'Provider: Books in "$categoryName": ${category.books.keys.toList()}');
    }
  }

  /// Remove a custom book from tracking
  Future<void> removeCustomBook({
    required String categoryName,
    required String bookName,
  }) async {
    if (_dynamicDataLoaderService == null) {
      throw UnsupportedError(
        'Removing custom books is only supported with DynamicDataLoaderService',
      );
    }

    final bookId = '$categoryName:$bookName';
    _logger.info('Removing custom book: $bookId');
    await _dynamicDataLoaderService.removeBook(bookId);
    await reload();
  }

  /// Check if a book is already tracked
  bool isBookTracked(String categoryName, String bookName) {
    if (_dynamicDataLoaderService != null) {
      return _dynamicDataLoaderService.isBookTracked(categoryName, bookName);
    }
    // Legacy: check if book exists in loaded data
    return hasBook(categoryName, bookName);
  }

  /// Get all custom (user-added) books across all categories
  /// Returns a list of tuples: (categoryName, bookName, bookDetails)
  List<Map<String, dynamic>> getCustomBooks() {
    if (_dynamicDataLoaderService == null) {
      // Legacy mode: no custom books
      return [];
    }
    if (!_trackedBooksReady) {
      _logger.fine(
          'getCustomBooks called before tracked books cache ready, returning empty list');
      return [];
    }
    final customBooks = <Map<String, dynamic>>[];
    final allTrackedBooks = _trackedBooksCache;
    // Filter only non-built-in books
    for (final trackedBook in allTrackedBooks) {
      if (!trackedBook.isBuiltIn) {
        customBooks.add({
          'categoryName': trackedBook.categoryName,
          'bookName': trackedBook.bookName,
          'bookDetails': trackedBook.bookDetails,
          'topLevelCategoryKey': trackedBook.categoryName,
        });
      }
    }
    _logger.info('getCustomBooks: Found ${customBooks.length} custom books');
    return customBooks;
  }

  @override
  void dispose() {
    _logger.fine('Disposing ShamorZachorDataProvider');
    super.dispose();
  }
}
