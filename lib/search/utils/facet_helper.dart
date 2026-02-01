import 'package:otzaria/models/books.dart';
import 'package:otzaria/search/book_facet.dart';

/// Helper class for facet-related operations
class FacetHelper {
  FacetHelper._();

  /// Resolves the category path for a book
  static String? resolveCategoryPath(Book book) {
    if (book.category?.path != null && book.category!.path.isNotEmpty) {
      return book.category!.path;
    }
    if (book.categoryPath != null && book.categoryPath!.isNotEmpty) {
      return book.categoryPath;
    }
    if (book.topics.isNotEmpty) {
      final topicsPath = BookFacet.topicsToPath(book.topics);
      return topicsPath.isEmpty ? null : topicsPath;
    }
    return null;
  }

  /// Builds a book facet path from category path and title
  static String buildBookFacet(String? categoryPath, String title) {
    if (categoryPath == null || categoryPath.isEmpty || categoryPath == '/') {
      return '/$title';
    }
    return '$categoryPath/$title';
  }

  /// Increments a facet count in the given map
  static void incrementFacet(Map<String, int> counts, String facet,
      [int delta = 1]) {
    counts[facet] = (counts[facet] ?? 0) + delta;
  }

  /// Increments facet counts for all ancestors in the category path
  static void incrementFacetWithAncestors(
      Map<String, int> counts, String categoryPath,
      [int delta = 1]) {
    if (categoryPath.isEmpty) return;

    final normalized =
        categoryPath.startsWith('/') ? categoryPath : '/$categoryPath';

    incrementFacet(counts, '/', delta);
    final parts = normalized.split('/').where((p) => p.isNotEmpty).toList();
    var current = '';
    for (final part in parts) {
      current = '$current/$part';
      incrementFacet(counts, current, delta);
    }
  }

  /// Builds facet counts from search results and library books
  static Map<String, int> buildFacetCountsFromResults(
    List<dynamic> results,
    Map<String, Book> bookByTitle,
  ) {
    final counts = <String, int>{};
    if (results.isEmpty) {
      return counts;
    }

    for (final result in results) {
      final title = result.title;
      final book = bookByTitle[title];
      final categoryPath = book != null ? resolveCategoryPath(book) : null;
      final bookFacet = buildBookFacet(categoryPath, title);

      incrementFacet(counts, bookFacet);
      incrementFacet(counts, '/$title');

      if (categoryPath != null && categoryPath.isNotEmpty) {
        incrementFacetWithAncestors(counts, categoryPath);
      } else {
        incrementFacet(counts, '/');
      }
    }

    return counts;
  }
}
