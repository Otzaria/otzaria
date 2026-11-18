import 'package:otzaria/models/books.dart';
import 'package:otzaria/search/utils/find_match_utils.dart';

/// מחזירה עץ תוכן עניינים מסונן לפי טקסט החיפוש.
///
/// אם הטקסט מנורמל לריק (למשל רק ניקוד/רווחים), מוחזר עץ ריק.
List<TocEntry> filterTocEntriesForSearch(
  List<TocEntry> entries,
  String rawQuery,
) {
  final query = normalizeFindQuery(rawQuery);
  if (query.isEmpty) return [];

  return [
    for (final entry in _filterEntries(entries, query, skipFirst: true))
      entry.toTocEntry(null),
  ];
}

/// הנרמול אינו תלוי בשאילתה, ולכן נשמר בין הקלדה להקלדה.
final Expando<String> _matchTextCache = Expando<String>();
final Expando<String> _rankTextCache = Expando<String>();
final Expando<String> _rankFullTextCache = Expando<String>();

/// הטקסט שלפיו נקבעת ההתאמה.
String _matchText(TocEntry entry) =>
    _matchTextCache[entry] ??= normalizeFindText(entry.text);

// נרמול הדירוג שומר על סמנטיקת השאילתה בלי FFI לכל כותרת.
String _rankText(TocEntry entry) => _rankTextCache[entry] ??=
    normalizeFindRankText(entry.text, normalizedFindText: _matchText(entry));

/// fullText בונה מחדש את שרשרת ההורים בכל קריאה — ממטמנים כמו את הכותרת.
String _rankFullText(TocEntry entry) {
  return _rankFullTextCache[entry] ??=
      entry.parent == null || entry.parent!.level <= 1
      ? _rankText(entry)
      : normalizeFindRankText(entry.fullText);
}

class _RetainedEntry {
  final TocEntry source;
  final List<_RetainedEntry> children;
  final int rank;
  final int lengthDelta;

  const _RetainedEntry(
    this.source,
    this.children, {
    this.rank = 6,
    this.lengthDelta = 0,
  });

  TocEntry toTocEntry(TocEntry? parent) {
    final entry = TocEntry(
      text: source.text,
      index: source.index,
      level: source.level,
      parent: parent,
    );
    if (children.isNotEmpty) {
      entry.children = [for (final child in children) child.toTocEntry(entry)];
    }
    return entry;
  }
}

List<_RetainedEntry> _filterEntries(
  List<TocEntry> entries,
  String query, {
  bool skipFirst = false,
}) {
  List<_RetainedEntry>? kept;
  for (var i = 0; i < entries.length; i++) {
    final entry = entries[i];
    final selfMatches =
        !(skipFirst && i == 0) &&
        findNormalizedTextMatches(
          normalizedQuery: query,
          normalizedPrimaryText: _matchText(entry),
        );
    final children = _filterEntries(entry.children, query);
    if (!selfMatches && children.isEmpty) continue;

    // אב לצאצא תואם נשאר בסדר הספר, אלא אם השאילתה תואמת מילים שלמות בשמו.
    final rankByTitle =
        children.isEmpty ||
        (selfMatches && ' ${_matchText(entry)} '.contains(' $query '));
    (kept ??= []).add(
      rankByTitle
          ? _rankEntry(entry, children, query)
          : _RetainedEntry(entry, children),
    );
  }

  if (kept == null) return const [];
  if (kept.length > 1) kept.sort(_compareRelevance);
  return kept;
}

_RetainedEntry _rankEntry(
  TocEntry entry,
  List<_RetainedEntry> children,
  String query,
) {
  final rankText = _rankText(entry);
  final rankFullText = _rankFullText(entry);
  return _RetainedEntry(
    entry,
    children,
    rank: findNormalizedTextMatchRank(
      normalizedQuery: query,
      normalizedPrimaryText: rankText,
      normalizedSecondaryText: rankFullText,
    ),
    lengthDelta: findNormalizedTextMatchLengthDelta(
      normalizedQuery: query,
      normalizedPrimaryText: rankText,
      normalizedSecondaryText: rankFullText,
    ),
  );
}

int _compareRelevance(_RetainedEntry a, _RetainedEntry b) {
  final rank = a.rank.compareTo(b.rank);
  if (rank != 0) return rank;

  if (a.rank < 6) {
    final length = a.lengthDelta.compareTo(b.lengthDelta);
    if (length != 0) return length;
  }

  final level = a.source.level.compareTo(b.source.level);
  if (level != 0) return level;

  return a.source.index.compareTo(b.source.index);
}
