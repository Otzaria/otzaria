import 'package:flutter/material.dart';
import 'package:otzaria/search/bloc/search_bloc.dart';
import 'package:otzaria/search/bloc/search_event.dart';
import 'package:otzaria/search/models/external_search_status.dart';
import 'package:otzaria/search/models/external_search_summary.dart';
import 'package:otzaria/search/models/search_preview_target.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/search/search_defaults.dart';
import 'package:otzaria/search/search_query_builder.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart';

class SearchingTab extends OpenedTab {
  late final SearchBloc searchBloc;
  final queryController = TextEditingController();
  final negativeQueryController = TextEditingController();
  final searchFieldFocusNode = FocusNode();
  late final ValueNotifier<String> titleNotifier;
  final ValueNotifier<bool> isLeftPaneOpen = ValueNotifier(true);

  /// סיכום סיווג התוצאות של ספק החיפוש החיצוני (תוסף), כשפעיל — מזין את
  /// ספירות הקטגוריות בעץ הסינון. נכתב ע"י מדור התוצאות החיצוני.
  final ValueNotifier<ExternalSearchSummary?> externalSearchSummary =
      ValueNotifier(null);

  /// מצב המדור החיצוני להצגה בשורת המונים שבראש הטאב (מקור, התקדמות
  /// וספירות). נכתב ע"י מדור התוצאות החיצוני; null כשאין ספק פעיל.
  final ValueNotifier<ExternalSearchStatus?> externalSearchStatus =
      ValueNotifier(null);

  /// התוצאה שמוצגת כרגע בתצוגה המקדימה (לחיצה אחת על תוצאה); null = סגורה.
  /// מצב זמני של המסך — לא נשמר ב-JSON של הטאב.
  final ValueNotifier<SearchPreviewTarget?> previewTarget = ValueNotifier(null);

  final ItemScrollController scrollController = ItemScrollController();
  List<Book> allBooks = [];

  // אפשרויות חיפוש לכל מילה (מילה_אינדקס -> אפשרויות)
  final Map<String, Map<String, bool>> searchOptions = {};
  final Map<String, Map<String, bool>> negativeSearchOptions = {};

  // אפשרויות חיפוש גלובליות החלות על כל המילים יחד
  // (אינן נאבדות בשינוי מילים בשאילתה)
  final Map<String, bool> globalSearchOptions = {};
  final Map<String, bool> negativeGlobalSearchOptions = {};

  // האם להשתמש בהגדרות הגלובליות (true) או בהגדרות פר-מילה (false)
  final ValueNotifier<bool> useGlobalSearchOptions = ValueNotifier(true);
  final ValueNotifier<bool> useGlobalNegativeSearchOptions = ValueNotifier(
    true,
  );

  // מילים חילופיות לכל מילה (אינדקס_מילה -> רשימת מילים חילופיות)
  final Map<int, List<String>> alternativeWords = {};
  final Map<int, List<String>> negativeAlternativeWords = {};

  // הרחבת החיפוש בחלופות השמורות הגלובליות — כבוי בכל חיפוש חדש (לא נשמר)
  bool useSavedAlternatives = false;

  // מרווחים בין מילים (מפתח_מרווח -> ערך_מרווח)
  final Map<String, String> spacingValues = {};
  final Map<String, String> negativeSpacingValues = {};

  // notifier לעדכון התצוגה כשמשתמש משנה אפשרויות
  final ValueNotifier<int> searchOptionsChanged = ValueNotifier(0);
  final ValueNotifier<int> negativeSearchOptionsChanged = ValueNotifier(0);

  // notifier לעדכון התצוגה כשמשתמש משנה מילים חילופיות
  final ValueNotifier<int> alternativeWordsChanged = ValueNotifier(0);
  final ValueNotifier<int> negativeAlternativeWordsChanged = ValueNotifier(0);

  // notifier לעדכון התצוגה כשמשתמש משנה מרווחים
  final ValueNotifier<int> spacingValuesChanged = ValueNotifier(0);
  final ValueNotifier<int> negativeSpacingValuesChanged = ValueNotifier(0);

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
    SearchBloc? searchBloc,

    /// האם להריץ אוטומטית שאילתה ממתינה (queryController) כשהטאב מוצג
    /// לראשונה. תוספים יכולים לפתוח טאב עם הטקסט בשדה בלי להריץ חיפוש
    /// (reader.openSearchTab עם autoSearch: false) — אז המשתמש מריץ ידנית.
    this.autoRunInitialSearch = true,
  }) {
    // בלי configuration מפורשת זה טאב חיפוש חדש — הוא נפתח עם המיון ומצב
    // האיחוד שהמשתמש בחר לאחרונה.
    this.searchBloc =
        searchBloc ??
        SearchBloc(
          initialConfiguration:
              initialConfiguration ?? SearchDefaults.withResultPreferences(),
        );
    titleNotifier = ValueNotifier(title);
    if (searchText != null) {
      queryController.text = searchText;
      // החיפוש מופעל לעצמאי כשהטאב מוצג לראשונה (ראה TantivyFullTextSearch.initState)
    }
  }

  /// האם להריץ אוטומטית שאילתה ממתינה בפתיחה הראשונה של הטאב.
  final bool autoRunInitialSearch;

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
      autoRunInitialSearch: other.autoRunInitialSearch,
    );

    cloned.searchOptions.addAll(
      other.searchOptions.map(
        (key, value) => MapEntry(key, Map<String, bool>.from(value)),
      ),
    );
    cloned.globalSearchOptions.addAll(other.globalSearchOptions);
    cloned.negativeSearchOptions.addAll(
      other.negativeSearchOptions.map(
        (key, value) => MapEntry(key, Map<String, bool>.from(value)),
      ),
    );
    cloned.negativeGlobalSearchOptions.addAll(
      other.negativeGlobalSearchOptions,
    );
    cloned.useGlobalSearchOptions.value = other.useGlobalSearchOptions.value;
    cloned.useGlobalNegativeSearchOptions.value =
        other.useGlobalNegativeSearchOptions.value;
    cloned.alternativeWords.addAll(
      other.alternativeWords.map(
        (key, value) => MapEntry(key, List<String>.from(value)),
      ),
    );
    cloned.spacingValues.addAll(other.spacingValues);
    cloned.negativeAlternativeWords.addAll(
      other.negativeAlternativeWords.map(
        (key, value) => MapEntry(key, List<String>.from(value)),
      ),
    );
    cloned.negativeSpacingValues.addAll(other.negativeSpacingValues);
    cloned.negativeQueryController.text = other.negativeQueryController.text;
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
    String normMap(Map m) => Map.fromEntries(
      m.entries.toList()
        ..sort((a, b) => a.key.toString().compareTo(b.key.toString())),
    ).toString();
    return [
      normMap(searchOptions),
      normMap(globalSearchOptions),
      useGlobalSearchOptions.value.toString(),
      normMap(spacingValues),
      negativeQueryController.text.trim(),
      normMap(negativeSearchOptions),
      normMap(negativeGlobalSearchOptions),
      useGlobalNegativeSearchOptions.value.toString(),
      normMap(negativeSpacingValues),
      Map.fromEntries(
        negativeAlternativeWords.entries.toList()
          ..sort((a, b) => a.key.compareTo(b.key)),
      ).toString(),
      Map.fromEntries(
        alternativeWords.entries.toList()
          ..sort((a, b) => a.key.compareTo(b.key)),
      ).toString(),
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

  Map<String, Map<String, bool>> effectiveNegativeSearchOptions({
    String? query,
  }) {
    return SearchQueryBuilder.effectiveSearchOptions(
      query: query ?? negativeQueryController.text,
      useGlobalOptions: useGlobalNegativeSearchOptions.value,
      globalOptions: negativeGlobalSearchOptions,
      perWordOptions: negativeSearchOptions,
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
    final negativeParameters = SearchQueryBuilder.normalizeParametersForMode(
      searchBloc.state.configuration.searchMode,
      customSpacing: negativeSpacingValues,
      alternativeWords: negativeAlternativeWords,
      searchOptions: effectiveNegativeSearchOptions(
        query: searchBloc.state.negativeQuery,
      ),
    );
    return searchBloc.countForFacet(
      facet,
      customSpacing: normalizedParameters.customSpacing,
      alternativeWords: normalizedParameters.alternativeWords,
      searchOptions: normalizedParameters.searchOptions,
      negativeCustomSpacing: negativeParameters.customSpacing,
      negativeAlternativeWords: negativeParameters.alternativeWords,
      negativeSearchOptions: negativeParameters.searchOptions,
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
    final negativeParameters = SearchQueryBuilder.normalizeParametersForMode(
      searchBloc.state.configuration.searchMode,
      customSpacing: negativeSpacingValues,
      alternativeWords: negativeAlternativeWords,
      searchOptions: effectiveNegativeSearchOptions(
        query: searchBloc.state.negativeQuery,
      ),
    );
    return searchBloc.countForMultipleFacets(
      facets,
      customSpacing: normalizedParameters.customSpacing,
      alternativeWords: normalizedParameters.alternativeWords,
      searchOptions: normalizedParameters.searchOptions,
      negativeCustomSpacing: negativeParameters.customSpacing,
      negativeAlternativeWords: negativeParameters.alternativeWords,
      negativeSearchOptions: negativeParameters.searchOptions,
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

    final fut = countForFacet(f)
        .then((result) {
          sw.stop();
          debugPrint(
            '⏱️ Direct count for $key took ${sw.elapsedMilliseconds}ms: $result',
          );
          searchBloc.add(UpdateFacetCounts({f: result}));
          return result;
        })
        .whenComplete(() {
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
    negativeQueryController.dispose();
    searchFieldFocusNode.dispose();
    searchOptionsChanged.dispose();
    alternativeWordsChanged.dispose();
    spacingValuesChanged.dispose();
    negativeSearchOptionsChanged.dispose();
    negativeAlternativeWordsChanged.dispose();
    negativeSpacingValuesChanged.dispose();
    useGlobalSearchOptions.dispose();
    useGlobalNegativeSearchOptions.dispose();
    externalSearchSummary.dispose();
    externalSearchStatus.dispose();
    previewTarget.dispose();
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

    final initialDistance = distanceJson is int
        ? distanceJson
        : defaultConfig.distance;
    final initialMode =
        (searchModeIndex is int &&
            searchModeIndex >= 0 &&
            searchModeIndex < SearchMode.values.length)
        ? SearchMode.values[searchModeIndex]
        : defaultConfig.searchMode;
    final initialNumResults = numResultsJson is int
        ? numResultsJson
        : defaultConfig.numResults;
    final initialSortBy =
        (sortByIndex is int &&
            sortByIndex >= 0 &&
            sortByIndex < ResultsOrder.values.length)
        ? ResultsOrder.values[sortByIndex]
        : defaultConfig.sortBy;
    final scopeIndex = json['proximityScope'];
    final initialProximityScope =
        (scopeIndex is int &&
            scopeIndex >= 0 &&
            scopeIndex < SearchScope.values.length)
        ? SearchScope.values[scopeIndex]
        : defaultConfig.proximityScope;
    final groupingIndex = json['resultGrouping'];
    final initialGrouping =
        (groupingIndex is int &&
            groupingIndex >= 0 &&
            groupingIndex < ResultGroupingMode.values.length)
        ? ResultGroupingMode.values[groupingIndex]
        : defaultConfig.resultGrouping;
    final initialCurrentFacets = rawCurrentFacets is List
        ? rawCurrentFacets.map((e) => e.toString()).toList(growable: false)
        : defaultConfig.currentFacets;
    final initialScopeFacets = rawScopeFacets is List
        ? rawScopeFacets.map((e) => e.toString()).toList(growable: false)
        : defaultConfig.searchScopeFacets;
    final wordMatchModeIndex = json['wordMatchMode'];
    final initialWordMatchMode =
        (wordMatchModeIndex is int &&
            wordMatchModeIndex >= 0 &&
            wordMatchModeIndex < WordMatchMode.values.length)
        ? WordMatchMode.values[wordMatchModeIndex]
        : defaultConfig.wordMatchMode;
    final wordMatchCountJson = json['wordMatchCount'];
    final initialWordMatchCount =
        wordMatchCountJson is int && wordMatchCountJson >= 1
        ? wordMatchCountJson
        : defaultConfig.wordMatchCount;

    final initialConfig = SearchConfiguration(
      distance: initialDistance,
      proximityScope: initialProximityScope,
      searchMode: initialMode,
      numResults: initialNumResults,
      sortBy: initialSortBy,
      resultGrouping: initialGrouping,
      currentFacets: initialCurrentFacets,
      searchScopeFacets: initialScopeFacets,
      wordMatchMode: initialWordMatchMode,
      wordMatchCount: initialWordMatchCount,
      pluginSearchSelections: switch (json['pluginSearchSelections']) {
        final Map values => {
          for (final entry in values.entries)
            if (entry.key is String && entry.value is bool)
              entry.key as String: entry.value as bool,
        },
        _ => defaultConfig.pluginSearchSelections,
      },
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
      autoRunInitialSearch: json['autoRunInitialSearch'] is bool
          ? json['autoRunInitialSearch'] as bool
          : true,
    );
    tab.negativeQueryController.text = json['negativeSearchText'] ?? '';

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

    final rawNegativeSearchOptions = json['negativeSearchOptions'];
    if (rawNegativeSearchOptions is Map) {
      for (final entry in rawNegativeSearchOptions.entries) {
        final value = entry.value;
        if (value is Map) {
          tab.negativeSearchOptions[entry.key.toString()] = {
            for (final inner in value.entries)
              inner.key.toString(): inner.value == true,
          };
        }
      }
    }

    final rawNegativeGlobalOptions = json['negativeGlobalSearchOptions'];
    if (rawNegativeGlobalOptions is Map) {
      for (final entry in rawNegativeGlobalOptions.entries) {
        tab.negativeGlobalSearchOptions[entry.key.toString()] =
            entry.value == true;
      }
    }

    final useGlobal = json['useGlobalSearchOptions'];
    if (useGlobal is bool) {
      tab.useGlobalSearchOptions.value = useGlobal;
    }

    final useGlobalNegative = json['useGlobalNegativeSearchOptions'];
    if (useGlobalNegative is bool) {
      tab.useGlobalNegativeSearchOptions.value = useGlobalNegative;
    }

    final rawAlternatives = json['alternativeWords'];
    if (rawAlternatives is Map) {
      for (final entry in rawAlternatives.entries) {
        final key = int.tryParse(entry.key.toString());
        final value = entry.value;
        if (key != null && value is List) {
          tab.alternativeWords[key] = value
              .map((e) => e.toString())
              .toList(growable: true);
        }
      }
    }

    final rawSpacing = json['spacingValues'];
    if (rawSpacing is Map) {
      for (final entry in rawSpacing.entries) {
        tab.spacingValues[entry.key.toString()] = entry.value.toString();
      }
    }

    final rawNegativeAlternatives = json['negativeAlternativeWords'];
    if (rawNegativeAlternatives is Map) {
      for (final entry in rawNegativeAlternatives.entries) {
        final key = int.tryParse(entry.key.toString());
        final value = entry.value;
        if (key != null && value is List) {
          tab.negativeAlternativeWords[key] = value
              .map((e) => e.toString())
              .toList(growable: true);
        }
      }
    }

    final rawNegativeSpacing = json['negativeSpacingValues'];
    if (rawNegativeSpacing is Map) {
      for (final entry in rawNegativeSpacing.entries) {
        tab.negativeSpacingValues[entry.key.toString()] = entry.value
            .toString();
      }
    }

    tab.dropStalePerWordStateIfNeeded();

    return tab;
  }

  /// state פר-מילה משוחזר שנבנה על ספירת מילים ישנה (חוקי הפיצול של
  /// המנוע השתנו מאז השמירה, למשל `רמב"ם` שהפך משתי מילים לאחת) נופל
  /// בשקט או זולג למילה הלא-נכונה — במקרה כזה עדיף למחוק אותו כליל
  /// והמשתמש יגדיר מחדש.
  void dropStalePerWordStateIfNeeded() {
    final query = queryController.text;
    if (query.trim().isNotEmpty) {
      bool matches;
      try {
        matches = SearchQueryBuilder.restoredPerWordStateMatches(
          query,
          searchOptions: searchOptions,
          alternativeWords: alternativeWords,
          spacingValues: spacingValues,
        );
      } catch (_) {
        // המנוע עדיין לא אותחל — אין דרך לאמת; משאירים כמות שהוא.
        return;
      }
      if (!matches) {
        searchOptions.clear();
        alternativeWords.clear();
        spacingValues.clear();
      }
    }
    if (negativeQueryController.text.trim().isEmpty) return;
    bool negativeMatches;
    try {
      negativeMatches = SearchQueryBuilder.restoredPerWordStateMatches(
        negativeQueryController.text,
        searchOptions: negativeSearchOptions,
        alternativeWords: negativeAlternativeWords,
        spacingValues: negativeSpacingValues,
      );
    } catch (_) {
      return;
    }
    if (!negativeMatches) {
      negativeSearchOptions.clear();
      negativeAlternativeWords.clear();
      negativeSpacingValues.clear();
    }
  }

  @override
  Map<String, dynamic> toJson() {
    final config = searchBloc.state.configuration;
    return {
      'title': title,
      'searchText': queryController.text,
      'negativeSearchText': negativeQueryController.text,
      'autoRunInitialSearch': autoRunInitialSearch,
      'isPinned': isPinned,
      'type': 'SearchingTabWindow',
      'distance': config.distance,
      'proximityScope': config.proximityScope.index,
      'searchMode': config.searchMode.index,
      'numResults': config.numResults,
      'sortBy': config.sortBy.index,
      'resultGrouping': config.resultGrouping.index,
      'currentFacets': config.currentFacets,
      'searchScopeFacets': config.searchScopeFacets,
      'wordMatchMode': config.wordMatchMode.index,
      'wordMatchCount': config.wordMatchCount,
      'pluginSearchSelections': config.pluginSearchSelections,
      'regexEnabled': config.regexEnabled,
      'caseSensitive': config.caseSensitive,
      'multiline': config.multiline,
      'dotAll': config.dotAll,
      'unicode': config.unicode,
      'searchOptions': searchOptions,
      'negativeSearchOptions': negativeSearchOptions,
      'globalSearchOptions': globalSearchOptions,
      'negativeGlobalSearchOptions': negativeGlobalSearchOptions,
      'useGlobalSearchOptions': useGlobalSearchOptions.value,
      'useGlobalNegativeSearchOptions': useGlobalNegativeSearchOptions.value,
      'alternativeWords': {
        for (final entry in alternativeWords.entries)
          entry.key.toString(): entry.value,
      },
      'negativeAlternativeWords': {
        for (final entry in negativeAlternativeWords.entries)
          entry.key.toString(): entry.value,
      },
      'spacingValues': spacingValues,
      'negativeSpacingValues': negativeSpacingValues,
    };
  }
}
