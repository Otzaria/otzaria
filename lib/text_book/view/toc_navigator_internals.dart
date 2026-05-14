import 'package:otzaria/models/books.dart';

/// פריט יחיד ברשימה השטוחה של ה-TOC.
/// משמש כשעוברים למצב וירטואליזציה אמיתית (ספרים עם הרבה ערכי TOC).
class TocFlatItem {
  final TocEntry entry;
  final bool isExpanded;
  const TocFlatItem(this.entry, this.isExpanded);

  @override
  bool operator ==(Object other) =>
      other is TocFlatItem &&
      other.entry == entry &&
      other.isExpanded == isExpanded;

  @override
  int get hashCode => Object.hash(entry, isExpanded);
}

/// סופר רקורסיבית את כל ערכי ה-TOC (כל הרמות).
/// משמש כדי להחליט אם לעבור למצב וירטואלי שטוח.
int countAllTocEntries(List<TocEntry> entries) {
  var count = entries.length;
  for (final e in entries) {
    count += countAllTocEntries(e.children);
  }
  return count;
}

/// מחזיר את הערכים הגלויים כרגע ברשימה שטוחה (לפי [expanded]).
///
/// כללי הרחבה ברירת-מחדל (כשאין הכרעה ב-[expanded]):
/// - ערך ברמה 1 מורחב.
/// - "ילד ראשון" של אב מורחב מורחב גם הוא (שרשרת first-child).
///
/// המפה [expanded] מאפשרת למשתמש לעקוף את ברירת המחדל - הערך בה
/// קובע הכל אם קיים (true=מורחב, false=מכווץ).
List<TocFlatItem> flattenVisibleToc(
  List<TocEntry> entries,
  Map<int, bool> expanded, {
  bool parentIsFirstChild = true,
}) {
  final result = <TocFlatItem>[];
  for (var i = 0; i < entries.length; i++) {
    final entry = entries[i];
    final isFirstChild = parentIsFirstChild && i == 0;

    if (entry.children.isEmpty) {
      result.add(TocFlatItem(entry, false));
      continue;
    }

    final fallbackExpanded = entry.level == 1 || isFirstChild;
    final isExpanded = expanded[entry.index] ?? fallbackExpanded;
    result.add(TocFlatItem(entry, isExpanded));
    if (isExpanded) {
      result.addAll(flattenVisibleToc(
        entry.children,
        expanded,
        parentIsFirstChild: isFirstChild,
      ));
    }
  }
  return result;
}
