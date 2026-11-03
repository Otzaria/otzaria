import 'package:otzaria/data/book_identity.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/search/book_facet.dart';

/// Helper class for facet-related operations
class FacetHelper {
  FacetHelper._();

  // facets ממדיים חולקים רשימה עם נתיבי הקטגוריות, אך אינם חלק מהעץ.
  // שינוי הרשימה חייב לשמר אותם; המנוע מחבר OR בתוך ממד ו-AND בין ממדים.

  /// facet של "ספרי יסוד בלבד".
  static const String baseDimensionFacet = '/base';

  /// שורש ממד התקופה. הערכים: CommentaryEra.hebrewName.
  static const String eraDimensionPrefix = '/era/';

  /// שורש ממד המחבר. הערכים: author.name מ-seforim.db (אחרי סניטציה).
  static const String authorDimensionPrefix = '/author/';

  /// האם [facet] הוא facet ממדי (ולא נתיב קטגוריה/ספר).
  static bool isDimensionFacet(String facet) =>
      facet == baseDimensionFacet ||
      facet.startsWith(eraDimensionPrefix) ||
      facet.startsWith(authorDimensionPrefix);

  /// רק נתיבי הקטגוריות/ספרים מתוך [facets] — הקלט ללוגיקת עץ הקטגוריות.
  static List<String> categoryFacetsOf(Iterable<String> facets) =>
      facets.where((facet) => !isDimensionFacet(facet)).toList();

  /// רק ה-facets הממדיים מתוך [facets] — לשימור בכל כתיבה מחדש של הרשימה.
  static List<String> dimensionFacetsOf(Iterable<String> facets) =>
      facets.where(isDimensionFacet).toList();

  /// '/' הוא מפריד הרמות של facet — שם שמכיל אותו היה נקרא כהיררכיה.
  /// אותה סניטציה שמבוצעת בזמן האינדוקס (BookFacetMetadataCache).
  static String sanitizeDimensionSegment(String value) =>
      value.replaceAll('/', '־').trim();

  /// בונה facet של מחבר: `/author/<שם מסונטז>`.
  static String buildAuthorFacet(String authorName) =>
      '$authorDimensionPrefix${sanitizeDimensionSegment(authorName)}';

  /// בונה facet של תקופה: `/era/<שם מסונטז>`.
  static String buildEraFacet(String eraName) =>
      '$eraDimensionPrefix${sanitizeDimensionSegment(eraName)}';

  /// Resolves the category path for a book
  static String? resolveCategoryPath(Book book) {
    // path נבנה בהליכה עד השורש — פעם אחת ולא לכל בדיקה.
    final categoryPath = book.category?.path;
    if (categoryPath != null && categoryPath.isNotEmpty) {
      return BookFacet.resolveFacetCategoryPath(categoryPath: categoryPath);
    }
    if (book.categoryPath != null && book.categoryPath!.isNotEmpty) {
      return BookFacet.resolveFacetCategoryPath(
        categoryPath: book.categoryPath,
      );
    }
    if (book.topics.isNotEmpty) {
      final topicsPath = BookFacet.resolveFacetCategoryPath(
        topics: book.topics,
      );
      return topicsPath.isEmpty ? null : topicsPath;
    }
    return null;
  }

  /// נתיב facet לספר, לפי מפתח זהות ולא לפי הכותרת לבדה.
  static String buildBookFacet(String? categoryPath, Book book) {
    final bookKey = BookIdentity.keyOf(book);
    if (categoryPath == null || categoryPath.isEmpty || categoryPath == '/') {
      return '/$bookKey';
    }
    return '$categoryPath/$bookKey';
  }

  /// ה-facet של [category]: כמו באינדקס ובספירות, פסיק בשם תיקייה הוא מפריד.
  static String categoryFacet(Category category) {
    final facet = BookFacet.resolveFacetCategoryPath(
      categoryPath: category.path,
    );
    return facet.isEmpty ? '/' : facet;
  }

  /// Increments a facet count in the given map
  static void incrementFacet(
    Map<String, int> counts,
    String facet, [
    int delta = 1,
  ]) {
    counts[facet] = (counts[facet] ?? 0) + delta;
  }

  /// Increments facet counts for all ancestors in the category path
  static void incrementFacetWithAncestors(
    Map<String, int> counts,
    String categoryPath, [
    int delta = 1,
  ]) {
    if (categoryPath.isEmpty) return;

    final normalized = categoryPath.startsWith('/')
        ? categoryPath
        : '/$categoryPath';

    incrementFacet(counts, '/', delta);
    final parts = normalized.split('/').where((p) => p.isNotEmpty).toList();
    var current = '';
    for (final part in parts) {
      current = '$current/$part';
      incrementFacet(counts, current, delta);
    }
  }

  /// Builds facet counts from search results and library books.
  ///
  /// כל תוצאה מפוענחת לספר דרך שדה ה-`filePath` שנכתב על מסמכיה באינדוקס
  /// (המפתח היציב של הספר) — ולא דרך הסדר הקטלוגי המוטמע במזהה המסמך,
  /// שמשתנה כשספרים נוספים/נמחקים מהספרייה אחרי האינדוקס.
  static Map<String, int> buildFacetCountsFromResults(
    List<dynamic> results,
    Map<String, Book> bookByIndexedFilePath,
  ) {
    final counts = <String, int>{};
    if (results.isEmpty) {
      return counts;
    }

    for (final result in results) {
      final book = bookByIndexedFilePath[result.filePath as String];
      if (book == null) continue;

      _incrementBookAndAncestors(counts, book);
    }

    return counts;
  }

  /// Builds facet counts from a per-book count map returned by the search engine.
  static Map<String, int> buildFacetCountsFromBookCounts(
    Map<String, int> bookCounts,
    Map<String, Book> bookByIndexedFilePath,
  ) {
    final counts = <String, int>{};
    // בחיפוש רחב זה כל הספרייה: הנתיב נפתר פעם אחת לקטגוריה, והאבות
    // מקבלים את סכום הנתיב במקום תוספת לכל ספר.
    final pathByCategory = Map<Category, String?>.identity();
    var countByCategoryPath = <String, int>{};

    for (final entry in bookCounts.entries) {
      final count = entry.value;
      if (count <= 0) continue;

      final book = bookByIndexedFilePath[entry.key];
      if (book == null) continue;

      final category = book.category;
      final categoryPath = category == null
          ? resolveCategoryPath(book)
          : pathByCategory.putIfAbsent(
              category,
              () => resolveCategoryPath(book),
            );
      incrementFacet(counts, buildBookFacet(categoryPath, book), count);
      incrementFacet(countByCategoryPath, categoryPath ?? '', count);
    }

    // כל נתיב מעביר את סכומו לאביו ('' הוא השורש), כך שנתיב של אב נבנה
    // ונספר פעם אחת בכל רמה ולא שוב לכל קטגוריה שתחתיו.
    while (countByCategoryPath.isNotEmpty) {
      final parentCounts = <String, int>{};
      for (final MapEntry(key: categoryPath, value: count)
          in countByCategoryPath.entries) {
        if (categoryPath.isEmpty) {
          incrementFacet(counts, '/', count);
          continue;
        }
        incrementFacet(counts, categoryPath, count);
        final cut = categoryPath.lastIndexOf('/');
        final parent = cut > 0 ? categoryPath.substring(0, cut) : '';
        incrementFacet(parentCounts, parent, count);
      }
      countByCategoryPath = parentCounts;
    }

    return counts;
  }

  static void _incrementBookAndAncestors(
    Map<String, int> counts,
    Book book, {
    int delta = 1,
  }) {
    final categoryPath = resolveCategoryPath(book);
    final bookFacet = buildBookFacet(categoryPath, book);

    incrementFacet(counts, bookFacet, delta);

    if (categoryPath != null && categoryPath.isNotEmpty) {
      incrementFacetWithAncestors(counts, categoryPath, delta);
    } else {
      incrementFacet(counts, '/', delta);
    }
  }
}
