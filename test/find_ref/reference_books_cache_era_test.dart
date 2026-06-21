import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/cache/books_cache.dart';
import 'package:otzaria/find_ref/repository/reference_books_cache.dart';
import 'package:otzaria/services/commentary_service.dart';

/// בדיקות למימוש האמיתי של [ReferenceBooksCache.searchByEraAndTopic] —
/// סיווג דור מנתיב הקטגוריה, התאמת תחיליות בכותרת, ומגבלת התוצאות.
void main() {
  final cache = ReferenceBooksCache.instance;

  /// מזין ספר לשני הקאשים בעקביות (BooksCache + הקאשים של ReferenceBooksCache).
  void seedBooks(
    List<({int id, String normalizedTitle, String categoryPath})> books, {
    String fileType = 'txt',
  }) {
    BooksCache.instance.setBooksForTesting([
      for (final b in books)
        BookCacheEntry(
          id: b.id,
          title: b.normalizedTitle,
          filePath: null,
          fileType: fileType,
          categoryId: b.id,
          orderIndex: 999.0,
        ),
    ]);
    cache.seedForTesting(
      normalizedTitles: {for (final b in books) b.id: b.normalizedTitle},
      categoryPaths: {for (final b in books) b.id: b.categoryPath},
    );
  }

  tearDown(() {
    cache.clear();
    BooksCache.instance.clear();
  });

  test('מסווג דור לפי segment בנתיב — רק ראשונים מוחזרים', () {
    seedBooks([
      (
        id: 1,
        normalizedTitle: 'רשי על סנהדרין',
        categoryPath: 'תלמוד בבלי, ראשונים, רשי, סדר נזיקין'
      ),
      (
        id: 2,
        normalizedTitle: 'יד רמה על סנהדרין',
        categoryPath: 'תלמוד בבלי, ראשונים, יד רמה, סדר נזיקין'
      ),
      (
        id: 3,
        normalizedTitle: 'יכין סנהדרין',
        categoryPath: 'משנה, אחרונים, יכין, סדר נזיקין'
      ),
      (
        id: 4,
        normalizedTitle: 'סנהדרין',
        categoryPath: 'תלמוד בבלי, סדר נזיקין'
      ),
    ]);

    final hits = cache.searchByEraAndTopic(
      CommentaryEra.rishonim,
      const ['סנהדרין'],
    );

    expect(hits.map((h) => h.bookId), unorderedEquals([1, 2]),
        reason: 'רק ספרי ראשונים על סנהדרין; אחרונים וספר-הבסיס מסוננים');
  });

  test('"אחרונים" מחזיר את ספר האחרונים בלבד', () {
    seedBooks([
      (
        id: 1,
        normalizedTitle: 'רשי על סנהדרין',
        categoryPath: 'תלמוד בבלי, ראשונים, רשי, סדר נזיקין'
      ),
      (
        id: 3,
        normalizedTitle: 'יכין סנהדרין',
        categoryPath: 'משנה, אחרונים, יכין, סדר נזיקין'
      ),
    ]);

    final hits = cache.searchByEraAndTopic(
      CommentaryEra.acharonim,
      const ['סנהדרין'],
    );
    expect(hits.map((h) => h.bookId), [3]);
  });

  test('"מחברי זמננו" מזוהה כ-segment בנתיב', () {
    seedBooks([
      (
        id: 5,
        normalizedTitle: 'רשימות שיעורים על סנהדרין',
        categoryPath: 'תלמוד בבלי, מחברי זמננו, רשימות שיעורים'
      ),
    ]);

    final hits = cache.searchByEraAndTopic(
      CommentaryEra.modern,
      const ['סנהדרין'],
    );
    expect(hits.map((h) => h.bookId), [5]);
  });

  test('התאמת תחילית בכותרת — "סנהד" תופס "סנהדרין"', () {
    seedBooks([
      (
        id: 1,
        normalizedTitle: 'רשי על סנהדרין',
        categoryPath: 'תלמוד בבלי, ראשונים, רשי, סדר נזיקין'
      ),
      (
        id: 2,
        normalizedTitle: 'רשי על ברכות',
        categoryPath: 'תלמוד בבלי, ראשונים, רשי, סדר זרעים'
      ),
    ]);

    final hits = cache.searchByEraAndTopic(
      CommentaryEra.rishonim,
      const ['סנהד'],
    );
    expect(hits.map((h) => h.bookId), [1],
        reason: 'תחילית תופסת את סנהדרין אך לא את ברכות');
  });

  test('כל טוקני-הנושא חייבים להופיע בכותרת', () {
    seedBooks([
      (
        id: 1,
        normalizedTitle: 'חידושי הריטבא על סנהדרין',
        categoryPath: 'תלמוד בבלי, ראשונים, ריטבא, סדר נזיקין'
      ),
      (
        id: 2,
        normalizedTitle: 'רשי על סנהדרין',
        categoryPath: 'תלמוד בבלי, ראשונים, רשי, סדר נזיקין'
      ),
    ]);

    final hits = cache.searchByEraAndTopic(
      CommentaryEra.rishonim,
      const ['חידושי', 'סנהדרין'],
    );
    expect(hits.map((h) => h.bookId), [1],
        reason: 'רק כותרת שמכילה גם "חידושי" וגם "סנהדרין"');
  });

  test('נתיב ריק / בלי segment דור → לא מוחזר', () {
    seedBooks([
      (id: 1, normalizedTitle: 'סנהדרין', categoryPath: ''),
      (
        id: 2,
        normalizedTitle: 'משנה תורה הלכות סנהדרין',
        categoryPath: 'הלכה, משנה תורה, ספר שופטים'
      ),
    ]);

    final hits = cache.searchByEraAndTopic(
      CommentaryEra.rishonim,
      const ['סנהדרין'],
    );
    expect(hits, isEmpty);
  });

  test('limit חוסם את מספר התוצאות', () {
    seedBooks([
      for (var i = 0; i < 10; i++)
        (
          id: i,
          normalizedTitle: 'רשי על סנהדרין $i',
          categoryPath: 'תלמוד בבלי, ראשונים, רשי, סדר נזיקין'
        ),
    ]);

    final hits = cache.searchByEraAndTopic(
      CommentaryEra.rishonim,
      const ['סנהדרין'],
      limit: 4,
    );
    expect(hits, hasLength(4));
  });
}
