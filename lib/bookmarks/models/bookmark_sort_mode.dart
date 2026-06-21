import 'package:flutter_settings_screens/flutter_settings_screens.dart';

/// אופן מיון רשימת הסימניות. הבחירה נשמרת בין הפעלות.
enum BookmarkSortMode {
  /// לפי מיקום בספרייה (קטגוריה → ספר → מיקום בספר). ברירת המחדל.
  category,

  /// לפי מועד ההוספה — החדשות ביותר ראשונות.
  dateAdded,
}

const String _kBookmarkSortModeKey = 'key-bookmark-sort-mode';

/// טוען את אופן המיון השמור; ברירת מחדל [BookmarkSortMode.category].
BookmarkSortMode loadBookmarkSortMode() {
  final raw = Settings.getValue<String>(_kBookmarkSortModeKey);
  return BookmarkSortMode.values.firstWhere(
    (mode) => mode.name == raw,
    orElse: () => BookmarkSortMode.category,
  );
}

/// שומר את אופן המיון שנבחר.
Future<void> saveBookmarkSortMode(BookmarkSortMode mode) async {
  await Settings.setValue<String>(_kBookmarkSortModeKey, mode.name);
}
