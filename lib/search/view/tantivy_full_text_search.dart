import 'package:flutter/material.dart';
import 'package:otzaria/theme/app_tokens.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/widgets/navigation/app_top_bar.dart';
import 'package:otzaria/settings/settings_exports.dart';
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
import 'package:otzaria/search/search_query_builder.dart';
import 'package:otzaria/search/view/full_text_settings_widgets.dart';
import 'package:otzaria/search/view/tantivy_search_results.dart';
import 'package:otzaria/search/view/full_text_facet_filtering.dart';
import 'package:otzaria/search/view/search_dialog.dart';
import 'package:otzaria/widgets/controls/bar_button.dart';
import 'package:otzaria/widgets/navigation/nav_panel_search.dart';
import 'package:otzaria/widgets/navigation/nav_side_panel.dart';
import 'package:otzaria/widgets/text/otzaria_search_field.dart';
import 'package:otzaria/widgets/feedback/indexing_warning.dart';

/// רוחב הסרגל שמתחתיו בוררי המיון והאיחוד מתכווצים לכפתורי אייקון.
/// הבדיקה היא על רוחב הסרגל עצמו (ולא על גודל החלון), כדי שהכיווץ יקרה
/// בדיוק כשאין מקום לשני ה-dropdown ברוחב מלא.
const double _kMenusCollapseWidth = 900;

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

class _TantivyFullTextSearchState extends State<TantivyFullTextSearch>
    with AutomaticKeepAliveClientMixin {
  static const _externalCountLineMaxWidth = 240.0;
  @override
  bool get wantKeepAlive => true;

  bool _indexInProgressWarningDismissed = false;
  // חיווי הגבלת ה-scope ניתן להסתרה ידנית. ההסתרה היא ויזואלית בלבד (אינה
  // משנה את החיפוש) ומתאפסת בחיפוש חדש או בשינוי הטווח — ראה ה-listener ב-build.
  bool _facetBannerDismissed = false;
  // במסך צר עץ הקטגוריות תופס את כל הרוחב ומסתיר את התוצאות. לכן בכניסה
  // הראשונה לכל טאב במסך צר סוגרים את העץ אוטומטית; המשתמש עדיין יכול
  // לפתוח אותו ידנית, וזה לא משפיע על מסכים רחבים שבהם השניים מוצגים זה
  // לצד זה.
  bool _appliedNarrowLeftPaneDefault = false;
  // רוחב חי של פאנל הסינון בזמן גרירה; נשמר להגדרות ב-onPaneResizeEnd.
  double? _facetPaneWidthOverride;

  /// פעולת החיפוש של חלונית הסינון — מוזנת לסרגל שבסרגל העליון.
  final NavPanelSearchHost _searchHost = NavPanelSearchHost();

  @override
  void dispose() {
    _searchHost.dispose();
    super.dispose();
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
      final searchMode = widget.tab.searchBloc.state.configuration.searchMode;
      final normalizedParameters =
          SearchQueryBuilder.normalizeParametersForMode(
            searchMode,
            customSpacing: widget.tab.spacingValues,
            alternativeWords: widget.tab.alternativeWords,
            searchOptions: widget.tab.effectiveSearchOptions(
              query: pendingQuery,
            ),
          );
      final negativeQuery = widget.tab.negativeQueryController.text;
      final normalizedNegativeParameters =
          SearchQueryBuilder.normalizeParametersForMode(
            searchMode,
            customSpacing: widget.tab.negativeSpacingValues,
            alternativeWords: widget.tab.negativeAlternativeWords,
            searchOptions: widget.tab.effectiveNegativeSearchOptions(
              query: negativeQuery,
            ),
          );
      widget.tab.searchBloc.add(
        UpdateSearchQuery(
          pendingQuery,
          negativeQuery: negativeQuery,
          customSpacing: normalizedParameters.customSpacing,
          alternativeWords: normalizedParameters.alternativeWords,
          searchOptions: normalizedParameters.searchOptions,
          negativeCustomSpacing: normalizedNegativeParameters.customSpacing,
          negativeAlternativeWords:
              normalizedNegativeParameters.alternativeWords,
          negativeSearchOptions: normalizedNegativeParameters.searchOptions,
        ),
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

  void _requestSearchFieldFocus() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.tab.searchFieldFocusNode.canRequestFocus) {
        // Check if this tab is the currently selected tab
        final tabsState = context.read<TabsBloc>().state;
        if (_isTabDisplayed(tabsState)) {
          widget.tab.searchFieldFocusNode.requestFocus();
          // Register as screen-level restorer so window events restore focus here
          FocusRepository().setScreenRestorer(
            restore: () {
              if (mounted && widget.tab.searchFieldFocusNode.canRequestFocus) {
                widget.tab.searchFieldFocusNode.requestFocus();
              }
            },
            canRestore: () {
              if (!mounted ||
                  !widget.tab.searchFieldFocusNode.canRequestFocus) {
                return false;
              }
              return _isTabDisplayed(context.read<TabsBloc>().state);
            },
          );
        }
      }
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
        child: Scaffold(
          body: LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 800;
              // במסך צר, בכניסה הראשונה של הטאב, סוגרים את עץ הקטגוריות
              // כדי שהתוצאות יוצגו ולא יוסתרו ע"י העץ ברוחב מלא.
              if (isNarrow &&
                  !_appliedNarrowLeftPaneDefault &&
                  widget.tab.isLeftPaneOpen.value) {
                _appliedNarrowLeftPaneDefault = true;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) widget.tab.isLeftPaneOpen.value = false;
                });
              }
              final collapseMenus = constraints.maxWidth < _kMenusCollapseWidth;
              if (isNarrow) return _buildForSmallScreens(collapseMenus);
              return _buildForWideScreens(collapseMenus);
            },
          ),
        ),
      ),
    );
  }

  Widget _buildForSmallScreens(bool collapseMenus) {
    return BlocBuilder<SearchBloc, SearchState>(
      builder: (context, state) {
        return Container(
          clipBehavior: Clip.hardEdge,
          decoration: const BoxDecoration(),
          child: Column(
            children: [
              _buildIndexingWarning(),
              _buildSearchTopBar(state, collapseMenus: collapseMenus),
              // חיווי סינון קטגוריות
              if (_shouldShowFacetFilterBanner(state))
                _buildFacetFilterBanner(context, state),
              Expanded(
                child: Stack(
                  children: [
                    // כל מצבי אזור התוצאות (ריק/טעינה/שגיאה/תוצאות) מרונדרים
                    // בתוך TantivySearchResults — רשימה מאוחדת אחת שמכילה גם
                    // את תוצאות הספק החיצוני כשהוא פעיל.
                    Container(
                      clipBehavior: Clip.hardEdge,
                      decoration: const BoxDecoration(),
                      child: TantivySearchResults(
                        tab: widget.tab,
                        onEditSearch: _openEditDialog,
                      ),
                    ),
                    ValueListenableBuilder(
                      valueListenable: widget.tab.isLeftPaneOpen,
                      builder: (context, value, child) => AnimatedSize(
                        duration: const Duration(milliseconds: 300),
                        child: SizedBox(
                          width: value ? 500 : 0,
                          child: Container(
                            color: Theme.of(context).colorScheme.surface,
                            child: Column(
                              children: [
                                Expanded(
                                  child: SearchFacetFiltering(tab: widget.tab),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildForWideScreens(bool collapseMenus) {
    return Column(
      children: [
        _buildIndexingWarning(),
        Expanded(
          child: BlocBuilder<SearchBloc, SearchState>(
            builder: (context, state) {
              return Column(
                children: [
                  _buildSearchTopBar(
                    state,
                    collapseMenus: collapseMenus,
                    showPaneSearchBar: true,
                  ),
                  if (_shouldShowFacetFilterBanner(state))
                    _buildFacetFilterBanner(context, state),
                  Expanded(
                    child: ValueListenableBuilder<bool>(
                      valueListenable: widget.tab.isLeftPaneOpen,
                      builder: (context, isOpen, _) {
                        return BlocBuilder<SettingsBloc, SettingsState>(
                          buildWhen: (p, c) =>
                              p.facetFilteringWidth != c.facetFilteringWidth,
                          builder: (context, settingsState) {
                            final paneWidth =
                                (_facetPaneWidthOverride ??
                                        settingsState.facetFilteringWidth)
                                    .clamp(220.0, 600.0);
                            return NavSidePanel(
                              isOpen: isOpen,
                              alignment: AlignmentDirectional.centerEnd,
                              mainContent: _buildResultsContent(context),
                              paneContent: NavPanelSearchScope(
                                host: _searchHost,
                                child: NavPanelSearchSlot(
                                  index: 0,
                                  child: SearchFacetFiltering(
                                    tab: widget.tab,
                                  ),
                                ),
                              ),
                              paneWidth: paneWidth,
                              minMainContentWidth: 300,
                              onClose: () =>
                                  widget.tab.isLeftPaneOpen.value = false,
                              isResizable: true,
                              minPaneWidth: 220,
                              maxPaneWidth: 600,
                              autoHandleResponsiveVisibility: false,
                              onPaneWidthChanged: (w) =>
                                  _facetPaneWidthOverride = w,
                              onPaneResizeEnd: () {
                                final w = _facetPaneWidthOverride;
                                if (w != null) {
                                  context.read<SettingsBloc>().add(
                                    UpdateFacetFilteringWidth(w),
                                  );
                                }
                              },
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
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
            style: muted,
          );
          return collapsed ? Tooltip(message: engineLine, child: text) : text;
        }
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'אוצריא: ${collapsed ? compactEngineLine : engineLine}',
              style: muted.copyWith(fontSize: 12),
            ),
            _buildExternalCountLine(context, status, muted),
          ],
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
    return ConstrainedBox(
      // כותרת המקור מגיעה מתוסף; הסרגל העליון אינו יכול להתרחב בשבילה.
      constraints: const BoxConstraints(maxWidth: _externalCountLineMaxWidth),
      child: Row(
        children: [
          Expanded(
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
      ),
    );
  }

  /// תוכן אזור התוצאות — רשימה מאוחדת אחת ([TantivySearchResults]) שמכילה
  /// את כל מצבי המנוע (loader / ריק / שגיאה / תוצאות) וגם את תוצאות הספק
  /// החיצוני של תוסף כשהוא פעיל (sliver שמכווץ את עצמו לכלום אחרת).
  Widget _buildResultsContent(BuildContext context) {
    return Container(
      clipBehavior: Clip.hardEdge,
      decoration: const BoxDecoration(),
      child: TantivySearchResults(
        tab: widget.tab,
        onEditSearch: _openEditDialog,
        // חלונית התצוגה המקדימה מוצגת רק בפריסה הרחבה; במסך צר לחיצה
        // אחת ממשיכה לפתוח את התוצאה בעיון.
        showPreviewPane: true,
      ),
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

  /// הסרגל העליון של מסך החיפוש — זהה בכל רוחבי המסך.
  /// [collapseMenus] מכווץ את בוררי המיון והאיחוד לכפתורי אייקון.
  /// [showPaneSearchBar] — רק בפריסה הרחבה, שבה חלונית הסינון היא
  /// [NavSidePanel] ושדה "איתור ספר" עולה לסרגל. בפריסה הצרה החלונית מציירת
  /// אותו בעצמה.
  Widget _buildSearchTopBar(
    SearchState state, {
    required bool collapseMenus,
    bool showPaneSearchBar = false,
  }) {
    final hasQuery = state.searchQuery.isNotEmpty;
    return AppTopBar(
      leadingItems: [
        if (showPaneSearchBar)
          AppTopBarItem(
            widget: ValueListenableBuilder<bool>(
              valueListenable: widget.tab.isLeftPaneOpen,
              builder: (context, isOpen, _) =>
                  BlocBuilder<SettingsBloc, SettingsState>(
                    buildWhen: (p, c) =>
                        p.facetFilteringWidth != c.facetFilteringWidth,
                    builder: (context, settingsState) => NavPanelSearchBar(
                      host: _searchHost,
                      isOpen: isOpen,
                      paneWidth:
                          (_facetPaneWidthOverride ??
                                  settingsState.facetFilteringWidth)
                              .clamp(220.0, 600.0),
                    ),
                  ),
            ),
          ),
        AppTopBarItem(
          widget: ValueListenableBuilder<bool>(
            valueListenable: widget.tab.isLeftPaneOpen,
            builder: (context, isOpen, _) => NavPanelToggleButton(
              isOpen: isOpen,
              onToggle: () => widget.tab.isLeftPaneOpen.value = !isOpen,
            ),
          ),
        ),
      ],
      center: hasQuery ? _buildQueryDisplay(context) : const SizedBox.shrink(),
      trailingItems: hasQuery
          ? [
              AppTopBarItem(
                widget: _buildResultCounts(
                  context,
                  state,
                  collapsed: collapseMenus,
                ),
              ),
              // לחצן העין קיים רק בפריסה הרחבה — שם יש חלונית תצוגה מקדימה.
              if (showPaneSearchBar)
                AppTopBarItem(
                  dividerBefore: true,
                  widget: _buildPreviewToggleButton(),
                ),
              AppTopBarItem(
                dividerBefore: true,
                widget: _animatedBarControl(
                  collapsed: collapseMenus,
                  child: OrderOfResults(
                    widget: TantivySearchResults(tab: widget.tab),
                    iconOnly: collapseMenus,
                  ),
                ),
              ),
              AppTopBarItem(
                widget: _animatedBarControl(
                  collapsed: collapseMenus,
                  child: GroupingOfResults(iconOnly: collapseMenus),
                ),
              ),
              AppTopBarItem(
                widget: _animatedBarControl(
                  collapsed: collapseMenus,
                  child: ExternalResultsPositionControl(
                    tab: widget.tab,
                    compact: collapseMenus,
                  ),
                ),
              ),
            ]
          : const [],
    );
  }

  /// לחצן עין לכיבוי/הפעלה קבועים של התצוגה המקדימה של תוצאות — כמו בספרייה.
  Widget _buildPreviewToggleButton() {
    return BlocBuilder<SettingsBloc, SettingsState>(
      buildWhen: (p, c) =>
          p.searchShowPreview != c.searchShowPreview ||
          p.compactMenuMode != c.compactMenuMode,
      builder: (context, settingsState) {
        final showPreview = settingsState.searchShowPreview;
        return BarButton.icon(
          compact: settingsState.compactMenuMode,
          tooltip: showPreview ? 'הסתר תצוגה מקדימה' : 'הצג תצוגה מקדימה',
          icon: showPreview
              ? FluentIcons.eye_24_filled
              : FluentIcons.eye_24_regular,
          selected: showPreview,
          onPressed: () {
            final next = !showPreview;
            context.read<SettingsBloc>().add(UpdateSearchShowPreview(next));
            if (!next) {
              widget.tab.previewTarget.value = null;
            }
          },
        );
      },
    );
  }

  /// מילות החיפוש בתוך סרגל בעיצוב שדה החיפוש; לחיצה עליו פותחת את דיאלוג
  /// העריכה.
  Widget _buildQueryDisplay(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'חיפוש',
          style: TextStyle(
            fontSize: AppTokens.fontMD,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(width: AppTokens.spaceSM),
        Flexible(
          child: OtzariaSearchDisplayBar(
            icon: FluentIcons.edit_24_regular,
            tooltip: 'ערוך חיפוש',
            onTap: _openEditDialog,
            child: ScrollConfiguration(
              behavior: ScrollConfiguration.of(
                context,
              ).copyWith(scrollbars: false),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SearchTermsDisplay(tab: widget.tab),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// מעבר מונפש בין ה-dropdown המלא לכפתור האייקון המכווץ.
  Widget _animatedBarControl({
    required bool collapsed,
    required Widget child,
  }) {
    return AnimatedSize(
      duration: AppTokens.animNormal,
      curve: Curves.easeInOut,
      child: AnimatedSwitcher(
        duration: AppTokens.animNormal,
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: ScaleTransition(scale: animation, child: child),
        ),
        child: KeyedSubtree(key: ValueKey(collapsed), child: child),
      ),
    );
  }
}
