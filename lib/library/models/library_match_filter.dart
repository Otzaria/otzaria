import 'package:otzaria/data/repository/data_repository.dart';

/// צ'יפי הסינון של תוצאות האיתור לפי במה הן תאמו לחיפוש.
enum LibraryMatchFilter {
  title('שם הספר', BookMatchKind.title),
  author('מחבר', BookMatchKind.author),
  acronym('כינוי', BookMatchKind.acronym),
  folder('בתוך תיקייה', BookMatchKind.folder),
  spelling('כתיב דומה', BookMatchKind.spelling),

  /// כרטיסי התיקיות שתאמו לחיפוש, לא ספרים.
  folders('תיקיות', null);

  const LibraryMatchFilter(this.label, this.bookKind);

  final String label;
  final BookMatchKind? bookKind;

  /// ספר עם [kinds] מוצג כשאין סינון, או כשאחד מסוגי ההתאמה שלו נבחר.
  static bool showsBook(Set<LibraryMatchFilter> selected, int kinds) =>
      selected.isEmpty ||
      selected.any((f) => f.bookKind != null && kinds & f.bookKind!.bit != 0);

  /// הסוגים שיש להם תוצאות — בחירה של סוג אחר הייתה מסתירה הכול.
  static Set<LibraryMatchFilter> present(
    Iterable<int> bookKinds, {
    required bool hasFolders,
  }) {
    final all = bookKinds.fold(0, (a, b) => a | b);
    return {
      for (final filter in values)
        if (filter.bookKind case final kind?)
          if (all & kind.bit != 0) filter,
      if (hasFolders) folders,
    };
  }

  static bool showsFolders(Set<LibraryMatchFilter> selected) =>
      selected.isEmpty || selected.contains(folders);
}
