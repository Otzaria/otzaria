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

  // Sorting visits the top categories repeatedly; cache their fixed ranks
  // instead of scanning the list for every comparator invocation.
  static final Map<String, int> _topCategoryRanks = {
    for (var i = 0; i < _orderedTopCategories.length; i++)
      _orderedTopCategories[i]: i,
  };

  static List<T> buildOrderedKeys<T>(
    Library library, {
    required T Function(dynamic book) keyOf,
  }) {
    final orderedKeys = <T>[];
    // ספרי מסד מצורף תמיד בסוף — גם כשהם ממוזגים לקטגוריות הספרייה — כדי
    // שצירוף מסד לא יזיז את סדר כל שאר הספרים בתוצאות.
    final attachedKeys = <T>[];

    void collectBooks(Category category) {
      final sortedSubCategories = category.subCategories.toList()
        ..sort(subCategoryOrder(category));

      // ספרי הקטגוריה קודמים לתת-הקטגוריות: "מפרשים" הוא תת-קטגוריה של
      // הספר שהוא מפרש, וסריקתו קודם הציבה את המפרשים לפני המדרש עצמו.
      final sortedBooks = category.books.toList()
        ..sort((a, b) => a.order.compareTo(b.order));

      for (final book in sortedBooks) {
        (book.source.isAttached ? attachedKeys : orderedKeys).add(keyOf(book));
      }

      for (final subCategory in sortedSubCategories) {
        collectBooks(subCategory);
      }
    }

    collectBooks(library);
    // גרסאות שאינן בעץ — אחרי ספרי העץ מאותה סיבה, ולפני ספרי המסדים.
    for (final book in library.offTreeBooks) {
      (book.source.isAttached ? attachedKeys : orderedKeys).add(keyOf(book));
    }
    orderedKeys.addAll(attachedKeys);
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

  static int topCategoryOrder(Category cat) {
    final normalized = cat.title
        .replaceAll('\u05F4', '"')
        .replaceAll('\u05F3', "'");
    return _topCategoryRanks[normalized] ??
        _orderedTopCategories.length + cat.order;
  }

  static int normalizeOrder(int order) =>
      order >= 0 ? order : 1000 + order.abs();

  /// סדר התצוגה של תת-הקטגוריות של [parent], כמו במסך הספרייה: התיקיות
  /// העליונות לפי [topCategoryOrder], וכל רמה פנימית לפי [normalizeOrder].
  static Comparator<Category> subCategoryOrder(Category parent) =>
      parent is Library ? _compareTopCategories : _compareNestedCategories;

  static int _compareTopCategories(Category a, Category b) =>
      topCategoryOrder(a).compareTo(topCategoryOrder(b));

  static int _compareNestedCategories(Category a, Category b) =>
      normalizeOrder(a.order).compareTo(normalizeOrder(b.order));
}
