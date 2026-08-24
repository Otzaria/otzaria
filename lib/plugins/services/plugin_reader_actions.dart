import 'package:otzaria/history/bloc/history_event.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/navigation/bloc/navigation_event.dart';
import 'package:otzaria/navigation/bloc/navigation_state.dart';
import 'package:otzaria/plugins/bridge/plugin_search_api.dart';
import 'package:otzaria/plugins/declarative/services/declarative_host_action_executor.dart';
import 'package:otzaria/plugins/services/plugin_ref_line_resolver.dart';
import 'package:otzaria/search/bloc/search_event.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/search/search_defaults.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/tabs/models/searching_tab.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/utils/navigation/book_open_coordinator.dart';
import 'package:otzaria/utils/text/text_manipulation.dart';

/// פותח כרטיסיית חיפוש מובנית עם שאילתה — המסלול המשותף ל-`reader.openSearchTab`
/// בגשר ולפקודה הדקלרטיבית `search.open`.
bool openPluginSearchTab({
  required BookOpenCoordinator coordinator,
  required String query,
  required bool autoSearch,
  PluginOpenSearchTabSettings? settings,
  Map<String, bool> pluginSearchSelections = const {},
}) {
  final resolved =
      settings ?? PluginOpenSearchTabSettings.parse(null, query: query);
  final tab = SearchingTab(
    SearchingTab.titleForQuery(query),
    query,
    initialConfiguration: SearchDefaults.withResultPreferences(
      SearchConfiguration(
        searchMode: resolved.searchMode,
        distance: resolved.distance,
        proximityScope: resolved.proximityScope,
        wordMatchMode: resolved.wordMatchMode,
        wordMatchCount: resolved.wordMatchCount,
        pluginSearchSelections: pluginSearchSelections,
      ),
    ),
    autoRunInitialSearch: autoSearch,
  );
  // אפשרויות פר-מילה נשמרות בטאב (לתצוגה ב-UI ולחיפוש ידני), ומועברות גם
  // להרצה האוטומטית כדי שלא תרוץ ללא 'קידומות' וכד'.
  tab.searchOptions.addAll(resolved.searchOptions);
  if (resolved.searchOptions.isNotEmpty) {
    tab.useGlobalSearchOptions.value = false;
  }
  if (autoSearch) {
    tab.searchBloc.add(
      UpdateSearchQuery(query, searchOptions: resolved.searchOptions),
    );
  }
  coordinator.historyBloc.add(AddHistory(tab));
  coordinator.tabsBloc.add(AddTab(tab));
  coordinator.navigationBloc.add(const NavigateToScreen(Screen.search));
  return true;
}

/// גלילת חלונית הקריאה **הפעילה** לקטע, בלי לפתוח את הספר מחדש.
class PluginReaderScrollService {
  final TabsBloc tabsBloc;

  const PluginReaderScrollService(this.tabsBloc);

  /// ב-PDF [sectionIndex] הוא מספר העמוד (מבוסס-1), כמו `currentIndex`
  /// ב-`reader.getCurrentState`; בספר טקסט זהו אינדקס השורה (מבוסס-0).
  bool scrollToSection(int sectionIndex, {bool highlight = false}) {
    if (sectionIndex < 0) return false;
    final pane = tabsBloc.state.readingPane;
    if (pane is TextBookTab) {
      pane.bloc.add(
        ApplyMarkHighlight(
          permanentHighlightLine: highlight ? sectionIndex : null,
          scrollToIndex: sectionIndex,
        ),
      );
      return true;
    }
    if (pane is PdfBookTab) {
      final controller = pane.pdfViewerController;
      if (!controller.isReady) return false;
      controller.goToPage(pageNumber: sectionIndex < 1 ? 1 : sectionIndex);
      return true;
    }
    return false;
  }
}

/// פותר הפניה מול הספר הפתוח וגולל אליה — מימוש `reader.scrollToRef`
/// של המנוע הדקלרטיבי.
class PluginDeclarativeReaderScroller implements DeclarativeReaderScroller {
  final TabsBloc tabsBloc;
  final PluginReaderScrollService _scroller;
  final PluginRefLineResolver _refResolver;

  PluginDeclarativeReaderScroller({
    required this.tabsBloc,
    PluginReaderScrollService? scroller,
    PluginRefLineResolver? refResolver,
  }) : _scroller = scroller ?? PluginReaderScrollService(tabsBloc),
       _refResolver = refResolver ?? PluginRefLineResolver();

  @override
  Future<bool> scrollToRef(String ref, {bool highlight = false}) async {
    final trimmed = ref.trim();
    if (trimmed.isEmpty) return false;
    final pane = tabsBloc.state.readingPane;
    if (pane is! TextBookTab) return false;
    final index = await _resolveIndex(pane.book, trimmed);
    if (index == null) return false;
    return _scroller.scrollToSection(index, highlight: highlight);
  }

  /// אותם שני מסלולים של `reader.openBookAtRef`: רזולוציה לרמת שורה דרך
  /// ה-heRef, ואם אין התאמה — התאמת TOC מקומית (בעיקר לבבלי).
  Future<int?> _resolveIndex(TextBook book, String ref) async {
    try {
      final lineIndex = await _refResolver.resolve(book: book, ref: ref);
      if (lineIndex != null) return lineIndex;
    } catch (_) {}
    try {
      final toc = flattenToc(await book.tableOfContents);
      for (final entry in toc) {
        if (tocTextMatchesRef(entry.text, ref)) return entry.index;
      }
    } catch (_) {}
    return null;
  }
}

/// מימוש `search.open` של המנוע הדקלרטיבי.
class PluginDeclarativeSearchOpener implements DeclarativeSearchOpener {
  final BookOpenCoordinator coordinator;

  const PluginDeclarativeSearchOpener(this.coordinator);

  @override
  Future<bool> openSearch(String query, {bool autoSearch = true}) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return false;
    return openPluginSearchTab(
      coordinator: coordinator,
      query: trimmed,
      autoSearch: autoSearch,
    );
  }
}
