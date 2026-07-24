import 'package:flutter/foundation.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';

/// Shared in-memory cache for the `book` table.
///
/// This cache is used by both:
/// - Library screen (DatabaseLibraryProvider) for displaying books
/// - FindRef feature for matching book titles
///
/// By sharing this cache, we avoid loading the same data twice into memory.
class BooksCache {
  BooksCache._();

  static final BooksCache instance = BooksCache._();

  bool _isLoaded = false;
  Future<void>? _loadingFuture;

  /// מונה דורות לזיהוי [clear] שקרה במהלך טעינה.
  /// כל [clear] מעלה את המונה; טעינה שנפתחה לפניו תפסיק לכתוב נתונים
  /// אחרי ה-yield הבא, ולא תסמן `_isLoaded = true`.
  int _generation = 0;

  final List<BookCacheEntry> _books = <BookCacheEntry>[];
  final Map<int, BookCacheEntry> _booksById = <int, BookCacheEntry>{};

  bool get isLoaded => _isLoaded;

  /// Returns all cached books
  List<BookCacheEntry> get books => List.unmodifiable(_books);

  /// Returns a book by its ID, or null if not found
  BookCacheEntry? getBookById(int id) => _booksById[id];

  Future<void> warmUp() async {
    if (_isLoaded) return;
    if (_loadingFuture != null) return _loadingFuture;

    _loadingFuture = _loadInternal();

    try {
      await _loadingFuture;
    } finally {
      _loadingFuture = null;
    }
  }

  Future<void> _loadInternal() async {
    final myGen = _generation;
    final repository = SqliteDataProvider.instance.repository;
    if (repository == null) {
      debugPrint('[BooksCache] DB not initialized; skipping warmup');
      if (myGen == _generation) {
        _books.clear();
        _booksById.clear();
        _isLoaded = false;
      }
      return;
    }

    try {
      final allBooks = await repository.database.bookDao.getAllLocalBooks();
      if (myGen != _generation) return; // הופסק על ידי clear()

      // בונים למבני ביניים מקומיים — ה-cache החי לא נוגע עד ה-swap בסוף.
      // יציאה ל-event loop כל chunk כדי לא לחסום את ה-UI thread על
      // ספריות גדולות (~50K ספרים).
      final localBooks = <BookCacheEntry>[];
      final localBooksById = <int, BookCacheEntry>{};
      const yieldBatch = 1000;
      var i = 0;
      for (final b in allBooks) {
        final entry = BookCacheEntry(
          id: b.id,
          title: b.title,
          filePath: b.filePath,
          fileType: b.fileType ?? 'txt',
          categoryId: b.categoryId,
          orderIndex: b.order,
        );
        localBooks.add(entry);
        localBooksById[b.id] = entry;
        if (++i % yieldBatch == 0) {
          await Future<void>.delayed(Duration.zero);
          if (myGen != _generation) return; // הופסק על ידי clear()
        }
      }

      // Swap אטומי (סינכרוני בדארט) — רק אם הדור עדיין שלנו.
      if (myGen != _generation) return;
      _books
        ..clear()
        ..addAll(localBooks);
      _booksById
        ..clear()
        ..addAll(localBooksById);
      _isLoaded = true;
      debugPrint(
        '[BooksCache] Loaded ${_books.length} books into shared cache',
      );
    } catch (e) {
      debugPrint('[BooksCache] Warmup failed: $e');
      // לא מסמנים loaded: כשל זמני (למשל DB locked בעלייה) יאופשר retry
      // ב-warmUp הבא, במקום ספרייה ריקה לכל ה-session.
      if (myGen == _generation) {
        _books.clear();
        _booksById.clear();
      }
    }
  }

  void clear() {
    _generation++;
    _books.clear();
    _booksById.clear();
    _isLoaded = false;
    _loadingFuture = null;
  }

  /// בדיקות בלבד — מזריק רשימת ספרים ישירות בלי לעבור דרך ה-DB.
  @visibleForTesting
  void setBooksForTesting(List<BookCacheEntry> books) {
    _books
      ..clear()
      ..addAll(books);
    _booksById
      ..clear()
      ..addEntries(books.map((b) => MapEntry(b.id, b)));
    _isLoaded = true;
  }
}

/// Represents a single book entry in the cache
class BookCacheEntry {
  final int id;
  final String title;
  final String? filePath;
  final String fileType;
  final int categoryId;
  final double orderIndex;

  const BookCacheEntry({
    required this.id,
    required this.title,
    required this.filePath,
    required this.fileType,
    required this.categoryId,
    required this.orderIndex,
  });
}
