import 'package:otzaria/data/data_providers/database_library_provider.dart';
import 'package:otzaria/data/data_providers/library_provider_manager.dart';
import 'package:otzaria/migration/models/alt_toc_entry.dart';
import 'package:otzaria/migration/models/alt_toc_structure.dart';
import 'package:otzaria/models/books.dart';

/// מבנה "דיבורי המתחיל" בלשונית 'כותרות' — מסונתז בלקוח מטבלת `line_dh`
/// ומעץ ה-TOC של הספר, ולא קיים במסד כמבנה חלופי.
const int kDibburimStructureId = -1;

const AltTocStructure dibburimStructure = AltTocStructure(
  id: kDibburimStructureId,
  bookId: 0,
  key: 'Dibburim',
  heTitle: 'דיבורי המתחיל',
);

/// מספר המילים המרבי שמוצג מדיבור. המחלץ במסד לוקח את כל טווח ההדגשה, שברבים
/// מהספרים הוא משפט שלם.
const int kDibburMaxWords = 4;

/// מקצר [text] ל-[maxWords] מילים ראשונות, עם "…" כשנחתך.
String truncateDibbur(String text, {int maxWords = kDibburMaxWords}) {
  final words = text.trim().split(RegExp(r'\s+'));
  if (words.length <= maxWords) return text.trim();
  return '${words.take(maxWords).join(' ')}…';
}

/// דיבורי-המתחיל של [book] (`lineIndex` → הצורה המודפסת), או מפה ריקה כשאין.
Future<Map<int, String>> loadDibburimForBook(TextBook book) async {
  // הדיבורים ממופים ל-lineIndex של הטקסט במסד של הספר. ספר אישי, מהדורה
  // חלופית או ספר שתוכנו מוגש מקבצים — ממוספרים אחרת.
  if (book.isUserBook || book.versionTitle != null) return const {};
  if (book.source.isOfficial &&
      LibraryProviderManager.instance.getProviderForBook(
            book.title,
            categoryId: book.categoryId,
            fileType: book.fileType,
          )
          is! DatabaseLibraryProvider) {
    return const {};
  }
  return DatabaseLibraryProvider.instance.getDibburHamatchilByLineIndex(
    book.title,
    categoryId: book.categoryId,
    source: book.source,
  );
}

/// מזהה הערך במבנה המסונתז לשורה [lineIndex]. שלילי, כדי שלא יתנגש במזהי
/// `alt_toc_entry` של המבנים האמיתיים — התצוגה מחזיקה מצב לפי מזהה בלבד.
int dibburimEntryId(int lineIndex) => -(lineIndex + 1);

/// ההפוך של [dibburimEntryId].
int dibburimLineIndex(int entryId) => -entryId - 1;

/// מחזירה עותק של [toc] שבו כל דיבור-מתחיל ב-[dibburim] (`lineIndex` → טקסט)
/// הוא עלה תחת הכותרת האחרונה שלפניו בסדר הספר — גם כשזו כותרת שהייתה עלה
/// בעצמה. העץ המקורי אינו משתנה. דיבור שלפני הכותרת הראשונה נשמט.
List<TocEntry> attachDibburimToToc(
  List<TocEntry> toc,
  Map<int, String> dibburim,
) {
  if (dibburim.isEmpty) return toc;

  final lineIndexes = dibburim.keys.toList()..sort();
  var nextDibbur = 0;
  TocEntry? lastHeading;

  // מצרף ל-[lastHeading] את כל הדיבורים שלפני הכותרת הבאה (או את כולם).
  void attachDibburimBefore(int? nextHeadingIndex) {
    while (nextDibbur < lineIndexes.length &&
        (nextHeadingIndex == null ||
            lineIndexes[nextDibbur] < nextHeadingIndex)) {
      final lineIndex = lineIndexes[nextDibbur++];
      final heading = lastHeading;
      if (heading == null) continue;
      heading.children.add(
        TocEntry(
          text: dibburim[lineIndex]!,
          index: lineIndex,
          level: heading.level + 1,
          parent: heading,
        ),
      );
    }
    // דיבור על שורת הכותרת עצמה אינו קיים במסד; אם בכל זאת הגיע — נשמט.
    if (nextHeadingIndex != null &&
        nextDibbur < lineIndexes.length &&
        lineIndexes[nextDibbur] == nextHeadingIndex) {
      nextDibbur++;
    }
  }

  List<TocEntry> copyLevel(List<TocEntry> entries, TocEntry? parent) {
    return [
      for (final entry in entries)
        () {
          attachDibburimBefore(entry.index);
          final copy = TocEntry(
            text: entry.text,
            index: entry.index,
            level: entry.level,
            parent: parent,
          );
          lastHeading = copy;
          copy.children.addAll(copyLevel(entry.children, copy));
          return copy;
        }(),
    ];
  }

  final result = copyLevel(toc, null);
  attachDibburimBefore(null);
  return result;
}

/// ערכי המבנה המסונתז: הדיבורים כעלים תחת כותרות ה-TOC שלהם, בלי כותרות
/// שאין תחתיהן דיבור. שורש יחיד (שם הספר) מושמט — כותרת המבנה ממלאת את
/// מקומו. הרשימה מסודרת לפי סדר הספר; טקסט הדיבור מקוצר ל-[kDibburMaxWords].
List<AltTocEntry> buildDibburimEntries(
  List<TocEntry> toc,
  Map<int, String> dibburim,
) {
  if (dibburim.isEmpty) return const [];

  // כותרת נשמרת רק אם היא עצמה דיבור או שיש דיבור בצאצאיה.
  final kept = <TocEntry>{};
  bool mark(TocEntry entry) {
    var keep = dibburim.containsKey(entry.index);
    for (final child in entry.children) {
      keep = mark(child) || keep;
    }
    if (keep) kept.add(entry);
    return keep;
  }

  List<TocEntry> prune(List<TocEntry> entries) =>
      entries.where(kept.contains).toList();

  final merged = attachDibburimToToc(toc, dibburim);
  merged.forEach(mark);
  var roots = prune(merged);
  if (roots.length == 1 && !dibburim.containsKey(roots.single.index)) {
    roots = prune(roots.single.children);
  }

  final result = <AltTocEntry>[];
  void visit(List<TocEntry> entries, int? parentId, int level) {
    for (var i = 0; i < entries.length; i++) {
      final entry = entries[i];
      final isDibbur = dibburim.containsKey(entry.index);
      final children = isDibbur ? const <TocEntry>[] : prune(entry.children);
      result.add(
        AltTocEntry(
          id: dibburimEntryId(entry.index),
          structureId: kDibburimStructureId,
          parentId: parentId,
          textId: 0,
          level: level,
          isLastChild: i == entries.length - 1,
          hasChildren: children.isNotEmpty,
          text: isDibbur ? truncateDibbur(entry.text) : entry.text,
        ),
      );
      visit(children, dibburimEntryId(entry.index), level + 1);
    }
  }

  visit(roots, null, 0);
  return result;
}

/// האם לפחות דיבור אחד יכול להופיע במבנה המסונתז.
///
/// דיבור בלי כותרת קודמת, או על אותה שורה של כותרת, מושמט בבנייה ולכן אינו
/// מצדיק הצגת לשונית ריקה.
bool hasDibburimEntries(List<TocEntry> toc, Map<int, String> dibburim) {
  if (toc.isEmpty || dibburim.isEmpty) return false;

  final headingIndexes = <int>{};
  var firstHeadingIndex = toc.first.index;
  void collect(List<TocEntry> entries) {
    for (final entry in entries) {
      headingIndexes.add(entry.index);
      if (entry.index < firstHeadingIndex) firstHeadingIndex = entry.index;
      collect(entry.children);
    }
  }

  collect(toc);
  return dibburim.keys.any(
    (lineIndex) =>
        lineIndex > firstHeadingIndex && !headingIndexes.contains(lineIndex),
  );
}

/// מזהה הערך במבנה המסונתז ששורת התחלתו היא האחרונה שאינה אחרי [lineIndex],
/// או null כשהשורה קודמת לכל הערכים. [entries] הן פלט [buildDibburimEntries].
int? activeDibburimEntryId(List<AltTocEntry> entries, int lineIndex) {
  var low = 0;
  var high = entries.length;
  while (low < high) {
    final middle = low + (high - low) ~/ 2;
    if (dibburimLineIndex(entries[middle].id) <= lineIndex) {
      low = middle + 1;
    } else {
      high = middle;
    }
  }
  return low == 0 ? null : entries[low - 1].id;
}
