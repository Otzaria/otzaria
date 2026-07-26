import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/library/bloc/library_bloc.dart';
import 'package:otzaria/library/bloc/library_state.dart';
import 'package:otzaria/search/bloc/search_bloc.dart';
import 'package:otzaria/search/bloc/search_event.dart';
import 'package:otzaria/search/bloc/search_state.dart';
import 'package:otzaria/search/search_query_builder.dart';
import 'package:otzaria/search/search_scope_preferences.dart';
import 'package:otzaria/search/utils/facet_helper.dart';
import 'package:otzaria/search/view/search_navigation_tree.dart';
import 'package:otzaria/services/commentary_service.dart';
import 'package:otzaria/tabs/models/searching_tab.dart';
import 'package:otzaria/widgets/text/otzaria_search_field.dart';

// Constants
const double _kMinQueryLength = 2;

class SearchFacetFiltering extends StatefulWidget {
  final SearchingTab tab;

  const SearchFacetFiltering({
    super.key,
    required this.tab,
  });

  @override
  State<SearchFacetFiltering> createState() => _SearchFacetFilteringState();
}

class _SearchFacetFilteringState extends State<SearchFacetFiltering>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  final TextEditingController _filterQuery = TextEditingController();
  final Map<String, bool> _expansionState = {};

  @override
  void dispose() {
    _filterQuery.dispose();
    super.dispose();
  }

  void _clearFilter() {
    _filterQuery.clear();
    context.read<SearchBloc>().add(ClearFilter());
  }

  @override
  void initState() {
    _filterQuery.text = context.read<SearchBloc>().state.filterQuery ?? '';
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _restorePersistedDimensions();
    });
  }

  /// שחזור הבחירה הממדית השמורה לטאב "נקי" בלבד: אם כבר רץ חיפוש (או שה-state
  /// כבר נושא ממדים) לא דורסים את ההיקף שנקבע לו.
  void _restorePersistedDimensions() {
    if (!mounted) return;
    final persisted = SearchScopePreferences.loadDimensionFacets();
    if (persisted.isEmpty) return;

    final searchBloc = context.read<SearchBloc>();
    final state = searchBloc.state;
    if (state.searchQuery.isNotEmpty || state.isLoading) return;
    if (FacetHelper.dimensionFacetsOf(state.currentFacets).isNotEmpty) return;

    final categories = FacetHelper.categoryFacetsOf(state.currentFacets);
    final effectiveCategories = categories.isEmpty ? const ['/'] : categories;
    final sortedDimensions = persisted.toList()..sort();
    searchBloc.add(
      SetFacetsWithoutSearch([...effectiveCategories, ...sortedDimensions]),
    );
  }

  void _onQueryChanged(String query) {
    if (query.length >= _kMinQueryLength) {
      context.read<SearchBloc>().add(UpdateFilterQuery(query));
    } else if (query.isEmpty) {
      context.read<SearchBloc>().add(ClearFilter());
    }
  }

  /// ב-Mac המוסכמה לריבוי בחירה היא Cmd+Click, בשאר הפלטפורמות Ctrl+Click.
  bool _isMultiSelectModifierPressed() {
    final keyboard = HardwareKeyboard.instance;
    if (Platform.isMacOS) {
      return keyboard.isMetaPressed || keyboard.isControlPressed;
    }
    return keyboard.isControlPressed;
  }

  void _handleFacetToggle(BuildContext context, String facet) {
    final searchBloc = context.read<SearchBloc>();
    final state = searchBloc.state;
    final dimensionFacets = FacetHelper.dimensionFacetsOf(state.currentFacets);
    if (dimensionFacets.isEmpty) {
      if (state.currentFacets.contains(facet)) {
        searchBloc.add(RemoveFacet(facet));
      } else {
        searchBloc.add(AddFacet(facet));
      }
      return;
    }

    // כשפעילים facets ממדיים (/base, /era/, /author/) עוקפים את AddFacet/
    // RemoveFacet: המסלול הממוזער בצד-לקוח שלהם מסנן לפי נתיבי קטגוריה
    // בלבד ואינו מכיר את סמנטיקת ה-AND של הממדים במנוע.
    final categories = FacetHelper.categoryFacetsOf(state.currentFacets);
    if (categories.contains(facet)) {
      categories.remove(facet);
    } else {
      categories.add(facet);
    }
    _dispatchCategoriesWithDimensions(searchBloc, categories, dimensionFacets);
  }

  void _setFacet(BuildContext context, String facet) {
    final searchBloc = context.read<SearchBloc>();
    final state = searchBloc.state;
    final normalizedParameters = SearchQueryBuilder.normalizeParametersForMode(
      state.configuration.searchMode,
      customSpacing: widget.tab.spacingValues,
      alternativeWords: widget.tab.alternativeWords,
      searchOptions: widget.tab.effectiveSearchOptions(
        query: state.searchQuery,
      ),
    );

    final dimensionFacets = FacetHelper.dimensionFacetsOf(state.currentFacets);
    if (dimensionFacets.isEmpty) {
      searchBloc.add(
        SetFacet(
          facet,
          customSpacing: normalizedParameters.customSpacing,
          alternativeWords: normalizedParameters.alternativeWords,
          searchOptions: normalizedParameters.searchOptions,
        ),
      );
      return;
    }

    // שחזור סמנטיקת SetFacet('/') — "כל הספרים בתוך ההיקף" — תוך שימור
    // ה-facets הממדיים שרוכבים על אותה רשימה.
    final categories = facet == '/'
        ? FacetHelper.categoryFacetsOf(state.searchScopeFacets)
        : <String>[facet];
    _dispatchCategoriesWithDimensions(
      searchBloc,
      categories,
      dimensionFacets,
    );
  }

  /// שולח בחירת קטגוריות חדשה יחד עם ה-facets הממדיים הפעילים, ומריץ את
  /// החיפוש מחדש דרך המנוע (הממדים חייבים להגיע למנוע — סינון מקומי לפי
  /// קטגוריות היה מתעלם מהם).
  void _dispatchCategoriesWithDimensions(
    SearchBloc searchBloc,
    List<String> categories,
    List<String> dimensionFacets,
  ) {
    final effectiveCategories = categories.isEmpty ? const ['/'] : categories;
    searchBloc.add(
      SetFacetsWithoutSearch([...effectiveCategories, ...dimensionFacets]),
    );
    searchBloc.add(const RerunSearch());
  }

  /// התקופות המוצעות לסינון. 'שאר מפרשים' לעולם לא מוטבעת, ו'תורה שבכתב'
  /// אינה תקופת פרשנות רלוונטית לסינון.
  static final List<String> _eraNames = [
    for (final era in CommentaryEra.values)
      if (era != CommentaryEra.other && era != CommentaryEra.torahShebichtav)
        era.hebrewName,
  ];

  /// מוסיף/מסיר facet ממדי (ספרי יסוד/תקופה), שומר בהעדפות ומריץ חיפוש מחדש
  /// דרך המנוע יחד עם הקטגוריות הפעילות.
  void _toggleDimension(BuildContext context, String dimFacet) {
    final searchBloc = context.read<SearchBloc>();
    final state = searchBloc.state;
    final categories = FacetHelper.categoryFacetsOf(state.currentFacets);
    final dimensions = FacetHelper.dimensionFacetsOf(
      state.currentFacets,
    ).toSet();
    if (dimensions.contains(dimFacet)) {
      dimensions.remove(dimFacet);
    } else {
      dimensions.add(dimFacet);
    }
    SearchScopePreferences.saveDimensionFacets(dimensions);

    _dispatchCategoriesWithDimensions(
      searchBloc,
      categories,
      dimensions.toList()..sort(),
    );
  }

  /// מנקה את כל הסינון (קטגוריות + ממדים) — חזרה ל"כל הספרים".
  void _clearAllScope(BuildContext context) {
    final searchBloc = context.read<SearchBloc>();
    SearchScopePreferences.saveDimensionFacets(const {});
    _dispatchCategoriesWithDimensions(
      searchBloc,
      const ['/'],
      const [],
    );
  }

  Widget _buildSearchField() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: OtzariaSearchField(
        controller: _filterQuery,
        hintText: 'איתור ספר…',
        slim: true,
        onChanged: _onQueryChanged,
        onClear: _clearFilter,
        trailingActions: [_buildDimensionFilterButton()],
      ),
    );
  }

  /// כפתור סינון בשדה — פותח תפריט שטוח (בלי תתי-תפריטים) של מאפייני הספר:
  /// ספרי יסוד ותקופות. סימון מרובה נשמר פתוח (closeOnActivate: false).
  Widget _buildDimensionFilterButton() {
    return BlocBuilder<SearchBloc, SearchState>(
      buildWhen: (p, c) => p.currentFacets != c.currentFacets,
      builder: (context, state) {
        final cs = Theme.of(context).colorScheme;
        final dims = FacetHelper.dimensionFacetsOf(state.currentFacets).toSet();
        final activeCount = dims.length;

        Widget checkItem(String label, String facet) {
          final selected = dims.contains(facet);
          return MenuItemButton(
            closeOnActivate: false,
            leadingIcon: Icon(
              selected
                  ? FluentIcons.checkbox_checked_24_filled
                  : FluentIcons.checkbox_unchecked_24_regular,
              size: 18,
              color: selected ? cs.primary : cs.onSurfaceVariant,
            ),
            onPressed: () => _toggleDimension(context, facet),
            child: Text(label),
          );
        }

        return MenuAnchor(
          menuChildren: [
            checkItem('ספרי יסוד', FacetHelper.baseDimensionFacet),
            for (final era in _eraNames)
              checkItem(era, FacetHelper.buildEraFacet(era)),
          ],
          builder: (context, controller, child) => SizedBox(
            width: 32,
            height: 32,
            child: IconButton(
              padding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
              tooltip: 'סינון לפי מאפיין',
              color: activeCount > 0 ? cs.primary : cs.onSurfaceVariant,
              icon: activeCount > 0
                  ? Badge(
                      label: Text('$activeCount'),
                      child: const Icon(
                        FluentIcons.filter_24_regular,
                        size: 20,
                      ),
                    )
                  : const Icon(FluentIcons.filter_24_regular, size: 20),
              onPressed: () =>
                  controller.isOpen ? controller.close() : controller.open(),
            ),
          ),
        );
      },
    );
  }

  Widget _buildFacetTree() {
    return BlocBuilder<LibraryBloc, LibraryState>(
      builder: (context, libraryState) {
        if (libraryState.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }

        if (libraryState.error != null) {
          return Center(child: Text('Error: ${libraryState.error}'));
        }

        return BlocBuilder<SearchBloc, SearchState>(
          builder: (context, searchState) {
            final library = libraryState.library;
            if (library == null) {
              return const Center(child: Text('No library data available'));
            }

            return SearchNavigationTree(
              library: library,
              facetCounts: searchState.facetCounts,
              selectedFacets: searchState.currentFacets,
              expansion: _expansionState,
              filterQuery: _filterQuery.text,
              isLoading: searchState.isLoading,
              hasResults: searchState.results.isNotEmpty,
              onSetFacet: (facet) => _setFacet(context, facet),
              onToggleFacet: (facet) => _handleFacetToggle(context, facet),
              onToggleExpand: (path) => setState(() {
                _expansionState[path] = !(_expansionState[path] ?? false);
              }),
              isMultiSelectPressed: _isMultiSelectModifierPressed,
              onClearAll: () => _clearAllScope(context),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(
      children: [
        _buildSearchField(),
        Expanded(
          child: _buildFacetTree(),
        ),
      ],
    );
  }
}
