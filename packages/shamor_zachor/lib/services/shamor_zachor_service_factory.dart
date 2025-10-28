import 'package:shared_preferences/shared_preferences.dart';
import 'package:logging/logging.dart';

import 'dynamic_data_loader_service.dart';
import 'book_scanner_service.dart';
import 'custom_books_service.dart';

/// Factory for creating Shamor Zachor services
///
/// This factory provides lazy initialization of the service stack:
/// - DynamicDataLoaderService
/// - BookScannerService
/// - CustomBooksService
class ShamorZachorServiceFactory {
  static final Logger _logger = Logger('ShamorZachorServiceFactory');

  static DynamicDataLoaderService? _dynamicLoaderInstance;
  static bool _isInitializing = false;

  /// Create or get the DynamicDataLoaderService instance
  ///
  /// [libraryBasePath] - Path to the library root (e.g., from Settings)
  /// [getTocFunction] - Function to get TOC from a book file
  ///
  /// This method is async and will initialize all required services
  static Future<DynamicDataLoaderService> getDynamicLoader({
    required String libraryBasePath,
    required Future<List<Map<String, dynamic>>> Function(String bookPath) getTocFunction,
  }) async {
    // Return existing instance if available
    if (_dynamicLoaderInstance != null) {
      return _dynamicLoaderInstance!;
    }

    // Prevent concurrent initialization
    if (_isInitializing) {
      _logger.info('Already initializing, waiting...');
      // Wait a bit and retry
      await Future.delayed(const Duration(milliseconds: 100));
      return getDynamicLoader(
        libraryBasePath: libraryBasePath,
        getTocFunction: getTocFunction,
      );
    }

    _isInitializing = true;

    try {
      _logger.info('Initializing Shamor Zachor services...');

      // 1. Get SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      _logger.info('SharedPreferences initialized');

      // 2. Create CustomBooksService
      final customBooksService = CustomBooksService(prefs);
      await customBooksService.init();
      _logger.info('CustomBooksService initialized');

      // 3. Create BookScannerService
      final scannerService = BookScannerService(
        libraryBasePath: libraryBasePath,
        getTocFromFile: getTocFunction,
      );
      _logger.info('BookScannerService initialized');

      // 4. Create DynamicDataLoaderService
      final dynamicLoader = DynamicDataLoaderService(
        scannerService: scannerService,
        customBooksService: customBooksService,
        prefs: prefs,
      );

      // 5. Initialize it (this will scan built-in books on first run)
      await dynamicLoader.initialize();
      _logger.info('DynamicDataLoaderService initialized');

      _dynamicLoaderInstance = dynamicLoader;
      return dynamicLoader;
    } catch (e, stackTrace) {
      _logger.severe('Failed to initialize services', e, stackTrace);
      rethrow;
    } finally {
      _isInitializing = false;
    }
  }

  /// Reset the factory (useful for testing)
  static void reset() {
    _dynamicLoaderInstance = null;
    _isInitializing = false;
  }

  /// Check if services are initialized
  static bool get isInitialized => _dynamicLoaderInstance != null;
}
