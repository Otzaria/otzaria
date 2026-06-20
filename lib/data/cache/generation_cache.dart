import 'package:flutter/foundation.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:otzaria/services/commentary_service.dart';

/// מטמון בזיכרון של דור המחבר לכל ספר (bookId), מתוך טבלאות book_author →
/// author → generation. משמש לשובר-שוויון לפי סדר הדורות בחיפוש הספרייה.
///
/// בניגוד ל-heuristic לפי נתיב (שמסווג שגוי ספרי "משנה תורה" כחז"ל), כאן הדור
/// נלקח מהנתון המוסמך ב-DB; ספר בלי דור משויך לסוף ([CommentaryEra.other]).
class GenerationCache {
  GenerationCache._();

  static final GenerationCache instance = GenerationCache._();

  bool _isLoaded = false;
  Future<void>? _loadingFuture;
  int _generation = 0;

  final Map<int, int> _orderByBookId = <int, int>{};

  bool get isLoaded => _isLoaded;

  /// מחזיר את סדר הדור של הספר (נמוך = מוקדם). ספר לא ידוע → סוף הרשימה.
  int getOrderForBook(int? bookId) => bookId == null
      ? CommentaryEra.other.order
      : (_orderByBookId[bookId] ?? CommentaryEra.other.order);

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

      final rows = db.select('''
        SELECT b.id AS bookId, g.name AS generationName
        FROM book b
        JOIN book_author ba ON b.id = ba.bookId
        JOIN author a ON ba.authorId = a.id
        JOIN generation g ON a.generationId = g.id
      ''');

      final local = <int, int>{};
      for (final row in rows) {
        final bookId = row['bookId'] as int?;
        final name = row['generationName'] as String?;
        if (bookId == null || name == null) continue;
        final order = _orderForGenerationName(name);
        // ספר עם כמה מחברים — בוחרים את הדור המוקדם ביותר (order מינימלי),
        // קומוטטיבי ולכן דטרמיניסטי בלי תלות בסדר השורות.
        final existing = local[bookId];
        if (existing == null || order < existing) {
          local[bookId] = order;
        }
      }

      if (myGen != _generation) return;
      _orderByBookId
        ..clear()
        ..addAll(local);
      _isLoaded = true;
      debugPrint(
        '[GenerationCache] Loaded generations for ${_orderByBookId.length} books',
      );
    } catch (e) {
      debugPrint('[GenerationCache] Warmup failed: $e');
      if (myGen == _generation) {
        _orderByBookId.clear();
        _isLoaded = true; // למנוע ניסיונות חוזרים
      }
    }
  }

  void clear() {
    _generation++;
    _orderByBookId.clear();
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
