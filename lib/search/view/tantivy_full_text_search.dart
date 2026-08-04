import 'package:flutter/material.dart';
import 'package:otzaria/theme/app_tokens.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/widgets/navigation/app_top_bar.dart';
import 'package:otzaria/widgets/widgets_exports.dart';
import 'package:otzaria/settings/settings_exports.dart';
import 'package:otzaria/search/utils/facet_helper.dart';
import 'package:otzaria/search/bloc/search_bloc.dart';
import 'package:otzaria/search/bloc/search_event.dart';
import 'package:otzaria/search/bloc/search_state.dart';
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
import 'package:otzaria/widgets/layout/adaptive_side_pane.dart';
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

class _TantivyFullTextSearchState extends State<TantivyFullTextSearch>
    with AutomaticKeepAliveClientMixin {
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

  // משמש כדי להבדיל בין "חיפוש חדש" (שבו נרצה להציג מסך טעינה מלא)
  // לבין "טען תוצאות נוספות" (שבו אסור להעלים את התוצאות הקיימות).
  String _lastCompletedQuery = '';

  bool _shouldShowBlockingLoader(SearchState state) {
    final currentQuery = state.searchQuery.trim();
    final lastQuery = _lastCompletedQuery.trim();
    // אם יש חיפוש חדש (הטקסט השתנה) והוא עוד בטעינה — נחסום עם ספינר.
    // אם זה רק "טען עוד" (אותו query) — לא נחסום.
    return state.isLoading &&
        currentQuery.isNotEmpty &&
        currentQuery != lastQuery;
  }

  void _updateLastCompletedQuery(SearchState state) {
    if (!state.isLoading) {
      _lastCompletedQuery = state.searchQuery;
    }
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

  Widget _buildNoCategoriesSelectedMessage(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              FluentIcons.filter_dismiss_24_regular,
              size: 56,
              color: colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              'לא נבחרו קטגוריות',
              style: TextStyle(
                fontSize: 18,
                color: colorScheme.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'בחר קטגוריה אחת לפחות כדי לבצע חיפוש.',
              style: TextStyle(
                fontSize: 14,
                color: colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInitialSearchState(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              FluentIcons.search_24_regular,
              size: 64,
              color: colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              'לא בוצע חיפוש',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'הקלד מילות חיפוש ולחץ על כפתור "חפש" כדי להתחיל.',
              style: TextStyle(
                fontSize: 14,
                color: colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoResultsState(BuildContext context, {bool truncated = false}) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              truncated
                  ? FluentIcons.warning_24_regular
                  : FluentIcons.document_search_24_regular,
              size: 56,
              color: colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              truncated ? 'הגעת למגבלת אפשרויות החיפוש' : 'אין תוצאות',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              truncated
                  ? 'שילוב הגדרות ההרחבה (קידומות, סיומות, שגיאות כתיב וכד׳) '
                        'יצר יותר מדי אפשרויות עבור המנוע. נסה להוריד חלק '
                        'מהגדרות החיפוש או לצמצם את מילות החיפוש.'
                  : 'נסה להרחיב קטגוריות, לשנות מצב חיפוש או לעדכן את מילות '
                        'החיפוש.',
              style: TextStyle(
                fontSize: 14,
                color: colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ActionButton.neutral(
              text: 'ערוך חיפוש',
              onPressed: _openEditDialog,
              icon: FluentIcons.edit_24_regular,
            ),
          ],
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();

    // Request focus on search field when the widget is first created
    _requestSearchFieldFocus();

    // הפעל חיפוש ממתין - רק כשהטאב מוצג לראשונה (לא בפתיחת האפליקציה).
    // חשוב להעביר גם את ה-customSpacing/alternativeWords/searchOptions
    // שנשמרו ב-tab, אחרת חיפוש משוחזר (מ-fromJson) ירוץ ללא 'חלק ממילה'
    // ושאר אפשרויות פר-מילה, ויחזיר 0 תוצאות גם כשהשאילתה תקפה.
    final pendingQuery = widget.tab.queryController.text.trim();
    if (pendingQuery.isNotEmpty &&
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
              if (isNarrow) return _buildForSmallScreens();
              return _buildForWideScreens();
            },
          ),
        ),
      ),
    );
  }

  Widget _buildForSmallScreens() {
    return BlocBuilder<SearchBloc, SearchState>(
      builder: (context, state) {
        _updateLastCompletedQuery(state);
        final showBlockingLoader = _shouldShowBlockingLoader(state);
        return Container(
          clipBehavior: Clip.hardEdge,
          decoration: const BoxDecoration(),
          child: Column(
            children: [
              _buildIndexingWarning(),
              // השורה התחתונה - מוצגת תמיד!
              _buildBottomRow(state),
              // חיווי סינון קטגוריות
              if (_shouldShowFacetFilterBanner(state))
                _buildFacetFilterBanner(context, state),
              Expanded(
                child: Stack(
                  children: [
                    if (showBlockingLoader)
                      const Center(child: CircularProgressIndicator())
                    else if (state.searchQuery.isEmpty)
                      _buildInitialSearchState(context)
                    else if (state.hasNoSelectedFacets)
                      _buildNoCategoriesSelectedMessage(context)
                    else if (state.results.isEmpty)
                      // הבחנה בין חיפוש ריק לכשל מנוע — ראה state.errorMessage.
                      state.errorMessage != null
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(8.0),
                                child: Text(
                                  state.errorMessage!,
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.error,
                                  ),
                                ),
                              ),
                            )
                          : _buildNoResultsState(
                              context,
                              truncated: state.resultsTruncated,
                            )
                    else
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

  Widget _buildForWideScreens() {
    return Column(
      children: [
        _buildIndexingWarning(),
        Expanded(
          child: BlocBuilder<SearchBloc, SearchState>(
            builder: (context, state) {
              _updateLastCompletedQuery(state);
              final showBlockingLoader = _shouldShowBlockingLoader(state);
              return Column(
                children: [
                  AppTopBar(
                    leadingItems: [
                      AppTopBarItem(
                        widget: BarButton.icon(
                          tooltip: 'הצג/הסתר עץ ספרים',
                          icon: FluentIcons.line_horizontal_3_20_regular,
                          compact: context
                              .read<SettingsBloc>()
                              .state
                              .compactMenuMode,
                          onPressed: () {
                            widget.tab.isLeftPaneOpen.value =
                                !widget.tab.isLeftPaneOpen.value;
                          },
                        ),
                      ),
                    ],
                    center: state.searchQuery.isEmpty
                        ? const SizedBox.shrink()
                        : Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Flexible(
                                child: Text(
                                  'מוצגות תוצאות של חיפוש: ',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurface
                                        .withValues(alpha: 0.7),
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Flexible(
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
                              const SizedBox(width: 8),
                              BarButton.icon(
                                tooltip: 'ערוך חיפוש',
                                icon: FluentIcons.edit_24_regular,
                                compact: context
                                    .read<SettingsBloc>()
                                    .state
                                    .compactMenuMode,
                                onPressed: _openEditDialog,
                              ),
                            ],
                          ),
                    trailingItems: state.searchQuery.isEmpty
                        ? const []
                        : [
                            AppTopBarItem(
                              widget: Text(
                                state.totalGroups != null
                                    ? '${state.results.length}/${state.totalGroups} תוצאות מאוחדות (מתוך ${state.totalResults})'
                                    : '${state.results.length}/${state.totalResults} תוצאות',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Theme.of(context).colorScheme.onSurface
                                      .withValues(alpha: 0.7),
                                ),
                              ),
                            ),
                            AppTopBarItem(
                              dividerBefore: true,
                              widget: OrderOfResults(
                                widget: TantivySearchResults(tab: widget.tab),
                              ),
                            ),
                            const AppTopBarItem(
                              widget: GroupingOfResults(),
                            ),
                          ],
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
                            return AdaptiveSidePane(
                              isOpen: isOpen,
                              alignment: AlignmentDirectional.centerEnd,
                              mainContent: _buildResultsContent(
                                context,
                                state,
                                showBlockingLoader,
                              ),
                              paneContent: SearchFacetFiltering(
                                tab: widget.tab,
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

  /// תוכן אזור התוצאות (loader / מצב התחלתי / אין קטגוריות / שגיאה / תוצאות).
  Widget _buildResultsContent(
    BuildContext context,
    SearchState state,
    bool showBlockingLoader,
  ) {
    if (showBlockingLoader) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.searchQuery.isEmpty) {
      return _buildInitialSearchState(context);
    }
    if (state.hasNoSelectedFacets) {
      return _buildNoCategoriesSelectedMessage(context);
    }
    if (state.results.isEmpty) {
      if (state.errorMessage != null) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Text(
              state.errorMessage!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        );
      }
      return _buildNoResultsState(context, truncated: state.resultsTruncated);
    }
    return Container(
      clipBehavior: Clip.hardEdge,
      decoration: const BoxDecoration(),
      child: TantivySearchResults(
        tab: widget.tab,
        onEditSearch: _openEditDialog,
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

  // השורה העליונה - כפתור תפריט + מילות חיפוש + כפתור עריכה
  Widget _buildBottomRow(SearchState state) {
    return Container(
      height: 60, // גובה קבוע
      color: Theme.of(context).colorScheme.surfaceContainer,
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
      child: Row(
        children: [
          // כפתור פתיחה/סגירה של עץ הספרים - שלושה פסים
          IconButton(
            tooltip: "הצג/הסתר עץ ספרים",
            icon: const Icon(FluentIcons.line_horizontal_3_20_regular),
            onPressed: () {
              widget.tab.isLeftPaneOpen.value =
                  !widget.tab.isLeftPaneOpen.value;
            },
          ),
          // מילות החיפוש + כפתור עריכה (רק אם יש חיפוש)
          if (state.searchQuery.isNotEmpty) ...[
            Expanded(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'חיפוש: ',
                    style: TextStyle(
                      fontSize: 14,
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.7),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // הצגת מילות החיפוש רק בחיפוש מתקדם
                  if (state.isAdvancedSearchEnabled)
                    Flexible(
                      child: SearchTermsDisplay(tab: widget.tab),
                    )
                  else
                    Flexible(
                      child: Text(
                        state.searchQuery,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  IconButton(
                    icon: const Icon(FluentIcons.edit_24_regular, size: 20),
                    tooltip: 'ערוך חיפוש',
                    onPressed: _openEditDialog,
                  ),
                ],
              ),
            ),
            // מספר תוצאות
            Text(
              state.totalGroups != null
                  ? '${state.results.length}/${state.totalGroups} תוצאות מאוחדות (מתוך ${state.totalResults})'
                  : '${state.results.length}/${state.totalResults} תוצאות',
              style: TextStyle(
                fontSize: 13,
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(width: 4),
            // סדר מיון
            OrderOfResults(
              widget: TantivySearchResults(tab: widget.tab),
              compact: true,
            ),
            const SizedBox(width: 4),
            // איחוד תוצאות
            const GroupingOfResults(compact: true),
          ],
        ],
      ),
    );
  }
}
