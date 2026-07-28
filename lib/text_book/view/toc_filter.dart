import 'package:otzaria/models/books.dart';
import 'package:otzaria/search/utils/find_match_utils.dart';

/// מחזירה עץ תוכן עניינים מסונן לפי טקסט החיפוש.
///
/// אם הטקסט מנורמל לריק (למשל רק ניקוד/רווחים), מוחזר עץ ריק.
List<TocEntry> filterTocEntriesForSearch(
  List<TocEntry> entries,
  String rawQuery,
) {
  final normalizedQuery = _normalizeQuery(rawQuery);
  if (normalizedQuery.isEmpty) return [];

  final filtered = _buildFilteredEntries(entries, normalizedQuery);
  return _sortEntriesByRelevance(filtered);
}

/// קובע אם צומת צריך להיות פתוח כברירת מחדל במצב חיפוש.
bool shouldExpandInSearch(bool? expandedFlag) => expandedFlag ?? true;

String _normalizeQuery(String rawQuery) {
  return normalizeFindQuery(rawQuery);
}

bool _isBookTitle(
  TocEntry entry,
  int depth,
  int index,
  bool isFirstEntry,
) {
  return (depth == 0 && index == 0) ||
      (entry.level <= 1 && index == 0 && isFirstEntry);
}

/// הנרמול אינו תלוי בשאילתה, ולכן נשמר בין הקלדה להקלדה. בלעדיו כל תו
/// שהוקלד נרמל מחדש את כל כותרות הספר (עשרות אלפים במיקרופדיה), והנרמול
/// לדירוג אף קורא ל-sanitizeQuery של מנוע החיפוש (FFI סינכרוני).
final Expando<String> _matchTextCache = Expando<String>();
final Expando<String> _rankTextCache = Expando<String>();
final Expando<String> _rankFullTextCache = Expando<String>();

/// הטקסט שלפיו נקבעת ההתאמה.
String _matchText(TocEntry entry) =>
    _matchTextCache[entry] ??= normalizeFindText(entry.text);

// הדירוג מנרמל כשאילתה ולא כטקסט - שני הנרמולים נותנים תוצאה שונה על
// גרשיים טיפוגרפיים ופיסוק (שו”ע → "שוע" מול "שו ע"), ואיחודם משנה סדר.
String _rankText(TocEntry entry) =>
    _rankTextCache[entry] ??= normalizeFindQuery(entry.text);

/// fullText בונה מחדש את שרשרת ההורים בכל קריאה — ממטמנים כמו את הכותרת.
String _rankFullText(TocEntry entry) =>
    _rankFullTextCache[entry] ??= normalizeFindQuery(entry.fullText);

/// מפתחות הדירוג של העותק המסונן. נקבעים בזמן הסינון מתוך הערך המקורי,
/// ששם המטמונים חיים בין חיפוש לחיפוש (העותקים נוצרים מחדש בכל חיפוש).
final Expando<_RankKeys> _rankKeysCache = Expando<_RankKeys>();

class _RankKeys {
  final int rank;
  final int lengthDelta;

  const _RankKeys(this.rank, this.lengthDelta);
}

/// מסננת ענף יחיד, ומחזירה עותק מסונן או null אם אין בו התאמה.
///
/// הענף נשמר אם הוא עצמו תואם או אם נשמר לפחות צאצא אחד — כך התשובה
/// "יש צאצא תואם" נגזרת מהסינון עצמו, במעבר יחיד על העץ.
TocEntry? _filterEntry(
  TocEntry entry,
  String query, {
  required int depth,
  required int index,
  required bool isFirstEntry,
  TocEntry? parent,
}) {
  final isBookTitle = _isBookTitle(entry, depth, index, isFirstEntry);
  final selfMatches =
      !isBookTitle &&
      findNormalizedTextMatches(
        normalizedQuery: query,
        normalizedPrimaryText: _matchText(entry),
      );

  final cloned = TocEntry(
    text: entry.text,
    index: entry.index,
    level: entry.level,
    parent: parent,
  );

  final children = <TocEntry>[];
  for (int i = 0; i < entry.children.length; i++) {
    final child = _filterEntry(
      entry.children[i],
      query,
      depth: depth + 1,
      index: i,
      isFirstEntry: false,
      parent: cloned,
    );
    if (child != null) children.add(child);
  }
  cloned.children = children;

  if (!selfMatches && children.isEmpty) return null;

  final rankText = _rankText(entry);
  final rankFullText = _rankFullText(entry);
  _rankKeysCache[cloned] = _RankKeys(
    findNormalizedTextMatchRank(
      normalizedQuery: query,
      normalizedPrimaryText: rankText,
      normalizedSecondaryText: rankFullText,
    ),
    findNormalizedTextMatchLengthDelta(
      normalizedQuery: query,
      normalizedPrimaryText: rankText,
      normalizedSecondaryText: rankFullText,
    ),
  );
  return cloned;
}

List<TocEntry> _buildFilteredEntries(
  List<TocEntry> entries,
  String query,
) {
  final result = <TocEntry>[];
  for (int i = 0; i < entries.length; i++) {
    final filtered = _filterEntry(
      entries[i],
      query,
      depth: 0,
      index: i,
      isFirstEntry: true,
    );
    if (filtered != null) result.add(filtered);
  }
  return result;
}

/// ממיינת לפי מפתחות הדירוג שנקבעו ב-[_filterEntry]. חישובם בתוך
/// ה-comparator הריץ את הנרמול O(n log n) פעמים והקפיא את התוכנה בספרים
/// עם עשרות אלפי כותרות.
List<TocEntry> _sortEntriesByRelevance(List<TocEntry> entries) {
  const fallback = _RankKeys(6, 0);
  final sorted = List<TocEntry>.from(entries)
    ..sort((a, b) {
      final keysA = _rankKeysCache[a] ?? fallback;
      final keysB = _rankKeysCache[b] ?? fallback;

      final rankCompare = keysA.rank.compareTo(keysB.rank);
      if (rankCompare != 0) return rankCompare;

      // length-delta רלוונטי רק לערכים שתאמו בעצמם; ערכי-אב שנכללו בגלל
      // צאצא בלבד (rank 6) חייבים לשמור על סדר הספר ולא להידרג לפי אורך.
      if (keysA.rank < 6) {
        final lengthCompare = keysA.lengthDelta.compareTo(keysB.lengthDelta);
        if (lengthCompare != 0) return lengthCompare;
      }

      final levelCompare = a.level.compareTo(b.level);
      if (levelCompare != 0) return levelCompare;

      return a.index.compareTo(b.index);
    });

  for (final entry in sorted) {
    if (entry.children.isNotEmpty) {
      entry.children = _sortEntriesByRelevance(entry.children);
    }
  }

  return sorted;
}
