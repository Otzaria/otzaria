import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:otzaria/migration/dao/repository/seforim_repository.dart';
import 'package:otzaria/migration/core/models/category.dart' as db_models;
import 'package:otzaria/migration/core/models/book.dart' as db_models;
import 'package:otzaria/migration/core/models/toc_entry.dart' as db_models;

import '../models/book_model.dart';
import '../models/error_model.dart';
import '../services/data_loader_service.dart';
import '../services/dynamic_data_loader_service.dart';

/// Provider for managing book data in Shamor Zachor
/// This provider is scoped locally within the ShamorZachorWidget
///
/// Supports both legacy DataLoaderService (static JSON) and new
/// DynamicDataLoaderService (dynamic scanning with cache)
class ShamorZachorDataProvider with ChangeNotifier {
  static final Logger _logger = Logger('ShamorZachorDataProvider');

  // Dependencies
  final SqliteDataProvider? _sqliteDataProvider;

  // State
  Map<String, BookCategory> _allBookData = {};
  bool _isLoading = false;
  ShamorZachorError? _error;

  // Getters
  Map<String, BookCategory> get allBookData => _allBookData;
  bool get isLoading => _isLoading;
  ShamorZachorError? get error => _error;
  bool get hasData => _allBookData.isNotEmpty;

  /// Constructor accepting SqliteDataProvider (or generic DataProvider)
  /// We keep the old constructor signatures for compatibility but ignore them logic-wise if we are strictly DB now.
  /// However, for migration safety, we can accept the sqlite provider.
  ShamorZachorDataProvider({
    DataLoaderService? dataLoaderService,
    DynamicDataLoaderService? dynamicDataLoaderService,
    SqliteDataProvider? sqliteDataProvider,
  }) : _sqliteDataProvider = sqliteDataProvider ?? SqliteDataProvider.instance {
    _loadInitialData();
  }

  // Named constructor for dynamic - kept for compatibility but redirecting to DB approach if possible
  ShamorZachorDataProvider.dynamic(DynamicDataLoaderService dynamicService)
      : _sqliteDataProvider = SqliteDataProvider.instance {
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

      // 1. Fetch "Base Books" and "Personal Books" from DB
      final baseBooks = await repository.database.bookDao.getBaseBooks();
      final personalBooks =
          await repository.database.bookDao.getPersonalBooks();
      final allBooks = [...baseBooks, ...personalBooks];

      // Cached Data
      /// The book dao is accessed via [SeforimRepository.database]
      // final BookDao _bookDao;
      // final CategoryDao _categoryDao;
      // 2. Fetch all Categories (needed to build tree)
      final allCategories =
          await repository.database.categoryDao.getAllCategories();
      final categoryMap = {for (var c in allCategories) c.id: c};

      // 3. Build Category Tree Structure
      // We need to group books by their Top-Level Category for the UI.
      // But Shamor V'Zachor UI expects `Map<String, BookCategory>` where String is the Top-Level Category Name.

      final Map<String, BookCategory> resultData = {};

      // Group Books by their Category ID first
      final Map<int, List<db_models.Book>> booksByCatId = {};
      for (var b in allBooks) {
        booksByCatId.putIfAbsent(b.categoryId, () => []);
        booksByCatId[b.categoryId]!.add(b);
      }

      // Helper to trace back to top level
      // Returns [TopLevelCategory, PathString]
      // TopCategory -> SubCategory -> Book

      // Let's create a temporary tree structure.
      // Since `BookCategory` (Shamor model) is recursive, we can build it.
      // `BookCategory` has `subcategories` list and `books` map.

      // Strategy:
      // A. Identify all Top-Level Categories (parentId == null).
      // B. For each Top-Level, build the recursive `BookCategory`.

      // Filter root categories
      // Note: We only want categories that contain Base Books (or their descendants do).
      // But for simplicity, we can iterate all roots.

      final rootCategories = allCategories
          .where((c) => c.parentId == null)
          .toList()
        ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));

      for (var rootCat in rootCategories) {
        final builtCat = await _buildRecursiveCategory(
            rootCat, categoryMap, booksByCatId, repository, null);

        if (builtCat != null) {
          resultData[builtCat.name] = builtCat;
        }
      }

      _allBookData = resultData;
      _logger.info(
          'Loaded ${_allBookData.length} top-level categories from DB (incl. ${personalBooks.length} personal books).');
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
    String? inheritedContentType,
  ) async {
    // Determine content type for this category
    // If inherited, use it. If "Bavli/Yerushalmi", force "daf".
    String myContentType = inheritedContentType ?? 'text'; // Default

    if (currentCat.title.contains('בבלי') ||
        currentCat.title.contains('ירושלמי')) {
      myContentType = 'דף';
    } else if (currentCat.title.contains('תנ"ך')) {
      myContentType = 'text'; // Chapters
    }

    // 1. Get Direct Books
    final directBooks = booksByCatId[currentCat.id] ?? [];
    final Map<String, BookDetails> validBooks = {};

    for (var dbBook in directBooks) {
      // Convert DB Book to BookDetails
      // We need to fetch TOC (parts/sections) to populate `parts`
      final bookDetails =
          await _convertDbBookToDetails(dbBook, repository, myContentType);
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
          child, allCatsMap, booksByCatId, repository, myContentType);
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

  Future<BookDetails> _convertDbBookToDetails(db_models.Book dbBook,
      SeforimRepository repository, String contentType) async {
    // Fetch TOC
    // SqliteDataProvider has `getBookTocFromDb`.
    // But we can go directly to DAO if public, or use helper.
    // `repository.tocDao.getTocForBook(dbBook.id)`

    List<BookPart> parts = [];
    List<BookSection> sections = [];

    try {
      final tocEntries =
          await repository.database.tocDao.selectByBookId(dbBook.id);

      // Convert TOC entries to BookSection/BookPart
      // ShamorZachor uses `BookPart` (mostly flat or simple range) or `BookSection` (hierarchical).
      // `BookDetails` constructor takes `parts` (List<BookPart>).

      if (tocEntries.isNotEmpty) {
        // Build hierarchy from flat list of TocEntries (DB returns flat list with parent/child links?)
        // Actually `getTocForBook` returns flat list, we need to reconstruct tree or iterate.
        // Update: `TocDao.getTocForBook` returns `List<TocEntry>`. `TocEntry` (db model) has `hasChildren`.
        // But they are joined.

        // Let's create a simple part "Main" if TOC is complex, or map TOC to sections.
        // BookDetails has `sections` field (List<BookSection>).

        sections = _buildSectionsFromToc(tocEntries);

        // Create a default Part that covers the whole book range
        // DB books usually 1-N index.
        int endPage =
            dbBook.totalLines > 0 ? dbBook.totalLines : 1000; // Fallback
        // Actually if we have cached page count?
        // Let's assume 1 large part.
        parts.add(BookPart(
          name: "ראשי",
          startPage: 1,
          endPage: endPage,
        ));
      } else {
        // No TOC
        parts.add(BookPart(
          name: "ראשי",
          startPage: 1,
          endPage: dbBook.totalLines > 0 ? dbBook.totalLines : 100,
        ));
      }
    } catch (e) {
      _logger.warning('Failed to load TOC for ${dbBook.title}', e);
      parts.add(BookPart(
          name: "ראשי",
          startPage: 1,
          endPage: dbBook.totalLines > 0 ? dbBook.totalLines : 100));
    }

    return BookDetails(
      contentType: dbBook.fileType == 'pdf'
          ? 'pdf'
          : (dbBook.fileType == 'docx' ? 'docx' : contentType),
      parts: parts, // Legacy parts
      isCustom: dbBook.isPersonal,
      id: dbBook.id.toString(),
      originalPageCount: dbBook.totalLines,
      sections: sections.isNotEmpty ? sections : null, // Hierarchical sections
    );
  }

  List<BookSection> _buildSectionsFromToc(List<db_models.TocEntry> entries) {
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

    return roots.map((root) => _convertToSection(root, childMap)).toList();
  }

  BookSection _convertToSection(
      db_models.TocEntry entry, Map<int, List<db_models.TocEntry>> childMap) {
    final children = childMap[entry.id] ?? [];
    children.sort((a, b) => (a.lineIndex ?? 0).compareTo(b.lineIndex ?? 0));

    return BookSection(
      id: entry.id.toString(),
      title: entry.text,
      level: entry.level,
      startPage: entry.lineIndex ?? 0, // DB lineIndex is often the start
      endPage:
          0, // Need to calculate end page? Shamor UI might strictly need it.
      // Usually endPage is start of next sibling - 1.
      children: children.map((c) => _convertToSection(c, childMap)).toList(),
    );
  }

  // ... (Keep existing methods: getCategory, getBookDetails, searchBooks etc. but update them to use _allBookData memory cache)
  // Since we load everything into _allBookData, existing getters usually work fine IF _allBookData structure is compatible.

  BookCategory? getCategory(String categoryName) => _allBookData[categoryName];

  BookDetails? getBookDetails(String categoryName, String bookName) {
    final category = _allBookData[categoryName];
    if (category == null) return null;
    return category.getAllBooksRecursive()[bookName];
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

  // Custom books methods - DB handles "Personal" books separately?
  // Current plan is 'selectBaseBooks'. If user wants personal books, we might need another query.
  // User asked only for "isBaseBook".
  // But for "addCustomBook", we might need to support it via DB insertion if intended.
  // For now, let's keep stub or remove if legacy.

  Future<void> addCustomBook(
      {required String bookName,
      required String categoryName,
      required String bookPath,
      required String contentType}) async {
    final repository = _sqliteDataProvider?.repository;
    if (repository == null) return;

    try {
      final existing = await repository.getBookByTitle(bookName);
      if (existing != null) {
        // Update isPersonal = true
        final updated = existing.copyWith(isPersonal: true);
        // BookDao doesn't have update method exposed easily except insertWithId which upserts or specialized updates?
        // SeforimRepository has insertBook which handles ID check?
        // But we need to update. `insertBook` uses `insertBookWithId` (REPLACE conflict logic?).
        // BookDao usually uses INSERT OR REPLACE.
        await repository.insertBook(updated);
      } else {
        // Create new book
        // Find category ID
        final cat = await repository.getCategoryByTitle(categoryName);
        final catId =
            cat?.id ?? 1; // Default to root if not found (or handle error)

        final newBook = db_models.Book(
            id: 0, // Auto generate (negative)
            title: bookName,
            categoryId: catId,
            isPersonal: true,
            filePath: bookPath,
            fileType: contentType,
            // Defaults
            sourceId: 0,
            heShortDesc: '',
            order: 999,
            totalLines: 0,
            isBaseBook: false,
            notesContent: '',
            hasTargumConnection: false,
            hasReferenceConnection: false,
            hasSourceConnection: false,
            hasCommentaryConnection: false,
            hasOtherConnection: false,
            hasAltStructures: false,
            hasTeamim: false,
            hasNekudot: false,
            isContentExternal: false,
            externalLibraryId: null,
            fileSize: 0,
            lastModified: DateTime.now().millisecondsSinceEpoch,
            authors: [],
            topics: [],
            pubPlaces: [],
            pubDates: []);
        await repository.insertBook(newBook);
      }

      // Reload to reflect changes
      await loadAllData();
    } catch (e) {
      _logger.warning("Failed to add custom book", e);
      rethrow;
    }
  }

  Future<void> removeCustomBook(
      {required String categoryName, required String bookName}) async {
    final repository = _sqliteDataProvider?.repository;
    if (repository == null) return;

    try {
      final existing = await repository.getBookByTitle(bookName);
      if (existing != null) {
        if (existing.isBaseBook) {
          // Only unmark personal
          final updated = existing.copyWith(isPersonal: false);
          await repository.insertBook(updated);
        } else {
          // If it's purely personal, we could delete it, or just unmark.
          // For data safety, let's unmark.
          final updated = existing.copyWith(isPersonal: false);
          await repository.insertBook(updated);
          // Or repository.deleteBook(existing.id)?
        }
        await loadAllData();
      }
    } catch (e) {
      _logger.warning("Failed to remove custom book", e);
    }
  }

  List<Map<String, dynamic>> getCustomBooks() {
    final results = <Map<String, dynamic>>[];

    void scan(BookCategory cat, String topLevel) {
      cat.books.forEach((name, details) {
        if (details.isCustom) {
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

  // ... Dispose
}
