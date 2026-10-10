import 'package:otzaria/book_common/utils/commentary_search_utils.dart';

/// Total number of matches across all commentary items.
int totalCommentarySearchResults(Map<String, int> countsByKey) =>
    countsByKey.values.fold(0, (sum, count) => sum + count);

/// The global index of each item's first match, in display order.
///
/// A key that appears twice keeps its first offset, as the highlight lookup
/// stops at the first item with that key.
Map<String, int> commentarySearchOffsets(
  Iterable<String> orderedKeys,
  Map<String, int> countsByKey,
) {
  final offsets = <String, int>{};
  var cumulative = 0;
  for (final key in orderedKeys) {
    offsets.putIfAbsent(key, () => cumulative);
    cumulative += countsByKey[key] ?? 0;
  }
  return offsets;
}

/// The index of the current match inside the item [key], or -1 when the
/// current match belongs to another item.
int commentarySearchRelativeIndex({
  required String key,
  required int currentIndex,
  required Map<String, int> offsets,
  required Map<String, int> countsByKey,
}) {
  final itemResults = countsByKey[key] ?? 0;
  if (itemResults == 0) return -1;
  final start = offsets[key];
  if (start == null) return -1;
  final relativeIndex = currentIndex - start;
  return relativeIndex >= 0 && relativeIndex < itemResults ? relativeIndex : -1;
}

/// The snippets of all items in display order, each with the global index
/// that navigation scrolls to.
List<CommentarySearchSnippet> orderCommentarySearchSnippets<T>({
  required Iterable<T> items,
  required String Function(T item) keyOf,
  required String Function(T item) pathOf,
  required Map<String, int> countsByKey,
  required List<String> Function(String key, int count) snippetsOf,
}) {
  final result = <CommentarySearchSnippet>[];
  var globalIndex = 0;
  for (final item in items) {
    final key = keyOf(item);
    final count = countsByKey[key] ?? 0;
    for (final snippet in snippetsOf(key, count)) {
      result.add(
        CommentarySearchSnippet(
          path: pathOf(item),
          snippet: snippet,
          globalIndex: globalIndex,
        ),
      );
    }
    globalIndex += count;
  }
  return result;
}

/// Match counts summed per commentator path, without empty paths or counts.
Map<String, int> commentarySearchCountsByPath(
  Map<String, int> countsByKey,
  Map<String, String> pathByKey,
) {
  final byPath = <String, int>{};
  for (final entry in countsByKey.entries) {
    final path = pathByKey[entry.key] ?? '';
    if (path.isNotEmpty && entry.value > 0) {
      byPath[path] = (byPath[path] ?? 0) + entry.value;
    }
  }
  return byPath;
}
