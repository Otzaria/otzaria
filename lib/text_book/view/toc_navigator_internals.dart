import 'package:otzaria/models/books.dart';
import 'package:otzaria/utils/text/text_manipulation.dart';

/// פריט יחיד ברשימה השטוחה של ה-TOC.
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

/// שורשי העץ לתצוגה מתחת לכותרת [bookTitle]: שורש יחיד ששמו כשם הספר
/// מוחלף בילדיו, כדי שהשם לא יופיע פעמיים.
List<TocEntry> tocRootsBelowTitle(List<TocEntry> entries, String bookTitle) {
  if (entries.length != 1) return entries;
  final root = entries.single;
  if (root.children.isEmpty ||
      stripHtmlIfNeeded(root.text).trim() != bookTitle.trim()) {
    return entries;
  }
  return root.children;
}

/// מחזיר את הערכים הגלויים כרגע ברשימה שטוחה (לפי [expanded]).
///
/// כללי הרחבה ברירת-מחדל (כשאין הכרעה ב-[expanded]):
/// - ערך ברמה 1 מורחב.
/// - "ילד ראשון" של אב מורחב מורחב גם הוא (שרשרת first-child).
///
/// המפה [expanded] מאפשרת למשתמש לעקוף את ברירת המחדל - הערך בה
/// קובע הכל אם קיים (true=מורחב, false=מכווץ).
///
/// [expandByDefault] פותח הכל כברירת מחדל - כך נראות תוצאות החיפוש.
List<TocFlatItem> flattenVisibleToc(
  List<TocEntry> entries,
  Map<int, bool> expanded, {
  bool parentIsFirstChild = true,
  bool expandByDefault = false,
}) {
  final result = <TocFlatItem>[];
  for (var i = 0; i < entries.length; i++) {
    final entry = entries[i];
    final isFirstChild = parentIsFirstChild && i == 0;

    if (entry.children.isEmpty) {
      result.add(TocFlatItem(entry, false));
      continue;
    }

    final fallbackExpanded =
        expandByDefault || entry.level == 1 || isFirstChild;
    final isExpanded = expanded[entry.index] ?? fallbackExpanded;
    result.add(TocFlatItem(entry, isExpanded));
    if (isExpanded) {
      result.addAll(
        flattenVisibleToc(
          entry.children,
          expanded,
          parentIsFirstChild: isFirstChild,
          expandByDefault: expandByDefault,
        ),
      );
    }
  }
  return result;
}

/// מצב ההרחבה של "כווץ הכל": כל ערך עם ילדים סגור, חוץ משרשרת של שורש
/// יחיד (כותרת הספר שמעל השערים) - אחרת לא היה נשאר דבר גלוי.
Map<int, bool> collapsedTocExpansion(List<TocEntry> entries) {
  final result = <int, bool>{};
  var level = entries;
  while (level.length == 1 && level.first.children.isNotEmpty) {
    result[level.first.index] = true;
    level = level.first.children;
  }
  void collapse(List<TocEntry> list) {
    for (final entry in list) {
      if (entry.children.isEmpty) continue;
      result.putIfAbsent(entry.index, () => false);
      collapse(entry.children);
    }
  }

  collapse(level);
  return result;
}

/// מצב ההרחבה של "הרחב הכל": כל ערך עם ילדים פתוח.
Map<int, bool> expandedTocExpansion(List<TocEntry> entries) {
  final result = <int, bool>{};
  void expand(List<TocEntry> list) {
    for (final entry in list) {
      if (entry.children.isEmpty) continue;
      result[entry.index] = true;
      expand(entry.children);
    }
  }

  expand(entries);
  return result;
}

/// האם אין בעץ הגלוי [visible] ענף פתוח מעבר למצב [collapsed] (של
/// [collapsedTocExpansion]). ענף שנסגר ביד, גם שורש שהמצב המכווץ משאיר פתוח,
/// נחשב מכווץ: אחרת הכפתור היה מציע "כווץ הכל" כשהכל כבר סגור (#3103).
bool isTocCollapsed(List<TocFlatItem> visible, Map<int, bool> collapsed) {
  for (final item in visible) {
    if (item.entry.children.isEmpty || !item.isExpanded) continue;
    if (collapsed[item.entry.index] != true) return false;
  }
  return true;
}
