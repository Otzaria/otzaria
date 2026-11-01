import 'package:otzaria/navigation/bloc/navigation_state.dart';
import 'package:otzaria/plugins/bloc/plugin_system_state.dart';
import 'package:otzaria/plugins/models/installed_plugin.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/search/search_query_builder.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/combined_tab.dart';
import 'package:otzaria/tabs/models/commentators_tab.dart';
import 'package:otzaria/tabs/models/pdf_commentators_tab.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/tabs/models/searching_tab.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/tabs/models/tool_tab.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';

/// מה החלון מציג: מסך, כרטיסייה נוכחית, ספירה לפי סוג ותוספים גלויים.
/// משמש את רשומות ה-context של אבחון המפתחים ואת הדיווח על התוכנה.
Map<String, Object?> describeAppContext({
  required Screen screen,
  required TabsState tabs,
  required PluginSystemState pluginState,
}) {
  final current = tabs.currentTab;
  final tabsByType = <String, int>{};
  for (final tab in tabs.tabs) {
    tabsByType.update(
      tab.runtimeType.toString(),
      (count) => count + 1,
      ifAbsent: () => 1,
    );
  }
  final readers = current == null
      ? const <Map<String, Object?>>[]
      : _readersContextOrError(current);
  return {
    'screen': screen.name,
    'tabs': tabs.tabs.length,
    'tabsByType': tabsByType,
    'currentTab': current?.runtimeType.toString(),
    'currentTitle': current == null || leafPanes(current).any(_isPrivateTitle)
        ? null
        : current.title,
    'plugins': [
      for (final id in {
        for (final key in ToolTab.visiblePluginInstancesOf(current))
          key.pluginId,
      })
        _pluginContext(id, pluginState),
    ],
    if (readers.isNotEmpty) 'readers': readers,
  };
}

/// כשל כאן לא יפיל את שאר ההקשר; הודעת השגיאה עלולה להכיל טקסט, ולכן רק הסוג.
List<Map<String, Object?>> _readersContextOrError(OpenedTab current) {
  try {
    return _readersContext(current);
  } catch (error) {
    return [
      {'error': error.runtimeType.toString()},
    ];
  }
}

/// מצב הקורא והחיפוש שבספר, בלי טקסט השאילתה ובלי טקסט הספר.
List<Map<String, Object?>> _readersContext(OpenedTab current) => [
  for (final pane in leafPanes(current))
    if (pane is TextBookTab)
      _textReaderContext(pane.blocState)
    else if (pane is PdfBookTab)
      {
        'kind': 'pdf',
        ..._searchContext(
          query: pane.searchText,
          mode: pane.searchMode,
          distance: pane.searchDistance,
          origin: pane.searchOrigin,
          policy: pane.matchPolicy,
          options: pane.searchOptions,
          alternativeWords: pane.alternativeWords,
          spacing: pane.spacingValues,
        ),
      },
];

Map<String, Object?> _textReaderContext(TextBookState state) {
  if (state is TextBookInitial) {
    return {
      'kind': 'text',
      'state': 'initial',
      'view': _viewName(
        pageShape: state.showPageShapeView,
        split: state.splitedView,
      ),
      ..._searchContext(
        query: state.searchText,
        mode: state.searchMode,
        distance: state.searchDistance,
        origin: state.searchOrigin,
        policy: state.matchPolicy,
        options: state.searchOptions,
        alternativeWords: state.alternativeWords,
        spacing: state.spacingValues,
      ),
    };
  }
  if (state is! TextBookLoaded) {
    return {'kind': 'text', 'state': state.runtimeType.toString()};
  }
  return {
    'kind': 'text',
    'state': 'loaded',
    'view': _viewName(
      pageShape: state.showPageShapeView,
      split: state.showSplitView,
    ),
    'continuousReading': state.continuousReadingMode,
    'commentators': state.activeCommentators.length,
    'lines': state.content.length,
    'maxLineChars': _maxLineChars(state.content),
    'partiallyLoaded': state.loadedLineFlags != null,
    'highlightLine': state.highlightText.isNotEmpty,
    'pinpointHighlight': state.pinpointHighlightText?.isNotEmpty ?? false,
    ..._searchContext(
      query: state.searchText,
      mode: state.searchMode,
      distance: state.searchDistance,
      origin: state.searchOrigin,
      policy: state.matchPolicy,
      options: state.searchOptions,
      alternativeWords: state.alternativeWords,
      spacing: state.spacingValues,
      wholeWord: state.searchWholeWord,
      resultLines: state.searchResultLines?.length,
    ),
  };
}

String _viewName({required bool pageShape, required bool split}) =>
    pageShape ? 'pageShape' : (split ? 'split' : 'below');

/// שורה ארוכה מייקרת את ההדגשה; שורה שטרם נטענה היא מחרוזת ריקה.
int _maxLineChars(List<String> content) =>
    content.fold(0, (max, line) => line.length > max ? line.length : max);

/// מפתחות האפשרויות פר-מילה מכילים את המילה, ולכן נספרות רק שמות האפשרויות.
Map<String, Object?> _searchContext({
  required String query,
  required SearchMode mode,
  required int distance,
  required InBookSearchOrigin origin,
  required SearchMatchPolicy policy,
  required Map<String, Map<String, bool>> options,
  required Map<int, List<String>> alternativeWords,
  required Map<String, String> spacing,
  bool? wholeWord,
  int? resultLines,
}) {
  if (query.isEmpty) return const {'searchActive': false};
  final trimmed = query.trim();
  final wordOptions = <String, int>{};
  for (final perWord in options.values) {
    for (final option in perWord.entries) {
      if (!option.value) continue;
      final id =
          SearchQueryBuilder.pluginOptionIdByWordOptionKey[option.key] ??
          'other';
      wordOptions.update(id, (count) => count + 1, ifAbsent: () => 1);
    }
  }
  return {
    'searchActive': true,
    'search': {
      'mode': mode.name,
      'origin': origin.name,
      'distance': distance,
      'queryChars': query.length,
      'queryWords': trimmed.isEmpty ? 0 : trimmed.split(RegExp(r'\s+')).length,
      'slashWrapped':
          trimmed.length > 2 &&
          trimmed.startsWith('/') &&
          trimmed.endsWith('/'),
      'hasQuotes': query.contains('"') || query.contains('״'),
      'wholeWord': ?wholeWord,
      'wordOptions': wordOptions,
      'alternativeWords': alternativeWords.values.fold<int>(
        0,
        (sum, words) => sum + words.length,
      ),
      'customSpacing': spacing.values
          .where((value) => value.trim().isNotEmpty)
          .length,
      'matchPolicy': policy.toJson(),
      'resultLines': ?resultLines,
    },
  };
}

/// כותרת חיפוש היא השאילתה, וכותרת ספר אישי היא לרוב שם הקובץ.
bool _isPrivateTitle(OpenedTab pane) =>
    pane is SearchingTab ||
    (pane is CommentatorsTab && _isPrivateTitle(pane.sourceTab)) ||
    (pane is PdfCommentatorsTab && _isPrivateTitle(pane.sourceTab)) ||
    (pane is PdfBookTab && pane.book.isUserBook) ||
    (pane is TextBookTab && pane.book.isUserBook);

Map<String, Object?> _pluginContext(String pluginId, PluginSystemState state) {
  final plugins = state is PluginSystemLoaded
      ? state.plugins
      : const <InstalledPlugin>[];
  for (final plugin in plugins) {
    if (plugin.pluginId != pluginId) continue;
    return {
      'id': pluginId,
      'version': plugin.version,
      'source': plugin.sourceType,
      'enabled': plugin.enabled,
    };
  }
  return {'id': pluginId};
}
