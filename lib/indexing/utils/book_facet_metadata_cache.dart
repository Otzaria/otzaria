import 'package:flutter/foundation.dart';
import 'package:otzaria/data/cache/generation_cache.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:otzaria/data/data_providers/user_books_database_holder.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/services/commentary_service.dart';

/// מטמון חד-פעמי לריצת אינדוקס: ממדי ה-facet הנוספים של כל ספר —
/// מחברים (`book_author`), תקופה (דרך [GenerationCache], בדליי
/// [CommentaryEra]) ודגל ספר-יסוד (`isBaseBook` ב-DB).
///
/// הממדים מוטבעים בזמן אינדוקס כערכי facet נוספים על שדה `topics` של
/// המנוע, תחת שורשים שמורים באנגלית (ראו FACET_DIMENSION_ROOTS במנוע):
/// `/author/<שם>`, `/era/<תקופה>`, `/base`. בסינון: OR בתוך ממד, AND בין
/// ממדים. ספר שאין לו נתון (מחבר/תקופה לא ידועים) פשוט לא ישא את ה-facet
/// ולא ייכלל בסינון לפי אותו ממד.
class BookFacetMetadataCache {
  BookFacetMetadataCache._();

  static final BookFacetMetadataCache instance = BookFacetMetadataCache._();

  bool _isLoaded = false;
  Future<void>? _loadingFuture;

  final Map<int, List<String>> _authorsByBookId = <int, List<String>>{};
  final Map<int, List<String>> _authorsByUserBookId = <int, List<String>>{};
  final Set<int> _baseBookIds = <int>{};
  final Set<int> _baseUserBookIds = <int>{};

  static const String _authorsSql = '''
        SELECT ba.bookId AS bookId, a.name AS name
        FROM book_author ba
        JOIN author a ON a.id = ba.authorId
      ''';

  static const String _baseBooksSql =
      'SELECT id FROM book WHERE isBaseBook = 1';

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
    // התקופה מגיעה מ-GenerationCache — מחומם יחד כדי שהאינדוקס לא ירוץ
    // לפני שהדורות נטענו (ואז כל הספרים היו נטבעים בלי /era).
    await GenerationCache.instance.warmUp();

    final repository = SqliteDataProvider.instance.repository;
    if (repository == null) {
      debugPrint('[BookFacetMetadataCache] DB not initialized; skipping');
      return;
    }
    try {
      final db = await repository.database.database;
      _accumulateAuthors(db.select(_authorsSql), _authorsByBookId);
      for (final row in db.select(_baseBooksSql)) {
        final id = row['id'] as int?;
        if (id != null) _baseBookIds.add(id);
      }

      // ספרים אישיים — רק אם ה-DB שלהם כבר פתוח, בלי לכפות יצירה.
      final userRepo = UserBooksDatabaseHolder.instance.repositoryIfInitialized;
      if (userRepo != null) {
        try {
          final userDb = await userRepo.database.database;
          _accumulateAuthors(userDb.select(_authorsSql), _authorsByUserBookId);
          for (final row in userDb.select(_baseBooksSql)) {
            final id = row['id'] as int?;
            if (id != null) _baseUserBookIds.add(id);
          }
        } catch (e) {
          debugPrint('[BookFacetMetadataCache] user_books skipped: $e');
        }
      }
      _isLoaded = true;
      debugPrint(
        '[BookFacetMetadataCache] Loaded authors for '
        '${_authorsByBookId.length} books, ${_baseBookIds.length} base books',
      );
    } catch (e) {
      debugPrint('[BookFacetMetadataCache] warmup failed: $e');
      _authorsByBookId.clear();
      _authorsByUserBookId.clear();
      _baseBookIds.clear();
      _baseUserBookIds.clear();
    }
  }

  static void _accumulateAuthors(Iterable rows, Map<int, List<String>> into) {
    for (final row in rows) {
      final bookId = row['bookId'] as int?;
      final name = row['name'] as String?;
      if (bookId == null || name == null || name.trim().isEmpty) continue;
      into.putIfAbsent(bookId, () => <String>[]).add(name.trim());
    }
  }

  void clear() {
    _isLoaded = false;
    _loadingFuture = null;
    _authorsByBookId.clear();
    _authorsByUserBookId.clear();
    _baseBookIds.clear();
    _baseUserBookIds.clear();
  }

  /// נתיבי ה-facet הממדיים של הספר, לפרמטר `extraFacets` של המנוע.
  /// [isFoundational] — סיווג ספרי-היסוד לפי נתיב הקטגוריה
  /// (FoundationalBookClassifier), שמשלים את דגל ה-DB.
  List<String> extraFacetsForBook(Book book, {required bool isFoundational}) {
    final facets = <String>[];
    final id = book.id;
    final authors = id == null
        ? null
        : _authorsFor(id, isUserBook: book.isUserBook);
    if (authors != null) {
      for (final author in authors) {
        facets.add('/author/${_sanitizeSegment(author)}');
      }
    }
    final eraName = _eraNameFor(book);
    if (eraName != null) {
      facets.add('/era/${_sanitizeSegment(eraName)}');
    }
    final isBase =
        isFoundational ||
        (id != null &&
            (book.isUserBook
                ? _baseUserBookIds.contains(id)
                : _baseBookIds.contains(id)));
    if (isBase) {
      facets.add('/base');
    }
    return facets;
  }

  List<String>? _authorsFor(int bookId, {required bool isUserBook}) =>
      isUserBook ? _authorsByUserBookId[bookId] : _authorsByBookId[bookId];

  /// שם התקופה לפי דלי [CommentaryEra] של הספר; null לדלי "שאר מפרשים"
  /// (ספר בלי דור ידוע) — עדיף שלא ישא facet מאשר שישא תקופה שגויה.
  static String? _eraNameFor(Book book) {
    final order = GenerationCache.instance.getOrderForBook(
      book.id,
      book.isUserBook,
    );
    if (order == CommentaryEra.other.order) return null;
    for (final era in CommentaryEra.values) {
      if (era.order == order) return era.hebrewName;
    }
    return null;
  }

  /// '/' הוא מפריד הרמות של facet — שם שמכיל אותו היה נקרא כהיררכיה.
  static String _sanitizeSegment(String value) =>
      value.replaceAll('/', '־').trim();
}
