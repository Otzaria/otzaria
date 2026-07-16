import 'dart:async';
import 'dart:convert';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/indexing/repository/indexing_repository.dart';
import 'package:otzaria/search/bloc/search_event.dart';
import 'package:otzaria/search/bloc/search_state.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/data/data_providers/tantivy_data_provider.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/search/search_repository.dart';
import 'package:otzaria/search/utils/search_catalogue_order_helper.dart';
import 'package:otzaria/search/search_query_builder.dart';
import 'package:otzaria/search/utils/facet_helper.dart';
import 'package:flutter/foundation.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart';

/// צילום קלטי ספירת ה-facets ברגע בניית החתימה. אירועי *WithoutSearch יכולים
/// לשנות את ה-state בזמן שהספירה רצה ברקע — הספירה חייבת לרוץ בדיוק עם
/// הערכים שנחתמו, אחרת ספירה של state חדש נשמרת תחת חתימה ישנה.
typedef _FacetRecountInputs = ({
  List<String> scopeFacets,
  bool fuzzy,
  int distance,
  SearchMode searchMode,
  String negativeQuery,
  SearchScope proximityScope,
  WordMatchMode wordMatchMode,
  int wordMatchCount,
});

class SearchBloc extends Bloc<SearchEvent, SearchState> {
  final SearchRepository _repository;
  int _searchRequestId = 0;

  /// חתימת החיפוש שעבורו חושבו ספירות ה-facets שב-state כרגע.
  /// מאפשרת לדלג על ספירת כל-האינדקס (countByBook) כשלחיצה על קטגוריה
  /// מפעילה חיפוש חוזר עם אותה שאילתה ואותן אפשרויות — התוצאה זהה ממילא.
  String? _facetCountsSignature;

  @visibleForTesting
  SearchRepository get repositoryForTesting => _repository;

  @visibleForTesting
  String facetRecountSignatureForTesting(UpdateSearchQuery event) =>
      _facetRecountSignature(event.query, event, _currentFacetRecountInputs());

  @visibleForTesting
  String? get facetCountsSignatureForTesting => _facetCountsSignature;

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

  SearchBloc({
    SearchConfiguration? initialConfiguration,
    SearchRepository repository = const SearchRepository(),
  })  : _repository = repository,
        super(SearchState(
          configuration: initialConfiguration ?? const SearchConfiguration(),
        )) {
    on<UpdateSearchQuery>(_onUpdateSearchQuery);
    on<UpdateDistance>(_onUpdateDistance);
    on<UpdateDistanceWithoutSearch>(_onUpdateDistanceWithoutSearch);
    on<UpdateProximityScope>(_onUpdateProximityScope);
    on<UpdateProximityScopeWithoutSearch>(_onUpdateProximityScopeWithoutSearch);
    on<UpdateWordMatchMode>(_onUpdateWordMatchMode);
    on<UpdateWordMatchModeWithoutSearch>(_onUpdateWordMatchModeWithoutSearch);
    on<ToggleSearchMode>(_onToggleSearchMode);
    on<SetSearchMode>(_onSetSearchMode);
    on<SetSearchModeWithoutSearch>(_onSetSearchModeWithoutSearch);
    on<UpdateBooksToSearch>(_onUpdateBooksToSearch);
    on<AddFacet>(_onAddFacet);
    on<RemoveFacet>(_onRemoveFacet);
    on<SetFacet>(_onSetFacet);
    on<SetFacetsWithoutSearch>(_onSetFacetsWithoutSearch);
    on<UpdateSortOrder>(_onUpdateSortOrder);
    on<UpdateResultGrouping>(_onUpdateResultGrouping);
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
    final negativeQuery = event.negativeQuery ?? state.negativeQuery;
    if (event.query.isEmpty) {
      emit(state.copyWith(
        searchQuery: event.query,
        negativeQuery: negativeQuery,
        results: [],
        totalResults: 0,
        totalGroups: null,
        facetCounts: const {},
      ));
      return;
    }

    if (state.currentFacets.isEmpty) {
      emit(state.copyWith(
        searchQuery: event.query,
        negativeQuery: negativeQuery,
        results: [],
        totalResults: 0,
        totalGroups: null,
        isLoading: false,
        facetCounts: const {},
      ));
      return;
    }

    final requestedFacets = List<String>.from(state.currentFacets);
    final shouldPreserveFacetCounts =
        state.searchQuery == query && state.facetCounts.isNotEmpty;
    // הצילום והחתימה נבנים באותו בלוק סינכרוני — בלי await ביניהם — כדי
    // שהספירה שתרוץ ברקע תתאים תמיד לחתימה שתישמר איתה.
    final recountInputs = _currentFacetRecountInputs();
    final recountSignature =
        _facetRecountSignature(query, event, recountInputs);
    final shouldSkipFacetRecount = state.facetCounts.isNotEmpty &&
        recountSignature == _facetCountsSignature;

    // Clear global cache for new search
    TantivyDataProvider.clearGlobalCache();

    emit(state.copyWith(
      searchQuery: query,
      negativeQuery: negativeQuery,
      isLoading: true,
      facetCounts: shouldPreserveFacetCounts ? state.facetCounts : const {},
      // איפוס שגיאה קודמת בתחילת חיפוש חדש, אחרת הודעת שגיאה ישנה הייתה
      // נשארת ב-state ומבלבלת את המשתמש במהלך החיפוש החדש.
      errorMessage: null,
      // איפוס דגל התוצאות-החלקיות; ייקבע מחדש מאירוע הספירות אם השאילתה
      // חורגת מתקציב האיסוף במנוע.
      resultsTruncated: false,
    ));

    Map<String, Book>? bookByIndexedFilePath;

    // עץ ה-facets נבנה על טווח הסריקה המקורי. כשהחיפוש רץ על אותו טווח
    // (המקרה הרגיל), הספירות של ה-stream המשולב משרתות גם את העץ וגם את
    // הספירה הכוללת — ריצה אחת של השאילתה במקום שלוש. רק כשהמשתמש צמצם
    // לתת-בחירה מהעץ נדרשת ספירת-ספרים נפרדת על הטווח המלא.
    final scopeEqualsSearch = setEquals(
      requestedFacets.toSet(),
      state.searchScopeFacets.toSet(),
    );

    try {
      // ספירת-ספרים נפרדת נדרשת רק כשהחיפוש רץ על תת-בחירה מהעץ (אחרת
      // ה-stream המשולב מספק את הספירות), וגם אז רק אם החתימה השתנתה.
      if (!scopeEqualsSearch && !shouldSkipFacetRecount) {
        unawaited(_refreshFacetCountsForAllBooks(
            event, requestId, recountSignature, recountInputs));
      }

      // stream משולב: האירוע הראשון נושא ספירה כוללת + ספירה לפי ספר
      // מאותו מעבר אינדקס, ואחריו chunks של תוצאות.
      final stream = _repository.searchTextsStreamWithCounts(
        SearchQueryBuilder.sanitizeQuery(query),
        requestedFacets,
        state.numResults,
        chunkSize: 50, // 50 תוצאות בכל chunk
        fuzzy: state.fuzzy,
        distance: state.distance,
        negativeQuery: SearchQueryBuilder.sanitizeQuery(negativeQuery),
        negativeDistance: state.distance,
        scope: state.proximityScope,
        negativeScope: state.proximityScope,
        searchMode: state.configuration.searchMode,
        order: state.sortBy,
        customSpacing: event.customSpacing,
        alternativeWords: event.alternativeWords,
        searchOptions: event.searchOptions,
        negativeCustomSpacing: event.negativeCustomSpacing,
        negativeAlternativeWords: event.negativeAlternativeWords,
        negativeSearchOptions: event.negativeSearchOptions,
        grouping: state.configuration.resultGrouping.engineGrouping,
        wordMatchMode: state.wordMatchMode,
        wordMatchCount: state.wordMatchCount,
      );

      final allResults = <SearchResult>[];

      await for (final update in stream) {
        if (requestId != _searchRequestId) {
          return; // החיפוש בוטל
        }

        final bookCounts = update.bookCounts;
        if (update.totalCount != null) {
          // אירוע הספירות — מגיע עוד לפני ה-chunk הראשון של התוצאות.
          Map<String, int>? aggregated;
          if (scopeEqualsSearch && bookCounts != null) {
            bookByIndexedFilePath ??= _buildBooksByIndexedFilePath(
              await DataRepository.instance.library,
            );
            aggregated = FacetHelper.buildFacetCountsFromBookCounts(
              bookCounts,
              bookByIndexedFilePath,
            );
            // הספירות שנכנסות ל-state חושבו עבור החתימה הנוכחית — שמירה שלה
            // מאפשרת לדלג על ספירה חוזרת בלחיצה על קטגוריה מהעץ.
            _facetCountsSignature = recountSignature;
          }
          emit(state.copyWith(
            totalResults: update.totalCount,
            // מספר הקבוצות כשהאיחוד פעיל; null בחיפוש שטוח — ואז הרשימה
            // נמדדת ב-totalResults כרגיל.
            totalGroups: update.groupCount,
            // null משאיר את הספירות הקיימות (למשל כשהעץ מתעדכן בנפרד
            // דרך ReplaceFacetCounts במקרה של תת-בחירה).
            facetCounts: aggregated,
            isLoading: true,
            // דגל התוצאות-החלקיות מגיע באירוע הספירות בלבד.
            resultsTruncated: update.truncated,
          ));
        }

        if (update.results.isEmpty) {
          continue;
        }
        allResults.addAll(update.results);
        emit(state.copyWith(
          results: List.from(allResults),
          isLoading: true, // עדיין טוען
        ));
      }

      // סיום - כל התוצאות התקבלו
      if (requestId != _searchRequestId) {
        return;
      }

      // יישוב הספירה: כשהעמוד הראשון ביקש את כל התוצאות (total <= limit)
      // אך המנוע החזיר פחות ממה שספר (מסמך שנספר אבל נכשל בשליפה מה-store,
      // נרשם ביומן המנוע), המונה הגולמי היה מצייר "3/4 תוצאות" עם כפתור
      // "טען עוד" שלעולם לא מספק. מיישרים את הספירה למה שבאמת ניתן להצגה.
      // במצב איחוד הרשימה נמדדת בקבוצות — היישוב חל על מונה הקבוצות.
      final effectiveTotal = state.displayTotal;
      final reconciledTotal = (effectiveTotal <= state.numResults &&
              allResults.length < effectiveTotal)
          ? allResults.length
          : effectiveTotal;

      emit(state.copyWith(
        results: allResults,
        totalResults:
            state.totalGroups == null ? reconciledTotal : state.totalResults,
        totalGroups: state.totalGroups == null ? null : reconciledTotal,
        isLoading: false,
      ));
    } catch (e, stackTrace) {
      // זיהוי שגיאה: שגיאת מנוע (למשל כשל קומפילציית רגקס) פעם נבלעה כאן
      // בשקט והוצגה כ"0 תוצאות" — מצב שלא נבדל מחיפוש ריק לגיטימי. כעת:
      // (1) toast מיידי דרך UiSnack, וגם (2) שדה errorMessage ב-state כדי
      // שה-UI יציג שגיאה במקום "אין תוצאות" באופן מתמשך עד החיפוש הבא.
      debugPrint('❌ Search failed: $e\n$stackTrace');
      UiSnack.showError('אירעה שגיאה בעת החיפוש');
      emit(state.copyWith(
        results: [],
        totalResults: 0,
        totalGroups: null,
        isLoading: false,
        errorMessage: 'אירעה שגיאה בעת החיפוש',
      ));
    }
  }

  /// צילום סינכרוני של קלטי הספירה מתוך ה-state הנוכחי.
  _FacetRecountInputs _currentFacetRecountInputs() {
    return (
      scopeFacets: List<String>.from(state.searchScopeFacets),
      fuzzy: state.fuzzy,
      distance: state.distance,
      searchMode: state.configuration.searchMode,
      negativeQuery: state.negativeQuery,
      proximityScope: state.proximityScope,
      wordMatchMode: state.wordMatchMode,
      wordMatchCount: state.wordMatchCount,
    );
  }

  /// חתימה של כל הקלטים שמשפיעים על תוצאת countByBook. חוסר-התאמה גורר
  /// לכל היותר ספירה מיותרת (הכיוון הבטוח), לכן הצפנת ה-JSON אינה ממוינת.
  String _facetRecountSignature(
      String query, UpdateSearchQuery event, _FacetRecountInputs inputs) {
    return [
      query,
      inputs.searchMode.name,
      inputs.fuzzy,
      inputs.distance,
      inputs.scopeFacets.join(','),
      event.negativeQuery ?? inputs.negativeQuery,
      inputs.proximityScope.name,
      inputs.wordMatchMode.name,
      inputs.wordMatchCount,
      jsonEncode(event.customSpacing ?? const <String, String>{}),
      jsonEncode((event.alternativeWords ?? const <int, List<String>>{})
          .map((k, v) => MapEntry(k.toString(), v))),
      jsonEncode(event.searchOptions ?? const <String, Map<String, bool>>{}),
      jsonEncode(event.negativeCustomSpacing ?? const <String, String>{}),
      jsonEncode((event.negativeAlternativeWords ?? const <int, List<String>>{})
          .map((k, v) => MapEntry(k.toString(), v))),
      jsonEncode(
          event.negativeSearchOptions ?? const <String, Map<String, bool>>{}),
    ].join('|');
  }

  Future<void> _refreshFacetCountsForAllBooks(UpdateSearchQuery event,
      int requestId, String signature, _FacetRecountInputs inputs) async {
    final query = event.query;
    final negativeQuery = event.negativeQuery ?? inputs.negativeQuery;
    if (query.isEmpty) return;
    if (requestId != _searchRequestId) return;

    // קבל את כל הספרים מהספרייה כדי למפות key -> Book
    final library = await DataRepository.instance.library;
    final bookByIndexedFilePath = _buildBooksByIndexedFilePath(library);

    // סופר ברמת ספר במנוע עצמו, בלי למשוך עשרות אלפי snippets לדארט.
    // הקלטים מגיעים מהצילום שנלקח עם החתימה — לא מ-state שאולי השתנה מאז.
    final Map<String, int> bookCounts;
    try {
      bookCounts = await TantivyDataProvider.instance.countByBook(
        SearchQueryBuilder.sanitizeQuery(query),
        inputs.scopeFacets,
        fuzzy: inputs.fuzzy,
        distance: inputs.distance,
        negativeQuery: SearchQueryBuilder.sanitizeQuery(negativeQuery),
        negativeDistance: inputs.distance,
        scope: inputs.proximityScope,
        negativeScope: inputs.proximityScope,
        searchMode: inputs.searchMode,
        wordMatchMode: inputs.wordMatchMode,
        wordMatchCount: inputs.wordMatchCount,
        customSpacing: event.customSpacing,
        alternativeWords: event.alternativeWords,
        searchOptions: event.searchOptions,
        negativeCustomSpacing: event.negativeCustomSpacing,
        negativeAlternativeWords: event.negativeAlternativeWords,
        negativeSearchOptions: event.negativeSearchOptions,
      );
    } catch (e, stackTrace) {
      // עדכון ה-facets רץ ב-fire-and-forget (unawaited). המנוע דוחה שאילתה
      // רחבה מדי בשגיאת max expansions — כולל מילה בודדת רחבה — ובלי ה-catch
      // הזה השגיאה הייתה בורחת כחריגה אסינכרונית לא מטופלת. מסלול החיפוש
      // הראשי כבר תופס את אותה שגיאה ומציג toast, לכן כאן רק נרשם ללוג ונשמרות
      // ספירות ה-facets החלקיות שכבר חושבו מהתוצאות.
      debugPrint('❌ Facet count refresh failed: $e\n$stackTrace');
      return;
    }

    // Ignore stale results if query changed while searching
    if (state.searchQuery != query || requestId != _searchRequestId) {
      return;
    }

    final aggregated = FacetHelper.buildFacetCountsFromBookCounts(
      bookCounts,
      bookByIndexedFilePath,
    );

    add(ReplaceFacetCounts(aggregated,
        requestId: requestId, signature: signature));
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
    } catch (e, stackTrace) {
      // זיהוי שגיאה גם במסלול סינון הספרים — אחרת המשתמש רואה "אין תוצאות"
      // ולא מבין שזו תקלה, בדיוק כמו במסלולי החיפוש הראשי וטעינת עוד.
      // הסינון נורה על כל הקלדה, אך UiSnack מחזיק overlay יחיד שמתרענן
      // (לא נערם), כך שאין הצפת toasts גם אם הכשל מתמשך.
      debugPrint('❌ Book filter failed: $e\n$stackTrace');
      UiSnack.showError('אירעה שגיאה בסינון הספרים');
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

  void _onUpdateProximityScope(
    UpdateProximityScope event,
    Emitter<SearchState> emit,
  ) {
    if (!_updateProximityScopeConfiguration(event.scope, emit)) {
      return;
    }
    add(UpdateSearchQuery(state.searchQuery));
  }

  void _onUpdateProximityScopeWithoutSearch(
    UpdateProximityScopeWithoutSearch event,
    Emitter<SearchState> emit,
  ) {
    _updateProximityScopeConfiguration(event.scope, emit);
  }

  bool _updateProximityScopeConfiguration(
    SearchScope scope,
    Emitter<SearchState> emit,
  ) {
    final newConfig = state.configuration.copyWith(proximityScope: scope);
    if (newConfig == state.configuration) {
      return false;
    }

    emit(state.copyWith(configuration: newConfig));
    return true;
  }

  void _onUpdateWordMatchMode(
    UpdateWordMatchMode event,
    Emitter<SearchState> emit,
  ) {
    if (!_updateWordMatchConfiguration(event.mode, event.count, emit)) {
      return;
    }
    add(UpdateSearchQuery(state.searchQuery));
  }

  void _onUpdateWordMatchModeWithoutSearch(
    UpdateWordMatchModeWithoutSearch event,
    Emitter<SearchState> emit,
  ) {
    _updateWordMatchConfiguration(event.mode, event.count, emit);
  }

  bool _updateWordMatchConfiguration(
    WordMatchMode mode,
    int? count,
    Emitter<SearchState> emit,
  ) {
    final newConfig = state.configuration.copyWith(
      wordMatchMode: mode,
      wordMatchCount: count,
    );
    if (newConfig == state.configuration) {
      return false;
    }

    emit(state.copyWith(configuration: newConfig));
    return true;
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

  Future<void> _onAddFacet(
    AddFacet event,
    Emitter<SearchState> emit,
  ) async {
    final newFacets = List<String>.from(state.currentFacets);
    if (!newFacets.contains(event.facet)) {
      debugPrint('➕ AddFacet: ${event.facet} (before=$newFacets)');
      newFacets.add(event.facet);
      final newConfig = state.configuration.copyWith(currentFacets: newFacets);
      if (await _applyClientSideFacetNarrow(
          newFacets, newConfig, UpdateSearchQuery(state.searchQuery), emit)) {
        return;
      }
      emit(state.copyWith(configuration: newConfig));
      add(UpdateSearchQuery(state.searchQuery));
    }
  }

  Future<void> _onRemoveFacet(
    RemoveFacet event,
    Emitter<SearchState> emit,
  ) async {
    final newFacets = List<String>.from(state.currentFacets);
    if (newFacets.contains(event.facet)) {
      debugPrint('➖ RemoveFacet: ${event.facet} (before=$newFacets)');
      newFacets.remove(event.facet);
      final newConfig = state.configuration.copyWith(currentFacets: newFacets);
      if (await _applyClientSideFacetNarrow(
          newFacets, newConfig, UpdateSearchQuery(state.searchQuery), emit)) {
        return;
      }
      emit(state.copyWith(configuration: newConfig));
      add(UpdateSearchQuery(state.searchQuery));
    }
  }

  Future<void> _onSetFacet(
    SetFacet event,
    Emitter<SearchState> emit,
  ) async {
    // Clicking root "/" in a scoped search means "all books within scope"
    final effectiveFacets = (event.facet == '/' && state.hasScopedFacetFilter)
        ? state.searchScopeFacets
        : [event.facet];
    final newConfig =
        state.configuration.copyWith(currentFacets: effectiveFacets);
    final searchEvent = UpdateSearchQuery(
      state.searchQuery,
      customSpacing: event.customSpacing,
      alternativeWords: event.alternativeWords,
      searchOptions: event.searchOptions,
    );
    if (await _applyClientSideFacetNarrow(
        effectiveFacets, newConfig, searchEvent, emit)) {
      return;
    }
    emit(state.copyWith(configuration: newConfig));
    add(searchEvent);
  }

  /// האם [child] נמצא בתוך היקף ה-facet של [parent] (או שווה לו).
  @visibleForTesting
  static bool facetContains(String parent, String child) =>
      parent == '/' || child == parent || child.startsWith('$parent/');

  /// האם המעבר ל-[newFacets] רק מצמצם את ההיקף הנוכחי [oldFacets] —
  /// כלומר כל facet חדש מוכל באחד הקיימים.
  @visibleForTesting
  static bool isFacetNarrowing(
    List<String> oldFacets,
    List<String> newFacets,
  ) =>
      newFacets.isNotEmpty &&
      newFacets.every(
          (newFacet) => oldFacets.any((old) => facetContains(old, newFacet)));

  /// לחיצת קטגוריה מצמצמת כשכל התוצאות כבר בידינו — סינון מקומי מיידי
  /// במקום חיפוש מנוע מלא. מחזירה false כשהתנאים לא מתקיימים (תוצאות
  /// חלקיות, הרחבה, או שהאפשרויות השתנו מאז החיפוש האחרון) — ואז
  /// הקורא ממשיך במסלול המנוע הרגיל.
  Future<bool> _applyClientSideFacetNarrow(
    List<String> newFacets,
    SearchConfiguration newConfig,
    UpdateSearchQuery searchEvent,
    Emitter<SearchState> emit,
  ) async {
    // הסט שבידינו שלם רק כשהמנוע החזיר פחות מהמכסה — אחרת התוצאות חתוכות
    // וסינון מקומי היה מאבד התאמות שמעבר להן.
    //
    // איחוד תוצאות פוסל את המסלול המקומי משתי סיבות: (1) הנציג של קבוצה
    // (במיוחד ב-identicalText) עשוי להיות מספר אחד בעוד חברות הקבוצה
    // (merged) מספרים אחרים — סינון לפי ספר-הנציג בלבד היה מפיל/משאיר
    // קבוצות שלא כדין; (2) totalGroups לא היה מתעדכן כאן והדפדוף היה
    // נשבר. במקום זה החיפוש חוזר למנוע, שמקבץ מחדש בתוך הסינון.
    if (state.searchQuery.isEmpty ||
        state.isLoading ||
        state.errorMessage != null ||
        state.currentFacets.isEmpty ||
        state.results.length >= state.numResults ||
        state.configuration.resultGrouping != ResultGroupingMode.none) {
      return false;
    }

    // האפשרויות המתקדמות אינן נשמרות ב-state; חתימת הספירות מעידה שהחיפוש
    // האחרון רץ עם בדיוק אותם קלטים כמו הלחיצה הנוכחית.
    final signature = _facetRecountSignature(
        state.searchQuery, searchEvent, _currentFacetRecountInputs());
    if (signature != _facetCountsSignature) {
      return false;
    }

    if (!isFacetNarrowing(state.currentFacets, newFacets)) {
      return false;
    }

    final stateBeforeAwait = state;
    final library = await DataRepository.instance.library;
    // ה-handlers רצים במקביל (bloc 9) — אם state השתנה בזמן ההמתנה,
    // התנאים שנבדקו כבר לא תקפים ונופלים למסלול המנוע.
    if (!identical(state, stateBeforeAwait)) {
      return false;
    }

    final bookByCatalogueOrder = _buildBooksByCatalogueOrder(library);
    final filtered = <SearchResult>[];
    for (final result in state.results) {
      final catalogueOrder =
          IndexingRepository.catalogueOrderFromDocumentId(result.id);
      final book = bookByCatalogueOrder[catalogueOrder];
      if (book == null) {
        return false;
      }
      final facetPath = FacetHelper.buildBookFacet(
          FacetHelper.resolveCategoryPath(book), book);
      if (newFacets.any((facet) => facetContains(facet, facetPath))) {
        filtered.add(result);
      }
    }

    // מבטל המשכים תלויים של החיפוש הקודם (כמו countTexts שעוד ממתין) —
    // אחרת הם היו דורסים את totalResults המסונן בספירת ההיקף הרחב.
    _searchRequestId++;

    emit(state.copyWith(
      configuration: newConfig,
      results: filtered,
      totalResults: filtered.length,
      isLoading: false,
    ));
    return true;
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

  void _onUpdateResultGrouping(
    UpdateResultGrouping event,
    Emitter<SearchState> emit,
  ) {
    if (event.grouping == state.configuration.resultGrouping) return;
    final newConfig =
        state.configuration.copyWith(resultGrouping: event.grouping);
    emit(state.copyWith(configuration: newConfig, totalGroups: null));
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
    _facetCountsSignature = null;
    emit(const SearchState());
  }

  Future<int> countForFacet(
    String facet, {
    Map<String, String>? customSpacing,
    Map<int, List<String>>? alternativeWords,
    Map<String, Map<String, bool>>? searchOptions,
    Map<String, String>? negativeCustomSpacing,
    Map<int, List<String>>? negativeAlternativeWords,
    Map<String, Map<String, bool>>? negativeSearchOptions,
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
      negativeQuery: SearchQueryBuilder.sanitizeQuery(state.negativeQuery),
      negativeDistance: state.distance,
      scope: state.proximityScope,
      negativeScope: state.proximityScope,
      searchMode: state.configuration.searchMode,
      wordMatchMode: state.wordMatchMode,
      wordMatchCount: state.wordMatchCount,
      customSpacing: customSpacing,
      alternativeWords: alternativeWords,
      searchOptions: searchOptions,
      negativeCustomSpacing: negativeCustomSpacing,
      negativeAlternativeWords: negativeAlternativeWords,
      negativeSearchOptions: negativeSearchOptions,
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
    Map<String, String>? negativeCustomSpacing,
    Map<int, List<String>>? negativeAlternativeWords,
    Map<String, Map<String, bool>>? negativeSearchOptions,
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
        negativeQuery: SearchQueryBuilder.sanitizeQuery(state.negativeQuery),
        negativeDistance: state.distance,
        scope: state.proximityScope,
        negativeScope: state.proximityScope,
        searchMode: state.configuration.searchMode,
        wordMatchMode: state.wordMatchMode,
        wordMatchCount: state.wordMatchCount,
        customSpacing: customSpacing,
        alternativeWords: alternativeWords,
        searchOptions: searchOptions,
        negativeCustomSpacing: negativeCustomSpacing,
        negativeAlternativeWords: negativeAlternativeWords,
        negativeSearchOptions: negativeSearchOptions,
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
    // התעלמות מספירות של חיפוש שכבר הוחלף בזמן שה-event המתין בתור.
    if (event.requestId != _searchRequestId) return;
    // החתימה נשמרת רק כשהספירות באמת נכנסות ל-state, כדי שהדילוג על ספירה
    // חוזרת לעולם לא יסתמך על ספירות שנזרקו בגלל requestId ישן.
    _facetCountsSignature = event.signature;
    emit(state.copyWith(facetCounts: event.facetCounts));
  }

  Future<void> _onLoadMoreResults(
    LoadMoreResults event,
    Emitter<SearchState> emit,
  ) async {
    if (state.searchQuery.isEmpty || state.isLoading) {
      return;
    }

    // במצב איחוד הרשימה והדפדוף נספרים בקבוצות (displayTotal מחזיר את
    // מונה הקבוצות כשהוא קיים).
    final canLoadMore = state.results.length < state.displayTotal;

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
        negativeQuery: SearchQueryBuilder.sanitizeQuery(state.negativeQuery),
        negativeDistance: state.distance,
        scope: state.proximityScope,
        negativeScope: state.proximityScope,
        searchMode: state.configuration.searchMode,
        order: state.sortBy,
        customSpacing: event.customSpacing,
        alternativeWords: event.alternativeWords,
        searchOptions: event.searchOptions,
        negativeCustomSpacing: event.negativeCustomSpacing,
        negativeAlternativeWords: event.negativeAlternativeWords,
        negativeSearchOptions: event.negativeSearchOptions,
        grouping: state.configuration.resultGrouping.engineGrouping,
        wordMatchMode: state.wordMatchMode,
        wordMatchCount: state.wordMatchCount,
      );

      final combined = [...state.results, ...nextResults];
      final exhausted = nextResults.isEmpty;
      emit(state.copyWith(
        results: combined,
        // עמוד ריק למרות שהמונה מבטיח עוד: ההיטים הנותרים נספרו אך
        // אינם ניתנים לשליפה (ראה יומן המנוע). בלי היישור הזה הכפתור היה
        // מציג "טען תוצאות נוספות (N)" לנצח ומסתובב בלי להביא כלום.
        // היישור חל על המונה שהרשימה נמדדת בו: קבוצות במצב איחוד.
        totalResults:
            exhausted && state.totalGroups == null ? combined.length : null,
        totalGroups: exhausted && state.totalGroups != null
            ? combined.length
            : state.totalGroups,
        isLoading: false,
      ));
    } catch (e, stackTrace) {
      debugPrint('❌ Load more results failed: $e\n$stackTrace');
      UiSnack.showError('אירעה שגיאה בטעינת תוצאות נוספות');
      emit(state.copyWith(isLoading: false));
    }
  }

  /// הספר האמיתי של תוצאת חיפוש לפי שדה ה-filePath של המסמך — מפתח יציב
  /// שאינו תלוי בסדר הקטלוג בזמן האינדוקס ('uid:5'/'id:5' או נתיב PDF).
  ///
  /// פתיחה לפי כותרת בלבד מאבדת את זהות הספר (isUserBook/categoryId),
  /// וספר אישי שכותרתו זהה לספר רשמי היה נפתח כרשמי. מחזירה null אם
  /// המפתח לא אותר בקטלוג (ואז נופלים לבנייה לפי כותרת).
  Future<Book?> resolveBookForIndexedPath(String indexedFilePath) async {
    final library = await DataRepository.instance.library;
    if (!identical(library, _resolveCacheLibrary)) {
      _resolveCacheLibrary = library;
      _booksByIndexedFilePathCache = bookForIndexedFilePathMap(library);
    }
    return _booksByIndexedFilePathCache?[indexedFilePath];
  }

  Library? _resolveCacheLibrary;
  Map<String, Book>? _booksByIndexedFilePathCache;

  @visibleForTesting
  static Map<String, Book> bookForIndexedFilePathMap(Library library) =>
      _buildBooksByIndexedFilePath(library);

  Map<int, Book> _buildBooksByCatalogueOrder(Library library) {
    final keyOrder = SearchCatalogueOrderHelper.buildKeyOrderMap(
      library,
      keyOf: (book) => IndexingRepository.catalogueOrderKey(book as Book),
    );
    final booksByOrder = <int, Book>{};
    for (final book in library.getAllBooks()) {
      final order = keyOrder[IndexingRepository.catalogueOrderKey(book)];
      if (order != null) {
        booksByOrder.putIfAbsent(order, () => book);
      }
    }
    return booksByOrder;
  }

  static Map<String, Book> _buildBooksByIndexedFilePath(Library library) {
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
