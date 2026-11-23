import 'package:otzaria/library/models/library.dart';

/// אינדקס קטגוריות אחיות לפי מפתח כותרת מנורמל.
class CategoryMergeTargets {
  CategoryMergeTargets(
    this._categories,
    this._normalizeTitle, {
    bool Function(Category)? exclude,
  }) {
    for (final category in _categories) {
      if (exclude?.call(category) != true) _index(category);
    }
  }

  final List<Category> _categories;
  final String Function(String title) _normalizeTitle;
  final Map<String, Category> _byKey = {};

  void _index(Category category) => _byKey.putIfAbsent(
    _normalizeTitle(category.title),
    () => category,
  );

  Category? find(String title) => _byKey[_normalizeTitle(title)];

  void add(Category category) {
    _categories.add(category);
    _index(category);
  }
}
