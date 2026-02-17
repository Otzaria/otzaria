import 'package:flutter/foundation.dart' show debugPrint;
import 'package:otzaria/data/data_providers/library_provider.dart';
import 'package:otzaria/data/data_providers/file_system_library_provider.dart';
import 'package:otzaria/data/data_providers/database_library_provider.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/links.dart';

/// Manages multiple library providers and coordinates book loading.
///
/// This class is responsible for:
/// - Initializing all providers
/// - Loading books from all providers
/// - Resolving conflicts (same book in multiple providers)
/// - Providing unified access to book content
class LibraryProviderManager {
  final List<LibraryProvider> _providers = [];
  final Map<String, LibraryProvider> _bookToProvider = {};
  bool _isInitialized = false;
  Future<void>? _initializationFuture;

  /// Singleton instance
  static LibraryProviderManager? _instance;

  LibraryProviderManager._();

  static LibraryProviderManager get instance {
    _instance ??= LibraryProviderManager._();
    return _instance!;
  }

  bool get isInitialized => _isInitialized;

  /// Gets all registered providers
  List<LibraryProvider> get providers => List.unmodifiable(_providers);

  /// Gets the file system provider
  FileSystemLibraryProvider get fileSystemProvider =>
      FileSystemLibraryProvider.instance;

  /// Gets the database provider
  DatabaseLibraryProvider get databaseProvider =>
      DatabaseLibraryProvider.instance;

  /// Initializes all providers
  Future<void> initialize() async {
    if (_isInitialized) {
      return;
    }

    // If initialization is already in progress, wait for it
    if (_initializationFuture != null) {
      return _initializationFuture;
    }

    _initializationFuture = _doInitialize();
    return _initializationFuture;
  }

  Future<void> _doInitialize() async {
    // Register providers in priority order
    _providers.clear();
    _providers.add(DatabaseLibraryProvider.instance);
    _providers.add(FileSystemLibraryProvider.instance);

    // Sort by priority (lower = higher priority)
    _providers.sort((a, b) => a.priority.compareTo(b.priority));

    // Initialize all providers
    for (final provider in _providers) {
      try {
        await provider.initialize();
        debugPrint('✅ Initialized provider: ${provider.displayName}');
      } catch (e) {
        debugPrint(
            '⚠️ Failed to initialize provider ${provider.displayName}: $e');
      }
    }

    _isInitialized = true;
    debugPrint(
        '📚 LibraryProviderManager initialized with ${_providers.length} providers');
  }

  /// Loads all books from all providers.
  ///
  /// Returns a map of category name -> list of books.
  /// Books from higher priority providers take precedence.
  Future<Map<String, List<Book>>> loadAllBooks(
      Map<String, Map<String, dynamic>> metadata) async {
    if (!_isInitialized) await initialize();

    final Map<String, List<Book>> allBooksByCategory = {};
    final Set<String> loadedKeys = {};
    _bookToProvider.clear();

    // Load from each provider in priority order
    for (final provider in _providers) {
      if (!provider.isInitialized) continue;

      try {
        final books = await provider.loadBooks(metadata);

        for (final entry in books.entries) {
          final categoryName = entry.key;
          final categoryBooks = entry.value;

          allBooksByCategory.putIfAbsent(categoryName, () => []);

          for (final book in categoryBooks) {
            // Add all books to the category list, allowing duplicates
            allBooksByCategory[categoryName]!.add(book);

            final key = _generateKey(
                book.title, book.categoryPath ?? '', book.fileType ?? 'txt');

            // Only map the first occurrence (highest priority) for key-based lookups
            if (!loadedKeys.contains(key)) {
              loadedKeys.add(key);
              _bookToProvider[key] = provider;
            } else {
              debugPrint(
                  'ℹ️ Duplicate book "${book.title}" from ${provider.displayName} - keeping primary mapping to ${_bookToProvider[key]?.displayName}');
            }
          }
        }

        debugPrint(
            '📚 Loaded ${books.values.expand((b) => b).length} books from ${provider.displayName}');
      } catch (e) {
        debugPrint('⚠️ Error loading books from ${provider.displayName}: $e');
      }
    }

    debugPrint('📚 Total: ${loadedKeys.length} unique books loaded');
    return allBooksByCategory;
  }

  String _generateKey(String title, String category, String fileType) {
    return '$title|$category|$fileType';
  }

  /// Gets the provider that owns a specific book
  LibraryProvider? getProviderForBook(
      String title, String category, String fileType) {
    final key = _generateKey(title, category, fileType);
    if (_bookToProvider.containsKey(key)) {
      return _bookToProvider[key];
    }

    // Fuzzy match if category is empty (backward compatibility)
    if (category.isEmpty) {
      for (final k in _bookToProvider.keys) {
        if (k.startsWith('$title|')) return _bookToProvider[k];
      }
    }

    return null;
  }

  /// Gets the data source indicator for a book
  Future<String> getBookDataSource(
      String title, String category, String fileType) async {
    final provider = getProviderForBook(title, category, fileType);
    return provider?.sourceIndicator ?? 'ק';
  }

  /// Gets the text content of a book from the appropriate provider
  Future<String?> getBookText(
      String title, String category, String fileType) async {
    if (!_isInitialized) await initialize();

    final provider = getProviderForBook(title, category, fileType);
    if (provider != null) {
      final categoryId = category.hashCode; // Convert to ID
      return await provider.getBookText(title, categoryId, fileType);
    }

    // Fallback: try each provider
    debugPrint('⚠️ Book "$title" not in cache, searching providers...');
    final key = '$title|$category|$fileType';
    final categoryId = category.hashCode; // Convert to ID
    for (final p in _providers) {
      if (await p.hasBook(title, categoryId, fileType)) {
        debugPrint('✅ Found "$title" in ${p.displayName}');
        final text = await p.getBookText(title, categoryId, fileType);
        if (text != null) {
          // Cache the provider for future use
          _bookToProvider[key] = p;
          return text;
        }
      }
    }

    debugPrint('❌ Book "$title" not found in any provider');
    return null;
  }

  /// Gets the table of contents for a book from the appropriate provider
  Future<List<TocEntry>?> getBookToc(
      String title, String category, String fileType) async {
    final provider = getProviderForBook(title, category, fileType);
    final categoryId = category.hashCode; // Convert to ID
    if (provider != null) {
      return await provider.getBookToc(title, categoryId, fileType);
    }

    // Fallback: try each provider
    final key = '$title|$category|$fileType';
    for (final p in _providers) {
      if (await p.hasBook(title, categoryId, fileType)) {
        final toc = await p.getBookToc(title, categoryId, fileType);
        if (toc != null && toc.isNotEmpty) {
          // Cache the provider for future use
          _bookToProvider[key] = p;
          return toc;
        }
      }
    }

    return null;
  }

  /// Checks if a book exists in any provider
  Future<bool> bookExists(
      String title, String category, String fileType) async {
    final categoryId = category.hashCode; // Convert to ID
    for (final provider in _providers) {
      if (await provider.hasBook(title, categoryId, fileType)) {
        return true;
      }
    }
    return false;
  }

  /// Clears all caches
  void clearCaches() {
    _bookToProvider.clear();
    databaseProvider.clearCache();
    // fileSystemProvider.refresh();
    debugPrint('🔄 All provider caches cleared');
  }

  /// Gets the content of a specific link from the appropriate provider
  Future<String> getLinkContent(Link link) async {
    // Try to find the provider for the target book
    final targetTitle = link.path2.split('/').last.replaceAll('.txt', '');

    // Find key that starts with targetTitle + '|'
    String? key;
    for (final k in _bookToProvider.keys) {
      if (k.startsWith('$targetTitle|')) {
        key = k;
        break;
      }
    }

    final provider = key != null ? _bookToProvider[key] : null;

    if (provider != null) {
      try {
        final content = await provider.getLinkContent(link);
        if (content.isNotEmpty && !content.startsWith('שגיאה')) {
          return content;
        }
      } catch (e) {
        // Continue to fallback
      }
    }

    // Fallback: try each provider
    for (final p in _providers) {
      try {
        final content = await p.getLinkContent(link);
        if (content.isNotEmpty && !content.startsWith('שגיאה')) {
          return content;
        }
      } catch (e) {
        continue;
      }
    }

    return 'שגיאה: לא נמצא תוכן';
  }

  /// Gets statistics from all providers
  Future<Map<String, dynamic>> getStats() async {
    final stats = <String, dynamic>{
      'providers': _providers.length,
      'totalBooks': _bookToProvider.length,
    };

    // Add database stats
    final dbStats = await databaseProvider.getStats();
    stats['database'] = dbStats;

    // Count books per provider
    final bookCounts = <String, int>{};
    for (final entry in _bookToProvider.entries) {
      final providerName = entry.value.displayName;
      bookCounts[providerName] = (bookCounts[providerName] ?? 0) + 1;
    }
    stats['booksByProvider'] = bookCounts;

    return stats;
  }

  /// Builds a unified library catalog from all providers.
  ///
  /// This method delegates to the highest priority provider that is initialized.
  /// The database provider builds from the database structure,
  /// while the file system provider builds from the folder hierarchy.
  ///
  /// [metadata] - Book metadata for enriching book information
  /// [rootPath] - The root path of the library (e.g., 'אוצריא' folder)
  Future<Library> buildLibraryCatalog(
    Map<String, Map<String, dynamic>> metadata,
    String rootPath,
  ) async {
    if (!_isInitialized) await initialize();

    // Use the highest priority provider that is initialized
    for (final provider in _providers) {
      if (provider.isInitialized) {
        debugPrint('📚 Building catalog from ${provider.displayName}');
        final library = await provider.buildLibraryCatalog(metadata, rootPath);

        // Update book to provider mapping
        await _updateBookToProviderMapping(library, provider);

        debugPrint(
            '✅ Library catalog built with ${library.subCategories.length} top-level categories');
        return library;
      }
    }

    debugPrint('⚠️ No initialized provider found, returning empty library');
    return Library(categories: []);
  }

  /// Updates the book to provider mapping from a library catalog.
  /// Maps books to the appropriate provider based on their type:
  /// - TextBooks that are in the database -> DatabaseLibraryProvider
  /// - PdfBooks and other file-based books -> FileSystemLibraryProvider
  Future<void> _updateBookToProviderMapping(
      Library library, LibraryProvider primaryProvider) async {
    _bookToProvider.clear();
    await _mapBooksRecursive(library, primaryProvider);
  }

  /// Recursively maps all books in a category to their provider.
  /// PdfBooks are always mapped to FileSystemLibraryProvider since they're file-based.
  /// TextBooks are mapped based on whether they exist in the database or file system.
  Future<void> _mapBooksRecursive(
      Category category, LibraryProvider primaryProvider) async {
    // Get all DB book titles once for efficiency
    final dbTitles = await databaseProvider.getAvailableBookTitles();

    _mapBooksRecursiveWithCache(category, primaryProvider, dbTitles);
  }

  /// Helper method that uses cached DB titles for efficient mapping
  void _mapBooksRecursiveWithCache(Category category,
      LibraryProvider primaryProvider, Set<String> dbTitles) {
    for (final book in category.books) {
      final key = _generateKey(
          book.title, book.categoryPath ?? '', book.fileType ?? 'txt');

      if (book is FileBook) {
        // PDF books are always file-based
        _bookToProvider[key] = fileSystemProvider;
      } else {
        if (dbTitles.contains(key)) {
          _bookToProvider[key] = databaseProvider;
        } else {
          _bookToProvider[key] = fileSystemProvider;
        }
      }
    }
    for (final subCat in category.subCategories) {
      _mapBooksRecursiveWithCache(subCat, primaryProvider, dbTitles);
    }
  }
}
