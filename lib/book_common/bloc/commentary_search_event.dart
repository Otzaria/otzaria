part of 'commentary_search_bloc.dart';

sealed class CommentarySearchEvent {}

class CommentarySearchRequested extends CommentarySearchEvent {
  final List<Link> links;
  final String query;
  final TextDisplayProfile displayProfile;
  final bool includeSnippets;

  /// גופי ההערות המוצגות מעל המפרשים — נספרות לפניהם, כמו בתצוגה.
  final List<String> notes;

  /// חייב לשקף את `partialWordHighlight` שבו ההערות מודגשות.
  final bool notesPartialWordMatch;

  CommentarySearchRequested({
    required Iterable<Link> links,
    required this.query,
    required this.displayProfile,
    required this.includeSnippets,
    Iterable<String> notes = const [],
    this.notesPartialWordMatch = true,
  }) : links = List.unmodifiable(links),
       notes = List.unmodifiable(notes);
}

class CommentarySearchReported extends CommentarySearchEvent {
  final int generation;
  final String key;
  final int? count;
  final List<String>? snippets;

  CommentarySearchReported({
    required this.generation,
    required this.key,
    this.count,
    this.snippets,
  });
}

class _SearchFlush extends CommentarySearchEvent {
  final int generation;
  _SearchFlush(this.generation);
}
