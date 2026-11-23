import 'dart:collection';

import 'package:otzaria/data/data_providers/book_composite_key.dart';

/// אוסף מפתחות ספרים עם cache מוגבל להתאמת כותרת, סוג קובץ וקטגוריה.
class BookKeySet extends SetBase<BookCompositeKey> {
  static const _matchCacheLimit = 128;

  final Set<BookCompositeKey> _keys = {};
  final _matches = <(String, String, int?), BookCompositeKey?>{};

  BookCompositeKey? firstMatch(
    String title,
    String fileType, [
    int? categoryId,
  ]) {
    if (_keys.isEmpty) return null;
    final query = (title, fileType, categoryId);
    if (_matches.containsKey(query)) return _matches[query];

    BookCompositeKey? match;
    for (final key in _keys) {
      if (key.title == title &&
          key.fileType == fileType &&
          (categoryId == null || key.categoryId == categoryId)) {
        match = key;
        break;
      }
    }
    if (_matches.length == _matchCacheLimit) {
      _matches.remove(_matches.keys.first);
    }
    return _matches[query] = match;
  }

  void _invalidateMatches(BookCompositeKey key) {
    if (_matches.isEmpty) return;
    _matches.remove((key.title, key.fileType, null));
    _matches.remove((key.title, key.fileType, key.categoryId));
  }

  @override
  bool add(BookCompositeKey value) {
    if (!_keys.add(value)) return false;
    _invalidateMatches(value);
    return true;
  }

  @override
  bool remove(Object? value) {
    if (value is! BookCompositeKey || !_keys.remove(value)) return false;
    _invalidateMatches(value);
    return true;
  }

  @override
  void clear() {
    _keys.clear();
    _matches.clear();
  }

  @override
  bool contains(Object? element) => _keys.contains(element);

  @override
  BookCompositeKey? lookup(Object? element) => _keys.lookup(element);

  @override
  Iterator<BookCompositeKey> get iterator => _keys.iterator;

  @override
  int get length => _keys.length;

  @override
  Set<BookCompositeKey> toSet() => _keys.toSet();
}
