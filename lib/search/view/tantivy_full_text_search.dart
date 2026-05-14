import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/search/bloc/search_bloc.dart';
import 'package:otzaria/search/bloc/search_event.dart';
import 'package:otzaria/search/bloc/search_state.dart';
import 'package:otzaria/tabs/models/searching_tab.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_state.dart';
import 'package:otzaria/core/focus_repository.dart';
import 'package:otzaria/search/search_query_builder.dart';
import 'package:otzaria/search/view/full_text_settings_widgets.dart';
import 'package:otzaria/search/view/tantivy_search_results.dart';
import 'package:otzaria/search/view/full_text_facet_filtering.dart';
import 'package:otzaria/search/view/search_edit_panel.dart';
import 'package:otzaria/settings/settings_exports.dart';
import 'package:otzaria/widgets/layout/resizable_facet_filtering.dart';
import 'package:otzaria/widgets/feedback/indexing_warning.dart';
import 'package:otzaria/widgets/misc/thin_divider.dart';

class TantivyFullTextSearch extends StatefulWidget {
  final SearchingTab tab;
  const TantivyFullTextSearch({super.key, required this.tab});
  @override
  State<TantivyFullTextSearch> createState() => _TantivyFullTextSearchState();
}

class _TantivyFullTextSearchState extends State<TantivyFullTextSearch>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  bool _indexInProgressWarningDismissed = false;
  bool _showEditPanel = false;

  Widget _buildIndexingWarning() {
    return IndexingWarningContainer(
      inProgressDismissed: _indexInProgressWarningDismissed,
      onDismiss: () =>
          setState(() => _indexInProgressWarningDismissed = true),
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

  bool _shouldShowFacetFilterBanner(SearchState state) {
    return state.hasScopedFacetFilter && state.searchQuery.isNotEmpty;
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
              textDirection: TextDirection.rtl,
            ),
            const SizedBox(height: 8),
            Text(
              'בחר קטגוריה אחת לפחות כדי לבצע חיפוש.',
              style: TextStyle(
                fontSize: 14,
                color: colorScheme.onSurfaceVariant,
              ),
              textDirection: TextDirection.rtl,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  void _resetSearchScope() {
    final searchMode = widget.tab.searchBloc.state.configuration.searchMode;
    final normalizedParameters = SearchQueryBuilder.normalizeParametersForMode(
      searchMode,
      customSpacing: widget.tab.spacingValues,
      alternativeWords: widget.tab.alternativeWords,
      searchOptions: widget.tab.effectiveSearchOptions(
        query: widget.tab.searchBloc.state.searchQuery,
      ),
    );
    widget.tab.searchBloc.add(const SetFacetsWithoutSearch(['/']));
    widget.tab.searchBloc.add(UpdateSearchQuery(
      widget.tab.searchBloc.state.searchQuery,
      customSpacing: normalizedParameters.customSpacing,
      alternativeWords: normalizedParameters.alternativeWords,
      searchOptions: normalizedParameters.searchOptions,
    ));
  }

  @override
  void initState() {
    super.initState();

    // Request focus on search field when the widget is first created
    _requestSearchFieldFocus();

    // הפעל חיפוש ממתין - רק כשהטאב מוצג לראשונה (לא בפתיחת האפליקציה)
    final pendingQuery = widget.tab.queryController.text.trim();
    if (pendingQuery.isNotEmpty &&
        widget.tab.searchBloc.state.searchQuery.isEmpty) {
      widget.tab.searchBloc.add(UpdateSearchQuery(pendingQuery));
    }
  }

  @override
  void didUpdateWidget(TantivyFullTextSearch oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Request focus when switching back to this tab
    _requestSearchFieldFocus();
  }

  void _requestSearchFieldFocus() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.tab.searchFieldFocusNode.canRequestFocus) {
        // Check if this tab is the currently selected tab
        final tabsState = context.read<TabsBloc>().state;
        if (tabsState.hasOpenTabs &&
            tabsState.currentTabIndex < tabsState.tabs.length &&
            tabsState.tabs[tabsState.currentTabIndex] == widget.tab) {
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
              final state = context.read<TabsBloc>().state;
              return state.hasOpenTabs &&
                  state.currentTabIndex < state.tabs.length &&
                  state.tabs[state.currentTabIndex] == widget.tab;
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
      child: Scaffold(
        body: LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < 800) return _buildForSmallScreens();
            return _buildForWideScreens();
          },
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
              Row(children: [_buildMenuButton()]),
              // השורה התחתונה - מוצגת תמיד!
              _buildBottomRow(state),
              const ThinDivider(),
              // חיווי סינון קטגוריות
              if (_shouldShowFacetFilterBanner(state))
                _buildFacetFilterBanner(context, state),
              // פאנל עריכה - מופיע מתחת לשורה התחתונה
              if (_showEditPanel)
                SearchEditPanel(
                  tab: widget.tab,
                  onClose: () {
                    setState(() {
                      _showEditPanel = false;
                    });
                  },
                ),
              Expanded(
                child: Stack(
                  children: [
                    if (showBlockingLoader)
                      const Center(child: CircularProgressIndicator())
                    else if (state.searchQuery.isEmpty)
                      Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              FluentIcons.search_24_regular,
                              size: 64,
                              color: Colors.grey.shade400,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              "לא בוצע חיפוש",
                              style: TextStyle(
                                fontSize: 18,
                                color: Colors.grey.shade600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              "לחץ על 'חיפוש חדש' כדי להתחיל",
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey.shade500,
                              ),
                            ),
                          ],
                        ),
                      )
                    else if (state.hasNoSelectedFacets)
                      _buildNoCategoriesSelectedMessage(context)
                    else if (state.results.isEmpty)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.all(8.0),
                          child: Text('אין תוצאות'),
                        ),
                      )
                    else
                      Container(
                        clipBehavior: Clip.hardEdge,
                        decoration: const BoxDecoration(),
                        child: TantivySearchResults(tab: widget.tab),
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
    return Container(
      clipBehavior: Clip.hardEdge,
      decoration: const BoxDecoration(),
      child: Column(
        children: [
          _buildIndexingWarning(),
          Expanded(
            child: BlocBuilder<SearchBloc, SearchState>(
              builder: (context, state) {
                _updateLastCompletedQuery(state);
                final showBlockingLoader = _shouldShowBlockingLoader(state);
                return Column(
                  children: [
                    // שורה אחת פשוטה
                    Container(
                      height: 60,
                      color: Theme.of(context).colorScheme.surfaceContainer,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8.0,
                        vertical: 4.0,
                      ),
                      child: Row(
                        children: [
                          // כפתור תפריט
                          IconButton(
                            tooltip: "הצג/הסתר עץ ספרים",
                            icon: const Icon(
                              FluentIcons.line_horizontal_3_20_regular,
                            ),
                            onPressed: () {
                              widget.tab.isLeftPaneOpen.value =
                                  !widget.tab.isLeftPaneOpen.value;
                            },
                          ),
                          // רווח כשהעץ פתוח
                          ValueListenableBuilder(
                            valueListenable: widget.tab.isLeftPaneOpen,
                            builder: (context, isOpen, child) {
                              if (!isOpen) {
                                return const SizedBox.shrink();
                              }
                              final width = context
                                  .watch<SettingsBloc>()
                                  .state
                                  .facetFilteringWidth
                                  .clamp(280.0, 600.0);
                              return SizedBox(width: width);
                            },
                          ),
                          // מילות חיפוש + בקרות
                          Expanded(
                            child: BlocBuilder<SearchBloc, SearchState>(
                              builder: (context, searchState) {
                                if (searchState.searchQuery.isEmpty) {
                                  return const SizedBox.shrink();
                                }

                                return Row(
                                  children: [
                                    // הודעת "מוצגות תוצאות של חיפוש" + כפתור עריכה
                                    Expanded(
                                      child: Padding(
                                        padding: const EdgeInsets.only(
                                          left: 16.0,
                                        ),
                                        child: Row(
                                          children: [
                                            Flexible(
                                              fit: FlexFit.loose,
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
                                            const SizedBox(width: 8),
                                            Flexible(
                                              child: ScrollConfiguration(
                                                behavior:
                                                    ScrollConfiguration.of(
                                                            context)
                                                        .copyWith(
                                                            scrollbars: false),
                                                child: SingleChildScrollView(
                                                  scrollDirection:
                                                      Axis.horizontal,
                                                  child: SearchTermsDisplay(
                                                    tab: widget.tab,
                                                  ),
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            // כפתור עריכה - תמיד מוצג
                                            IconButton(
                                              icon: Icon(
                                                _showEditPanel
                                                    ? FluentIcons
                                                        .chevron_up_24_regular
                                                    : FluentIcons
                                                        .edit_24_regular,
                                                size: 20,
                                              ),
                                              tooltip: _showEditPanel
                                                  ? 'סגור עריכה'
                                                  : 'ערוך חיפוש',
                                              onPressed: () {
                                                setState(() {
                                                  _showEditPanel =
                                                      !_showEditPanel;
                                                });
                                              },
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16.0,
                                      ),
                                      child: Text(
                                        '${searchState.results.length}/${searchState.totalResults} תוצאות',
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurface
                                              .withValues(alpha: 0.7),
                                        ),
                                      ),
                                    ),
                                    OrderOfResults(
                                      widget: TantivySearchResults(
                                        tab: widget.tab,
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                    const ThinDivider(),
                    // חיווי סינון קטגוריות
                    if (_shouldShowFacetFilterBanner(state))
                      _buildFacetFilterBanner(context, state),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // פאנל עריכה - מופיע מתחת לשורה העליונה
                          if (_showEditPanel)
                            SearchEditPanel(
                              tab: widget.tab,
                              onClose: () {
                                setState(() {
                                  _showEditPanel = false;
                                });
                              },
                            ),
                          Expanded(
                            child: Row(
                              children: [
                                // עץ הסינון - עם אפשרות להסתיר/להציג
                                ValueListenableBuilder(
                                  valueListenable: widget.tab.isLeftPaneOpen,
                                  builder: (context, isOpen, child) {
                                    return AnimatedContainer(
                                      duration:
                                          const Duration(milliseconds: 300),
                                      width: isOpen ? null : 0,
                                      child: isOpen
                                          ? ResizableFacetFiltering(
                                              tab: widget.tab)
                                          : const SizedBox.shrink(),
                                    );
                                  },
                                ),
                                // תוצאות החיפוש
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      Expanded(
                                        child: Builder(
                                          builder: (context) {
                                            if (showBlockingLoader) {
                                              return const Center(
                                                child:
                                                    CircularProgressIndicator(),
                                              );
                                            }
                                            if (state.searchQuery.isEmpty) {
                                              return Center(
                                                child: Column(
                                                  mainAxisAlignment:
                                                      MainAxisAlignment.center,
                                                  children: [
                                                    Icon(
                                                      FluentIcons
                                                          .search_24_regular,
                                                      size: 64,
                                                      color:
                                                          Colors.grey.shade400,
                                                    ),
                                                    const SizedBox(height: 16),
                                                    Text(
                                                      "לא בוצע חיפוש",
                                                      style: TextStyle(
                                                        fontSize: 18,
                                                        color: Colors
                                                            .grey.shade600,
                                                      ),
                                                    ),
                                                    const SizedBox(height: 8),
                                                    Text(
                                                      "לחץ על כפתור 'חיפוש' בתפריט כדי להתחיל",
                                                      style: TextStyle(
                                                        fontSize: 14,
                                                        color: Colors
                                                            .grey.shade500,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              );
                                            }
                                            if (state.hasNoSelectedFacets) {
                                              return _buildNoCategoriesSelectedMessage(
                                                context,
                                              );
                                            }
                                            if (state.results.isEmpty) {
                                              return const Center(
                                                child: Padding(
                                                  padding: EdgeInsets.all(8.0),
                                                  child: Text('אין תוצאות'),
                                                ),
                                              );
                                            }
                                            return Container(
                                              clipBehavior: Clip.hardEdge,
                                              decoration: const BoxDecoration(),
                                              child: TantivySearchResults(
                                                tab: widget.tab,
                                              ),
                                            );
                                          },
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMenuButton() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 0, 8, 0),
      child: IconButton(
        tooltip: "הגדרות חיפוש",
        icon: const Icon(FluentIcons.navigation_24_regular),
        onPressed: () {
          widget.tab.isLeftPaneOpen.value = !widget.tab.isLeftPaneOpen.value;
        },
      ),
    );
  }

  /// באנר שמראה באילו קטגוריות מתבצע החיפוש
  Widget _buildFacetFilterBanner(BuildContext context, SearchState state) {
    final cs = Theme.of(context).colorScheme;
    // חילוץ שמות הקטגוריות מטווח החיפוש המקורי
    final facetNames = state.searchScopeFacets.map((facet) {
      // facet בפורמט "/תנ"ך" או "/תנ"ך/ראשונים" - ניקח את החלק האחרון
      final parts = facet.split('/').where((p) => p.isNotEmpty).toList();
      return parts.isNotEmpty ? parts.last : facet;
    }).toList();
    final tooltipMessage = 'חיפוש בקטגוריות: ${facetNames.join(', ')}';

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
            'החיפוש הוגבל לקטגוריות מסוימות',
            style: TextStyle(
              fontSize: 13,
              color: cs.primary,
              fontWeight: FontWeight.w500,
            ),
            textDirection: TextDirection.rtl,
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
              borderRadius: BorderRadius.circular(14),
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
          // כפתור לאיפוס הסינון - חזרה לכל הקטגוריות
          IconButton(
            icon: Icon(
              FluentIcons.dismiss_24_regular,
              size: 16,
              color: cs.primary,
            ),
            tooltip: 'חפש בכל הקטגוריות',
            onPressed: _resetSearchScope,
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
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.7),
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
                    icon: Icon(
                      _showEditPanel
                          ? FluentIcons.chevron_up_24_regular
                          : FluentIcons.edit_24_regular,
                      size: 20,
                    ),
                    tooltip: _showEditPanel ? 'סגור עריכה' : 'ערוך חיפוש',
                    onPressed: () {
                      setState(() {
                        _showEditPanel = !_showEditPanel;
                      });
                    },
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
