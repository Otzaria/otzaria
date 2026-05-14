import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import 'package:otzaria/data/data_providers/book_composite_key.dart';
import 'package:otzaria/data/data_providers/database_library_provider.dart';
import 'package:otzaria/data/data_providers/file_system_library_provider.dart';
import 'package:otzaria/data/data_providers/library_provider.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/books.dart';
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
  final Map<BookCompositeKey, LibraryProvider> _bookToProvider = {};
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
    final Set<BookCompositeKey> loadedKeys = {};
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

            final key = BookCompositeKey.fromBook(book);
            if (key == null) {
              debugPrint(
                  '⚠️ Book "${book.title}" has no categoryId, skipping provider map');
              continue;
            }

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

  BookCompositeKey? _resolveBookKey(
    String title, {
    int? categoryId,
    String? fileType,
    bool preferUserBooks = false,
  }) {
    final normalizedFileType = BookCompositeKey.normalizeFileType(fileType);

    if (categoryId != null) {
      // categoryId לבדו אינו חד-משמעי — `5` יכול להיות גם בseforim וגם
      // ב-user_books. ננסה את שני הוריאנטים בסדר המתאים להעדפת המשתמש.
      final order = preferUserBooks ? const [true, false] : const [false, true];
      for (final isUser in order) {
        final exactKey = BookCompositeKey.create(
          title: title,
          categoryId: categoryId,
          fileType: normalizedFileType,
          isUserBook: isUser,
        );
        if (_bookToProvider.containsKey(exactKey)) {
          return exactKey;
        }
      }
    }

    // עיברה על המפתחות בשני מעברים: קודם התאמה מלאה (כולל fileType),
    // ואז התאמה לפי כותרת בלבד. ה-`accept` מסנן את אוסף המפתחות
    // המועמדים — שימושי כדי לחפש קודם רק ב-user_books, ואז רק
    // בכל השאר, בלי לסרוק את user_books פעמיים.
    BookCompositeKey? findIn(bool Function(BookCompositeKey) accept) {
      for (final key in _bookToProvider.keys) {
        if (!accept(key)) continue;
        if (key.matches(title, otherFileType: normalizedFileType)) return key;
      }
      for (final key in _bookToProvider.keys) {
        if (!accept(key)) continue;
        if (key.matchesTitle(title)) return key;
      }
      return null;
    }

    if (preferUserBooks) {
      final fromUserBooks = findIn((k) => k.isUserBook);
      if (fromUserBooks != null) return fromUserBooks;
      return findIn((k) => !k.isUserBook);
    }

    return findIn((_) => true);
  }

  Future<BookCompositeKey?> _findKeyInProvider(
    LibraryProvider provider,
    String title, {
    String? fileType,
    bool preferUserBooks = false,
  }) async {
    final normalizedFileType = BookCompositeKey.normalizeFileType(fileType);
    final rawKeys = await provider.getAvailableBookTitles();

    if (preferUserBooks) {
      for (final rawKey in rawKeys) {
        final parsed = BookCompositeKey.tryParse(rawKey);
        if (parsed == null || !parsed.isUserBook) {
          continue;
        }
        if (parsed.matches(title, otherFileType: normalizedFileType)) {
          return parsed;
        }
      }
    }

    for (final rawKey in rawKeys) {
      final parsed = BookCompositeKey.tryParse(rawKey);
      if (parsed == null) continue;
      if (parsed.matches(title, otherFileType: normalizedFileType)) {
        return parsed;
      }
    }

    for (final rawKey in rawKeys) {
      final parsed = BookCompositeKey.tryParse(rawKey);
      if (parsed == null) continue;
      if (parsed.matchesTitle(title)) {
        return parsed;
      }
    }

    return null;
  }

  Future<({BookCompositeKey key, LibraryProvider provider})?>
      _locateBookInProviders(
    String title, {
    int? categoryId,
    String? fileType,
    bool preferUserBooks = false,
  }) async {
    final normalizedFileType = BookCompositeKey.normalizeFileType(fileType);

    for (final provider in _providers) {
      if (!provider.isInitialized) continue;

      if (categoryId != null) {
        final exists =
            await provider.hasBook(title, categoryId, normalizedFileType);
        if (exists) {
          return (
            key: BookCompositeKey.create(
              title: title,
              categoryId: categoryId,
              fileType: normalizedFileType,
              // הינט בלבד — ה-provider לא מחזיר אם זה user_books, ואנחנו
              // משתמשים בהעדפת הקורא להתאים את המפתח למה שב-cache.
              isUserBook: preferUserBooks,
            ),
            provider: provider
          );
        }
        continue;
      }

      final providerKey = await _findKeyInProvider(
        provider,
        title,
        fileType: normalizedFileType,
        preferUserBooks: preferUserBooks,
      );
      if (providerKey != null) {
        return (key: providerKey, provider: provider);
      }
    }

    return null;
  }

  /// Gets the provider that owns a specific book
  LibraryProvider? getProviderForBook(
    String title, {
    int? categoryId,
    String? fileType,
  }) {
    final key = _resolveBookKey(
      title,
      categoryId: categoryId,
      fileType: fileType,
    );
    if (key == null) return null;
    return _bookToProvider[key];
  }

  /// Gets the data source indicator for a book
  Future<String> getBookDataSource(
    String title, {
    int? categoryId,
    String? fileType,
  }) async {
    if (!_isInitialized) await initialize();

    final provider = getProviderForBook(
      title,
      categoryId: categoryId,
      fileType: fileType,
    );
    if (provider != null) {
      return provider.sourceIndicator;
    }

    final located = await _locateBookInProviders(
      title,
      categoryId: categoryId,
      fileType: fileType,
    );
    if (located == null) return 'ק';

    _bookToProvider[located.key] = located.provider;
    return located.provider.sourceIndicator;
  }

  /// Gets the text content of a book from the appropriate provider
  Future<String?> getBookText(
    String title, {
    int? categoryId,
    String? fileType,
    bool preferUserBooks = false,
  }) async {
    if (!_isInitialized) await initialize();

    final mappedKey = _resolveBookKey(
      title,
      categoryId: categoryId,
      fileType: fileType,
      preferUserBooks: preferUserBooks,
    );
    if (mappedKey != null) {
      final provider = _bookToProvider[mappedKey];
      if (provider != null) {
        return await provider.getBookText(
          title,
          mappedKey.categoryId,
          mappedKey.fileType,
          preferUserBooks: preferUserBooks,
        );
      }
    }

    debugPrint('⚠️ Book "$title" not in cache, searching providers...');
    final located = await _locateBookInProviders(
      title,
      categoryId: categoryId,
      fileType: fileType,
      preferUserBooks: preferUserBooks,
    );
    if (located == null) {
      debugPrint('❌ Book "$title" not found in any provider');
      return null;
    }

    final text = await located.provider.getBookText(
      title,
      located.key.categoryId,
      located.key.fileType,
      preferUserBooks: preferUserBooks,
    );
    if (text != null) {
      _bookToProvider[located.key] = located.provider;
    }
    return text;
  }

  /// Gets the table of contents for a book from the appropriate provider
  Future<List<TocEntry>?> getBookToc(
    String title, {
    int? categoryId,
    String? fileType,
    bool preferUserBooks = false,
  }) async {
    if (!_isInitialized) await initialize();
    final mappedKey = _resolveBookKey(
      title,
      categoryId: categoryId,
      fileType: fileType,
      preferUserBooks: preferUserBooks,
    );
    if (mappedKey != null) {
      final provider = _bookToProvider[mappedKey];
      if (provider != null) {
        return await provider.getBookToc(
          title,
          mappedKey.categoryId,
          mappedKey.fileType,
          preferUserBooks: preferUserBooks,
        );
      }
    }

    final located = await _locateBookInProviders(
      title,
      categoryId: categoryId,
      fileType: fileType,
      preferUserBooks: preferUserBooks,
    );
    if (located == null) return null;

    final toc = await located.provider.getBookToc(
      title,
      located.key.categoryId,
      located.key.fileType,
      preferUserBooks: preferUserBooks,
    );
    if (toc != null) {
      _bookToProvider[located.key] = located.provider;
    }
    return toc;
  }

  /// Checks if a book exists in any provider
  Future<bool> bookExists(
    String title, {
    int? categoryId,
    String? fileType,
  }) async {
    if (!_isInitialized) await initialize();

    final mapped = _resolveBookKey(
      title,
      categoryId: categoryId,
      fileType: fileType,
    );
    if (mapped != null) {
      return true;
    }

    final located = await _locateBookInProviders(
      title,
      categoryId: categoryId,
      fileType: fileType,
    );
    if (located == null) return false;

    _bookToProvider[located.key] = located.provider;
    return true;
  }

  /// Clears all caches
  void clearCaches() {
    _bookToProvider.clear();
    databaseProvider.clearCache();
    debugPrint('🔄 All provider caches cleared');
  }

  /// Resets provider initialization so the active library can be reloaded.
  void resetRuntimeState() {
    _bookToProvider.clear();
    _providers.clear();
    databaseProvider.clearCache();
    fileSystemProvider.resetRuntimeState();
    _isInitialized = false;
    _initializationFuture = null;
    debugPrint('🔄 LibraryProviderManager runtime state reset');
  }

  @visibleForTesting
  void seedMappingsForTesting({
    required Map<BookCompositeKey, LibraryProvider> mapping,
    required List<LibraryProvider> providers,
    bool initialized = true,
  }) {
    _bookToProvider
      ..clear()
      ..addAll(mapping);
    _providers
      ..clear()
      ..addAll(providers);
    _isInitialized = initialized;
  }

  @visibleForTesting
  void resetForTesting() {
    _bookToProvider.clear();
    _providers.clear();
    _isInitialized = false;
    _initializationFuture = null;
  }

  /// Gets the content of a specific link from the appropriate provider
  Future<String> getLinkContent(Link link) async {
    final targetTitle = link.path2.split('/').last.replaceAll('.txt', '');

    BookCompositeKey? targetKey;
    for (final key in _bookToProvider.keys) {
      if (key.matchesTitle(targetTitle)) {
        targetKey = key;
        break;
      }
    }

    final provider = targetKey != null ? _bookToProvider[targetKey] : null;

    if (provider != null) {
      try {
        final content = await provider.getLinkContent(link);
        if (content.isNotEmpty && !content.startsWith('שגיאה')) {
          return content;
        }
      } catch (e) {
        debugPrint(
            'LibraryProviderManager: provider failed for $targetTitle, continuing to fallback: $e');
      }
    }

    // Fallback: try each provider
    for (final p in _providers) {
      try {
        final content = await p.getLinkContent(link);
        if (content.isNotEmpty && !content.startsWith('שגיאה')) {
          return content;
        }
      } catch (_) {
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
        await _updateBookToProviderMapping(library);

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
  Future<void> _updateBookToProviderMapping(Library library) async {
    _bookToProvider.clear();
    await _mapBooksRecursive(library);
  }

  /// Recursively maps all books in a category to their provider.
  /// PdfBooks are always mapped to FileSystemLibraryProvider since they're file-based.
  /// TextBooks are mapped based on whether they exist in the database or file system.
  ///
  /// **שים לב:** פונקציה זו קוראת ל-`getAvailableBookTitles()` שמבצעת שאילתה ל-DB.
  /// היא נקראת פעם אחת בלבד מ-`_updateBookToProviderMapping` בזמן בניית הקטלוג.
  /// אין לקרוא לה ממקומות נוספים כדי לא ליצור שאילתות מיותרות.
  Future<void> _mapBooksRecursive(Category category) async {
    final dbRawKeys = await databaseProvider.getAvailableBookTitles();
    final dbKeys = dbRawKeys
        .map(BookCompositeKey.tryParse)
        .whereType<BookCompositeKey>()
        .toSet();

    _mapBooksRecursiveWithCache(category, dbKeys);
  }

  /// Helper method that uses cached DB keys for efficient mapping
  void _mapBooksRecursiveWithCache(
    Category category,
    Set<BookCompositeKey> dbKeys,
  ) {
    for (final book in category.books) {
      final key = BookCompositeKey.fromBook(book);
      if (key == null) continue;

      if (book is FileBook) {
        // PDF/DOCX books are always file-based
        _bookToProvider[key] = fileSystemProvider;
      } else {
        if (dbKeys.contains(key)) {
          _bookToProvider[key] = databaseProvider;
        } else {
          _bookToProvider[key] = fileSystemProvider;
        }
      }
    }

    for (final subCat in category.subCategories) {
      _mapBooksRecursiveWithCache(subCat, dbKeys);
    }
  }
}
