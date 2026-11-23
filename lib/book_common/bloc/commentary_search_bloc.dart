import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:flutter/foundation.dart';
import 'package:otzaria/book_common/models/commentator_group.dart';
import 'package:otzaria/book_common/utils/commentary_search_results.dart';
import 'package:otzaria/book_common/utils/commentary_search_utils.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/text_display/models/text_display_profile.dart';

part 'commentary_search_event.dart';
part 'commentary_search_state.dart';

typedef _SearchEntry = ({String key, String path, bool isNote});

/// מפתח החיפוש של ההערה [index] מתוך ההערות שבבקשה.
String commentaryNoteSearchKey(int index) => 'notes:$index';

/// מחשב חיפוש לכל הקישורים, כולל פריטים שלא נבנו ברשימה הווירטואלית.
class CommentarySearchBloc
    extends Bloc<CommentarySearchEvent, CommentarySearchState> {
  final String Function(Link) keyOf;
  CommentarySearchRequested? _request;
  List<_SearchEntry> _entries = const [];
  List<_SearchEntry> _linkEntries = const [];

  /// הקישורים שמהם נגזרו המפתחות והנתיבים בסדר התצוגה.
  List<Link> _keyedLinks = const [];
  Map<String, String> _pathsByKey = const {};
  int _generation = 0;
  Timer? _computeTimer;
  Timer? _flushTimer;
  final Map<String, int> _pendingCounts = {};
  final Map<String, List<String>> _pendingSnippets = {};
  final Map<String, List<String>> _snippets = {};

  CommentarySearchBloc({required this.keyOf})
    : super(const CommentarySearchState.empty()) {
    on<CommentarySearchRequested>(_onRequested);
    on<CommentarySearchReported>(_onReported);
    on<_SearchFlush>(_onFlush);
  }

  /// מזהה הבקשה שאליה שייך דיווח מפריט מרונדר.
  int get generation => _generation;

  void _onRequested(
    CommentarySearchRequested event,
    Emitter<CommentarySearchState> emit,
  ) {
    final linkEntries = listEquals(_keyedLinks, event.links)
        ? _linkEntries
        : [
            for (final link in event.links)
              (key: keyOf(link), path: link.path2, isNote: false),
          ];
    final previous = _request;
    final entries = event.notes.isEmpty
        ? linkEntries
        : identical(linkEntries, _linkEntries) &&
              previous?.notes.length == event.notes.length
        ? _entries
        : [
            for (var i = 0; i < event.notes.length; i++)
              (
                key: commentaryNoteSearchKey(i),
                path: kNotesCommentatorTitle,
                isNote: true,
              ),
            ...linkEntries,
          ];
    _keyedLinks = event.links;
    _linkEntries = linkEntries;
    final sameEntries = listEquals(_entries, entries);
    if (previous != null &&
        previous.query == event.query &&
        previous.displayProfile == event.displayProfile &&
        previous.includeSnippets == event.includeSnippets &&
        previous.notesPartialWordMatch == event.notesPartialWordMatch &&
        listEquals(previous.notes, event.notes) &&
        sameEntries) {
      return;
    }
    _request = event;
    if (!sameEntries) {
      _entries = entries;
      _pathsByKey = {for (final entry in entries) entry.key: entry.path};
    }
    final generation = ++_generation;
    _computeTimer?.cancel();
    _flushTimer?.cancel();
    _pendingCounts.clear();
    _pendingSnippets.clear();
    _snippets.clear();
    emit(CommentarySearchState.empty());
    if (event.query.isEmpty || entries.isEmpty) return;
    _computeTimer = Timer(const Duration(milliseconds: 250), () {
      unawaited(_compute(event, entries, generation));
    });
  }

  Future<void> _compute(
    CommentarySearchRequested request,
    List<_SearchEntry> entries,
    int generation,
  ) async {
    final notes = request.notes;
    final slice = Stopwatch()..start();
    for (var i = 0; i < entries.length; i++) {
      // תוכן שכבר נטען לא מוותר על ה-event loop; בלי זה הלולאה חוסמת את ה-UI.
      if (slice.elapsedMilliseconds >= 4) {
        await Future<void>.delayed(Duration.zero);
        slice.reset();
      }
      final isNote = i < notes.length;
      String content;
      try {
        content = isNote
            ? notes[i]
            : await request.links[i - notes.length].content;
      } catch (_) {
        content = '';
      }
      if (isClosed || generation != _generation) return;
      final count = countCommentarySearchMatches(
        content: content,
        query: request.query,
        displayProfile: request.displayProfile,
        partialWordMatch: !isNote || request.notesPartialWordMatch,
      );
      add(
        CommentarySearchReported(
          generation: generation,
          key: entries[i].key,
          count: count,
          snippets: request.includeSnippets && count > 0
              ? [
                  buildCommentarySearchSnippet(
                    content: content,
                    query: request.query,
                    displayProfile: request.displayProfile,
                    partialWordMatch: isNote && request.notesPartialWordMatch,
                  ),
                ]
              : const [],
        ),
      );
    }
  }

  void _onReported(
    CommentarySearchReported event,
    Emitter<CommentarySearchState> emit,
  ) {
    final request = _request;
    if (event.generation != _generation ||
        request == null ||
        request.query.isEmpty ||
        !_pathsByKey.containsKey(event.key)) {
      return;
    }
    final countChanged =
        event.count != null &&
        (_pendingCounts[event.key] ?? state.counts[event.key]) != event.count;
    final snippetsChanged =
        request.includeSnippets &&
        event.snippets != null &&
        !listEquals(
          _pendingSnippets[event.key] ??
              _snippets[event.key] ??
              const <String>[],
          event.snippets,
        );
    if (!countChanged && !snippetsChanged) return;
    if (countChanged) _pendingCounts[event.key] = event.count!;
    if (snippetsChanged) {
      _pendingSnippets[event.key] = List.unmodifiable(event.snippets!);
    }
    if (_flushTimer?.isActive ?? false) return;
    final generation = _generation;
    _flushTimer = Timer(
      const Duration(milliseconds: 150),
      () => add(_SearchFlush(generation)),
    );
  }

  void _onFlush(_SearchFlush event, Emitter<CommentarySearchState> emit) {
    if (event.generation != _generation) return;
    final counts = {...state.counts, ..._pendingCounts};
    _snippets.addAll(_pendingSnippets);
    _pendingCounts.clear();
    _pendingSnippets.clear();
    emit(
      CommentarySearchState._(
        entries: _entries,
        pathsByKey: _pathsByKey,
        counts: counts,
        snippetsByKey: _snippets,
        notesPartialWordMatch: _request!.notesPartialWordMatch,
      ),
    );
  }

  @override
  Future<void> close() {
    _generation++;
    _computeTimer?.cancel();
    _flushTimer?.cancel();
    return super.close();
  }
}
