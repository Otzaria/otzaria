import 'package:otzaria/indexing/repository/indexing_repository.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/search/book_facet.dart';

/// Helper class for facet-related operations
class FacetHelper {
  FacetHelper._();

  // --- Dimension facets (ממדי סינון) ---
  //
  // האינדקס מטביע לכל ספר, לצד נתיב הקטגוריה, ערכי facet ממדיים תחת
  // שורשים שמורים באנגלית: `/author/<שם>`, `/era/<שם תקופה>`, `/base`.
  // הם רוכבים על אותה רשימת facets שנשלחת למנוע — OR בתוך ממד, AND בין
  // ממדים ומול קבוצת הקטגוריות. לוגיקת עץ הקטגוריות באפליקציה חייבת
  // להתעלם מהם (הם אינם נתיבי קטגוריה) אך לשמר אותם בכל כתיבה של הרשימה.

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
    if (book.category?.path != null && book.category!.path.isNotEmpty) {
      return BookFacet.resolveFacetCategoryPath(
        categoryPath: book.category!.path,
      );
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

  /// Builds a book facet path from category path and book
  /// Uses catalogueOrderKey for uniqueness instead of title
  static String buildBookFacet(String? categoryPath, Book book) {
    final bookKey = _buildBookKey(book);
    if (categoryPath == null || categoryPath.isEmpty || categoryPath == '/') {
      return '/$bookKey';
    }
    return '$categoryPath/$bookKey';
  }

  /// Builds a unique key for a book (same logic as IndexingRepository.catalogueOrderKey)
  static String _buildBookKey(Book book) {
    return IndexingRepository.catalogueOrderKey(book);
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

    for (final entry in bookCounts.entries) {
      final count = entry.value;
      if (count <= 0) continue;

      final book = bookByIndexedFilePath[entry.key];
      if (book == null) continue;

      _incrementBookAndAncestors(counts, book, delta: count);
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
