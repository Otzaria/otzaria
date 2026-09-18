import 'package:flutter/foundation.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:otzaria/data/data_providers/user_books_database_holder.dart';
import 'package:otzaria/services/commentary_service.dart';

/// מטמון בזיכרון של דור הספר לכל ספר (bookId), מתוך טבלת book_generation →
/// generation. משמש לשובר-שוויון לפי סדר הדורות בחיפוש הספרייה.
///
/// הדור נלקח מהנתון המוסמך ב-DB (לא היוריסטי לפי נתיב); ספר בלי דור משויך
/// לסוף ([CommentaryEra.other]).
class GenerationCache {
  GenerationCache._();

  static final GenerationCache instance = GenerationCache._();

  bool _isLoaded = false;
  Future<void>? _loadingFuture;
  int _generation = 0;

  /// דור לפי id ב-seforim.db.
  final Map<int, int> _orderByBookId = <int, int>{};

  /// דור לפי id ב-user_books.db — מרחב id נפרד, לכן מפה נפרדת.
  final Map<int, int> _orderByUserBookId = <int, int>{};

  bool get isLoaded => _isLoaded;

  static const String _selectSql = '''
        SELECT b.id AS bookId, g.name AS generationName
        FROM book b
        JOIN book_generation bg ON bg.bookId = b.id
        JOIN generation g ON g.id = bg.generationId
      ''';

  /// מחזיר את סדר הדור של הספר (נמוך = מוקדם). ספר לא ידוע → סוף הרשימה.
  /// [isUserBook] מנתב למפת ה-id של user_books.db (מרחב id נפרד).
  int getOrderForBook(int? bookId, bool isUserBook) {
    if (bookId == null) return CommentaryEra.other.order;
    final map = isUserBook ? _orderByUserBookId : _orderByBookId;
    return map[bookId] ?? CommentaryEra.other.order;
  }

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
      debugPrint('[GenerationCache] DB not initialized; skipping warmup');
      return;
    }

    try {
      final db = await repository.database.database;
      if (myGen != _generation) return;

      final local = <int, int>{};
      if ((await repository.database.capabilities).hasGenerations) {
        _accumulate(db.select(_selectSql), local);
      }

      // דורות של ספרים אישיים (user_books.db) — רק אם ה-DB כבר פתוח, בלי
      // לכפות יצירתו. מרחב id נפרד, לכן מפה נפרדת.
      final localUser = <int, int>{};
      final userRepo = UserBooksDatabaseHolder.instance.repositoryIfInitialized;
      if (userRepo != null) {
        try {
          final userDb = await userRepo.database.database;
          if (myGen != _generation) return;
          if ((await userRepo.database.capabilities).hasGenerations) {
            _accumulate(userDb.select(_selectSql), localUser);
          }
        } catch (e) {
          debugPrint('[GenerationCache] user_books generations skipped: $e');
        }
      }

      if (myGen != _generation) return;
      _orderByBookId
        ..clear()
        ..addAll(local);
      _orderByUserBookId
        ..clear()
        ..addAll(localUser);
      _isLoaded = true;
      debugPrint(
        '[GenerationCache] Loaded generations for ${_orderByBookId.length} '
        'books (+${_orderByUserBookId.length} user books)',
      );
    } catch (e) {
      debugPrint('[GenerationCache] Warmup failed: $e');
      // לא מסמנים loaded: כשל זמני (למשל DB locked בעלייה) יאופשר retry
      // ב-warmUp הבא לפני החיפוש, במקום להישאר עם כל הספרים כ-other לכל ה-session.
      if (myGen == _generation) {
        _orderByBookId.clear();
        _orderByUserBookId.clear();
      }
    }
  }

  /// צובר bookId→order מתוצאת [_selectSql]. ספר רב-מחברי → הדור המוקדם
  /// ביותר (order מינימלי), קומוטטיבי ולכן דטרמיניסטי בלי תלות בסדר השורות.
  static void _accumulate(Iterable rows, Map<int, int> into) {
    for (final row in rows) {
      final bookId = row['bookId'] as int?;
      final name = row['generationName'] as String?;
      if (bookId == null || name == null) continue;
      final order = _orderForGenerationName(name);
      final existing = into[bookId];
      if (existing == null || order < existing) {
        into[bookId] = order;
      }
    }
  }

  void clear() {
    _generation++;
    _orderByBookId.clear();
    _orderByUserBookId.clear();
    _isLoaded = false;
    _loadingFuture = null;
  }

  /// ממפה שם דור מה-DB לסדר ([CommentaryEra]). גרשיים מנורמלים כדי
  /// להתאים בין כתיב ה-DB ל-hebrewName של ה-enum.
  static int _orderForGenerationName(String name) {
    final normalized = _stripGershayim(name);
    for (final era in CommentaryEra.values) {
      if (_stripGershayim(era.hebrewName) == normalized) return era.order;
    }
    return CommentaryEra.other.order;
  }

  static String _stripGershayim(String s) => s
      .replaceAll('"', '')
      .replaceAll("'", '')
      .replaceAll('״', '')
      .replaceAll('׳', '')
      .trim();
}
