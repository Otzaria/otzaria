import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/search/bloc/search_bloc.dart';
import 'package:otzaria/search/bloc/search_event.dart';
import 'package:otzaria/search/bloc/search_state.dart';
import 'package:otzaria/search/search_query_builder.dart';
import 'package:otzaria/search/search_scope_preferences.dart';
import 'package:otzaria/search/utils/facet_helper.dart';
import 'package:otzaria/search/view/search_scope_menu.dart';
import 'package:otzaria/tabs/models/searching_tab.dart';

/// סינון היקף החיפוש בסרגל התוצאות — עטיפה מחוברת-bloc של
/// [SearchScopeMenuButton], אותו כפתור-שדה מאוחד המשמש גם בדיאלוג החיפוש
/// (קטגוריות/ספרים, ספרי יסוד, תקופה ומחבר יחד).
///
/// הבחירה רוכבת על אותה רשימת facets שכבר נשלחת למנוע: OR בתוך ממד,
/// AND בין ממדים ומול קבוצת הקטגוריות. לכן כל שינוי משוגר דרך
/// [SetFacetsWithoutSearch] + [UpdateSearchQuery] (ולא דרך AddFacet/
/// RemoveFacet — המסלול הממוזער בצד-לקוח של ה-bloc מסנן לפי נתיבי
/// קטגוריה בלבד ואינו מכיר את סמנטיקת ה-AND של הממדים).
class SearchDimensionFilters extends StatefulWidget {
  final SearchingTab tab;

  const SearchDimensionFilters({super.key, required this.tab});

  @override
  State<SearchDimensionFilters> createState() => _SearchDimensionFiltersState();
}

class _SearchDimensionFiltersState extends State<SearchDimensionFilters> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _restorePersistedDimensions();
    });
  }

  /// שחזור הבחירה השמורה לטאב "נקי" בלבד: אם כבר רץ חיפוש (או שה-state
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

  /// מחליף את היקף החיפוש (קטגוריות + ממדים יחד), שומר את הממדים בהעדפות
  /// ומריץ מחדש את החיפוש (אם יש שאילתה).
  void _applyScope(Set<String> selection) {
    final searchBloc = context.read<SearchBloc>();
    final state = searchBloc.state;

    final categories = FacetHelper.categoryFacetsOf(selection);
    final effectiveCategories = categories.isEmpty ? const ['/'] : categories;
    final dimensions = FacetHelper.dimensionFacetsOf(selection).toSet();
    final sortedDimensions = dimensions.toList()..sort();

    SearchScopePreferences.saveDimensionFacets(dimensions);
    searchBloc.add(
      SetFacetsWithoutSearch([...effectiveCategories, ...sortedDimensions]),
    );

    if (state.searchQuery.isEmpty) return;
    final normalizedParameters = SearchQueryBuilder.normalizeParametersForMode(
      state.configuration.searchMode,
      customSpacing: widget.tab.spacingValues,
      alternativeWords: widget.tab.alternativeWords,
      searchOptions: widget.tab.effectiveSearchOptions(
        query: state.searchQuery,
      ),
    );
    searchBloc.add(
      UpdateSearchQuery(
        state.searchQuery,
        customSpacing: normalizedParameters.customSpacing,
        alternativeWords: normalizedParameters.alternativeWords,
        searchOptions: normalizedParameters.searchOptions,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SearchBloc, SearchState>(
      buildWhen: (previous, current) =>
          previous.currentFacets != current.currentFacets,
      builder: (context, state) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: SearchScopeMenuButton(
            selected: state.currentFacets.toSet(),
            onChanged: _applyScope,
            width: double.infinity,
            showChips: false,
          ),
        );
      },
    );
  }
}
