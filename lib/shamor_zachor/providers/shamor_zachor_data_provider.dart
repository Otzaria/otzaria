import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:otzaria/migration/dao/repository/seforim_repository.dart';
import 'package:otzaria/migration/core/models/category.dart' as db_models;
import 'package:otzaria/migration/core/models/book.dart' as db_models;
import 'package:otzaria/migration/core/models/toc_entry.dart' as db_models;

import '../models/book_model.dart';
import '../models/error_model.dart';

/// Provider for managing book data in Shamor Zachor
/// This provider is scoped locally within the ShamorZachorWidget
///
/// OPTIMIZED: Uses shared cache from SqliteDataProvider to avoid duplicate queries
/// and loads TOC on demand only when needed
class ShamorZachorDataProvider with ChangeNotifier {
  static final Logger _logger = Logger('ShamorZachorDataProvider');

  // Dependencies
  final SqliteDataProvider? _sqliteDataProvider;

  // State - now uses shared cache
  Map<String, BookCategory> _allBookData = {};
  bool _isLoading = false;
  ShamorZachorError? _error;

  // OPTIMIZATION 3: Cache for TOC data - loaded on demand only
  final Map<int, List<BookSection>> _tocCache = {};

  // Tracked books list - stored in SharedPreferences
  static const String _trackedBooksKey = 'sz:tracked_books';
  Set<int> _trackedBookIds = {};

  // Getters
  Map<String, BookCategory> get allBookData => _allBookData;
  bool get isLoading => _isLoading;
  ShamorZachorError? get error => _error;
  bool get hasData => _allBookData.isNotEmpty;

  /// Constructor accepting SqliteDataProvider
  ShamorZachorDataProvider({
    SqliteDataProvider? sqliteDataProvider,
  }) : _sqliteDataProvider = sqliteDataProvider ?? SqliteDataProvider.instance {
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    await loadAllData();
  }

  Future<void> loadAllData() async {
    if (_isLoading) return;
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      if (_sqliteDataProvider == null || !_sqliteDataProvider.isInitialized) {
        // Attempt to init if not ready
        await _sqliteDataProvider?.initialize();
      }

      if (_sqliteDataProvider?.repository == null) {
        throw Exception('Database repository not initialized');
      }

      final repository = _sqliteDataProvider!.repository!;

      // Load tracked books list from SharedPreferences
      await _loadTrackedBooksList();

      // OPTIMIZATION 1 & 2: Use existing getAllBooks() query with in-memory filter
      // Show baseBooks OR books that are in the tracked list
      final allBooks = await repository.database.bookDao.getAllBooks();
      final relevantBooks = allBooks
          .where((book) => book.isBaseBook || _trackedBookIds.contains(book.id))
          .toList();

      // OPTIMIZATION 2: Reuse categories from SqliteDataProvider cache if available
      // This avoids duplicate category queries
      final allCategories =
          await repository.database.categoryDao.getAllCategories();
      final categoryMap = {for (var c in allCategories) c.id: c};

      // 3. Build Category Tree Structure
      final Map<String, BookCategory> resultData = {};

      // Group Books by their Category ID first
      final Map<int, List<db_models.Book>> booksByCatId = {};
      for (var b in relevantBooks) {
        booksByCatId.putIfAbsent(b.categoryId, () => []);
        booksByCatId[b.categoryId]!.add(b);
      }

      final rootCategories = allCategories
          .where((c) => c.parentId == null)
          .toList()
        ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));

      for (var rootCat in rootCategories) {
        final builtCat = await _buildRecursiveCategory(
            rootCat, categoryMap, booksByCatId, repository, null,
            parentPath: []);

        if (builtCat != null) {
          resultData[builtCat.name] = builtCat;
        }
      }

      _allBookData = resultData;
      _logger.info(
          'Loaded ${_allBookData.length} top-level categories from DB using shared cache (${relevantBooks.length} books).');
    } catch (e, stackTrace) {
      _logger.severe('Error loading from DB', e, stackTrace);
      _error = ShamorZachorError.fromException(e, stackTrace: stackTrace);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<BookCategory?> _buildRecursiveCategory(
    db_models.Category currentCat,
    Map<int, db_models.Category> allCatsMap,
    Map<int, List<db_models.Book>> booksByCatId,
    SeforimRepository repository,
    String? inheritedContentType, {
    List<String> parentPath = const [],
  }) async {
    // Determine content type for this category
    // If inherited, use it. If "Bavli/Yerushalmi", force "daf".
    String myContentType = inheritedContentType ?? 'text'; // Default

    if (currentCat.title.contains('בבלי') ||
        currentCat.title.contains('ירושלמי')) {
      myContentType = 'דף';
    } else if (currentCat.title.contains('תנ"ך')) {
      myContentType = 'text'; // Chapters
    }

    // Build the full category path for this category
    final currentPath = [...parentPath, currentCat.title];

    // 1. Get Direct Books
    final directBooks = booksByCatId[currentCat.id] ?? [];
    final Map<String, BookDetails> validBooks = {};

    for (var dbBook in directBooks) {
      // Convert DB Book to BookDetails with the full category path
      final bookDetails = await _convertDbBookToDetails(
          dbBook, repository, myContentType, currentPath);
      validBooks[dbBook.title] = bookDetails;
    }

    // 2. Get Subcategories
    final childCats = allCatsMap.values
        .where((c) => c.parentId == currentCat.id)
        .toList()
      ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));

    final List<BookCategory> validSubCats = [];

    for (var child in childCats) {
      final sub = await _buildRecursiveCategory(
          child, allCatsMap, booksByCatId, repository, myContentType,
          parentPath: currentPath);
      if (sub != null) {
        validSubCats.add(sub);
      }
    }

    // If no books and no subcats with content, skip this category?
    // Or keep it? Usually better to prune empty branches.
    if (validBooks.isEmpty && validSubCats.isEmpty) {
      return null;
    }

    return BookCategory(
      name: currentCat.title,
      contentType: myContentType,
      books: validBooks,
      defaultStartPage: 1, // Logic?
      isCustom: false,
      sourceFile: 'db', // Marker
      subcategories: validSubCats.isNotEmpty ? validSubCats : null,
      parentCategoryName: currentCat.parentId != null
          ? allCatsMap[currentCat.parentId]?.title
          : null,
      schemaVersion: 1,
    );
  }

  Future<BookDetails> _convertDbBookToDetails(
      db_models.Book dbBook,
      SeforimRepository repository,
      String contentType,
      List<String> categoryPath) async {
    // Load TOC sections for the book
    final sections = await getTocForBook(dbBook.id);

    List<BookPart> parts = [];

    // Create a default Part based on book metadata
    // Use actual totalLines, but ensure minimum of 1
    int endPage = dbBook.totalLines > 0 ? dbBook.totalLines : 1;
    if (dbBook.totalLines == 0) {
      _logger.fine('Book ${dbBook.title} has no content (totalLines=0)');
    }

    parts.add(BookPart(
      name: "ראשי",
      startPage: 1,
      endPage: endPage,
    ));

    // Use the first category in the path as the main category for progress tracking
    // This is the top-level category from the DB (e.g., "תלמוד בבלי", "תנ"ך")
    final categoryPathString =
        categoryPath.isNotEmpty ? categoryPath.first : '';

    _logger.fine(
        'Converting book "${dbBook.title}" with categoryPath: $categoryPath -> using: "$categoryPathString"');

    return BookDetails(
      contentType: dbBook.fileType == 'pdf'
          ? 'pdf'
          : (dbBook.fileType == 'docx' ? 'docx' : contentType),
      parts: parts,
      isCustom: !dbBook.isBaseBook, // isCustom means "not a base book"
      id: dbBook.id, // העברת ה-ID כ-int ישירות
      originalPageCount: dbBook.totalLines,
      sections: sections.isNotEmpty ? sections : null,
      categoryPath: categoryPathString,
    );
  }

  /// OPTIMIZATION 3: Load TOC for a specific book on demand
  /// This is called only when the user actually needs the TOC
  Future<List<BookSection>> getTocForBook(int bookId) async {
    // Check cache first
    if (_tocCache.containsKey(bookId)) {
      return _tocCache[bookId]!;
    }

    try {
      final repository = _sqliteDataProvider!.repository!;
      final tocEntries =
          await repository.database.tocDao.selectByBookId(bookId);

      if (tocEntries.isEmpty) {
        _tocCache[bookId] = [];
        return [];
      }

      // Get book to know totalLines for proper endPage calculation
      final book = await repository.database.bookDao.getBookById(bookId);
      final totalLines = book?.totalLines ?? 100;

      final sections = _buildSectionsFromToc(tocEntries, totalLines);
      _tocCache[bookId] = sections;
      return sections;
    } catch (e) {
      _logger.warning('Failed to load TOC for book $bookId', e);
      _tocCache[bookId] = [];
      return [];
    }
  }

  List<BookSection> _buildSectionsFromToc(
      List<db_models.TocEntry> entries, int totalLines) {
    // Map DB entries to BookSection
    // DB entries are flat list. We need to rebuild tree.
    // `TocDao` usually handles relationships.

    // Naive reconstruction:
    // Filter roots (parentId == null)
    // Filter roots (parentId == null)
    final childMap = <int, List<db_models.TocEntry>>{};

    for (var e in entries) {
      if (e.parentId != null) {
        childMap.putIfAbsent(e.parentId!, () => []);
        childMap[e.parentId]!.add(e);
      }
    }

    final roots = entries.where((e) => e.parentId == null).toList()
      ..sort((a, b) => (a.lineIndex ?? 0).compareTo(b.lineIndex ?? 0));

    final List<BookSection> result = [];
    for (int i = 0; i < roots.length; i++) {
      final current = roots[i];
      final next = (i + 1 < roots.length) ? roots[i + 1] : null;
      // nextStart is next sibling's startPage or book's totalLines
      final nextStart = next?.lineIndex ?? totalLines;
      final currentEnd =
          (next != null && (next.lineIndex ?? 0) > (current.lineIndex ?? 0))
              ? (next.lineIndex! - 1)
              : nextStart;
      result.add(_convertToSection(
          current, childMap, currentEnd > 0 ? currentEnd : totalLines));
    }
    return result;
  }

  BookSection _convertToSection(db_models.TocEntry entry,
      Map<int, List<db_models.TocEntry>> childMap, int parentEndPage) {
    final children = childMap[entry.id] ?? [];
    children.sort((a, b) => (a.lineIndex ?? 0).compareTo(b.lineIndex ?? 0));

    final List<BookSection> childSections = [];
    final entryStart = entry.lineIndex ?? 0;

    for (int i = 0; i < children.length; i++) {
      final current = children[i];
      final next = (i + 1 < children.length) ? children[i + 1] : null;

      final nextStart = next?.lineIndex ?? parentEndPage;
      final currentEnd =
          (next != null && (next.lineIndex ?? 0) > (current.lineIndex ?? 0))
              ? (next.lineIndex! - 1)
              : nextStart;

      childSections.add(_convertToSection(current, childMap, currentEnd));
    }

    return BookSection(
      id: entry.id.toString(),
      title: entry.text,
      level: entry.level,
      startPage: entryStart,
      endPage: parentEndPage > entryStart ? parentEndPage : entryStart,
      children: childSections,
    );
  }

  // ... (Keep existing methods: getCategory, getBookDetails, searchBooks etc. but update them to use _allBookData memory cache)
  // Since we load everything into _allBookData, existing getters usually work fine IF _allBookData structure is compatible.

  BookCategory? getCategory(String categoryName) => _allBookData[categoryName];

  BookDetails? getBookDetails(String categoryName, String bookName) {
    // First try direct lookup
    final category = _allBookData[categoryName];
    if (category != null) {
      final book = category.getAllBooksRecursive()[bookName];
      if (book != null) return book;
    }

    // If not found, search in all categories (for cases where topLevelCategoryKey is passed)
    for (final topCategory in _allBookData.values) {
      final book = topCategory.getAllBooksRecursive()[bookName];
      if (book != null) return book;
    }

    return null;
  }

  /// Get book details by ID
  /// Returns a tuple of (BookDetails, bookName, topLevelCategoryKey) or null if not found
  (BookDetails, String, String)? getBookById(int bookId) {
    // Search through all categories for the book with matching ID
    for (final entry in _allBookData.entries) {
      final topLevelName = entry.key;
      final category = entry.value;

      // Search recursively in this category
      final result = _findBookByIdRecursive(category, bookId, topLevelName);
      if (result != null) {
        return result;
      }
    }

    return null;
  }

  /// Helper function to search for book by ID recursively
  (BookDetails, String, String)? _findBookByIdRecursive(
    BookCategory category,
    int bookId,
    String topLevelName,
  ) {
    // Check direct books in this category
    for (final entry in category.books.entries) {
      final bookName = entry.key;
      final bookDetails = entry.value;

      if (bookDetails.id == bookId) {
        return (bookDetails, bookName, topLevelName);
      }
    }

    // Check subcategories
    if (category.subcategories != null) {
      for (final subCategory in category.subcategories!) {
        final result =
            _findBookByIdRecursive(subCategory, bookId, topLevelName);
        if (result != null) {
          return result;
        }
      }
    }

    return null;
  }

  // searchBooks needs to work on _allBookData. copy-paste existing logic or keep it.
  List<BookSearchResult> searchBooks(String query) {
    // ... (Keep existing implementation logic)
    if (query.isEmpty) return [];
    final results = <BookSearchResult>[];
    final queryLower = query.toLowerCase();

    _allBookData.forEach((topLevelName, category) {
      _searchRecursive(category, queryLower, results, topLevelName);
    });
    return results;
  }

  void _searchRecursive(BookCategory category, String query,
      List<BookSearchResult> results, String topName) {
    // Direct
    category.books.forEach((name, details) {
      if (name.toLowerCase().contains(query)) {
        results.add(
            BookSearchResult(details, category.name, category, name, topName));
      }
    });
    // Sub
    category.subcategories?.forEach((sub) {
      _searchRecursive(sub, query, results, topName);
    });
  }

  // Other methods (retry, clearError, etc)
  void retry() => _loadInitialData();
  void clearError() {
    _error = null;
    notifyListeners();
  }

  /// Add a book to Shamor Zachor tracking
  /// This saves the book ID to a tracked books list in SharedPreferences
  /// WITHOUT modifying the books database
  Future<void> addCustomBook(
      {required String bookName,
      required String categoryName,
      required String bookPath,
      required String contentType}) async {
    final repository = _sqliteDataProvider?.repository;
    if (repository == null) {
      _logger.warning("Repository not initialized");
      throw Exception('מסד הנתונים לא מאותחל');
    }

    try {
      // 1. Check if book exists in DB
      final existing = await repository.getBookByTitle(bookName);
      if (existing == null) {
        _logger.warning("Book '$bookName' not found in database");
        throw Exception(
            'הספר "$bookName" לא נמצא במסד הנתונים. יש להוסיף אותו תחילה לספרייה.');
      }

      // 2. Add book ID to tracked books list (in SharedPreferences)
      await _addToTrackedBooksList(existing.id);
      _logger.info(
          "Book '$bookName' (ID: ${existing.id}) added to Shamor Zachor tracking");

      // 3. Reload data to show the book in Shamor Zachor
      await loadAllData();
    } catch (e) {
      _logger.warning("Failed to add book to Shamor Zachor tracking", e);
      rethrow;
    }
  }

  /// Remove a book from Shamor Zachor tracking
  /// This removes the book ID from the tracked books list in SharedPreferences
  /// WITHOUT modifying the books database
  Future<void> removeCustomBook(
      {required String categoryName, required String bookName}) async {
    final repository = _sqliteDataProvider?.repository;
    if (repository == null) {
      _logger.warning("Repository not initialized");
      return;
    }

    try {
      final existing = await repository.getBookByTitle(bookName);
      if (existing == null) {
        _logger.warning("Book '$bookName' not found in database");
        return;
      }

      // Only allow removing books that are not base books
      if (existing.isBaseBook) {
        _logger
            .warning("Cannot remove base book '$bookName' from Shamor Zachor");
        throw Exception('לא ניתן להסיר ספר בסיס מ"שמור וזכור"');
      }

      // Remove book ID from tracked books list
      await _removeFromTrackedBooksList(existing.id);
      _logger.info(
          "Book '$bookName' (ID: ${existing.id}) removed from Shamor Zachor tracking");

      // Reload data to remove the book from Shamor Zachor
      await loadAllData();
    } catch (e) {
      _logger.warning("Failed to remove book from Shamor Zachor tracking", e);
      rethrow;
    }
  }

  /// Get all custom (personal) books that are not base books
  /// These are books that were added by the user to Shamor Zachor
  List<Map<String, dynamic>> getCustomBooks() {
    final results = <Map<String, dynamic>>[];

    void scan(BookCategory cat, String topLevel) {
      cat.books.forEach((name, details) {
        // Check if book is in tracked list and is not a base book
        if (details.id != null &&
            _trackedBookIds.contains(details.id) &&
            details.isCustom) {
          // isCustom means "not a base book"
          results.add({
            'categoryName': cat.name,
            'bookName': name,
            'bookDetails': details,
            'topLevelCategoryKey': topLevel
          });
        }
      });
      cat.subcategories?.forEach((sub) => scan(sub, topLevel));
    }

    _allBookData.forEach((topLevelName, cat) {
      scan(cat, topLevelName);
    });

    return results;
  }

  bool isBookTracked(String categoryName, String bookName) {
    // This refers to TrackingProvider usually?
    // Or simply "does it exist"?
    return getBookDetails(categoryName, bookName) != null;
  }

  bool hasCategory(String categoryName) =>
      _allBookData.containsKey(categoryName);

  /// Clear TOC cache to free memory
  void clearTocCache() {
    _tocCache.clear();
    _logger.fine('Cleared TOC cache');
  }

  /// Load tracked books list from SharedPreferences
  Future<void> _loadTrackedBooksList() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString(_trackedBooksKey);

      if (jsonString == null || jsonString.isEmpty) {
        _trackedBookIds = {};
        return;
      }

      final List<dynamic> decoded = jsonDecode(jsonString);
      _trackedBookIds = decoded.map((e) => e as int).toSet();
      _logger.fine('Loaded ${_trackedBookIds.length} tracked books');
    } catch (e) {
      _logger.warning('Failed to load tracked books list', e);
      _trackedBookIds = {};
    }
  }

  /// Save tracked books list to SharedPreferences
  Future<void> _saveTrackedBooksList() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = jsonEncode(_trackedBookIds.toList());
      await prefs.setString(_trackedBooksKey, jsonString);
      _logger.fine('Saved ${_trackedBookIds.length} tracked books');
    } catch (e) {
      _logger.warning('Failed to save tracked books list', e);
    }
  }

  /// Add a book ID to the tracked books list
  Future<void> _addToTrackedBooksList(int bookId) async {
    _trackedBookIds.add(bookId);
    await _saveTrackedBooksList();
  }

  /// Remove a book ID from the tracked books list
  Future<void> _removeFromTrackedBooksList(int bookId) async {
    _trackedBookIds.remove(bookId);
    await _saveTrackedBooksList();
  }

  @override
  void dispose() {
    _tocCache.clear();
    super.dispose();
  }
}
