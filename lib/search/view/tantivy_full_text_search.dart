import 'package:flutter/material.dart';
import 'package:otzaria/theme/app_tokens.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/widgets/navigation/app_top_bar.dart';
import 'package:otzaria/search/utils/facet_helper.dart';
import 'package:otzaria/search/bloc/search_bloc.dart';
import 'package:otzaria/search/bloc/search_event.dart';
import 'package:otzaria/search/bloc/search_state.dart';
import 'package:otzaria/search/models/external_search_status.dart';
import 'package:otzaria/tabs/models/searching_tab.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_state.dart';
import 'package:otzaria/core/focus_repository.dart';
import 'package:otzaria/history/bloc/history_bloc.dart';
import 'package:otzaria/history/bloc/history_event.dart';
import 'package:otzaria/search/search_query_builder.dart';
import 'package:otzaria/search/view/full_text_settings_widgets.dart';
import 'package:otzaria/search/view/tantivy_search_results.dart';
import 'package:otzaria/search/view/full_text_facet_filtering.dart';
import 'package:otzaria/search/view/layout_fix_suggestion_banner.dart';
import 'package:otzaria/search/view/search_dialog.dart';
import 'package:otzaria/search/view/search_results_layout.dart';
import 'package:otzaria/widgets/feedback/indexing_warning.dart';

class TantivyFullTextSearch extends StatefulWidget {
  final SearchingTab tab;
  const TantivyFullTextSearch({super.key, required this.tab});
  @override
  State<TantivyFullTextSearch> createState() => _TantivyFullTextSearchState();
}

/// קובע אם להציג את באנר סינון הקטגוריות.
///
/// מחזיר `true` רק כשהחיפוש הוגבל *מראש* לקטגוריות מסוימות — כלומר כש-
/// [searchScopeFacets] מכיל קטגוריה שאינה השורש. סינון זמני שנבחר בעץ
/// התוצאות (currentFacets) אינו מפעיל את הבאנר. הפאסט `'/'` (שורש = כל
/// הספרייה) מנורמל החוצה, כך ש-`['/']` ו-`[]` נחשבים "ללא הגבלה" ולא
/// מציגים באנר מיותר.
@visibleForTesting
bool shouldShowFacetFilterBanner({
  required String searchQuery,
  required List<String> searchScopeFacets,
}) {
  if (searchQuery.isEmpty) {
    return false;
  }

  // facets ממדיים (/base, /era/, /author/) אינם הגבלת קטגוריה — סינון
  // ממדי בלבד לא מציג באנר "מסונן לפי קטגוריה" מטעה (החיווי שלו הוא
  // המונה בכותרת חלונית "תקופה, מחבר וספרי יסוד").
  final normalizedScope = searchScopeFacets.toSet()
    ..removeWhere(
      (facet) => facet == '/' || FacetHelper.isDimensionFacet(facet),
    );

  return normalizedScope.isNotEmpty;
}

/// אירוע הרצת [query] בטאב עם הגדרות החיפוש השמורות בו (חיוביות ושליליות),
/// מנורמלות למצב החיפוש הנוכחי של הטאב.
UpdateSearchQuery searchQueryEventForTab(SearchingTab tab, String query) {
  final searchMode = tab.searchBloc.state.configuration.searchMode;
  final negativeQuery = tab.negativeQueryController.text;
  final positive = SearchQueryBuilder.normalizeParametersForMode(
    searchMode,
    customSpacing: tab.spacingValues,
    alternativeWords: tab.alternativeWords,
    searchOptions: tab.effectiveSearchOptions(query: query),
  );
  final negative = SearchQueryBuilder.normalizeParametersForMode(
    searchMode,
    customSpacing: tab.negativeSpacingValues,
    alternativeWords: tab.negativeAlternativeWords,
    searchOptions: tab.effectiveNegativeSearchOptions(query: negativeQuery),
  );
  return UpdateSearchQuery(
    query,
    negativeQuery: negativeQuery,
    customSpacing: positive.customSpacing,
    alternativeWords: positive.alternativeWords,
    searchOptions: positive.searchOptions,
    negativeCustomSpacing: negative.customSpacing,
    negativeAlternativeWords: negative.alternativeWords,
    negativeSearchOptions: negative.searchOptions,
  );
}

class _TantivyFullTextSearchState extends State<TantivyFullTextSearch>
    with AutomaticKeepAliveClientMixin {
  static const _externalCountLineMaxWidth = 240.0;
  @override
  bool get wantKeepAlive => true;

  bool _indexInProgressWarningDismissed = false;
  // חיווי הגבלת ה-scope ניתן להסתרה ידנית. ההסתרה היא ויזואלית בלבד (אינה
  // משנה את החיפוש) ומתאפסת בחיפוש חדש או בשינוי הטווח — ראה ה-listener ב-build.
  bool _facetBannerDismissed = false;
  final FocusNode _contentFocusNode = FocusNode(
    debugLabel: 'search_tab_content',
    skipTraversal: true,
  );

  @override
  void dispose() {
    _contentFocusNode.dispose();
    super.dispose();
  }

  /// המשתמש לחץ על הצעת תיקון-המקלדת: מריצים חיפוש חדש של הטקסט המומר,
  /// כאילו הוקלד ונשלח ידנית (עדכון שדה, כותרת והיסטוריה). אפשרויות
  /// פר-מילה של השאילתה הקודמת לא רלוונטיות למילים החדשות — מתחילים נקי.
  /// זו הפעולה היחידה שמחליפה את השאילתה, והיא תמיד ביוזמת המשתמש.
  void _acceptLayoutFixSuggestion(String suggestion) {
    widget.tab.queryController.value = TextEditingValue(
      text: suggestion,
      selection: TextSelection.collapsed(offset: suggestion.length),
    );
    widget.tab.searchOptions.clear();
    widget.tab.alternativeWords.clear();
    widget.tab.spacingValues.clear();
    widget.tab.updateTitleFromAppliedQuery(suggestion);
    context.read<HistoryBloc>().add(AddHistory(widget.tab));

    widget.tab.searchBloc.add(searchQueryEventForTab(widget.tab, suggestion));
  }

  void _openEditDialog() {
    showDialog(
      context: context,
      builder: (_) => SearchDialog(editTab: widget.tab),
    );
  }

  Widget _buildIndexingWarning() {
    return IndexingWarningContainer(
      inProgressDismissed: _indexInProgressWarningDismissed,
      onDismiss: () => setState(() => _indexInProgressWarningDismissed = true),
    );
  }

  bool _shouldShowFacetFilterBanner(SearchState state) =>
      !_facetBannerDismissed &&
      shouldShowFacetFilterBanner(
        searchQuery: state.searchQuery,
        searchScopeFacets: state.searchScopeFacets,
      );

  /// השוואת טווחי-חיפוש ללא תלות בסדר — לזיהוי שינוי scope לצורך איפוס
  /// ההסתרה הידנית של החיווי. הפאסט `'/'` מנורמל החוצה כמו בלוגיקת ההצגה
  /// ([shouldShowFacetFilterBanner]), כך ש-`['/', '/תנ"ך']` ו-`['/תנ"ך']`
  /// נחשבים שקולים ולא מאפסים את ההסתרה לשווא.
  bool _sameFacetScope(List<String> a, List<String> b) {
    final setA = a.toSet()..removeWhere((facet) => facet == '/');
    final setB = b.toSet()..removeWhere((facet) => facet == '/');
    return setA.length == setB.length && setA.containsAll(setB);
  }

  @override
  void initState() {
    super.initState();

    // Request focus on search field when the widget is first created
    _requestSearchFieldFocus();

    // הפעל חיפוש ממתין - רק כשהטאב מוצג לראשונה (לא בפתיחת האפליקציה),
    // ורק אם לא סומן autoRunInitialSearch=false (תוסף שפתח טאב עם טקסט
    // בלי להריץ חיפוש — המשתמש מריץ ידנית).
    // חשוב להעביר גם את ה-customSpacing/alternativeWords/searchOptions
    // שנשמרו ב-tab, אחרת חיפוש משוחזר (מ-fromJson) ירוץ ללא 'חלק ממילה'
    // ושאר אפשרויות פר-מילה, ויחזיר 0 תוצאות גם כשהשאילתה תקפה.
    final pendingQuery = widget.tab.queryController.text.trim();
    if (widget.tab.autoRunInitialSearch &&
        pendingQuery.isNotEmpty &&
        widget.tab.searchBloc.state.searchQuery.isEmpty) {
      widget.tab.searchBloc.add(
        searchQueryEventForTab(widget.tab, pendingQuery),
      );
    }
  }

  @override
  void didUpdateWidget(TantivyFullTextSearch oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Request focus when switching back to this tab
    _requestSearchFieldFocus();
  }

  /// האם זו החלונית שהמשתמש עובד בה. חלונית שאינה פעילה אסור לה לתפוס את
  /// שדה החיפוש, אחרת חיצים ורווח מוקלדים לשדה במקום לגלול את הספר שנקרא.
  bool _isTabDisplayed(TabsState state) {
    if (!state.hasOpenTabs || state.currentTabIndex >= state.tabs.length) {
      return false;
    }
    return identical(state.activePane, widget.tab);
  }

  /// שדה החיפוש מוצג רק בדיאלוג, ואז ממקדים את תוכן הטאב. בלי פוקוס בתוכנה
  /// המקלדת נשארת ב-WebView של תוסף שעזבו, וקיצורי התוכנה מתים (issue #1349).
  void _focusTabContent() {
    final field = widget.tab.searchFieldFocusNode;
    if (field.enclosingScope != null && field.canRequestFocus) {
      field.requestFocus();
    } else if (!_contentFocusNode.hasFocus) {
      _contentFocusNode.requestFocus();
    }
  }

  void _requestSearchFieldFocus() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_isTabDisplayed(context.read<TabsBloc>().state)) return;
      _focusTabContent();
      // Register as screen-level restorer so window events restore focus here
      FocusRepository().setScreenRestorer(
        restore: () {
          if (mounted) _focusTabContent();
        },
        canRestore: () =>
            mounted && _isTabDisplayed(context.read<TabsBloc>().state),
      );
    });
  }

  void _onNavigationChanged(NavigationState state) {
    // Request focus when navigating to search screen
    if (state.currentScreen == Screen.search ||
        state.currentScreen == Screen.reading) {
      _requestSearchFieldFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    // אותו child מונע מפעימות ההורה לעקוף את buildWhen של עץ הסינון.
    final facetPane = SearchFacetFiltering(tab: widget.tab);
    return BlocListener<NavigationBloc, NavigationState>(
      listener: (context, state) => _onNavigationChanged(state),
      child: BlocListener<SearchBloc, SearchState>(
        // חיפוש חדש (שינוי שאילתה) או שינוי טווח → מציגים שוב חיווי שהוסתר ידנית.
        listenWhen: (previous, current) =>
            previous.searchQuery != current.searchQuery ||
            !_sameFacetScope(
              previous.searchScopeFacets,
              current.searchScopeFacets,
            ),
        listener: (context, state) {
          if (_facetBannerDismissed) {
            setState(() => _facetBannerDismissed = false);
          }
        },
        child: Focus(
          focusNode: _contentFocusNode,
          child: Scaffold(
            body: BlocBuilder<SearchBloc, SearchState>(
              builder: (context, state) => SearchResultsLayout(
                tab: widget.tab,
                hasQuery: state.searchQuery.isNotEmpty,
                onEditSearch: _openEditDialog,
                header: _buildIndexingWarning(),
                countsBuilder: (context, collapsed) =>
                    _buildResultCounts(context, state, collapsed: collapsed),
                extraTrailingItems: _buildTrailingControls,
                banners: [
                  if (_shouldShowFacetFilterBanner(state))
                    _buildFacetFilterBanner(context, state),
                  // הצעת תיקון להקלדה עברית במצב מקלדת אנגלי (issue #975).
                  // הטקסט הגולמי מהשדה ולא state.searchQuery — הנרמול מוחק
                  // פסיק/נקודה שהם המקשים של ת/ץ, וההצעה הייתה יוצאת חסרה.
                  if (state.searchQuery.isNotEmpty)
                    LayoutFixSuggestionBanner(
                      query: widget.tab.queryController.text,
                      hint: 'לחיצה תריץ את החיפוש המוצע',
                      onAccept: _acceptLayoutFixSuggestion,
                    ),
                ],
                // כל מצבי אזור התוצאות (ריק/טעינה/שגיאה/תוצאות) מרונדרים בתוך
                // TantivySearchResults, כולל תוצאות הספק החיצוני כשהוא פעיל.
                resultsBuilder: (showPreviewPane) => TantivySearchResults(
                  tab: widget.tab,
                  onEditSearch: _openEditDialog,
                  showPreviewPane: showPreviewPane,
                ),
                facetPane: facetPane,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// מוני התוצאות בשורת הפקדים: ספירת המנוע, ומתחתיה — כשספק חיצוני פעיל —
  /// ספירת המקור החיצוני (ספרים ומופעים). שתי הספירות שונות במהותן (תוצאות
  /// מול ספרים), ולכן מוצגות שורה מעל שורה באותו מקום במקום מספר מאוחד.
  ///
  /// שורת המקור החיצוני נושאת גם את חיווי ההתקדמות בזמן החיפוש. כך הספירות
  /// של שני המקורות יושבות זו מעל זו במקום אחד, ואזור התוצאות מציג תוצאות
  /// בלבד.
  Widget _buildResultCounts(
    BuildContext context,
    SearchState state, {
    required bool collapsed,
  }) {
    final cs = Theme.of(context).colorScheme;
    final muted = TextStyle(fontSize: 14, color: cs.onSurfaceVariant);
    final engineLine = state.totalGroups != null
        ? '${state.results.length}/${state.totalGroups} תוצאות מאוחדות (מתוך ${state.totalResults})'
        : '${state.results.length}/${state.totalResults} תוצאות';
    final compactEngineLine =
        '${state.results.length}/${state.totalGroups ?? state.totalResults}';
    return ValueListenableBuilder<ExternalSearchStatus?>(
      valueListenable: widget.tab.externalSearchStatus,
      builder: (context, status, _) {
        if (status == null) {
          final text = Text(
            collapsed ? compactEngineLine : engineLine,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: muted,
          );
          return collapsed ? Tooltip(message: engineLine, child: text) : text;
        }
        // הבלוק כולו תחום ברוחב — הסרגל אינו יכול להתרחב בשבילו, ובלי
        // הגבלה שתי השורות חופפות את שאר פריטי הסרגל (issue #1051).
        return ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: _externalCountLineMaxWidth,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Tooltip(
                message: 'אוצריא: $engineLine',
                child: Text(
                  'אוצריא: ${collapsed ? compactEngineLine : engineLine}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: muted.copyWith(fontSize: 12),
                ),
              ),
              _buildExternalCountLine(context, status, muted),
            ],
          ),
        );
      },
    );
  }

  Widget _buildExternalCountLine(
    BuildContext context,
    ExternalSearchStatus status,
    TextStyle muted,
  ) {
    final style = muted.copyWith(fontSize: 12);
    final filteredNote = status.ofTotalBooks != null
        ? ' (מתוך ${status.ofTotalBooks})'
        : '';
    final books = status.books == 1 ? 'ספר אחד' : '${status.books} ספרים';
    final hits = status.hits == 1 ? 'מופע אחד' : '${status.hits} מופעים';
    final line = status.failed
        ? '${status.sourceTitle}: החיפוש נכשל'
        : status.isPending
        ? '${status.sourceTitle}: מחפש…'
        : '${status.sourceTitle}: $books$filteredNote, $hits';
    // הרוחב תחום אצל הקורא — הבלוק כולו עטוף ב-ConstrainedBox.
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(
            line,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: style,
          ),
        ),
        if (status.loading) ...[
          const SizedBox(width: 6),
          SizedBox(
            width: 10,
            height: 10,
            child: CircularProgressIndicator(
              strokeWidth: 1.5,
              color: style.color,
            ),
          ),
        ],
      ],
    );
  }

  /// באנר שמראה שהחיפוש הוגבל מראש לקטגוריות מסוימות (scope).
  /// מוצג רק כשהוגדר טווח מראש; כפתור ה-X מסתיר אותו ויזואלית בלבד.
  Widget _buildFacetFilterBanner(BuildContext context, SearchState state) {
    final cs = Theme.of(context).colorScheme;
    final facetNames = state.searchScopeFacets
        // facets ממדיים (/era/, /author/, /base) אינם קטגוריות — לא
        // נכללים ברשימת "חיפוש בקטגוריות" (כמו בתנאי ההצגה של הבאנר).
        .where((facet) => facet != '/' && !FacetHelper.isDimensionFacet(facet))
        .map((facet) {
          // facet בפורמט "/תנ"ך" או "/תנ"ך/ראשונים" - ניקח את החלק האחרון
          final parts = facet.split('/').where((p) => p.isNotEmpty).toList();
          return parts.isNotEmpty ? parts.last : facet;
        })
        .toList();
    final tooltipMessage = 'חיפוש בקטגוריות: ${facetNames.join(', ')}';
    const bannerTitle = 'החיפוש הוגבל לקטגוריות מסוימות';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0),
      color: cs.primaryContainer.withValues(alpha: 0.4),
      child: Row(
        children: [
          Icon(
            FluentIcons.filter_24_regular,
            size: 16,
            color: cs.primary,
          ),
          const SizedBox(width: 8),
          Text(
            bannerTitle,
            style: TextStyle(
              fontSize: 13,
              color: cs.primary,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 6),
          Tooltip(
            message: tooltipMessage,
            waitDuration: const Duration(milliseconds: 250),
            showDuration: const Duration(seconds: 4),
            preferBelow: false,
            verticalOffset: 18,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            margin: const EdgeInsets.symmetric(horizontal: 24),
            constraints: const BoxConstraints(maxWidth: 360),
            textStyle: TextStyle(
              fontSize: 13,
              height: 1.4,
              color: cs.onSurface,
            ),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: AppTokens.borderRadiusAll,
              border: Border.all(
                color: cs.outlineVariant.withValues(alpha: 0.55),
              ),
              boxShadow: [
                BoxShadow(
                  color: cs.shadow.withValues(alpha: 0.16),
                  blurRadius: 14,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Icon(
              FluentIcons.info_24_regular,
              size: 16,
              color: cs.primary,
            ),
          ),
          const Spacer(),
          // כפתור הסתרה - מסתיר את החיווי בלבד, ללא שינוי בחיפוש או בטווח.
          IconButton(
            icon: Icon(
              FluentIcons.dismiss_24_regular,
              size: 16,
              color: cs.primary,
            ),
            tooltip: 'הסתר הודעה זו',
            onPressed: () => setState(() => _facetBannerDismissed = true),
            constraints: const BoxConstraints(),
            padding: const EdgeInsets.all(4),
          ),
        ],
      ),
    );
  }

  /// בוררי המיון, האיחוד ומיקום התוצאות החיצוניות שבסוף הסרגל.
  List<AppTopBarItem> _buildTrailingControls(bool collapseMenus) => [
    AppTopBarItem(
      dividerBefore: true,
      widget: SearchResultsLayout.animatedBarControl(
        collapsed: collapseMenus,
        child: OrderOfResults(
          widget: TantivySearchResults(tab: widget.tab),
          iconOnly: collapseMenus,
        ),
      ),
    ),
    AppTopBarItem(
      widget: SearchResultsLayout.animatedBarControl(
        collapsed: collapseMenus,
        child: GroupingOfResults(iconOnly: collapseMenus),
      ),
    ),
    AppTopBarItem(
      widget: SearchResultsLayout.animatedBarControl(
        collapsed: collapseMenus,
        child: ExternalResultsPositionControl(
          tab: widget.tab,
          compact: collapseMenus,
        ),
      ),
    ),
  ];
}
