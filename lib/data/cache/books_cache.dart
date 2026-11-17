import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:otzaria/data/data_providers/db_read_worker.dart';
import 'package:otzaria/data/data_providers/official_catalog_rows.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:otzaria/find_ref/repository/find_ref_db_isolate.dart';
import 'package:otzaria/migration/database/daos/book_dao.dart';

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

  /// הדור הנוכחי, לצילום *לפני* קריאת נתונים שתיזרע ל-[seedFromRows].
  int get generation => _generation;

  /// כל הספרים — תצוגה חיה ולא עותק (נקראת בכל הקלדה); מי שממתין באמצע
  /// מעבר עליה חייב להעתיק.
  List<BookCacheEntry> get books => _booksView;
  late final List<BookCacheEntry> _booksView = UnmodifiableListView(_books);

  /// Returns a book by its ID, or null if not found
  BookCacheEntry? getBookById(int id) => _booksById[id];

  Future<void> warmUp() async {
    if (_isLoaded) return;
    if (_loadingFuture != null) return _loadingFuture;

    final loading = _loadInternal();
    _loadingFuture = loading;
    try {
      await loading;
    } finally {
      // clear() may have started a newer generation while this one awaited.
      // Never detach that newer in-flight load.
      if (identical(_loadingFuture, loading)) _loadingFuture = null;
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
      final rows = await _readRows();
      if (myGen != _generation) return; // הופסק על ידי clear()

      // בונים למבני ביניים מקומיים — ה-cache החי לא נוגע עד ה-swap בסוף.
      // יציאה ל-event loop כל chunk כדי לא לחסום את ה-UI thread על
      // ספריות גדולות (~50K ספרים).
      final localBooks = <BookCacheEntry>[];
      final localBooksById = <int, BookCacheEntry>{};
      const yieldBatch = 1000;
      var i = 0;
      for (final row in rows) {
        final entry = _entryFromRow(row);
        localBooks.add(entry);
        localBooksById[entry.id] = entry;
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

  /// זורע משורות הקטלוג כדי שטבלת `book` לא תיקרא שוב; no-op כשהקאש טעון או בטעינה.
  /// [generation] נצפה לפני שליפת [rows]: [clear] מאז פוסל את הזריעה.
  void seedFromRows(
    Iterable<Map<String, dynamic>> rows, {
    required int generation,
  }) {
    if (generation != _generation) return;
    if (_isLoaded || _loadingFuture != null) return;
    // Convert the entire catalogue before touching the live cache. If a
    // malformed row throws, readers must never observe a partially seeded list.
    final localBooks = <BookCacheEntry>[];
    final localBooksById = <int, BookCacheEntry>{};
    for (final row in rows) {
      final entry = _entryFromRow(row);
      localBooks.add(entry);
      localBooksById[entry.id] = entry;
    }
    _books
      ..clear()
      ..addAll(localBooks);
    _booksById
      ..clear()
      ..addAll(localBooksById);
    _isLoaded = true;
    debugPrint('[BooksCache] Seeded ${_books.length} books from catalog');
  }

  /// שורות הקטלוג נושאות את עמודות הקובץ בשמות נפרדים (ר' [BookDao]).
  static BookCacheEntry _entryFromRow(
    Map<String, dynamic> row,
  ) => BookCacheEntry(
    id: row['id'] as int,
    title: row['title'] as String,
    filePath: (row[BookDao.storedFilePathKey] ?? row['filePath']) as String?,
    fileType:
        (row[BookDao.storedFileTypeKey] ?? row['fileType']) as String? ?? 'txt',
    // הקטלוג מדלג על categoryId חסר; זריקה כאן תפיל את טעינת הספרייה כולה.
    categoryId: row['categoryId'] as int? ?? 0,
    orderIndex: (row['orderIndex'] as num?)?.toDouble() ?? 999.0,
  );

  static Future<List<Map<String, dynamic>>> _readRows() async {
    try {
      final catalog = await sharedOfficialCatalogRows(
        SqliteDataProvider.instance.dbPath,
      );
      if (catalog != null) return catalog.books;
    } on DbReadWorkerBusy {
      // ל-FindRef חיבור קבוע משלו, מחוץ לתור החיבורים הזמניים שהתמלא.
    }
    return fallbackRowsReader();
  }

  /// קורא השורות כשאין נתיב ל-seforim.db (המסד נפתח בלעדיו) או שתור
  /// הקריאות הזמניות מלא.
  @visibleForTesting
  static Future<List<Map<String, dynamic>>> Function() fallbackRowsReader =
      () async => (await FindRefDbIsolate.instance()).getAllLocalBooksSlim();

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
