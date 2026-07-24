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
  return _sortEntriesByRelevance(filtered, normalizedQuery);
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

bool _matchesEntryOrDescendants(
  TocEntry entry,
  String query, {
  required int depth,
  required int index,
  required bool isFirstEntry,
}) {
  final isBookTitle = _isBookTitle(entry, depth, index, isFirstEntry);
  final entryText = normalizeFindText(entry.text);
  final selfMatches =
      !isBookTitle &&
      findNormalizedTextMatches(
        normalizedQuery: query,
        normalizedPrimaryText: entryText,
      );
  if (selfMatches) return true;

  for (int i = 0; i < entry.children.length; i++) {
    final child = entry.children[i];
    if (_matchesEntryOrDescendants(
      child,
      query,
      depth: depth + 1,
      index: i,
      isFirstEntry: false,
    )) {
      return true;
    }
  }

  return false;
}

List<TocEntry> _buildFilteredEntries(
  List<TocEntry> entries,
  String query, {
  int depth = 0,
  bool isFirstEntry = true,
  TocEntry? parent,
}) {
  final result = <TocEntry>[];

  for (int i = 0; i < entries.length; i++) {
    final entry = entries[i];
    final isBookTitle = _isBookTitle(entry, depth, i, isFirstEntry);
    final entryText = normalizeFindText(entry.text);
    final selfMatches =
        !isBookTitle &&
        findNormalizedTextMatches(
          normalizedQuery: query,
          normalizedPrimaryText: entryText,
        );
    final hasMatchingDescendant = entry.children.asMap().entries.any((entry) {
      final childIndex = entry.key;
      final child = entry.value;
      return _matchesEntryOrDescendants(
        child,
        query,
        depth: depth + 1,
        index: childIndex,
        isFirstEntry: false,
      );
    });

    if (selfMatches || hasMatchingDescendant) {
      final cloned = TocEntry(
        text: entry.text,
        index: entry.index,
        level: entry.level,
        parent: parent,
      );
      cloned.children = _buildFilteredEntries(
        entry.children,
        query,
        depth: depth + 1,
        isFirstEntry: false,
        parent: cloned,
      );
      result.add(cloned);
    }
  }

  return result;
}

List<TocEntry> _sortEntriesByRelevance(
  List<TocEntry> entries,
  String query,
) {
  final sorted = List<TocEntry>.from(entries)
    ..sort((a, b) {
      final rankA = _matchRank(a, query);
      final rankCompare = rankA.compareTo(_matchRank(b, query));
      if (rankCompare != 0) return rankCompare;

      // length-delta רלוונטי רק לערכים שתאמו בעצמם; ערכי-אב שנכללו בגלל
      // צאצא בלבד (rank 6) חייבים לשמור על סדר הספר ולא להידרג לפי אורך.
      if (rankA < 6) {
        final lengthCompare = _matchLengthDelta(
          a,
          query,
        ).compareTo(_matchLengthDelta(b, query));
        if (lengthCompare != 0) return lengthCompare;
      }

      final levelCompare = a.level.compareTo(b.level);
      if (levelCompare != 0) return levelCompare;

      return a.index.compareTo(b.index);
    });

  for (final entry in sorted) {
    if (entry.children.isNotEmpty) {
      entry.children = _sortEntriesByRelevance(entry.children, query);
    }
  }

  return sorted;
}

int _matchRank(TocEntry entry, String query) {
  return findNormalizedTextMatchRank(
    normalizedQuery: query,
    normalizedPrimaryText: _normalizeQuery(entry.text),
    normalizedSecondaryText: _normalizeQuery(entry.fullText),
  );
}

int _matchLengthDelta(TocEntry entry, String query) {
  return findNormalizedTextMatchLengthDelta(
    normalizedQuery: query,
    normalizedPrimaryText: _normalizeQuery(entry.text),
    normalizedSecondaryText: _normalizeQuery(entry.fullText),
  );
}
