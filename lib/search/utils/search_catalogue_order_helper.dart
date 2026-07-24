import 'package:otzaria/library/models/library.dart';

/// Utilities for reproducing the same catalogue order used by the search tree.
class SearchCatalogueOrderHelper {
  SearchCatalogueOrderHelper._();

  static const List<String> _orderedTopCategories = [
    'תנ"ך',
    'מדרש',
    'משנה',
    'תלמוד בבלי',
    'תלמוד ירושלמי',
    'תוספתא',
    'הלכה',
    'שו"ת',
    'קבלה',
    'סדר התפילה',
    'מחשבת ישראל',
    'חסידות',
    'ספרי מוסר',
    'מילונים וספרי יעץ',
    'לימוד יומי',
    'ספרות עזר',
    'בית שני',
  ];

  static List<T> sortByLibraryOrder<T>(
    List<T> results,
    Library library, {
    required String Function(T result) titleOf,
  }) {
    if (results.length < 2) {
      return results;
    }

    final titleOrder = buildTitleOrderMap(library);
    final indexedResults = results.asMap().entries.toList();

    indexedResults.sort((a, b) {
      final orderA = titleOrder[titleOf(a.value)] ?? 1 << 30;
      final orderB = titleOrder[titleOf(b.value)] ?? 1 << 30;

      if (orderA != orderB) {
        return orderA.compareTo(orderB);
      }

      return a.key.compareTo(b.key);
    });

    return indexedResults.map((entry) => entry.value).toList(growable: false);
  }

  static List<T> buildOrderedKeys<T>(
    Library library, {
    required T Function(dynamic book) keyOf,
  }) {
    final orderedKeys = <T>[];

    void collectBooks(Category category) {
      final sortedSubCategories = category.subCategories.toList();
      if (category is Library) {
        sortedSubCategories.sort(
          (a, b) => topCategoryOrder(a).compareTo(topCategoryOrder(b)),
        );
      } else {
        sortedSubCategories.sort(
          (a, b) => normalizeOrder(a.order).compareTo(normalizeOrder(b.order)),
        );
      }

      for (final subCategory in sortedSubCategories) {
        collectBooks(subCategory);
      }

      final sortedBooks = category.books.toList()
        ..sort((a, b) => a.order.compareTo(b.order));

      for (final book in sortedBooks) {
        orderedKeys.add(keyOf(book));
      }
    }

    collectBooks(library);
    return orderedKeys;
  }

  static Map<T, int> buildKeyOrderMap<T>(
    Library library, {
    required T Function(dynamic book) keyOf,
  }) {
    final keyOrder = <T, int>{};
    final orderedKeys = buildOrderedKeys(library, keyOf: keyOf);

    for (var index = 0; index < orderedKeys.length; index++) {
      keyOrder.putIfAbsent(orderedKeys[index], () => index);
    }
    return keyOrder;
  }

  static Map<String, int> buildTitleOrderMap(Library library) {
    return buildKeyOrderMap(
      library,
      keyOf: (book) => book.title as String,
    );
  }

  static int topCategoryOrder(Category cat) {
    final normalized = cat.title
        .replaceAll('\u05F4', '"')
        .replaceAll('\u05F3', "'");
    final idx = _orderedTopCategories.indexOf(normalized);
    return idx >= 0 ? idx : _orderedTopCategories.length + cat.order;
  }

  static int normalizeOrder(int order) =>
      order >= 0 ? order : 1000 + order.abs();
}
