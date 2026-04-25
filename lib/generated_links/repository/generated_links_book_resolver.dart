import 'package:flutter/foundation.dart' show debugPrint;
import 'package:otzaria/data/cache/books_cache.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:otzaria/find_ref/repository/reference_books_cache.dart';
import 'package:otzaria/generated_links/models/generated_link_target.dart';
import 'package:otzaria/migration/database/repository/seforim_repository.dart';

/// פותר יעדי קישורים שנוצרו.
///
/// קולט [bookTitle] ו-[refText], מאתר את הספר בספרייה ומוצא את שורת
/// היעד ([targetIndex]) דרך תוכן עניינים ב-DB.
///
/// שומר cache בזיכרון לפי `bookTitle|refText` כדי לא לחזור על בקשות DB.
/// אחרי [_maxFailedAttempts] כשלים למפתח נתון, מפסיק לנסות.
class GeneratedLinksBookResolver {
  static const int _maxFailedAttempts = 3;

  final Map<String, GeneratedLinkTarget?> _resolvedCache = {};
  final Map<String, int> _failedAttempts = {};

  // ניתן להזרקה לצורך בדיקות
  final Future<void> Function()? warmUpReferenceBooks;
  final bool Function()? isReferenceBooksLoaded;
  final List<ReferenceBookHit> Function(String query, {int limit})? searchBooks;
  final Future<List<Map<String, dynamic>>> Function(
    int bookId,
    String bookTitle, {
    List<String>? queryTokens,
  })? getTocEntries;

  GeneratedLinksBookResolver({
    this.warmUpReferenceBooks,
    this.isReferenceBooksLoaded,
    this.searchBooks,
    this.getTocEntries,
  });

  /// מנסה לפתור [bookTitle] + [refText] לאובייקט [GeneratedLinkTarget] מלא.
  ///
  /// מחזיר null אם לא נמצא ספר, אם ה-ref לא קיים ב-TOC, או אם כלו ניסיונות.
  Future<GeneratedLinkTarget?> resolve({
    required String bookTitle,
    required String refText,
  }) async {
    final cacheKey = '$bookTitle|$refText';

    if (_resolvedCache.containsKey(cacheKey)) {
      return _resolvedCache[cacheKey];
    }

    // רק הצלחות נשמרות ב-_resolvedCache; _failedAttempts שולט בכשלונות.
    if ((_failedAttempts[cacheKey] ?? 0) >= _maxFailedAttempts) {
      return null;
    }

    final isLoaded =
        isReferenceBooksLoaded ?? () => ReferenceBooksCache.instance.isLoaded;
    if (!isLoaded()) {
      final warmUp =
          warmUpReferenceBooks ?? ReferenceBooksCache.instance.warmUp;
      await warmUp();
    }

    final search =
        searchBooks ?? (q, {int limit = 50}) =>
            ReferenceBooksCache.instance.search(q, limit: limit);

    final hits = search(bookTitle, limit: 5);

    // רק התאמה מדויקת (matchRank == 0) מתקבלת; כפילות → null כדי לא לקבע
    // ב-cache קישור שגוי לשם ספר שמשותף לכמה ספרים בקטגוריות שונות.
    final exactHits = hits.where((h) => h.matchRank == 0).toList();
    if (exactHits.length != 1) {
      return _recordFailure(
          cacheKey,
          '[GeneratedLinksBookResolver] '
          '${exactHits.isEmpty ? "no exact match" : "ambiguous (${exactHits.length} matches)"} '
          'for: $bookTitle');
    }
    final hit = exactHits.first;

    final toc = getTocEntries ??
        (int bookId, String title, {List<String>? queryTokens}) async {
          final SeforimRepository? repository =
              SqliteDataProvider.instance.repository;
          if (repository == null) return const <Map<String, dynamic>>[];
          return repository.getTocEntriesForReference(bookId, title,
              queryTokens: queryTokens);
        };

    final queryTokens = refText.split(' ').where((t) => t.isNotEmpty).toList();
    final tocEntries =
        await toc(hit.bookId, hit.title, queryTokens: queryTokens);

    if (tocEntries.isEmpty) {
      return _recordFailure(cacheKey,
          '[GeneratedLinksBookResolver] ref not found in TOC: $bookTitle $refText');
    }

    final targetIndex = tocEntries.first['segment'] as int;

    // חיפוש categoryId מ-BooksCache
    final hitBookId = hit.bookId; // local copy for closure type promotion
    int? categoryId;
    try {
      final entry =
          BooksCache.instance.books.firstWhere((b) => b.id == hitBookId);
      categoryId = entry.categoryId;
    } catch (_) {
      // BooksCache לא טעון או הספר לא נמצא — ממשיך ללא categoryId
    }

    final target = GeneratedLinkTarget(
      targetBookId: hit.bookId,
      bookTitle: hit.title,
      categoryId: categoryId,
      fileType: hit.fileType,
      targetIndex: targetIndex,
      displayRef: refText,
    );

    _resolvedCache[cacheKey] = target;
    return target;
  }

  GeneratedLinkTarget? _recordFailure(String cacheKey, String message) {
    _failedAttempts[cacheKey] = (_failedAttempts[cacheKey] ?? 0) + 1;
    debugPrint(message);
    return null; // אין שמירה ב-_resolvedCache — תאפשר ניסיון נוסף בעתיד
  }
}
