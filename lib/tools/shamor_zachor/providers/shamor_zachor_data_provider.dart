import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'dart:convert';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:otzaria/find_ref/repository/find_ref_db_isolate.dart';
import 'package:otzaria/migration/database/repository/seforim_repository.dart';
import 'package:otzaria/migration/models/category.dart' as db_models;
import 'package:otzaria/migration/models/book.dart' as db_models;
import 'package:otzaria/migration/models/toc_entry.dart' as db_models;

import '../models/book_model.dart';
import '../models/error_model.dart';
import '../services/shamor_zachor_bootstrap_worker.dart';
import 'package:otzaria/utils/file/document_format.dart';

typedef ShamorZachorCategoryTreeLoader =
    Future<Map<String, dynamic>> Function({
      required String dbPath,
      required List<int> trackedBookIds,
    });

/// Provider for managing book data in Shamor Zachor
class ShamorZachorDataProvider with ChangeNotifier {
  static final Logger _logger = Logger('ShamorZachorDataProvider');

  // Dependencies
  final SqliteDataProvider? _sqliteDataProvider;
  final ShamorZachorCategoryTreeLoader _categoryTreeLoader;

  // State
  Map<String, BookCategory> _allBookData = {};
  bool _isLoading = false;
  ShamorZachorError? _error;
  Future<void>? _loadFuture;
  int _generation = 0;
  bool _hasRequestedData = false;
  bool _disposed = false;

  // Cache for TOC data - loaded on demand only
  final Map<int, List<BookSection>> _tocCache = {};

  // Tracked books list - stored in Hive via Settings
  static const String _trackedBooksKey = 'sz:tracked_books';
  Set<int> _trackedBookIds = {};

  // Getters
  Map<String, BookCategory> get allBookData => _allBookData;
  bool get isLoading => _isLoading;
  ShamorZachorError? get error => _error;
  bool get hasData => _allBookData.isNotEmpty;

  /// מזהי הספרים שהמשתמש הוסיף ידנית למעקב (להבדיל מספרי בסיס שמוצגים תמיד)
  Set<int> get trackedBookIds => Set.unmodifiable(_trackedBookIds);

  /// בודק אם ספר נוסף ידנית למעקב לפי מזהה
  bool isBookTrackedById(int bookId) => _trackedBookIds.contains(bookId);

  /// Constructor accepting SqliteDataProvider
  ///
  /// NOTE: Data is NOT loaded automatically in the constructor to avoid
  /// slowing down app startup. Call ensureLoaded() when the widget is displayed.
  ShamorZachorDataProvider({
    SqliteDataProvider? sqliteDataProvider,
    ShamorZachorCategoryTreeLoader? categoryTreeLoader,
  }) : _sqliteDataProvider = sqliteDataProvider ?? SqliteDataProvider.instance,
       _categoryTreeLoader =
           categoryTreeLoader ?? ShamorZachorBootstrapWorker.loadCategoryTree {
    _sqliteDataProvider!.repositoryChanges.addListener(_onRepositoryChanged);
  }

  void _onRepositoryChanged() {
    _generation++;
    _allBookData = {};
    _tocCache.clear();
    _error = null;
    _loadFuture = null;
    _isLoading = false;
    if (_hasRequestedData && _sqliteDataProvider!.repository != null) {
      unawaited(loadAllData());
    } else {
      notifyListeners();
    }
  }

  bool _isCurrent(int generation) => !_disposed && generation == _generation;

  /// ממתין לטעינה פעילה, או משתמש בנתונים שכבר נטענו מהמאגר הנוכחי.
  Future<void> ensureLoaded() async {
    if (_loadFuture == null && (hasData || _error != null)) return;
    await loadAllData();
  }

  Future<void> loadAllData() async {
    if (_disposed) return;
    _hasRequestedData = true;
    final generation = _generation;
    await (_loadFuture ??= Future<void>.microtask(
      () => _loadAllData(generation),
    ));
    if (!_disposed &&
        generation != _generation &&
        _sqliteDataProvider!.repository != null) {
      await ensureLoaded();
    }
  }

  Future<void> _loadAllData(int generation) async {
    if (!_isCurrent(generation)) return;
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      if (!_isCurrent(generation)) return;
      if (_sqliteDataProvider == null || !_sqliteDataProvider.isInitialized) {
        // Attempt to init if not ready
        await _sqliteDataProvider?.initialize();
      }

      if (!_isCurrent(generation)) return;
      if (_sqliteDataProvider?.repository == null) {
        throw Exception('Database repository not initialized');
      }

      final repository = _sqliteDataProvider!.repository!;

      // Load tracked books list from Hive-backed settings
      await _loadTrackedBooksList();
      if (!_isCurrent(generation)) return;

      // Try loading the category tree off the main isolate to keep the UI
      // thread responsive while opening books. Falls back to in-isolate logic
      // if the worker fails for any reason.
      try {
        final workerResult = await _categoryTreeLoader(
          dbPath: _sqliteDataProvider.dbPath,
          trackedBookIds: _trackedBookIds.toList(),
        );
        if (!_isCurrent(generation)) return;
        final categories = (workerResult['categories'] as List)
            .map((raw) => (raw as Map).cast<String, dynamic>())
            .toList();
        _allBookData = _hydrateCategoryTree(categories);
        _logger.info(
          'Loaded ${_allBookData.length} top-level categories in isolate '
          '(${workerResult['relevantBookCount']} relevant books, '
          '${workerResult['allBookCount']} total books, '
          '${workerResult['categoryCount']} categories).',
        );
        return;
      } catch (e, stackTrace) {
        if (!_isCurrent(generation)) return;
        _logger.warning(
          'Failed to load Shamor Zachor data in isolate, falling back to main isolate',
          e,
          stackTrace,
        );
      }

      final allBooks = await repository.database.bookDao.getAllBooks();
      if (!_isCurrent(generation)) return;
      final relevantBooks = allBooks
          .where((book) => book.isBaseBook || _trackedBookIds.contains(book.id))
          .toList();

      final allCategories = await repository.database.categoryDao
          .getAllCategories();
      if (!_isCurrent(generation)) return;
      final categoryMap = {for (var c in allCategories) c.id: c};

      // Build Category Tree Structure
      final Map<String, BookCategory> resultData = {};

      // Group Books by their Category ID first
      final Map<int, List<db_models.Book>> booksByCatId = {};
      for (var b in relevantBooks) {
        booksByCatId.putIfAbsent(b.categoryId, () => []);
        booksByCatId[b.categoryId]!.add(b);
      }

      final rootCategories =
          allCategories.where((c) => c.parentId == null).toList()
            ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));

      for (var rootCat in rootCategories) {
        final builtCat = await _buildRecursiveCategory(
          rootCat,
          categoryMap,
          booksByCatId,
          null,
          parentPath: [],
          generation: generation,
        );

        if (!_isCurrent(generation)) return;
        if (builtCat != null) {
          resultData[builtCat.name] = builtCat;
        }
      }

      _allBookData = resultData;
      _logger.info(
        'Loaded ${_allBookData.length} top-level categories from DB using shared cache (${relevantBooks.length} books).',
      );
    } catch (e, stackTrace) {
      if (!_isCurrent(generation)) return;
      _logger.severe('Error loading from DB', e, stackTrace);
      _error = ShamorZachorError.fromException(e, stackTrace: stackTrace);
    } finally {
      if (_isCurrent(generation)) {
        _loadFuture = null;
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  Map<String, BookCategory> _hydrateCategoryTree(
    List<Map<String, dynamic>> categories,
  ) {
    return {
      for (final category in categories)
        category['name'] as String: _hydrateCategory(category),
    };
  }

  BookCategory _hydrateCategory(Map<String, dynamic> json) {
    final booksJson = json['books'] as Map;
    return BookCategory(
      name: json['name'] as String,
      contentType: json['contentType'] as String,
      books: {
        for (final entry in booksJson.entries)
          entry.key as String: _hydrateBookDetails(
            (entry.value as Map).cast<String, dynamic>(),
          ),
      },
      defaultStartPage: json['defaultStartPage'] as int? ?? 1,
      isCustom: json['isCustom'] as bool? ?? false,
      sourceFile: json['sourceFile'] as String? ?? 'db',
      subcategories: (json['subcategories'] as List?)
          ?.map((raw) => _hydrateCategory((raw as Map).cast<String, dynamic>()))
          .toList(),
      parentCategoryName: json['parentCategoryName'] as String?,
      schemaVersion: json['schemaVersion'] as int?,
    );
  }

  BookDetails _hydrateBookDetails(Map<String, dynamic> json) {
    return BookDetails(
      contentType: json['contentType'] as String,
      parts: (json['parts'] as List)
          .map((raw) => BookPart.fromJson((raw as Map).cast<String, dynamic>()))
          .toList(),
      isCustom: json['isCustom'] as bool? ?? false,
      id: json['id'] as int?,
      originalPageCount: json['originalPageCount'] as num?,
      sections: (json['sections'] as List?)
          ?.map(
            (raw) => BookSection.fromJson((raw as Map).cast<String, dynamic>()),
          )
          .toList(),
      categoryPath: json['categoryPath'] as String?,
    );
  }

  Future<BookCategory?> _buildRecursiveCategory(
    db_models.Category currentCat,
    Map<int, db_models.Category> allCatsMap,
    Map<int, List<db_models.Book>> booksByCatId,
    String? inheritedContentType, {
    List<String> parentPath = const [],
    required int generation,
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
        dbBook,
        myContentType,
        currentPath,
      );
      if (!_isCurrent(generation)) return null;
      validBooks[dbBook.title] = bookDetails;
    }

    // 2. Get Subcategories
    final childCats =
        allCatsMap.values.where((c) => c.parentId == currentCat.id).toList()
          ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));

    final List<BookCategory> validSubCats = [];

    for (var child in childCats) {
      final sub = await _buildRecursiveCategory(
        child,
        allCatsMap,
        booksByCatId,
        myContentType,
        parentPath: currentPath,
        generation: generation,
      );
      if (!_isCurrent(generation)) return null;
      if (sub != null) {
        validSubCats.add(sub);
      }
    }

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
    String contentType,
    List<String> categoryPath,
  ) async {
    // Load TOC sections for the book
    final sections = await getTocForBook(dbBook.id);

    List<BookPart> parts = [];

    // Create a default Part based on book metadata
    // Use actual totalLines, but ensure minimum of 1
    int endPage = dbBook.totalLines > 0 ? dbBook.totalLines : 1;

    parts.add(
      BookPart(
        name: "ראשי",
        startPage: 1,
        endPage: endPage,
      ),
    );

    // Use the first category in the path as the main category for progress tracking
    // This is the top-level category from the DB (e.g., "תלמוד בבלי", "תנ"ך")
    final categoryPathString = categoryPath.isNotEmpty
        ? categoryPath.first
        : '';

    return BookDetails(
      // ספר שתוכנו מומר (או PDF) אינו מבוסס-דף, ולכן אסור לו לרשת
      // contentType של "דף" מהקטגוריה. הסיומת עצמה משמשת כסוג.
      contentType: _nonDafContentType(dbBook.fileType) ?? contentType,
      parts: parts,
      isCustom: !dbBook.isBaseBook, // isCustom means "not a base book"
      id: dbBook.id, // העברת ה-ID כ-int ישירות
      originalPageCount: dbBook.totalLines,
      sections: sections.isNotEmpty ? sections : null,
      categoryPath: categoryPathString,
    );
  }

  /// Load TOC for a specific book on demand
  /// This is called only when the user actually needs the TOC
  Future<List<BookSection>> getTocForBook(int bookId) async {
    final generation = _generation;
    if (_disposed) return [];
    // Check cache first
    if (_tocCache.containsKey(bookId)) {
      return _tocCache[bookId]!;
    }

    try {
      final repository = _sqliteDataProvider!.repository!;
      final isolate = await FindRefDbIsolate.instance();
      if (!_isCurrent(generation)) return [];
      final tocEntries = await isolate.getBookTocEntries(bookId);
      if (!_isCurrent(generation)) return [];

      if (tocEntries.isEmpty) {
        _tocCache[bookId] = [];
        return [];
      }

      // Get book to know totalLines for proper endPage calculation
      final book = await repository.database.bookDao.getBookById(bookId);
      if (!_isCurrent(generation)) return [];
      final totalLines = book?.totalLines ?? 100;

      final sections = _buildSectionsFromToc(tocEntries, totalLines);
      _tocCache[bookId] = sections;
      return sections;
    } catch (e) {
      // בלי צריבה בקאש: כשל זמני (worker שנפל, DB נעול) היה מקבע "אין
      // פרקים" לספר עד ריענון, במקום להיות ניתן לניסיון חוזר.
      _logger.warning('Failed to load TOC for book $bookId', e);
      return [];
    }
  }

  List<BookSection> _buildSectionsFromToc(
    List<db_models.TocEntry> entries,
    int totalLines,
  ) {
    // DB entries are a flat list; the tree is rebuilt by parentId.
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
      result.add(
        _convertToSection(
          current,
          childMap,
          currentEnd > 0 ? currentEnd : totalLines,
        ),
      );
    }
    return result;
  }

  BookSection _convertToSection(
    db_models.TocEntry entry,
    Map<int, List<db_models.TocEntry>> childMap,
    int parentEndPage,
  ) {
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
        final result = _findBookByIdRecursive(
          subCategory,
          bookId,
          topLevelName,
        );
        if (result != null) {
          return result;
        }
      }
    }

    return null;
  }

  List<BookSearchResult> searchBooks(String query) {
    if (query.isEmpty) return [];
    final results = <BookSearchResult>[];
    final queryLower = query.toLowerCase();

    _allBookData.forEach((topLevelName, category) {
      _searchRecursive(category, queryLower, results, topLevelName);
    });
    return results;
  }

  void _searchRecursive(
    BookCategory category,
    String query,
    List<BookSearchResult> results,
    String topName,
  ) {
    // Direct
    category.books.forEach((name, details) {
      if (name.toLowerCase().contains(query)) {
        results.add(
          BookSearchResult(details, category.name, category, name, topName),
        );
      }
    });
    // Sub
    category.subcategories?.forEach((sub) {
      _searchRecursive(sub, query, results, topName);
    });
  }

  // Other methods (retry, etc)
  void retry() => loadAllData();

  /// Add a book to Shamor Zachor tracking
  /// This saves the book ID to a tracked books list in Hive-backed settings
  /// WITHOUT modifying the books database
  Future<void> addCustomBook({
    required String bookName,
    int? bookId,
    int? categoryId,
  }) async {
    final repository = _sqliteDataProvider?.repository;
    if (repository == null) {
      _logger.warning("Repository not initialized");
      throw Exception('מסד הנתונים לא מאותחל');
    }

    try {
      // 1. Check if book exists in DB
      final existing = await _findOfficialBook(
        repository,
        id: bookId,
        title: bookName,
        categoryId: categoryId,
      );
      if (existing == null) {
        _logger.warning("Book '$bookName' not found in database");
        throw Exception(
          'הספר "$bookName" לא נמצא במסד הנתונים. יש להוסיף אותו תחילה לספרייה.',
        );
      }

      // 2. Add book ID to tracked books list
      await _addToTrackedBooksList(existing.id);
      _logger.info(
        "Book '$bookName' (ID: ${existing.id}) added to Shamor Zachor tracking",
      );

      // 3. Reload data to show the book in Shamor Zachor
      await loadAllData();
    } catch (e) {
      _logger.warning("Failed to add book to Shamor Zachor tracking", e);
      rethrow;
    }
  }

  /// מוסיף מספר ספרים למעקב בקריאה אחת, עם טעינה מחדש אחת בלבד בסוף.
  ///
  /// כל פריט מזוהה לפי [id] מול המסד הרשמי בלבד — רשימת המעקב נשמרת
  /// כמזהי seforim.db, ולכן מזהה מ-user_books.db יציג ספר שגוי.
  /// מחזיר את מספר הספרים שנוספו ואת מספר אלו שלא נמצאו/נכשלו.
  Future<({int added, int failed})> addCustomBooks(
    List<({int? id, String bookName, int? categoryId})> books,
  ) async {
    final repository = _sqliteDataProvider?.repository;
    if (repository == null) {
      _logger.warning("Repository not initialized");
      throw Exception('מסד הנתונים לא מאותחל');
    }

    if (_trackedBookIds.isEmpty) {
      await _loadTrackedBooksList();
    }

    int added = 0;
    int failed = 0;
    for (final book in books) {
      try {
        final existing = await _findOfficialBook(
          repository,
          id: book.id,
          title: book.bookName,
          categoryId: book.categoryId,
        );
        if (existing == null) {
          _logger.warning("Book '${book.bookName}' not found in database");
          failed++;
          continue;
        }
        if (_trackedBookIds.add(existing.id)) {
          added++;
        }
      } catch (e) {
        _logger.warning("Failed to add book '${book.bookName}' to tracking", e);
        failed++;
      }
    }

    if (added > 0) {
      await _saveTrackedBooksList();
      await loadAllData();
    }

    return (added: added, failed: failed);
  }

  /// מאתר ספר במסד הרשמי בלבד — לפי [id] אם סופק, אחרת לפי כותרת.
  Future<db_models.Book?> _findOfficialBook(
    SeforimRepository repository, {
    int? id,
    required String title,
    int? categoryId,
  }) async {
    if (id != null) {
      return repository.getBook(id);
    }
    if (categoryId != null) {
      final byCategory = await repository.getBookByTitleAndCategory(
        title,
        categoryId,
      );
      if (byCategory != null) return byCategory;
    }
    return repository.getBookByTitle(title);
  }

  /// מסיר ספר מרשימת המעקב לפי מזהה, ללא תלות בהיותו ספר בסיס.
  ///
  /// ספר בסיס יורד מרשימת "בתהליך" ויישאר זמין תחת "הכל".
  Future<void> removeBookFromTracking(int bookId) async {
    await _removeFromTrackedBooksList(bookId);
    await loadAllData();
  }

  /// Load tracked books list from Hive
  Future<void> _loadTrackedBooksList() async {
    try {
      final jsonString = Settings.getValue<String>(_trackedBooksKey);

      if (jsonString == null || jsonString.isEmpty) {
        _trackedBookIds = {};
        return;
      }

      final List<dynamic> decoded = jsonDecode(jsonString);
      _trackedBookIds = decoded.map((e) => e as int).toSet();
    } catch (e) {
      _logger.warning('Failed to load tracked books list', e);
      _trackedBookIds = {};
    }
  }

  /// Save tracked books list to Hive
  Future<void> _saveTrackedBooksList() async {
    try {
      final jsonString = jsonEncode(_trackedBookIds.toList());
      await Settings.setValue<String>(_trackedBooksKey, jsonString);
    } catch (e) {
      _logger.warning('Failed to save tracked books list', e);
    }
  }

  /// Add a book ID to the tracked books list
  Future<void> _addToTrackedBooksList(int bookId) async {
    // Always load from Hive first to avoid overwriting existing tracked books
    // when the in-memory list hasn't been loaded yet (e.g. first call after app restart)
    if (_trackedBookIds.isEmpty) {
      await _loadTrackedBooksList();
    }
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
    _disposed = true;
    _generation++;
    _sqliteDataProvider!.repositoryChanges.removeListener(_onRepositoryChanged);
    _tocCache.clear();
    super.dispose();
  }
}

/// סוג התוכן לספר שאינו מבוסס-דף (PDF או פורמט שדורש המרה), או `null`
/// כשהספר הוא טקסט רגיל ויורש את סוג התוכן מהקטגוריה.
String? _nonDafContentType(String? fileType) {
  final format = documentFormatFromFileType(fileType);
  if (format == null) return null;
  return format == DocumentFormat.pdf || format.requiresConversion
      ? format.extension
      : null;
}
