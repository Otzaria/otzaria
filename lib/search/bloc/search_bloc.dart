import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/indexing/repository/indexing_repository.dart';
import 'package:otzaria/search/bloc/search_event.dart';
import 'package:otzaria/search/bloc/search_state.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/data/data_providers/tantivy_data_provider.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/search/search_repository.dart';
import 'package:otzaria/search/search_query_builder.dart';
import 'package:otzaria/search/utils/facet_helper.dart';
import 'package:otzaria/search/utils/search_catalogue_order_helper.dart';
import 'package:flutter/foundation.dart';
import 'package:search_engine/search_engine.dart';

class SearchBloc extends Bloc<SearchEvent, SearchState> {
  final SearchRepository _repository = SearchRepository();
  int _searchRequestId = 0;

  static int _defaultDistanceForMode(SearchMode mode) {
    return mode == SearchMode.fuzzy ? 2 : 0;
  }

  static int _resolveDistanceForModeChange(
    SearchMode currentMode,
    SearchMode newMode,
    int currentDistance,
  ) {
    final currentDefault = _defaultDistanceForMode(currentMode);
    if (currentDistance != currentDefault) {
      return currentDistance;
    }

    return _defaultDistanceForMode(newMode);
  }

  SearchBloc() : super(const SearchState()) {
    on<UpdateSearchQuery>(_onUpdateSearchQuery);
    on<UpdateDistance>(_onUpdateDistance);
    on<UpdateDistanceWithoutSearch>(_onUpdateDistanceWithoutSearch);
    on<ToggleSearchMode>(_onToggleSearchMode);
    on<SetSearchMode>(_onSetSearchMode);
    on<SetSearchModeWithoutSearch>(_onSetSearchModeWithoutSearch);
    on<UpdateBooksToSearch>(_onUpdateBooksToSearch);
    on<AddFacet>(_onAddFacet);
    on<RemoveFacet>(_onRemoveFacet);
    on<SetFacet>(_onSetFacet);
    on<SetFacetsWithoutSearch>(_onSetFacetsWithoutSearch);
    on<UpdateSortOrder>(_onUpdateSortOrder);
    on<UpdateNumResults>(_onUpdateNumResults);
    on<ResetSearch>(_onResetSearch);
    on<UpdateFilterQuery>(_onUpdateFilterQuery);
    on<ClearFilter>(_onClearFilter);

    // Handlers חדשים לרגקס
    on<ToggleRegex>(_onToggleRegex);
    on<ToggleCaseSensitive>(_onToggleCaseSensitive);
    on<ToggleMultiline>(_onToggleMultiline);
    on<ToggleDotAll>(_onToggleDotAll);
    on<ToggleUnicode>(_onToggleUnicode);
    on<UpdateFacetCounts>(_onUpdateFacetCounts);
    on<ReplaceFacetCounts>(_onReplaceFacetCounts);
    on<LoadMoreResults>(_onLoadMoreResults);
  }

  Future<void> _onUpdateSearchQuery(
    UpdateSearchQuery event,
    Emitter<SearchState> emit,
  ) async {
    final requestId = ++_searchRequestId;
    final query = event.query;
    if (event.query.isEmpty) {
      emit(state.copyWith(
        searchQuery: event.query,
        results: [],
        totalResults: 0,
        facetCounts: const {},
      ));
      return;
    }

    if (state.currentFacets.isEmpty) {
      emit(state.copyWith(
        searchQuery: event.query,
        results: [],
        totalResults: 0,
        isLoading: false,
        facetCounts: const {},
      ));
      return;
    }

    final requestedFacets = List<String>.from(state.currentFacets);
    final shouldPreserveFacetCounts =
        state.searchQuery == query && state.facetCounts.isNotEmpty;

    // Clear global cache for new search
    TantivyDataProvider.clearGlobalCache();

    emit(state.copyWith(
      searchQuery: query,
      isLoading: true,
      facetCounts: shouldPreserveFacetCounts ? state.facetCounts : const {},
    ));

    final booksToSearch = state.booksToSearch.map((e) => e.title).toList();
    Map<int, Book>? bookByCatalogueOrder;

    if (!shouldPreserveFacetCounts) {
      final library = await DataRepository.instance.library;
      bookByCatalogueOrder = _buildBooksByCatalogueOrder(library);
    }

    try {
      // התחל לבנות את עץ ה-facets המלא במקביל כבר מתחילת החיפוש.
      unawaited(_refreshFacetCountsForAllBooks(event, requestId));

      // שימוש ב-streaming לתוצאות מהירות יותר
      final stream = _repository.searchTextsStream(
        SearchQueryBuilder.sanitizeQuery(query),
        requestedFacets,
        state.numResults,
        chunkSize: 50, // 50 תוצאות בכל chunk
        fuzzy: state.fuzzy,
        distance: state.distance,
        searchMode: state.configuration.searchMode,
        order: state.sortBy,
        customSpacing: event.customSpacing,
        alternativeWords: event.alternativeWords,
        searchOptions: event.searchOptions,
      );

      final allResults = <SearchResult>[];
      bool isFirstChunk = true;

      await for (final chunk in stream) {
        if (requestId != _searchRequestId) {
          return; // החיפוש בוטל
        }

        allResults.addAll(chunk);

        // עדכון ה-UI עם כל chunk
        if (isFirstChunk) {
          // Chunk ראשון - בנה ספירות חלקיות
          isFirstChunk = false;
          final partialFacetCounts = bookByCatalogueOrder == null
              ? const <String, int>{}
              : FacetHelper.buildFacetCountsFromResults(
                  allResults,
                  bookByCatalogueOrder,
                );

          emit(state.copyWith(
            results: List.from(allResults),
            totalResults: allResults.length,
            isLoading: true, // עדיין טוען
            facetCounts:
                shouldPreserveFacetCounts || state.facetCounts.isNotEmpty
                    ? state.facetCounts
                    : partialFacetCounts,
          ));
        } else {
          // Chunks נוספים - רק עדכן תוצאות
          emit(state.copyWith(
            results: List.from(allResults),
            totalResults: allResults.length,
            isLoading: true, // עדיין טוען
          ));
        }
      }

      // סיום - כל התוצאות התקבלו
      if (requestId != _searchRequestId) {
        return;
      }

      emit(state.copyWith(
        results: allResults,
        totalResults: allResults.length,
        isLoading: false,
      ));

      // ספירה כוללת (אם צריך - אבל בעצם allResults.length כבר נותן את זה)
      final totalResults = await TantivyDataProvider.instance.countTexts(
        SearchQueryBuilder.sanitizeQuery(query),
        booksToSearch,
        requestedFacets,
        fuzzy: state.fuzzy,
        distance: state.distance,
        searchMode: state.configuration.searchMode,
        customSpacing: event.customSpacing,
        alternativeWords: event.alternativeWords,
        searchOptions: event.searchOptions,
      );

      if (requestId != _searchRequestId) {
        return;
      }
      emit(state.copyWith(
        totalResults: totalResults,
      ));
    } catch (e) {
      emit(state.copyWith(
        results: [],
        totalResults: 0,
        isLoading: false,
      ));
    }
  }

  Future<void> _refreshFacetCountsForAllBooks(
      UpdateSearchQuery event, int requestId) async {
    final query = event.query;
    if (query.isEmpty) return;
    if (requestId != _searchRequestId) return;

    // קבל את כל הספרים מהספרייה כדי למפות key -> Book
    final library = await DataRepository.instance.library;
    final bookByIndexedFilePath = _buildBooksByIndexedFilePath(library);

    // סופר ברמת ספר במנוע עצמו, בלי למשוך עשרות אלפי snippets לדארט.
    final activeFacets = List<String>.from(state.searchScopeFacets);
    final bookCounts = await TantivyDataProvider.instance.countByBook(
      SearchQueryBuilder.sanitizeQuery(query),
      activeFacets,
      fuzzy: state.fuzzy,
      distance: state.distance,
      searchMode: state.configuration.searchMode,
      customSpacing: event.customSpacing,
      alternativeWords: event.alternativeWords,
      searchOptions: event.searchOptions,
    );

    // Ignore stale results if query changed while searching
    if (state.searchQuery != query || requestId != _searchRequestId) {
      return;
    }

    final aggregated = FacetHelper.buildFacetCountsFromBookCounts(
      bookCounts,
      bookByIndexedFilePath,
    );

    add(ReplaceFacetCounts(aggregated));
  }

  Future<void> _onUpdateFilterQuery(
    UpdateFilterQuery event,
    Emitter<SearchState> emit,
  ) async {
    if (event.query.length < 3) {
      emit(state.copyWith(
        filterQuery: event.query,
        filteredBooks: null,
      ));
      return;
    }

    try {
      final results = await DataRepository.instance
          .findBooks(event.query, null, sortByRatio: false);

      emit(state.copyWith(
        filterQuery: event.query,
        filteredBooks: results,
      ));
    } catch (e) {
      emit(state.copyWith(
        filterQuery: event.query,
        filteredBooks: null,
      ));
    }
  }

  void _onClearFilter(
    ClearFilter event,
    Emitter<SearchState> emit,
  ) {
    emit(state.copyWith(
      filterQuery: null,
    ));
  }

  void _onUpdateDistance(
    UpdateDistance event,
    Emitter<SearchState> emit,
  ) {
    if (!_updateDistanceConfiguration(event.distance, emit)) {
      return;
    }
    add(UpdateSearchQuery(state.searchQuery));
  }

  void _onUpdateDistanceWithoutSearch(
    UpdateDistanceWithoutSearch event,
    Emitter<SearchState> emit,
  ) {
    _updateDistanceConfiguration(event.distance, emit);
  }

  void _onToggleSearchMode(
    ToggleSearchMode event,
    Emitter<SearchState> emit,
  ) {
    // מעבר בין שלושת המצבים: מתקדם -> מדוייק -> מקורב -> מתקדם
    SearchMode newMode;
    switch (state.configuration.searchMode) {
      case SearchMode.advanced:
        newMode = SearchMode.exact;
        break;
      case SearchMode.exact:
        newMode = SearchMode.fuzzy;
        break;
      case SearchMode.fuzzy:
        newMode = SearchMode.advanced;
        break;
    }

    final newConfig = state.configuration.copyWith(
      searchMode: newMode,
      distance: _resolveDistanceForModeChange(
        state.configuration.searchMode,
        newMode,
        state.configuration.distance,
      ),
    );
    emit(state.copyWith(configuration: newConfig));
    add(UpdateSearchQuery(state.searchQuery));
  }

  void _onSetSearchMode(
    SetSearchMode event,
    Emitter<SearchState> emit,
  ) {
    if (!_updateSearchModeConfiguration(event.searchMode, emit)) {
      return;
    }

    add(UpdateSearchQuery(state.searchQuery));
  }

  void _onSetSearchModeWithoutSearch(
    SetSearchModeWithoutSearch event,
    Emitter<SearchState> emit,
  ) {
    _updateSearchModeConfiguration(event.searchMode, emit);
  }

  bool _updateDistanceConfiguration(int distance, Emitter<SearchState> emit) {
    final newConfig = state.configuration.copyWith(distance: distance);
    if (newConfig == state.configuration) {
      return false;
    }

    emit(state.copyWith(configuration: newConfig));
    return true;
  }

  bool _updateSearchModeConfiguration(
    SearchMode searchMode,
    Emitter<SearchState> emit,
  ) {
    final newConfig = state.configuration.copyWith(
      searchMode: searchMode,
      distance: _resolveDistanceForModeChange(
        state.configuration.searchMode,
        searchMode,
        state.configuration.distance,
      ),
    );

    if (newConfig == state.configuration) {
      return false;
    }

    emit(state.copyWith(configuration: newConfig));
    return true;
  }

  void _onUpdateBooksToSearch(
    UpdateBooksToSearch event,
    Emitter<SearchState> emit,
  ) {
    emit(state.copyWith(booksToSearch: event.books));
    add(UpdateSearchQuery(state.searchQuery));
  }

  void _onAddFacet(
    AddFacet event,
    Emitter<SearchState> emit,
  ) {
    final newFacets = List<String>.from(state.currentFacets);
    if (!newFacets.contains(event.facet)) {
      debugPrint('➕ AddFacet: ${event.facet} (before=$newFacets)');
      newFacets.add(event.facet);
      final newConfig = state.configuration.copyWith(currentFacets: newFacets);
      emit(state.copyWith(configuration: newConfig));
      add(UpdateSearchQuery(state.searchQuery));
    }
  }

  void _onRemoveFacet(
    RemoveFacet event,
    Emitter<SearchState> emit,
  ) {
    final newFacets = List<String>.from(state.currentFacets);
    if (newFacets.contains(event.facet)) {
      debugPrint('➖ RemoveFacet: ${event.facet} (before=$newFacets)');
      newFacets.remove(event.facet);
      final newConfig = state.configuration.copyWith(currentFacets: newFacets);
      emit(state.copyWith(configuration: newConfig));
      add(UpdateSearchQuery(state.searchQuery));
    }
  }

  void _onSetFacet(
    SetFacet event,
    Emitter<SearchState> emit,
  ) {
    // Clicking root "/" in a scoped search means "all books within scope"
    final effectiveFacets = (event.facet == '/' && state.hasScopedFacetFilter)
        ? state.searchScopeFacets
        : [event.facet];
    final newConfig =
        state.configuration.copyWith(currentFacets: effectiveFacets);
    emit(state.copyWith(configuration: newConfig));
    add(UpdateSearchQuery(
      state.searchQuery,
      customSpacing: event.customSpacing,
      alternativeWords: event.alternativeWords,
      searchOptions: event.searchOptions,
    ));
  }

  void _onSetFacetsWithoutSearch(
    SetFacetsWithoutSearch event,
    Emitter<SearchState> emit,
  ) {
    final newConfig = state.configuration.copyWith(
      currentFacets: event.facets,
      searchScopeFacets: event.facets,
    );
    emit(state.copyWith(configuration: newConfig));
  }

  void _onUpdateSortOrder(
    UpdateSortOrder event,
    Emitter<SearchState> emit,
  ) {
    final newConfig = state.configuration.copyWith(sortBy: event.order);
    emit(state.copyWith(configuration: newConfig));
    add(UpdateSearchQuery(state.searchQuery));
  }

  void _onUpdateNumResults(
    UpdateNumResults event,
    Emitter<SearchState> emit,
  ) {
    final newConfig =
        state.configuration.copyWith(numResults: event.numResults);
    emit(state.copyWith(configuration: newConfig));
    add(UpdateSearchQuery(state.searchQuery));
  }

  void _onResetSearch(
    ResetSearch event,
    Emitter<SearchState> emit,
  ) {
    emit(const SearchState());
  }

  Future<int> countForFacet(
    String facet, {
    Map<String, String>? customSpacing,
    Map<int, List<String>>? alternativeWords,
    Map<String, Map<String, bool>>? searchOptions,
  }) async {
    if (state.searchQuery.isEmpty || state.currentFacets.isEmpty) {
      return 0;
    }

    // קודם נבדוק אם יש לנו את הספירה ב-state
    if (state.facetCounts.containsKey(facet)) {
      return state.facetCounts[facet]!;
    }

    // אם אין, נבצע ספירה ישירה (fallback)
    debugPrint('🔢 Counting texts for facet: $facet');
    debugPrint('🔢 Query: ${state.searchQuery}');
    debugPrint(
        '🔢 Books to search: ${state.booksToSearch.map((e) => e.title).toList()}');
    final result = await TantivyDataProvider.instance.countTexts(
      SearchQueryBuilder.sanitizeQuery(state.searchQuery),
      state.booksToSearch.map((e) => e.title).toList(),
      [facet],
      fuzzy: state.fuzzy,
      distance: state.distance,
      searchMode: state.configuration.searchMode,
      customSpacing: customSpacing,
      alternativeWords: alternativeWords,
      searchOptions: searchOptions,
    );
    debugPrint('🔢 Count result for $facet: $result');
    return result;
  }

  /// ספירה מקבצת של תוצאות עבור מספר facets בבת אחת - לשיפור ביצועים
  Future<Map<String, int>> countForMultipleFacets(
    List<String> facets, {
    Map<String, String>? customSpacing,
    Map<int, List<String>>? alternativeWords,
    Map<String, Map<String, bool>>? searchOptions,
  }) async {
    if (state.searchQuery.isEmpty || state.currentFacets.isEmpty) {
      return {for (final facet in facets) facet: 0};
    }

    // קודם נבדוק כמה facets יש לנו כבר ב-state
    final results = <String, int>{};
    final missingFacets = <String>[];

    for (final facet in facets) {
      if (state.facetCounts.containsKey(facet)) {
        results[facet] = state.facetCounts[facet]!;
      } else {
        missingFacets.add(facet);
      }
    }

    // אם יש facets חסרים, נבצע ספירה רק עבורם
    if (missingFacets.isNotEmpty) {
      final missingResults =
          await TantivyDataProvider.instance.countTextsForMultipleFacets(
        SearchQueryBuilder.sanitizeQuery(state.searchQuery),
        state.booksToSearch.map((e) => e.title).toList(),
        missingFacets,
        fuzzy: state.fuzzy,
        distance: state.distance,
        searchMode: state.configuration.searchMode,
        customSpacing: customSpacing,
        alternativeWords: alternativeWords,
        searchOptions: searchOptions,
      );
      results.addAll(missingResults);
    }

    return results;
  }

  /// מחזיר ספירה סינכרונית מה-state (אם קיימת)
  int getFacetCountFromState(String facet) {
    final result = state.facetCounts[facet] ?? 0;
    debugPrint(
        '🔍 getFacetCountFromState($facet) = $result, cache has ${state.facetCounts.length} entries');
    return result;
  }

  // Handlers חדשים לרגקס
  void _onToggleRegex(
    ToggleRegex event,
    Emitter<SearchState> emit,
  ) {
    final newConfig =
        state.configuration.copyWith(regexEnabled: !state.regexEnabled);
    emit(state.copyWith(configuration: newConfig));
    add(UpdateSearchQuery(state.searchQuery));
  }

  void _onToggleCaseSensitive(
    ToggleCaseSensitive event,
    Emitter<SearchState> emit,
  ) {
    final newConfig =
        state.configuration.copyWith(caseSensitive: !state.caseSensitive);
    emit(state.copyWith(configuration: newConfig));
    add(UpdateSearchQuery(state.searchQuery));
  }

  void _onToggleMultiline(
    ToggleMultiline event,
    Emitter<SearchState> emit,
  ) {
    final newConfig = state.configuration.copyWith(multiline: !state.multiline);
    emit(state.copyWith(configuration: newConfig));
    add(UpdateSearchQuery(state.searchQuery));
  }

  void _onToggleDotAll(
    ToggleDotAll event,
    Emitter<SearchState> emit,
  ) {
    final newConfig = state.configuration.copyWith(dotAll: !state.dotAll);
    emit(state.copyWith(configuration: newConfig));
    add(UpdateSearchQuery(state.searchQuery));
  }

  void _onToggleUnicode(
    ToggleUnicode event,
    Emitter<SearchState> emit,
  ) {
    final newConfig = state.configuration.copyWith(unicode: !state.unicode);
    emit(state.copyWith(configuration: newConfig));
    add(UpdateSearchQuery(state.searchQuery));
  }

  void _onUpdateFacetCounts(
    UpdateFacetCounts event,
    Emitter<SearchState> emit,
  ) {
    debugPrint(
        '📝 Updating facet counts: ${event.facetCounts.entries.where((e) => e.value > 0).map((e) => '${e.key}: ${e.value}').join(', ')}');
    final newFacetCounts = event.facetCounts.isEmpty
        ? <String, int>{} // אם מעבירים מפה ריקה, מנקים הכל
        : {...state.facetCounts, ...event.facetCounts};
    emit(state.copyWith(
      facetCounts: newFacetCounts,
    ));
    debugPrint('📊 Total facets in state: ${newFacetCounts.length}');
    if (newFacetCounts.isNotEmpty) {
      debugPrint(
          '📋 All cached facets: ${newFacetCounts.keys.take(10).join(', ')}...');
    } else {
      debugPrint('🧹 Facet counts cleared');
    }
  }

  void _onReplaceFacetCounts(
    ReplaceFacetCounts event,
    Emitter<SearchState> emit,
  ) {
    emit(state.copyWith(facetCounts: event.facetCounts));
  }

  Future<void> _onLoadMoreResults(
    LoadMoreResults event,
    Emitter<SearchState> emit,
  ) async {
    if (state.searchQuery.isEmpty || state.isLoading) {
      return;
    }

    final canLoadMore = state.results.length < state.totalResults;

    if (!canLoadMore) {
      return;
    }

    emit(state.copyWith(isLoading: true));

    try {
      // מבקשים את כל התוצאות עד עכשיו + עוד numResults תוצאות
      final nextResults = await _repository.searchTexts(
        SearchQueryBuilder.sanitizeQuery(state.searchQuery),
        state.currentFacets,
        state.numResults,
        offset: state.results.length,
        fuzzy: state.fuzzy,
        distance: state.distance,
        searchMode: state.configuration.searchMode,
        order: state.sortBy,
        customSpacing: event.customSpacing,
        alternativeWords: event.alternativeWords,
        searchOptions: event.searchOptions,
      );

      emit(state.copyWith(
        results: [...state.results, ...nextResults],
        isLoading: false,
      ));
    } catch (e) {
      emit(state.copyWith(isLoading: false));
    }
  }

  Map<int, Book> _buildBooksByCatalogueOrder(Library library) {
    final orderByBookKey = SearchCatalogueOrderHelper.buildKeyOrderMap(
      library,
      keyOf: (book) => IndexingRepository.catalogueOrderKey(book as Book),
    );
    final booksByCatalogueOrder = <int, Book>{};

    for (final book in library.getAllBooks()) {
      final order = orderByBookKey[IndexingRepository.catalogueOrderKey(book)];
      if (order == null) continue;
      booksByCatalogueOrder.putIfAbsent(order, () => book);
    }

    return booksByCatalogueOrder;
  }

  Map<String, Book> _buildBooksByIndexedFilePath(Library library) {
    final booksByIndexedFilePath = <String, Book>{};

    for (final book in library.getAllBooks()) {
      booksByIndexedFilePath.putIfAbsent(
        IndexingRepository.buildIndexedBookFilePath(book),
        () => book,
      );
    }

    return booksByIndexedFilePath;
  }
}
