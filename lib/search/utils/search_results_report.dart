import 'package:flutter/foundation.dart';
import 'package:otzaria/search/bloc/search_state.dart';
import 'package:otzaria/search/utils/snippet_builder.dart';
import 'package:otzaria/semantic_search/bloc/semantic_results_state.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/searching_tab.dart';
import 'package:otzaria/tabs/models/semantic_search_tab.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart'
    show SemanticResultSource, TextStatus;

/// כמה תוצאות לא מודגשות מפורטות בדיווח.
const int maxUnhighlightedSamples = 10;

/// מצב התוצאות בחלונית הפעילה, לדיווח מהתוכנה: ספירות לפי מצב הטקסט וההדגשה
/// ודוגמאות של תוצאות שלא הודגשו, בלי השאילתה ובלי טקסט התוצאות.
Map<String, Object?>? describeSearchResults(TabsState tabs) {
  final tab = tabs.activePane;
  if (tab is SemanticSearchTab) {
    final bloc = tab.createdResultsBloc;
    return bloc == null
        ? const {'kind': 'semantic', 'status': 'notStarted'}
        : describeSemanticResults(bloc.state);
  }
  if (tab is SearchingTab) return describeLexicalResults(tab.searchBloc.state);
  return null;
}

@visibleForTesting
Map<String, Object?> describeLexicalResults(SearchState state) {
  final configuration = state.configuration;
  return {
    'kind': 'lexical',
    'mode': configuration.searchMode.name,
    'wordMatch': configuration.wordMatchMode.name,
    'regex': configuration.regexEnabled,
    'loading': state.isLoading,
    'failed': state.errorMessage != null,
    'truncated': state.resultsTruncated,
    'total': state.totalResults,
    ..._summarize([
      for (final result in state.results)
        _ResultRow(
          filePath: result.filePath,
          title: result.title,
          segment: result.segment.toInt(),
          textStatus: result.textStatus,
          isPdf: result.isPdf,
          highlighted: SnippetBuilder.hasHighlight(result.text),
        ),
    ]),
  };
}

@visibleForTesting
Map<String, Object?> describeSemanticResults(SemanticResultsState state) {
  final bySource = <String, int>{};
  for (final item in state.items) {
    bySource.update(item.source.name, (n) => n + 1, ifAbsent: () => 1);
  }
  return {
    'kind': 'semantic',
    'status': state.status.name,
    'onlyLexical': state.onlyLexical,
    'bySource': bySource,
    ..._summarize([
      for (final item in state.items)
        _ResultRow(
          filePath: item.filePath,
          title: item.title,
          segment: item.segment,
          textStatus: item.textStatus,
          isPdf: item.isPdf,
          // התאמה לפי עניין בלבד מגיעה בלי סימון.
          highlighted:
              item.source == SemanticResultSource.semantic ||
              item.isHighlighted,
          source: item.source.name,
        ),
    ]),
  };
}

class _ResultRow {
  const _ResultRow({
    required this.filePath,
    required this.title,
    required this.segment,
    required this.textStatus,
    required this.isPdf,
    required this.highlighted,
    this.source,
  });

  final String filePath;
  final String title;
  final int segment;
  final TextStatus textStatus;
  final bool isPdf;
  final bool highlighted;
  final String? source;
}

Map<String, Object?> _summarize(List<_ResultRow> rows) {
  final byStatus = <String, int>{};
  for (final row in rows) {
    byStatus.update(row.textStatus.name, (n) => n + 1, ifAbsent: () => 1);
  }
  final unhighlighted = rows.where((row) => !row.highlighted).toList();
  return {
    'shown': rows.length,
    'pdf': rows.where((row) => row.isPdf).length,
    'textStatus': byStatus,
    'unhighlighted': unhighlighted.length,
    'unhighlightedSamples': [
      for (final row in unhighlighted.take(maxUnhighlightedSamples))
        _sample(row),
    ],
  };
}

/// רק ספר רשמי (`id:`) מזוהה בשמו; ספר אישי, חיצוני, מצורף או נתיב קובץ — בסוגו.
Map<String, Object?> _sample(_ResultRow row) {
  final isLibraryBook = row.filePath.startsWith('id:');
  return {
    'book': isLibraryBook ? row.filePath : _keyKind(row.filePath),
    if (isLibraryBook) 'title': row.title,
    'segment': row.segment,
    'textStatus': row.textStatus.name,
    if (row.isPdf) 'pdf': true,
    'source': ?row.source,
  };
}

String _keyKind(String filePath) {
  if (filePath.startsWith('uid:')) return 'user';
  if (filePath.startsWith('ext:')) return 'external';
  if (filePath.startsWith('db:')) return 'attached';
  return 'path';
}
