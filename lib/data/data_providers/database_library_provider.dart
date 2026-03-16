import 'dart:io';
import 'dart:isolate';
import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import 'package:otzaria/data/constants/database_constants.dart';
import 'package:otzaria/data/data_providers/book_composite_key.dart';
import 'package:otzaria/data/data_providers/library_provider.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:otzaria/migration/dao/sqflite/sqlite3_utils.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/migration/core/models/category.dart' as db_models;
import 'package:otzaria/migration/core/models/book.dart' as db_models;
import 'package:otzaria/migration/core/models/toc_entry.dart' as db_models;
import 'package:otzaria/migration/core/models/alt_toc_structure.dart';
import 'package:otzaria/migration/core/models/alt_toc_entry.dart';
import 'package:otzaria/utils/text_manipulation.dart';
import 'package:otzaria/utils/toc_parser.dart';
import 'package:otzaria/utils/docx_to_otzaria.dart';
import 'package:pdfrx/pdfrx.dart';

/// Library provider that loads books from the SQLite database.
class DatabaseLibraryProvider implements LibraryProvider {
  final SqliteDataProvider _sqliteProvider = SqliteDataProvider.instance;
  final Set<BookCompositeKey> _cachedKeys = {};
  final Map<int, String> _categoryIdToPath = {};
  final Map<int, db_models.Category> _categoriesById = {};
  bool _titlesCached = false;
  String? _bundledTalmudBavliPathCache;
  bool? _bundledTalmudBavliExistsCache;

  /// Singleton instance
  static DatabaseLibraryProvider? _instance;

  DatabaseLibraryProvider._();

  static DatabaseLibraryProvider get instance {
    _instance ??= DatabaseLibraryProvider._();
    return _instance!;
  }

  Future<bool> _bundledTalmudBavliDirectoryExists() async {
    final candidatePaths = DatabaseConstants.getTalmudBavliDirectoryPaths();
    if (_bundledTalmudBavliExistsCache != null &&
        _bundledTalmudBavliPathCache != null &&
        candidatePaths.contains(_bundledTalmudBavliPathCache)) {
      return _bundledTalmudBavliExistsCache!;
    }

    for (final candidatePath in candidatePaths) {
      final exists = await Directory(candidatePath).exists();
      if (exists) {
        _bundledTalmudBavliPathCache = candidatePath;
        _bundledTalmudBavliExistsCache = true;
        return true;
      }
    }

    _bundledTalmudBavliPathCache = candidatePaths.first;
    _bundledTalmudBavliExistsCache = false;
    return false;
  }

  Future<void> _addBundledTalmudBavliPdfBooksToCategory(
    Category category,
    Map<String, Map<String, dynamic>> metadata,
  ) async {
    final bundledPath = _bundledTalmudBavliPathCache;
    if (bundledPath == null || !await _bundledTalmudBavliDirectoryExists()) {
      return;
    }

    final bundledDir = Directory(bundledPath);

    // Build a map: title → sub-category that contains a TextBook with that title.
    // This lets us place each PDF next to its matching text book.
    final Map<String, Category> titleToSubCategory = {};
    for (final sub in category.getAllCategories()) {
      for (final book in sub.books) {
        if (book is TextBook) {
          titleToSubCategory[book.title] = sub;
        }
      }
    }

    // Collect all existing PDF titles across the entire tree to avoid duplicates.
    final existingPdfTitles = <String>{};
    for (final book in category.getAllBooks()) {
      if (book is PdfBook) existingPdfTitles.add(book.title);
    }

    final modifiedCategories = <Category>{};
    Category? orphanCategory;

    await for (final entity in bundledDir.list()) {
      if (entity is! File) continue;
      if (!entity.path.toLowerCase().endsWith('.pdf')) continue;

      final title = getTitleFromPath(entity.path);
      if (existingPdfTitles.contains(title)) continue;

      // Place PDF in the sub-category of its matching TextBook.
      // Orphans (no matching TextBook) go into a dedicated sub-category
      // appended after "סדר טהרות" so they don't float to the top.
      if (orphanCategory == null && !titleToSubCategory.containsKey(title)) {
        // Place right after "סדר טהרות" (order 30 in DB) → use 31.
        final tohorotOrder = category.subCategories
            .where((c) => c.title == 'סדר טהרות')
            .firstOrNull
            ?.order;
        final orphanOrder = tohorotOrder != null ? tohorotOrder + 1 : 31;
        orphanCategory = Category(
          title: 'מסכתות נוספות',
          description: '',
          shortDescription: '',
          subCategories: [],
          books: [],
          parent: category,
          order: orphanOrder,
        );
        category.subCategories.add(orphanCategory);
        category.subCategories.sort((a, b) => a.order.compareTo(b.order));
      }
      final targetCategory =
          titleToSubCategory[title] ?? orphanCategory ?? category;
      final targetCategoryId = titleToSubCategory.containsKey(title)
          ? targetCategory.title.hashCode
          : DatabaseConstants.talmudBavliFolderName.hashCode;

      final bookMeta = metadata[title];
      final matchingTextBook = targetCategory.books
          .where((b) => b is TextBook && b.title == title)
          .firstOrNull;
      final pdfBook = PdfBook(
        title: title,
        category: targetCategory,
        path: entity.path,
        filePath: entity.path,
        author: bookMeta?['author'] as String?,
        heShortDesc: bookMeta?['heShortDesc'] as String?,
        pubDate: bookMeta?['pubDate'] as String?,
        pubPlace: bookMeta?['pubPlace'] as String?,
        order: matchingTextBook?.order ?? bookMeta?['order'] as int? ?? 999,
        topics: DatabaseConstants.talmudBavliFolderName,
        categoryPath: DatabaseConstants.talmudBavliFolderName,
        categoryId: targetCategoryId,
      );

      targetCategory.books.add(pdfBook);
      existingPdfTitles.add(title);
      modifiedCategories.add(targetCategory);
      _cachedKeys.add(BookCompositeKey.create(
        title: title,
        categoryId: targetCategoryId,
        fileType: 'pdf',
      ));
      _categoryIdToPath[targetCategoryId] =
          DatabaseConstants.talmudBavliFolderName;
    }

    // Re-sort only the categories that were modified.
    for (final cat in modifiedCategories) {
      cat.books.sort((a, b) => a.order.compareTo(b.order));
    }
  }

  @visibleForTesting
  static bool shouldIncludeBookByPath(
    String? filePath, {
    required bool hasTalmudBavliDirectory,
    String? talmudBavliDirectoryPath,
  }) {
    if (hasTalmudBavliDirectory) {
      return true;
    }

    return !DatabaseConstants.isTalmudBavliFilePath(
      filePath,
      talmudBavliDirectoryPath: talmudBavliDirectoryPath,
    );
  }

  /// Helper method to build topics string from database book and category path
  String _buildTopics(db_models.Book dbBook, String categoryPath) {
    String topics = dbBook.topics.map((t) => t.name).join(', ');
    if (topics.isEmpty && categoryPath.isNotEmpty) {
      topics = categoryPath
          .split(',')
          .map((p) => p.trim())
          .where((p) => p.isNotEmpty)
          .join(', ');
    }
    return topics;
  }

  @override
  String get providerId => 'database';

  @override
  String get displayName => 'מסד נתונים';

  @override
  String get sourceIndicator => 'DB';

  @override
  int get priority => 1; // Higher priority than file system

  @override
  bool get isInitialized => _sqliteProvider.isInitialized;

  @override
  Future<void> initialize() async {
    await _sqliteProvider.initialize();
    debugPrint('💾 DatabaseLibraryProvider initialized');
  }

  @override
  Future<Map<String, List<Book>>> loadBooks(
      Map<String, Map<String, dynamic>> metadata) async {
    final Map<String, List<Book>> booksByCategory = {};

    if (!_sqliteProvider.isInitialized || _sqliteProvider.repository == null) {
      debugPrint('💾 Database not initialized, returning empty');
      return booksByCategory;
    }

    try {
      final hasTalmudBavliDirectory =
          await _bundledTalmudBavliDirectoryExists();
      final dbBooks = await _sqliteProvider.repository!.getAllBooks();
      final categories = await _sqliteProvider.repository!.getAllCategories();
      debugPrint('💾 Database found ${dbBooks.length} books');

      // Build category paths and caches
      final Map<int, db_models.Category> categoryMap = {
        for (var c in categories) c.id: c
      };
      final Map<int, String> categoryPaths = {};

      String getPath(int? categoryId) {
        if (categoryId == null) return '';
        if (categoryPaths.containsKey(categoryId)) {
          return categoryPaths[categoryId]!;
        }

        final List<String> path = [];
        var currentId = categoryId;
        // Prevent infinite loops with a max depth check or visited set if needed,
        // but assuming DAG/Tree structure here.
        while (categoryMap.containsKey(currentId)) {
          final category = categoryMap[currentId]!;
          path.insert(0, category.title);
          if (category.parentId == null) break;
          currentId = category.parentId!;
        }
        final pathStr = path.join(', ');
        categoryPaths[categoryId] = pathStr;
        return pathStr;
      }

      // Cache titles for quick lookup
      _cachedKeys.clear();
      _categoryIdToPath.clear();
      _categoriesById
        ..clear()
        ..addAll(categoryMap);

      for (final dbBook in dbBooks) {
        if (!shouldIncludeBookByPath(
          dbBook.filePath,
          hasTalmudBavliDirectory: hasTalmudBavliDirectory,
          talmudBavliDirectoryPath: _bundledTalmudBavliPathCache,
        )) {
          continue;
        }

        final categoryPath = getPath(dbBook.categoryId);
        _categoryIdToPath[dbBook.categoryId] = categoryPath;
        _cachedKeys.add(BookCompositeKey.create(
          title: dbBook.title,
          categoryId: dbBook.categoryId,
          fileType: dbBook.fileType,
        ));

        final categoryName =
            dbBook.topics.isNotEmpty ? dbBook.topics.first.name : 'ללא קטגוריה';

        final topics = _buildTopics(dbBook, categoryPath);

        final book = TextBook(
          id: dbBook.id,
          title: dbBook.title,
          author: dbBook.authors.isNotEmpty ? dbBook.authors.first.name : null,
          heShortDesc: dbBook.heShortDesc,
          pubDate:
              dbBook.pubDates.isNotEmpty ? dbBook.pubDates.first.date : null,
          pubPlace:
              dbBook.pubPlaces.isNotEmpty ? dbBook.pubPlaces.first.name : null,
          order: dbBook.order.toInt(),
          topics: topics,
          fileType: dbBook.fileType,
          categoryPath: categoryPath,
          categoryId: dbBook.categoryId,
          externalLibraryId: dbBook.externalLibraryId,
        );

        booksByCategory.putIfAbsent(categoryName, () => []);
        booksByCategory[categoryName]!.add(book);
      }

      _titlesCached = true;
      debugPrint(
          '💾 Database loaded ${dbBooks.length} books into ${booksByCategory.length} categories');
    } catch (e) {
      debugPrint('⚠️ Error loading books from database: $e');
    }

    return booksByCategory;
  }

  @override
  Future<bool> hasBook(String title, int categoryId, String fileType) async {
    final key = BookCompositeKey.create(
      title: title,
      categoryId: categoryId,
      fileType: fileType,
    );
    if (_cachedKeys.contains(key)) {
      return true;
    }

    final repository = _sqliteProvider.repository;
    if (repository == null) {
      return false;
    }

    final book = await repository.getBookByTitleCategoryAndFileType(
      title,
      categoryId,
      key.fileType,
    );
    return book != null;
  }

  /// Finds the category path for a given book title.
  /// Returns null if the book is not found in the database.
  Future<String?> findCategoryPathForBook(
    String title, {
    int? categoryId,
    String? fileType,
  }) async {
    final normalizedFileType = BookCompositeKey.normalizeFileType(fileType);

    if (_titlesCached) {
      BookCompositeKey? matchedKey;

      if (categoryId != null) {
        final exact = BookCompositeKey.create(
          title: title,
          categoryId: categoryId,
          fileType: normalizedFileType,
        );
        if (_cachedKeys.contains(exact)) {
          matchedKey = exact;
        }
      }

      if (matchedKey == null) {
        for (final key in _cachedKeys) {
          if (!key.matchesTitle(title)) continue;
          if (fileType != null && key.fileType != normalizedFileType) {
            continue;
          }
          matchedKey = key;
          break;
        }
      }

      if (matchedKey != null) {
        final path = await _getPathForCategoryId(matchedKey.categoryId);
        return path.isEmpty ? null : path;
      }
    }

    final repository = _sqliteProvider.repository;
    if (repository == null) {
      return null;
    }

    try {
      db_models.Book? book;

      if (categoryId != null) {
        if (fileType != null) {
          book = await repository.getBookByTitleCategoryAndFileType(
            title,
            categoryId,
            normalizedFileType,
          );
        } else {
          final booksInCategory =
              await repository.getBooksByCategory(categoryId);
          for (final candidate in booksInCategory) {
            if (candidate.title != title) continue;
            book = candidate;
            break;
          }
        }
      } else {
        book = await repository.getBookByTitle(title);
      }

      if (book == null) return null;
      final path = await _getPathForCategoryId(book.categoryId);
      return path.isEmpty ? null : path;
    } catch (_) {
      return null;
    }
  }

  /// Helper to get full path for a category ID from DB
  Future<String> _getPathForCategoryId(int categoryId) async {
    final cachedPath = _categoryIdToPath[categoryId];
    if (cachedPath != null) return cachedPath;

    final repository = _sqliteProvider.repository;
    if (repository == null) return '';

    if (_categoriesById.isEmpty) {
      final categories = await repository.getAllCategories();
      for (final category in categories) {
        _categoriesById[category.id] = category;
      }
    }

    final pathParts = <String>[];
    final visited = <int>{};
    int? currentId = categoryId;

    while (currentId != null && visited.add(currentId)) {
      var category = _categoriesById[currentId];
      category ??= await repository.getCategory(currentId);
      if (category == null) {
        break;
      }
      _categoriesById[category.id] = category;
      pathParts.insert(0, category.title);
      currentId = category.parentId;
    }

    final categoryPath = pathParts.join(', ');
    if (categoryPath.isNotEmpty) {
      _categoryIdToPath[categoryId] = categoryPath;
    }
    return categoryPath;
  }

  /// Checks if any book with the given title exists in the database.
  Future<bool> hasBookWithTitle(String title) async {
    if (!_titlesCached) {
      await getDatabaseOnlyBookTitles();
    }

    for (final key in _cachedKeys) {
      if (key.matchesTitle(title)) return true;
    }
    return false;
  }

  @override
  Future<String?> getBookText(
      String title, int categoryId, String fileType) async {
    if (_sqliteProvider.repository != null) {
      try {
        final book = await _sqliteProvider.repository!
            .getBookByTitleCategoryAndFileType(title, categoryId, fileType);
        if (book != null && book.isFileBacked && book.filePath != null) {
          final file = File(book.filePath!);
          if (await file.exists()) {
            return await file.readAsString();
          }
        }
        // If not external or file not found, try DB text
        if (book != null) {
          return await _sqliteProvider.getBookTextFromDb(
              title, categoryId, fileType);
        }
      } catch (e) {
        debugPrint('⚠️ Error reading external book text: $e');
      }
    }
    return null;
  }

  @override
  Future<List<TocEntry>?> getBookToc(
      String title, int categoryId, String fileType) async {
    return await _sqliteProvider.getBookTocFromDb(title, categoryId, fileType);
  }

  @override
  Future<Set<String>> getAvailableBookTitles() async {
    // Return only books that are actually in the database
    return await getDatabaseOnlyBookTitles();
  }

  /// Gets book titles that are ONLY in the database
  Future<Set<String>> getDatabaseOnlyBookTitles() async {
    if (_titlesCached) {
      return _cachedKeys.map((key) => key.toStorageKey()).toSet();
    }

    final repository = _sqliteProvider.repository;
    if (repository == null) {
      return {};
    }

    try {
      final hasTalmudBavliDirectory =
          await _bundledTalmudBavliDirectoryExists();
      final books = await repository.getAllBooks();
      final categories = await repository.getAllCategories();

      _cachedKeys.clear();
      _categoriesById
        ..clear()
        ..addEntries(
            categories.map((category) => MapEntry(category.id, category)));

      for (final book in books) {
        if (!shouldIncludeBookByPath(
          book.filePath,
          hasTalmudBavliDirectory: hasTalmudBavliDirectory,
          talmudBavliDirectoryPath: _bundledTalmudBavliPathCache,
        )) {
          continue;
        }

        _cachedKeys.add(BookCompositeKey.create(
          title: book.title,
          categoryId: book.categoryId,
          fileType: book.fileType,
        ));

        if (!_categoryIdToPath.containsKey(book.categoryId)) {
          final categoryPath = await _getPathForCategoryId(book.categoryId);
          if (categoryPath.isNotEmpty) {
            _categoryIdToPath[book.categoryId] = categoryPath;
          }
        }
      }

      _titlesCached = true;
      return _cachedKeys.map((key) => key.toStorageKey()).toSet();
    } catch (e) {
      debugPrint('⚠️ Error building DB key cache: $e');
      return {};
    }
  }

  /// Clears the cached titles (call when database changes)
  void clearCache() {
    _cachedKeys.clear();
    _categoryIdToPath.clear();
    _categoriesById.clear();
    _titlesCached = false;
    _bundledTalmudBavliPathCache = null;
    _bundledTalmudBavliExistsCache = null;
    debugPrint('💾 Database cache cleared');
  }

  @visibleForTesting
  void seedCacheForTesting({
    required Iterable<BookCompositeKey> keys,
    Map<int, String>? categoryIdToPath,
    bool titlesCached = true,
  }) {
    _cachedKeys
      ..clear()
      ..addAll(keys);
    _categoryIdToPath
      ..clear()
      ..addAll(categoryIdToPath ?? const {});
    _titlesCached = titlesCached;
  }

  /// Gets database statistics
  Future<Map<String, int>> getStats() async {
    return await _sqliteProvider.getDatabaseStats();
  }

  /// Gets the underlying SQLite provider for advanced operations
  SqliteDataProvider get sqliteProvider => _sqliteProvider;

  /// Private helper for database operations to reduce boilerplate
  Future<T> _dbOperation<T>(
    Future<T> Function(sqlite3.Database db) operation,
    T defaultValue,
    String errorContext,
  ) async {
    if (!_sqliteProvider.isInitialized || _sqliteProvider.repository == null) {
      return defaultValue;
    }

    try {
      final db = await _sqliteProvider.repository!.database.database;
      return await operation(db);
    } catch (e) {
      debugPrint('⚠️ Error in $errorContext: $e');
      return defaultValue;
    }
  }

  @override
  Future<Library> buildLibraryCatalog(
    Map<String, Map<String, dynamic>> metadata,
    String rootPath,
  ) async {
    if (!_sqliteProvider.isInitialized || _sqliteProvider.repository == null) {
      debugPrint('💾 Database not initialized, returning empty library');
      return Library(categories: []);
    }

    debugPrint('💾 Building library catalog from database...');

    // CRITICAL: Clear cache before rebuilding to ensure fresh data
    _titlesCached = false;
    _cachedKeys.clear();
    _categoryIdToPath.clear();
    _categoriesById.clear();

    final repository = _sqliteProvider.repository!;

    final hasTalmudBavliDirectory = await _bundledTalmudBavliDirectoryExists();

    // OPTIMIZATION: Load minimal book data (8 columns, no JOINs) instead of
    // full book data with relations (25+ columns + 4 junction table queries).
    // Both queries run inside a single transaction to prevent BackgroundSync
    // from locking the DB between them (which caused 17s delays).
    final tQuery = DateTime.now();

    late final List<Map<String, dynamic>> allDbBooks;
    late final List<Map<String, dynamic>> allCatRows;

    final db = await repository.database.database;
    withTransaction(db, () {
      allDbBooks = repository.database.bookDao.getAllBooksMinimal(db);
      allCatRows = repository.database.categoryDao.getAllCategoryRows(db);
    });

    debugPrint(
        '⏱️ Transaction (books+categories): ${DateTime.now().difference(tQuery).inMilliseconds}ms (${allDbBooks.length} books, ${allCatRows.length} categories)');

    final booksByCategory = <int, List<Map<String, dynamic>>>{};
    for (final bookData in allDbBooks) {
      if (!shouldIncludeBookByPath(
        bookData['filePath'] as String?,
        hasTalmudBavliDirectory: hasTalmudBavliDirectory,
        talmudBavliDirectoryPath: _bundledTalmudBavliPathCache,
      )) {
        continue;
      }

      // Use null-safe cast: corrupt data (null categoryId) should not crash the
      // entire library load. Books with no category are silently skipped.
      final catId = bookData['categoryId'] as int?;
      if (catId == null) continue;
      booksByCategory.putIfAbsent(catId, () => []);
      booksByCategory[catId]!.add(bookData);
    }

    // Parse category rows into model objects (filtering debug-only categories)
    final allCategories = allCatRows
        .map((row) => db_models.Category.fromJson(row))
        .where((cat) => cat.title != 'אודות התוכנה')
        .toList();
    _categoriesById
      ..clear()
      ..addEntries(allCategories.map((cat) => MapEntry(cat.id, cat)));

    final categoriesByParent = <int?, List<db_models.Category>>{};
    for (final cat in allCategories) {
      categoriesByParent.putIfAbsent(cat.parentId, () => []);
      categoriesByParent[cat.parentId]!.add(cat);
    }

    debugPrint('💾 Loaded ${allCategories.length} categories');

    // Build catalog tree starting from root categories (parentId = null)
    // Sort root categories by orderIndex (like Kotlin: sortedBy { it.order })
    final rootCategories = (categoriesByParent[null] ?? [])
      ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
    final Library library = Library(categories: []);

    debugPrint('💾 Found ${rootCategories.length} root categories');

    final tTree = DateTime.now();
    int totalCategories = 0;
    for (final rootCategory in rootCategories) {
      final catalogCategory = _buildCatalogCategoryRecursiveOptimized(
        rootCategory,
        booksByCategory,
        categoriesByParent,
        library,
        metadata,
      );
      library.subCategories.add(catalogCategory);
      totalCategories += _countCategories(catalogCategory);
    }
    debugPrint(
        '⏱️ Category tree build: ${DateTime.now().difference(tTree).inMilliseconds}ms');

    final talmudBavliCategory = library.subCategories.where((category) {
      return category.title == DatabaseConstants.talmudBavliFolderName;
    }).firstOrNull;
    if (talmudBavliCategory != null) {
      await _addBundledTalmudBavliPdfBooksToCategory(
        talmudBavliCategory,
        metadata,
      );
    }

    // NOTE: Sorting is now done during build (like Kotlin), no need for post-sort
    // _sortLibraryRecursive(library); // Removed - sorting happens in _buildCatalogCategoryRecursiveOptimized

    // Mark titles as cached
    _titlesCached = true;

    debugPrint(
        '💾 Database catalog built with $totalCategories categories and ${allDbBooks.length} books from DB');

    // NOTE: Library is now built ONLY from the database.
    // Files that are not in the DB will not appear in the library browser.
    // This is intentional - all book/file information should be in the DB.

    return library;
  }

  /// Gets or creates a category in the database for the given path.
  /// Returns the category ID.
  /// Implements the logic from CATEGORY_SYNC_PLAN.md - Step 3
  Future<int> _getOrCreateCategoryInDb(List<String> categoryPath) async {
    final repository = _sqliteProvider.repository;
    if (repository == null) {
      throw Exception(
          'Repository is not initialized - cannot create categories');
    }

    if (categoryPath.isEmpty) {
      // Return default category
      final defaultCategory =
          await repository.getCategoryByTitle('ללא קטגוריה');
      if (defaultCategory != null) {
        return defaultCategory.id;
      }
      // Create default category if it doesn't exist
      return await repository.insertCategory(
        db_models.Category(
          id: 0,
          title: 'ללא קטגוריה',
          parentId: null,
          level: 0,
        ),
      );
    }

    // Start from root (parentId = null)
    int? parentId;
    int currentLevel = 0;

    // Walk through each level of the category hierarchy
    for (final categoryName in categoryPath) {
      // Try to find existing category with this name under the current parent
      final existingCategory =
          await repository.getCategoryByTitleAndParent(categoryName, parentId);

      if (existingCategory != null) {
        // Category exists - use it as parent for next level
        parentId = existingCategory.id;
        currentLevel = existingCategory.level + 1;
      } else {
        // Category doesn't exist - create it
        final newCategoryId = await repository.insertCategory(
          db_models.Category(
            id: 0, // Will be auto-generated
            title: categoryName,
            parentId: parentId,
            level: currentLevel,
          ),
        );

        // Use the new category as parent for next level
        parentId = newCategoryId;
        currentLevel++;
      }
    }

    // Return the ID of the final (deepest) category
    return parentId!;
  }

  /// Parses TOC entries for an external text book.
  /// Returns a list of TocEntry objects ready for insertion.
  Future<List<db_models.TocEntry>?> _parseTocForExternalBook(
    File file,
    int bookId,
  ) async {
    try {
      final lowerPath = file.path.toLowerCase();

      List<TocEntry> tocEntries;

      if (lowerPath.endsWith('.pdf')) {
        // Parse PDF outline
        tocEntries = await _parsePdfOutline(file);
      } else {
        // Parse text content (TXT or DOCX)
        String content;
        if (lowerPath.endsWith('.docx')) {
          final title = getTitleFromPath(file.path);
          final bytes = await file.readAsBytes();
          content = await Isolate.run(() => docxToText(bytes, title));
        } else {
          content = await file.readAsString();
        }

        // Parse TOC using the existing TocParser
        tocEntries =
            await Isolate.run(() => TocParser.parseEntriesFromContent(content));
      }

      if (tocEntries.isEmpty) {
        return null;
      }

      // Convert to DB TocEntry format
      final dbEntries = <db_models.TocEntry>[];
      _convertTocEntriesToDb(tocEntries, dbEntries, bookId, null);

      return dbEntries;
    } catch (e) {
      debugPrint('⚠️ Failed to parse TOC for external book: $e');
      return null;
    }
  }

  /// Parses PDF outline and converts to TocEntry format.
  Future<List<TocEntry>> _parsePdfOutline(File file) async {
    try {
      final document = await PdfDocument.openFile(file.path);
      final outline = await document.loadOutline();

      if (outline.isEmpty) {
        return [];
      }

      final entries = <TocEntry>[];
      _convertPdfOutlineToTocEntries(outline, entries, level: 1);

      return entries;
    } catch (e) {
      debugPrint('⚠️ Failed to parse PDF outline: $e');
      return [];
    }
  }

  /// Recursively converts PDF outline nodes to TocEntry format.
  void _convertPdfOutlineToTocEntries(
    List<PdfOutlineNode> nodes,
    List<TocEntry> entries, {
    required int level,
    TocEntry? parent,
  }) {
    for (final node in nodes) {
      final pageNumber = node.dest?.pageNumber ?? 0;

      final entry = TocEntry(
        text: node.title,
        index: pageNumber,
        level: level,
        parent: parent,
      );

      // Process children recursively
      if (node.children.isNotEmpty) {
        _convertPdfOutlineToTocEntries(
          node.children,
          entry.children,
          level: level + 1,
          parent: entry,
        );
      }

      entries.add(entry);
    }
  }

  /// Recursively converts TocEntry objects to DB format.
  void _convertTocEntriesToDb(
    List<TocEntry> entries,
    List<db_models.TocEntry> dbEntries,
    int bookId,
    int? parentId,
  ) {
    for (int i = 0; i < entries.length; i++) {
      final entry = entries[i];
      final isLastChild = i == entries.length - 1;
      final hasChildren = entry.children.isNotEmpty;
      final localEntryId = dbEntries.length + 1;

      final dbEntry = db_models.TocEntry(
        id: localEntryId,
        bookId: bookId,
        parentId: parentId,
        text: entry.text,
        level: entry.level,
        lineId: null, // No line table entry for external books
        lineIndex: entry.index, // Store the index directly for external books
        isLastChild: isLastChild,
        hasChildren: hasChildren,
      );

      dbEntries.add(dbEntry);

      if (hasChildren) {
        _convertTocEntriesToDb(
          entry.children,
          dbEntries,
          bookId,
          localEntryId,
        );
      }
    }
  }

  /// Recursively builds a catalog category with its subcategories and books (OPTIMIZED - no async).
  /// Mirrors the Kotlin buildCatalogCategoryRecursive logic:
  /// - Books are sorted by order
  /// - Subcategories are sorted by orderIndex
  Category _buildCatalogCategoryRecursiveOptimized(
    db_models.Category dbCategory,
    Map<int, List<Map<String, dynamic>>> booksByCategory,
    Map<int?, List<db_models.Category>> categoriesByParent,
    Category parent,
    Map<String, Map<String, dynamic>> metadata,
  ) {
    // Create the category using orderIndex from DB (like Kotlin uses category.order)
    final category = Category(
      title: dbCategory.title,
      description: metadata[dbCategory.title]?['heDesc'] ?? '',
      shortDescription: metadata[dbCategory.title]?['heShortDesc'] ?? '',
      order: dbCategory.orderIndex,
      subCategories: [],
      books: [],
      parent: parent,
    );

    // Get books for this category and sort by order (like Kotlin: sortedBy { it.order })
    final dbBooks = (booksByCategory[dbCategory.id] ?? [])
      ..sort((a, b) {
        final orderA = (a['orderIndex'] as num?)?.toDouble() ?? 999.0;
        final orderB = (b['orderIndex'] as num?)?.toDouble() ?? 999.0;
        return orderA.compareTo(orderB);
      });
    for (final dbBook in dbBooks) {
      final book = _convertMinimalBookMapToBook(dbBook, category, metadata);
      if (book == null) continue;
      category.books.add(book);

      // Cache the book key for provider mapping
      final key = BookCompositeKey.create(
        title: book.title,
        categoryId: dbCategory.id,
        fileType: book.fileType,
      );
      _cachedKeys.add(key);
      if (book.categoryPath != null && book.categoryPath!.isNotEmpty) {
        _categoryIdToPath[dbCategory.id] = book.categoryPath!;
      }
    }

    // Get subcategories sorted by orderIndex (like Kotlin: sortedBy { it.order })
    final children = (categoriesByParent[dbCategory.id] ?? [])
      ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));

    for (final child in children) {
      final subCategory = _buildCatalogCategoryRecursiveOptimized(
        child,
        booksByCategory,
        categoriesByParent,
        category,
        metadata,
      );
      category.subCategories.add(subCategory);
    }

    return category;
  }

  /// Converts a minimal book map (from getAllBooksMinimal) to the app's Book model.
  /// Uses only the columns available: id, title, categoryId, orderIndex,
  /// fileType, filePath, heShortDesc.
  /// Falls back to metadata for author/pubDate/pubPlace/topics.
  Book? _convertMinimalBookMapToBook(
    Map<String, dynamic> bookMap,
    Category category,
    Map<String, Map<String, dynamic>> metadata,
  ) {
    final title = bookMap['title'] as String;
    final id = bookMap['id'] as int? ?? 0;
    final filePath = bookMap['filePath'] as String?;
    final fileType = bookMap['fileType'] as String?;
    final heShortDesc = bookMap['heShortDesc'] as String?;
    final orderDouble = (bookMap['orderIndex'] as num?)?.toDouble() ?? 999.0;
    final order = orderDouble.toInt();
    final categoryId = bookMap['categoryId'] as int? ?? 0;

    final bookMeta = metadata[title];

    // Build category path from the Category object
    String getCategoryPath(Category? cat) {
      final List<String> path = [];
      final Set<Category> visited = {};
      while (cat != null && !visited.contains(cat)) {
        if (cat.title == 'ספריית אוצריא') break;
        visited.add(cat);
        path.insert(0, cat.title);
        cat = cat.parent;
      }
      return path.join(', ');
    }

    final categoryPath = getCategoryPath(category);

    // Use metadata for topics (no junction table data available)
    String topics = '';
    if (categoryPath.isNotEmpty) {
      topics = categoryPath
          .split(',')
          .map((p) => p.trim())
          .where((p) => p.isNotEmpty)
          .join(', ');
    }

    // Use metadata for author/pubDate/pubPlace
    final author = bookMeta?['author'] as String?;
    final pubDate = bookMeta?['pubDate'] as String?;
    final pubPlace = bookMeta?['pubPlace'] as String?;
    final metaHeShortDesc = heShortDesc ?? bookMeta?['heShortDesc'] as String?;

    final normalizedFileType = (fileType ?? '').toLowerCase();

    // External catalog books (fileType='link') are no longer stored in seforim.db.
    // They are served from a separate database via ExternalCatalogRepository.
    if (normalizedFileType == 'link' || normalizedFileType == 'url') {
      return null;
    }

    if (filePath != null && fileType == 'pdf') {
      return PdfBook(
        id: id,
        title: title,
        category: category,
        path: filePath,
        author: author,
        heShortDesc: metaHeShortDesc,
        pubDate: pubDate,
        pubPlace: pubPlace,
        order: order,
        topics: topics,
        categoryPath: categoryPath,
        categoryId: categoryId,
      );
    }

    if (filePath != null && fileType == 'docx') {
      return DocxBook(
        id: id,
        title: title,
        category: category,
        path: filePath,
        author: author,
        heShortDesc: metaHeShortDesc,
        pubDate: pubDate,
        pubPlace: pubPlace,
        order: order,
        topics: topics,
        categoryPath: categoryPath,
        categoryId: categoryId,
      );
    }

    return TextBook(
      id: id,
      title: title,
      category: category,
      author: author,
      heShortDesc: metaHeShortDesc,
      pubDate: pubDate,
      pubPlace: pubPlace,
      order: order,
      topics: topics,
      categoryPath: categoryPath,
      categoryId: categoryId,
    );
  }

  /// Counts the total number of categories in the tree.
  int _countCategories(Category category) {
    return 1 +
        category.subCategories
            .fold(0, (sum, sub) => sum + _countCategories(sub));
  }

  @override
  Future<List<Link>> getAllLinksForBook(
      String title, int categoryId, String fileType) async {
    return _dbOperation<List<Link>>(
      (db) async {
        final book = await _sqliteProvider.repository!
            .getBookByTitleCategoryAndFileType(title, categoryId, fileType);
        if (book == null) {
          debugPrint('💾 Book "$title" not found in database');
          return [];
        }

        // Get all links where this book is the source
        final result = db.select('''
        SELECT 
          l.sourceLineId,
          l.targetLineId,
          sl.lineIndex as sourceLineIndex,
          tl.lineIndex as targetLineIndex,
          tb.title as targetBookTitle,
          ct.name as connectionTypeName
        FROM link l
        JOIN line sl ON l.sourceLineId = sl.id
        JOIN line tl ON l.targetLineId = tl.id
        JOIN book tb ON l.targetBookId = tb.id
        LEFT JOIN connection_type ct ON l.connectionTypeId = ct.id
        WHERE l.sourceBookId = ?
        ORDER BY sl.lineIndex
      ''', [book.id]).toMapList();

        final links = result.map((row) {
          final targetTitle = row['targetBookTitle'] as String;
          final connectionType =
              row['connectionTypeName'] as String? ?? 'reference';

          return Link(
            heRef: targetTitle,
            index1: (row['sourceLineIndex'] as int) + 1,
            path2: targetTitle,
            index2: (row['targetLineIndex'] as int) + 1,
            connectionType: connectionType,
          );
        }).toList();

        debugPrint('💾 Found ${links.length} links for book "$title"');
        return links;
      },
      [],
      'getAllLinksForBook "$title"',
    );
  }

  @override
  Future<String> getLinkContent(Link link) async {
    return _dbOperation<String>(
      (db) async {
        if (link.path2.isEmpty) {
          return 'שגיאה: נתיב ריק';
        }

        if (link.index2 <= 0) {
          return 'שגיאה: אינדקס לא תקין';
        }

        // Get the target book text and extract the specific line
        final targetTitle = link.path2.contains('/')
            ? link.path2.split('/').last.replaceAll('.txt', '')
            : link.path2;

        final bookText = await _sqliteProvider.getBookTextFromDb(targetTitle);
        if (bookText == null) {
          return 'שגיאה: הספר לא נמצא במסד הנתונים';
        }

        final lines = bookText.split('\n');

        if (link.index2 < 1 || link.index2 > lines.length) {
          return 'שגיאה: אינדקס מחוץ לטווח';
        }

        return lines[link.index2 - 1];
      },
      'שגיאה בטעינת תוכן המפרש',
      'getLinkContent',
    );
  }

  /// Get all alternative TOC structures available in the database for a specific book
  Future<List<AltTocStructure>> getAlternativeStructuresForBook(
      String bookTitle) async {
    return _dbOperation<List<AltTocStructure>>(
      (db) async {
        // First get the book ID
        final bookResults = db.select(
          'SELECT id FROM book WHERE title = ?',
          [bookTitle],
        ).toMapList();

        if (bookResults.isEmpty) {
          return [];
        }

        final bookId = bookResults.first['id'] as int;

        // Then get the structures
        final results = db.select(
          'SELECT * FROM alt_toc_structure WHERE bookId = ?',
          [bookId],
        ).toMapList();

        return results.map((json) => AltTocStructure.fromJson(json)).toList();
      },
      [],
      'getAlternativeStructuresForBook "$bookTitle"',
    );
  }

  /// Get all alternative TOC structures available in the database
  Future<List<AltTocStructure>> getAlternativeStructures() async {
    return _dbOperation<List<AltTocStructure>>(
      (db) async {
        final results =
            db.select('SELECT * FROM alt_toc_structure').toMapList();
        return results.map((json) => AltTocStructure.fromJson(json)).toList();
      },
      [],
      'getAlternativeStructures',
    );
  }

  /// Get all alternative TOC entries for a specific structure
  Future<List<AltTocEntry>> getAllAlternativeEntries(int structureId) async {
    return _dbOperation<List<AltTocEntry>>(
      (db) async {
        // We join with tocText to get the actual text
        // Order by ID to ensure consistent order (or maybe level/parentId)
        final results = db.select('''
          SELECT e.*, t.text
          FROM alt_toc_entry e
          JOIN tocText t ON e.textId = t.id
          WHERE e.structureId = ?
          ORDER BY e.id
        ''', [structureId]).toMapList();

        return results.map((json) => AltTocEntry.fromJson(json)).toList();
      },
      [],
      'getAllAlternativeEntries $structureId',
    );
  }

  /// Get links (books/lines) associated with a specific alternative TOC entry
  Future<List<Link>> getLinksForAltTocEntry(
      int structureId, int altTocEntryId) async {
    return _dbOperation<List<Link>>(
      (db) async {
        // Join line_alt_toc -> line -> book
        final results = db.select('''
          SELECT 
            b.title as bookTitle,
            l.lineIndex,
            l.heRef
          FROM line_alt_toc lat
          JOIN line l ON lat.lineId = l.id
          JOIN book b ON l.bookId = b.id
          WHERE lat.structureId = ? AND lat.altTocEntryId = ?
          ORDER BY b.title, l.lineIndex
        ''', [structureId, altTocEntryId]).toMapList();

        return results.map((row) {
          final bookTitle = row['bookTitle'] as String;
          final lineIndex = row['lineIndex'] as int;

          return Link(
            heRef: row['heRef'] as String? ?? '$bookTitle ${lineIndex + 1}',
            index1: 0, // Not relevant here
            path2: bookTitle,
            index2: lineIndex + 1, // 1-based index for UI
            connectionType: 'alt_toc',
          );
        }).toList();
      },
      [],
      'getLinksForAltTocEntry',
    );
  }

  /// Get the alternative TOC entry associated with a specific book line
  Future<int?> getAltTocEntryForLine(
      String bookTitle, int lineIndex, int structureId) async {
    return _dbOperation<int?>(
      (db) async {
        final results = db.select('''
          SELECT lat.altTocEntryId
          FROM line_alt_toc lat
          JOIN line l ON lat.lineId = l.id
          JOIN book b ON l.bookId = b.id
          WHERE b.title = ? AND l.lineIndex = ? AND lat.structureId = ?
          LIMIT 1
  ''', [bookTitle, lineIndex, structureId]).toMapList();

        if (results.isNotEmpty) {
          return results.first['altTocEntryId'] as int;
        }
        return null;
      },
      null,
      'getAltTocEntryForLine',
    );
  }

  /// This is called when a new custom folder is added.
  ///
  /// [folderPath] - The full path to the folder to scan
  /// [folderName] - The display name of the folder
  /// [repository] - The repository to use for database operations
  Future<void> scanAndAddExternalBooksFromFolder(
    String folderPath,
    String folderName,
    dynamic repository,
  ) async {
    debugPrint('📁 Scanning custom folder for external books: $folderPath');

    final dir = Directory(folderPath);
    if (!await dir.exists()) {
      debugPrint('⚠️ Folder does not exist: $folderPath');
      return;
    }

    // Load metadata (empty map if not available)
    final metadata = <String, Map<String, dynamic>>{};

    // Scan the folder recursively
    await _scanFolderForExternalBooks(
      dir,
      repository,
      metadata,
      ['ספרים אישיים', folderName],
    );

    debugPrint('📁 Finished scanning custom folder: $folderPath');
  }

  /// Recursively scans a folder and adds external books to the database.
  Future<void> _scanFolderForExternalBooks(
    Directory dir,
    dynamic repository,
    Map<String, Map<String, dynamic>> metadata,
    List<String> categoryPath,
  ) async {
    await for (FileSystemEntity entity in dir.list()) {
      try {
        await entity.stat();

        if (entity is Directory) {
          final subDirName = entity.path.split(Platform.pathSeparator).last;
          final newPath = [...categoryPath, subDirName];
          await _scanFolderForExternalBooks(
            entity,
            repository,
            metadata,
            newPath,
          );
        } else if (entity is File) {
          final fileName =
              entity.path.split(Platform.pathSeparator).last.toLowerCase();
          // Only process supported file types
          if (!fileName.endsWith('.pdf') &&
              !fileName.endsWith('.txt') &&
              !fileName.endsWith('.docx')) {
            continue;
          }

          await _addSingleExternalBookToDb(
            entity,
            repository,
            metadata,
            categoryPath,
          );
        }
      } catch (e) {
        debugPrint('⚠️ Skipping inaccessible entity: ${entity.path}');
        continue;
      }
    }
  }

  /// Adds a single external book to the database.
  Future<void> _addSingleExternalBookToDb(
    File file,
    dynamic repository,
    Map<String, Map<String, dynamic>> metadata,
    List<String> categoryPath,
  ) async {
    final path = file.path.toLowerCase();
    final title = getTitleFromPath(file.path);
    final fileStat = await file.stat();
    final fileSize = fileStat.size;
    final lastModified = fileStat.modified.millisecondsSinceEpoch;

    // Determine file type
    String fileType;
    if (path.endsWith('.pdf')) {
      fileType = 'pdf';
    } else if (path.endsWith('.txt')) {
      fileType = 'txt';
    } else if (path.endsWith('.docx')) {
      fileType = 'docx';
    } else {
      return;
    }

    // Check if the book already exists in DB (by file path)
    final existingBook = await repository.getExternalBookByFilePath(file.path);
    if (existingBook != null) {
      // Book exists - check if we need to update metadata
      if (existingBook.fileSize != fileSize ||
          existingBook.lastModified != lastModified) {
        await repository.updateExternalBookMetadata(
          existingBook.id,
          fileSize,
          lastModified,
        );
        debugPrint('📁 Updated external book metadata: $title');
      }
      return;
    }

    // Book doesn't exist - add it to DB
    try {
      // Get or create category in DB
      final categoryId = await _getOrCreateCategoryInDb(categoryPath);

      // Parse TOC for text-like files and PDFs
      List<db_models.TocEntry>? tocEntries;
      if (fileType == 'txt' || fileType == 'docx' || fileType == 'pdf') {
        tocEntries = await _parseTocForExternalBook(file, categoryId);
      }

      // Insert the external book
      await repository.insertExternalContentBook(
        categoryId: categoryId,
        title: title,
        filePath: file.path,
        fileType: fileType,
        fileSize: fileSize,
        lastModified: lastModified,
        heShortDesc: metadata[title]?['heShortDesc'],
        orderIndex: (metadata[title]?['order'] ?? 999).toDouble(),
        isPersonal: true,
        tocEntries: tocEntries,
      );

      debugPrint('📁 Inserted external book to DB: $title (type: $fileType)');
    } catch (e) {
      debugPrint('⚠️ Failed to insert external book to DB: $title - $e');
    }
  }
}
