import 'package:logging/logging.dart';
import '../models/book_model.dart';
import '../models/error_model.dart';

/// Service for loading book data from JSON assets
///
/// DEPRECATED: Book data is now loaded from SQLite via ShamorZachorDataProvider.
/// This service is kept for backward compatibility but returns empty data.
class DataLoaderService {
  static final Logger _logger = Logger('DataLoaderService');

  Map<String, BookCategory>? _cachedData;

  DataLoaderService(
      {String? assetsBasePath}); // Constructor preserved for compatibility

  /// Clear the cached data
  void clearCache() {
    _cachedData = null;
  }

  /// Load all book categories from JSON files
  Future<Map<String, BookCategory>> loadData() async {
    // Legacy JSON loading disabled
    _cachedData = {};
    return _cachedData!;
  }

  /// Load a specific category by name (lazy loading)
  Future<BookCategory?> loadCategory(String categoryName) async {
    return null;
  }

  /// Get list of available category names
  Future<List<String>> getAvailableCategories() async {
    return [];
  }

  /// Check if data is cached
  bool get isDataCached => _cachedData != null;

  /// Get cache size (number of categories)
  int get cacheSize => _cachedData?.length ?? 0;
}
