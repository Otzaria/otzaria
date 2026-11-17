part of 'commentary_search_bloc.dart';

class CommentarySearchState {
  final Map<String, int> counts;
  final Map<String, int> countsByPath;
  final List<CommentarySearchSnippet> snippets;
  final int total;

  const CommentarySearchState.empty()
    : counts = const {},
      countsByPath = const {},
      snippets = const [],
      total = 0;

  CommentarySearchState._({
    required List<_LinkSearchEntry> entries,
    required Map<String, String> pathsByKey,
    required Map<String, int> counts,
    required Map<String, List<String>> snippetsByKey,
  }) : counts = Map.unmodifiable(counts),
       countsByPath = Map.unmodifiable(
         commentarySearchCountsByPath(counts, pathsByKey),
       ),
       snippets = snippetsByKey.isEmpty
           ? const []
           : List.unmodifiable(
               orderCommentarySearchSnippets(
                 items: entries,
                 keyOf: (entry) => entry.key,
                 pathOf: (entry) => entry.path,
                 countsByKey: counts,
                 snippetsOf: (key, count) =>
                     count > 0 ? snippetsByKey[key] ?? const [] : const [],
               ),
             ),
       total = totalCommentarySearchResults(counts);
}
