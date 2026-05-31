import 'package:flutter/material.dart';
import 'package:otzaria/search/bloc/search_bloc.dart';
import 'package:otzaria/search/bloc/search_event.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/search/search_query_builder.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart';

class SearchingTab extends OpenedTab {
  late final SearchBloc searchBloc;
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
    SearchConfiguration? initialConfiguration,
  }) {
    searchBloc = SearchBloc(initialConfiguration: initialConfiguration);
    titleNotifier = ValueNotifier(title);
    if (searchText != null) {
      queryController.text = searchText;
      // החיפוש מופעל לעצמאי כשהטאב מוצג לראשונה (ראה TantivyFullTextSearch.initState)
    }
  }

  factory SearchingTab.clone(SearchingTab other) {
    // ה-configuration מועברת ל-Bloc בעת בנייתו, ולא דרך events אחר-כך,
    // כדי למנוע race condition עם UpdateSearchQuery ש-UI שולח ב-initState
    // (ראה הערה מקבילה ב-[SearchingTab.fromJson]).
    final cloned = SearchingTab(
      other.title,
      other.queryController.text,
      isPinned: other.isPinned,
      dedupeKey: other.dedupeKey,
      initialConfiguration: other.searchBloc.state.configuration,
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

    if (other.searchBloc.state.searchQuery.trim().isNotEmpty) {
      cloned.updateTitleFromAppliedQuery(other.searchBloc.state.searchQuery);
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
    // אנו מטמיעים את ה-configuration ישירות ב-SearchBloc בעת בנייתו,
    // ולא דרך events אחרי הבנייה. שליחת events היא async ועלולה
    // להתעבד אחרי שה-UI כבר הפעיל את החיפוש הראשון - וכך החיפוש היה
    // רץ עם distance=0 גם כשנשמר ערך אחר.
    const defaultConfig = SearchConfiguration();
    final distanceJson = json['distance'];
    final searchModeIndex = json['searchMode'];
    final numResultsJson = json['numResults'];
    final sortByIndex = json['sortBy'];
    final rawCurrentFacets = json['currentFacets'];
    final rawScopeFacets = json['searchScopeFacets'];

    final initialDistance =
        distanceJson is int ? distanceJson : defaultConfig.distance;
    final initialMode = (searchModeIndex is int &&
            searchModeIndex >= 0 &&
            searchModeIndex < SearchMode.values.length)
        ? SearchMode.values[searchModeIndex]
        : defaultConfig.searchMode;
    final initialNumResults =
        numResultsJson is int ? numResultsJson : defaultConfig.numResults;
    final initialSortBy = (sortByIndex is int &&
            sortByIndex >= 0 &&
            sortByIndex < ResultsOrder.values.length)
        ? ResultsOrder.values[sortByIndex]
        : defaultConfig.sortBy;
    final initialCurrentFacets = rawCurrentFacets is List
        ? rawCurrentFacets.map((e) => e.toString()).toList(growable: false)
        : defaultConfig.currentFacets;
    final initialScopeFacets = rawScopeFacets is List
        ? rawScopeFacets.map((e) => e.toString()).toList(growable: false)
        : defaultConfig.searchScopeFacets;

    final initialConfig = SearchConfiguration(
      distance: initialDistance,
      searchMode: initialMode,
      numResults: initialNumResults,
      sortBy: initialSortBy,
      currentFacets: initialCurrentFacets,
      searchScopeFacets: initialScopeFacets,
      regexEnabled: json['regexEnabled'] == true,
      caseSensitive: json['caseSensitive'] == true,
      multiline: json['multiline'] == true,
      dotAll: json['dotAll'] == true,
      unicode: json['unicode'] is bool
          ? json['unicode'] as bool
          : defaultConfig.unicode,
    );

    final tab = SearchingTab(
      json['title'],
      json['searchText'],
      isPinned: json['isPinned'] ?? false,
      initialConfiguration: initialConfig,
    );

    final rawSearchOptions = json['searchOptions'];
    if (rawSearchOptions is Map) {
      for (final entry in rawSearchOptions.entries) {
        final value = entry.value;
        if (value is Map) {
          tab.searchOptions[entry.key.toString()] = {
            for (final inner in value.entries)
              inner.key.toString(): inner.value == true,
          };
        }
      }
    }

    final rawGlobalOptions = json['globalSearchOptions'];
    if (rawGlobalOptions is Map) {
      for (final entry in rawGlobalOptions.entries) {
        tab.globalSearchOptions[entry.key.toString()] = entry.value == true;
      }
    }

    final useGlobal = json['useGlobalSearchOptions'];
    if (useGlobal is bool) {
      tab.useGlobalSearchOptions.value = useGlobal;
    }

    final rawAlternatives = json['alternativeWords'];
    if (rawAlternatives is Map) {
      for (final entry in rawAlternatives.entries) {
        final key = int.tryParse(entry.key.toString());
        final value = entry.value;
        if (key != null && value is List) {
          tab.alternativeWords[key] =
              value.map((e) => e.toString()).toList(growable: true);
        }
      }
    }

    final rawSpacing = json['spacingValues'];
    if (rawSpacing is Map) {
      for (final entry in rawSpacing.entries) {
        tab.spacingValues[entry.key.toString()] = entry.value.toString();
      }
    }

    return tab;
  }

  @override
  Map<String, dynamic> toJson() {
    final config = searchBloc.state.configuration;
    return {
      'title': title,
      'searchText': queryController.text,
      'isPinned': isPinned,
      'type': 'SearchingTabWindow',
      'distance': config.distance,
      'searchMode': config.searchMode.index,
      'numResults': config.numResults,
      'sortBy': config.sortBy.index,
      'currentFacets': config.currentFacets,
      'searchScopeFacets': config.searchScopeFacets,
      'regexEnabled': config.regexEnabled,
      'caseSensitive': config.caseSensitive,
      'multiline': config.multiline,
      'dotAll': config.dotAll,
      'unicode': config.unicode,
      'searchOptions': searchOptions,
      'globalSearchOptions': globalSearchOptions,
      'useGlobalSearchOptions': useGlobalSearchOptions.value,
      'alternativeWords': {
        for (final entry in alternativeWords.entries)
          entry.key.toString(): entry.value,
      },
      'spacingValues': spacingValues,
    };
  }
}
