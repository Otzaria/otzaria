import 'package:flutter/material.dart';
import 'package:otzaria/search/bloc/search_bloc.dart';
import 'package:otzaria/search/bloc/search_event.dart';
import 'package:otzaria/search/search_query_builder.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:otzaria/models/books.dart';

class SearchingTab extends OpenedTab {
  final searchBloc = SearchBloc();
  final queryController = TextEditingController();
  final searchFieldFocusNode = FocusNode();
  late final ValueNotifier<String> titleNotifier;
  final ValueNotifier<bool> isLeftPaneOpen = ValueNotifier(true);
  final ItemScrollController scrollController = ItemScrollController();
  List<Book> allBooks = [];

  // אפשרויות חיפוש לכל מילה (מילה_אינדקס -> אפשרויות)
  final Map<String, Map<String, bool>> searchOptions = {};

  // אפשרויות חיפוש גלובליות החלות על כל המילים יחד
  // (אינן נאבדות בשינוי מילים בשאילתה)
  final Map<String, bool> globalSearchOptions = {};

  // האם להשתמש בהגדרות הגלובליות (true) או בהגדרות פר-מילה (false)
  final ValueNotifier<bool> useGlobalSearchOptions = ValueNotifier(true);

  // מילים חילופיות לכל מילה (אינדקס_מילה -> רשימת מילים חילופיות)
  final Map<int, List<String>> alternativeWords = {};

  // מרווחים בין מילים (מפתח_מרווח -> ערך_מרווח)
  final Map<String, String> spacingValues = {};

  // notifier לעדכון התצוגה כשמשתמש משנה אפשרויות
  final ValueNotifier<int> searchOptionsChanged = ValueNotifier(0);

  // notifier לעדכון התצוגה כשמשתמש משנה מילים חילופיות
  final ValueNotifier<int> alternativeWordsChanged = ValueNotifier(0);

  // notifier לעדכון התצוגה כשמשתמש משנה מרווחים
  final ValueNotifier<int> spacingValuesChanged = ValueNotifier(0);

  // מטמון של בקשות ספירה פעילות כדי למנוע קריאות כפולות
  final Map<String, Future<int>> _inflight = {};

  static String titleForQuery(String query) {
    final trimmedQuery = query.trim();
    if (trimmedQuery.isEmpty) {
      return 'חיפוש';
    }
    return 'חיפוש: $trimmedQuery';
  }

  SearchingTab(
    super.title,
    String? searchText, {
    super.isPinned = false,
    super.dedupeKey,
  }) {
    titleNotifier = ValueNotifier(title);
    if (searchText != null) {
      queryController.text = searchText;
      // החיפוש מופעל לעצמאי כשהטאב מוצג לראשונה (ראה TantivyFullTextSearch.initState)
    }
  }

  factory SearchingTab.clone(SearchingTab other) {
    final cloned = SearchingTab(
      other.title,
      other.queryController.text,
      isPinned: other.isPinned,
      dedupeKey: other.dedupeKey,
    );

    cloned.searchOptions.addAll(
      other.searchOptions.map(
        (key, value) => MapEntry(key, Map<String, bool>.from(value)),
      ),
    );
    cloned.globalSearchOptions.addAll(other.globalSearchOptions);
    cloned.useGlobalSearchOptions.value = other.useGlobalSearchOptions.value;
    cloned.alternativeWords.addAll(
      other.alternativeWords.map(
        (key, value) => MapEntry(key, List<String>.from(value)),
      ),
    );
    cloned.spacingValues.addAll(other.spacingValues);
    cloned.isLeftPaneOpen.value = other.isLeftPaneOpen.value;

    final state = other.searchBloc.state;
    cloned.searchBloc.add(SetSearchMode(state.configuration.searchMode));
    cloned.searchBloc.add(SetFacetsWithoutSearch(state.searchScopeFacets));

    if (state.configuration.numResults !=
        cloned.searchBloc.state.configuration.numResults) {
      cloned.searchBloc.add(UpdateNumResults(state.configuration.numResults));
    }

    if (state.configuration.sortBy !=
        cloned.searchBloc.state.configuration.sortBy) {
      cloned.searchBloc.add(UpdateSortOrder(state.configuration.sortBy));
    }

    if (state.configuration.distance !=
        cloned.searchBloc.state.configuration.distance) {
      cloned.searchBloc.add(UpdateDistance(state.configuration.distance));
    }

    if (state.searchQuery.trim().isNotEmpty) {
      cloned.updateTitleFromAppliedQuery(state.searchQuery);
    }

    return cloned;
  }

  void updateTitleFromAppliedQuery(String query) {
    final newTitle = titleForQuery(query);
    if (title == newTitle) {
      return;
    }
    title = newTitle;
    titleNotifier.value = newTitle;
  }

  String _normalizeFacet(String s) =>
      s.trim().replaceAll(RegExp(r'/+'), '/'); // אחידות סלאשים + רווחים

  String _optionsHash() {
    String normMap(Map m) => Map.fromEntries(m.entries.toList()
          ..sort((a, b) => a.key.toString().compareTo(b.key.toString())))
        .toString();
    return [
      normMap(searchOptions),
      normMap(globalSearchOptions),
      useGlobalSearchOptions.value.toString(),
      normMap(spacingValues),
      Map.fromEntries(alternativeWords.entries.toList()
            ..sort((a, b) => a.key.compareTo(b.key)))
          .toString(),
    ].join('|');
  }

  String _cacheKey(String facet) {
    final f = _normalizeFacet(facet);
    final q = (searchBloc.state.searchQuery).trim();
    final bVer = searchBloc.state.booksToSearch.length.toString(); // מספר ספרים
    return '$f|q=$q|o=${_optionsHash()}|b=$bVer';
  }

  /// מחזיר את אפשרויות החיפוש האפקטיביות לפי המצב הנוכחי (גלובלי/פר-מילה).
  /// במצב גלובלי - מרחיב את ההגדרות הגלובליות לכל מילה בשאילתה.
  /// במצב פר-מילה - מחזיר את ההגדרות הפר-מיליות הקיימות.
  Map<String, Map<String, bool>> effectiveSearchOptions({String? query}) {
    return SearchQueryBuilder.effectiveSearchOptions(
      query: query ?? queryController.text,
      useGlobalOptions: useGlobalSearchOptions.value,
      globalOptions: globalSearchOptions,
      perWordOptions: searchOptions,
    );
  }

  Future<int> countForFacet(String facet) {
    final normalizedParameters = SearchQueryBuilder.normalizeParametersForMode(
      searchBloc.state.configuration.searchMode,
      customSpacing: spacingValues,
      alternativeWords: alternativeWords,
      searchOptions: effectiveSearchOptions(
        query: searchBloc.state.searchQuery,
      ),
    );
    return searchBloc.countForFacet(
      facet,
      customSpacing: normalizedParameters.customSpacing,
      alternativeWords: normalizedParameters.alternativeWords,
      searchOptions: normalizedParameters.searchOptions,
    );
  }

  /// ספירה מקבצת של תוצאות עבור מספר facets בבת אחת - לשיפור ביצועים
  Future<Map<String, int>> countForMultipleFacets(List<String> facets) {
    final normalizedParameters = SearchQueryBuilder.normalizeParametersForMode(
      searchBloc.state.configuration.searchMode,
      customSpacing: spacingValues,
      alternativeWords: alternativeWords,
      searchOptions: effectiveSearchOptions(
        query: searchBloc.state.searchQuery,
      ),
    );
    return searchBloc.countForMultipleFacets(
      facets,
      customSpacing: normalizedParameters.customSpacing,
      alternativeWords: normalizedParameters.alternativeWords,
      searchOptions: normalizedParameters.searchOptions,
    );
  }

  /// ספירה חכמה - מחזירה תוצאות מהירות מה-state או מבצעת ספירה
  Future<int> countForFacetCached(String facet) async {
    final f = _normalizeFacet(facet);

    // 0) אם יש ב-state (כולל 0) — החזר מיד
    if (searchBloc.state.facetCounts.containsKey(f)) {
      final v = searchBloc.getFacetCountFromState(f);
      debugPrint('💾 Cache hit for $f: $v');
      return v;
    }

    // 1) מפתח קאש כולל query/אפשרויות/גרסת ספרים
    final key = _cacheKey(facet);

    // 2) אם ספירה פעילה — הצמד אליה
    final existing = _inflight[key];
    if (existing != null) {
      debugPrint('⏳ Count in progress for [$key], waiting...');
      return existing;
    }

    debugPrint('🔄 Cache miss for $key, direct count...');
    final sw = Stopwatch()..start();

    final fut = countForFacet(f).then((result) {
      sw.stop();
      debugPrint(
          '⏱️ Direct count for $key took ${sw.elapsedMilliseconds}ms: $result');
      searchBloc.add(UpdateFacetCounts({f: result}));
      return result;
    }).whenComplete(() {
      // תמיד מנקים, גם בשגיאה
      _inflight.remove(key);
    });

    _inflight[key] = fut;
    return fut;
  }

  /// מחזיר ספירה סינכרונית מה-state (אם קיימת)
  int getFacetCountFromState(String facet) {
    return searchBloc.getFacetCountFromState(_normalizeFacet(facet));
  }

  @override
  void dispose() {
    titleNotifier.dispose();
    queryController.dispose();
    searchFieldFocusNode.dispose();
    searchOptionsChanged.dispose();
    alternativeWordsChanged.dispose();
    spacingValuesChanged.dispose();
    useGlobalSearchOptions.dispose();
    // סגירת ה-bloc כדי למנוע דליפה
    searchBloc.close();
    super.dispose();
  }

  factory SearchingTab.fromJson(Map<String, dynamic> json) {
    final tab = SearchingTab(json['title'], json['searchText'],
        isPinned: json['isPinned'] ?? false);
    return tab;
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'searchText': queryController.text,
      'isPinned': isPinned,
      'type': 'SearchingTabWindow'
    };
  }
}
