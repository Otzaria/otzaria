import 'dart:async';

import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/utils/text/text_manipulation.dart' as text_utils;
import 'package:otzaria_search_engine/otzaria_search_engine.dart';

/// סנטינל ל-copyWith: מבדיל בין "פרמטר לא הועבר" לבין "אפס במפורש ל-null"
/// עבור שדות nullable (ראה [SearchEngineRequest.copyWith]).
const Object _unset = Object();

/// בקשת חיפוש אחידה שמגיעה משכבת האפליקציה אל מנוע החיפוש.
///
/// המחלקה מכילה את בחירות ה-UI והניווט בלבד. מנוע החיפוש אחראי לכל
/// המשמעות האלגוריתמית של סוגי החיפוש.
class SearchEngineRequest {
  final String query;
  final List<String> facets;
  final int limit;
  final int offset;
  final ResultsOrder order;
  final SearchMode searchMode;
  final int distance;
  final String negativeQuery;
  final int negativeDistance;

  /// טווח הקרבה בין מילות שאילתה מרובת-מילים במצב המתקדם: מרווח מילים
  /// (סדר + מרחק), אותה פסקה, או אותה כותרת. רלוונטי רק ל-searchMode
  /// advanced — המצבים המדויק והמקורב מתעלמים ממנו.
  final SearchScope scope;
  final SearchScope negativeScope;

  /// כמה ממילות השאילתה חייבות להופיע בתוצאה (מצב מתקדם בלבד):
  /// כולן (ברירת המחדל) / מילה אחת / רוב / לפחות [wordMatchCount].
  /// בכל מצב שאינו all המנוע מוותר על דרישת הסדר והמרחק.
  final WordMatchMode wordMatchMode;

  /// מספר המילים הנדרש כש-[wordMatchMode] הוא atLeast; המנוע חותך
  /// לטווח החוקי.
  final int? wordMatchCount;
  final Map<String, String> customSpacing;
  final Map<String, String> negativeCustomSpacing;
  final Map<int, List<String>> alternativeWords;
  final Map<int, List<String>> negativeAlternativeWords;
  final Map<String, Map<String, bool>> searchOptions;
  final Map<String, Map<String, bool>> negativeSearchOptions;

  /// חיפוש מנוקד: ניקוד שהוקלד נדרש להופיע בטקסט; חל רק על שורות מנוקדות
  /// באינדקס. ברירת מחדל כבוי — חיפוש רגיל מתעלם מניקוד לחלוטין.
  final bool matchNikud;

  /// כמו [matchNikud] עבור טעמי המקרא.
  final bool matchTaamim;

  /// איחוד תוצאות במנוע: `null` = רשימה שטוחה (ההתנהגות הרגילה);
  /// [ResultGrouping.sameSection] = כרטיס אחד לכל סעיף עם מונה "נמצאו X
  /// תוצאות בטווח"; [ResultGrouping.identicalText] = איחוד שורות זהות
  /// חוצה-ספרים. limit/offset נספרים בקבוצות כשהאיחוד פעיל.
  final ResultGrouping? grouping;

  const SearchEngineRequest({
    required this.query,
    required this.facets,
    this.limit = 0,
    this.offset = 0,
    this.order = ResultsOrder.relevance,
    this.searchMode = SearchMode.exact,
    this.distance = 0,
    this.negativeQuery = '',
    this.negativeDistance = 0,
    this.scope = SearchScope.wordDistance,
    this.negativeScope = SearchScope.wordDistance,
    this.customSpacing = const {},
    this.negativeCustomSpacing = const {},
    this.alternativeWords = const {},
    this.negativeAlternativeWords = const {},
    this.searchOptions = const {},
    this.negativeSearchOptions = const {},
    this.matchNikud = false,
    this.matchTaamim = false,
    this.grouping,
    this.wordMatchMode = WordMatchMode.all,
    this.wordMatchCount,
  });

  SearchEngineRequest copyWith({
    String? query,
    List<String>? facets,
    int? limit,
    int? offset,
    ResultsOrder? order,
    SearchMode? searchMode,
    int? distance,
    String? negativeQuery,
    int? negativeDistance,
    SearchScope? scope,
    SearchScope? negativeScope,
    Map<String, String>? customSpacing,
    Map<String, String>? negativeCustomSpacing,
    Map<int, List<String>>? alternativeWords,
    Map<int, List<String>>? negativeAlternativeWords,
    Map<String, Map<String, bool>>? searchOptions,
    Map<String, Map<String, bool>>? negativeSearchOptions,
    bool? matchNikud,
    bool? matchTaamim,
    Object? grouping = _unset,
    WordMatchMode? wordMatchMode,
    Object? wordMatchCount = _unset,
  }) {
    return SearchEngineRequest(
      query: query ?? this.query,
      facets: facets ?? this.facets,
      limit: limit ?? this.limit,
      offset: offset ?? this.offset,
      order: order ?? this.order,
      searchMode: searchMode ?? this.searchMode,
      distance: distance ?? this.distance,
      negativeQuery: negativeQuery ?? this.negativeQuery,
      negativeDistance: negativeDistance ?? this.negativeDistance,
      scope: scope ?? this.scope,
      negativeScope: negativeScope ?? this.negativeScope,
      customSpacing: customSpacing ?? this.customSpacing,
      negativeCustomSpacing:
          negativeCustomSpacing ?? this.negativeCustomSpacing,
      alternativeWords: alternativeWords ?? this.alternativeWords,
      negativeAlternativeWords:
          negativeAlternativeWords ?? this.negativeAlternativeWords,
      searchOptions: searchOptions ?? this.searchOptions,
      negativeSearchOptions:
          negativeSearchOptions ?? this.negativeSearchOptions,
      matchNikud: matchNikud ?? this.matchNikud,
      matchTaamim: matchTaamim ?? this.matchTaamim,
      grouping: identical(grouping, _unset)
          ? this.grouping
          : grouping as ResultGrouping?,
      wordMatchMode: wordMatchMode ?? this.wordMatchMode,
      wordMatchCount: identical(wordMatchCount, _unset)
          ? this.wordMatchCount
          : wordMatchCount as int?,
    );
  }
}

/// ממשק קטן וניתן לבדיקה מעל ה-API של `search_engine`.
abstract class SearchEngineOperations {
  Future<List<SearchResult>> searchExact(SearchEngineRequest request);
  Future<List<SearchResult>> searchAdvanced(SearchEngineRequest request);
  Future<List<SearchResult>> searchFuzzy(SearchEngineRequest request);

  Future<SearchPageResult> searchAndCountExact(SearchEngineRequest request);
  Future<SearchPageResult> searchAndCountAdvanced(SearchEngineRequest request);
  Future<SearchPageResult> searchAndCountFuzzy(SearchEngineRequest request);

  Stream<List<SearchResult>> searchExactStream(
    SearchEngineRequest request, {
    required int chunkSize,
  });
  Stream<List<SearchResult>> searchAdvancedStream(
    SearchEngineRequest request, {
    required int chunkSize,
  });
  Stream<List<SearchResult>> searchFuzzyStream(
    SearchEngineRequest request, {
    required int chunkSize,
  });

  Future<int> countExact(SearchEngineRequest request);
  Future<int> countAdvanced(SearchEngineRequest request);
  Future<int> countFuzzy(SearchEngineRequest request);

  Future<Map<String, int>> countByBookExact(SearchEngineRequest request);
  Future<Map<String, int>> countByBookAdvanced(SearchEngineRequest request);
  Future<Map<String, int>> countByBookFuzzy(SearchEngineRequest request);

  Future<List<FacetCount>> getFacetCountsExact(
    SearchEngineRequest request, {
    required String facetPrefix,
  });
  Future<List<FacetCount>> getFacetCountsAdvanced(
    SearchEngineRequest request, {
    required String facetPrefix,
  });
  Future<List<FacetCount>> getFacetCountsFuzzy(
    SearchEngineRequest request, {
    required String facetPrefix,
  });

  /// מזין מראש את תבנית הדגשת-הספר-הפתוח מבוססת-האינדקס לפרמטרי החיפוש —
  /// כך שכשהמשתמש יפתח תוצאה, `utils.highLight` ימצא תבנית שמדגישה את
  /// הווריאנטים שהחיפוש באמת התאים (שגיאות כתיב, קידומות, חלק ממילה).
  /// Fire-and-forget; ברירת מחדל ריקה למימושי בדיקות.
  void primeHighlightPattern(SearchEngineRequest request) {}

  /// Stream חיפוש משולב: האירוע הראשון נושא את הספירה הכוללת ואת הספירה
  /// לפי ספר, ואחריו מגיעים chunks של תוצאות. במימוש ה-Rust כל אלה מחושבים
  /// במעבר אינדקס אחד — במקום שלוש ריצות נפרדות של אותה שאילתה (stream +
  /// count + countByBook).
  ///
  /// ברירת המחדל כאן מרכיבה את אותה סמנטיקה מהמתודות הקיימות, כך שמימושי
  /// בדיקות קיימים ממשיכים לעבוד בלי לממש את המתודה.
  Stream<SearchStreamUpdate> searchStreamWithCounts(
    SearchEngineRequest request, {
    required int chunkSize,
  }) async* {
    final Map<String, int> byBook = switch (request.searchMode) {
      SearchMode.exact => await countByBookExact(request),
      SearchMode.advanced => await countByBookAdvanced(request),
      SearchMode.fuzzy => await countByBookFuzzy(request),
    };
    yield SearchStreamUpdate(
      totalCount: byBook.values.fold<int>(0, (sum, count) => sum + count),
      bookCounts: byBook,
      results: const [],
      // This compatibility fallback runs the separate count/stream calls and
      // has no visibility into single-word budget truncation; the real Rust
      // stream surfaces it.
      truncated: false,
    );
    final chunks = switch (request.searchMode) {
      SearchMode.exact => searchExactStream(request, chunkSize: chunkSize),
      SearchMode.advanced => searchAdvancedStream(
        request,
        chunkSize: chunkSize,
      ),
      SearchMode.fuzzy => searchFuzzyStream(request, chunkSize: chunkSize),
    };
    await for (final chunk in chunks) {
      yield SearchStreamUpdate(results: chunk, truncated: false);
    }
  }
}

class RustSearchEngineOperations implements SearchEngineOperations {
  final SearchEngine _engine;

  const RustSearchEngineOperations(this._engine);

  /// חיפוש רגיל (מדויק) עם פרמטרים: ל-API המדויק של המנוע אין מרווח בין
  /// מילים ולא אפשרויות מילה, אבל המסלול המתקדם עם אותם פרמטרים בלבד
  /// מתנוון בדיוק לחיפוש הרגיל המורחב — המילים בסדרן, אכיפת מרווח לכל
  /// זוג, ואפשרויות המילה (שגיאות כתיב, קידומות/סיומות, כתיב מלא/חסר,
  /// חלק ממילה) — לכן בקשה מדויקת שנושאת אותם מנותבת אליו. הפרמטרים
  /// שהחיפוש הרגיל אינו תומך בהם (מילים חלופיות, מרווחים ידניים,
  /// שאילתה שלילית, scope) מרוקנים במפורש, כדי ששאריות ממצב מתקדם קודם
  /// לא יזלגו פנימה.
  ///
  /// מחזיר null כשאין מה לנתב (מרווח 0 ובלי אפשרויות — המסלול המדויק
  /// המהיר נשאר).
  static SearchEngineRequest? _exactWithParametersAsAdvanced(
    SearchEngineRequest request,
  ) {
    if (request.searchMode != SearchMode.exact) {
      return null;
    }
    final hasOptions = request.searchOptions.values.any(
      (options) => options.values.any((enabled) => enabled),
    );
    if (request.distance <= 0 && !hasOptions) {
      return null;
    }
    return request.copyWith(
      searchMode: SearchMode.advanced,
      negativeQuery: '',
      negativeDistance: 0,
      scope: SearchScope.wordDistance,
      negativeScope: SearchScope.wordDistance,
      customSpacing: const {},
      negativeCustomSpacing: const {},
      alternativeWords: const {},
      negativeAlternativeWords: const {},
      negativeSearchOptions: const {},
      wordMatchMode: WordMatchMode.all,
      wordMatchCount: null,
    );
  }

  @override
  Future<List<SearchResult>> searchExact(SearchEngineRequest request) {
    final gapped = _exactWithParametersAsAdvanced(request);
    if (gapped != null) return searchAdvanced(gapped);
    return _engine.searchExact(
      query: request.query,
      facets: request.facets,
      limit: request.limit,
      offset: request.offset,
      order: request.order,
      matchNikud: request.matchNikud,
      matchTaamim: request.matchTaamim,
      grouping: request.grouping,
    );
  }

  @override
  Future<List<SearchResult>> searchAdvanced(SearchEngineRequest request) {
    return _engine.searchAdvanced(
      query: request.query,
      negativeQuery: request.negativeQuery,
      facets: request.facets,
      limit: request.limit,
      offset: request.offset,
      distance: request.distance,
      negativeDistance: request.negativeDistance,
      customSpacing: request.customSpacing,
      negativeCustomSpacing: request.negativeCustomSpacing,
      alternativeWords: request.alternativeWords,
      negativeAlternativeWords: request.negativeAlternativeWords,
      searchOptions: request.searchOptions,
      negativeSearchOptions: request.negativeSearchOptions,
      order: request.order,
      matchNikud: request.matchNikud,
      matchTaamim: request.matchTaamim,
      scope: request.scope,
      negativeScope: request.negativeScope,
      grouping: request.grouping,
      wordMatchMode: request.wordMatchMode,
      wordMatchCount: request.wordMatchCount,
    );
  }

  @override
  Future<List<SearchResult>> searchFuzzy(SearchEngineRequest request) {
    return _engine.searchFuzzy(
      query: request.query,
      facets: request.facets,
      limit: request.limit,
      offset: request.offset,
      maxDistance: _fuzzyDistance(request.distance),
      order: request.order,
      matchNikud: request.matchNikud,
      matchTaamim: request.matchTaamim,
      grouping: request.grouping,
    );
  }

  @override
  Future<SearchPageResult> searchAndCountExact(SearchEngineRequest request) {
    final gapped = _exactWithParametersAsAdvanced(request);
    if (gapped != null) return searchAndCountAdvanced(gapped);
    return _engine.searchAndCountExact(
      query: request.query,
      facets: request.facets,
      limit: request.limit,
      offset: request.offset,
      order: request.order,
      matchNikud: request.matchNikud,
      matchTaamim: request.matchTaamim,
      grouping: request.grouping,
    );
  }

  @override
  Future<SearchPageResult> searchAndCountAdvanced(
    SearchEngineRequest request,
  ) {
    return _engine.searchAndCountAdvanced(
      query: request.query,
      negativeQuery: request.negativeQuery,
      facets: request.facets,
      limit: request.limit,
      offset: request.offset,
      distance: request.distance,
      negativeDistance: request.negativeDistance,
      customSpacing: request.customSpacing,
      negativeCustomSpacing: request.negativeCustomSpacing,
      alternativeWords: request.alternativeWords,
      negativeAlternativeWords: request.negativeAlternativeWords,
      searchOptions: request.searchOptions,
      negativeSearchOptions: request.negativeSearchOptions,
      order: request.order,
      matchNikud: request.matchNikud,
      matchTaamim: request.matchTaamim,
      scope: request.scope,
      negativeScope: request.negativeScope,
      grouping: request.grouping,
      wordMatchMode: request.wordMatchMode,
      wordMatchCount: request.wordMatchCount,
    );
  }

  @override
  Future<SearchPageResult> searchAndCountFuzzy(SearchEngineRequest request) {
    return _engine.searchAndCountFuzzy(
      query: request.query,
      facets: request.facets,
      limit: request.limit,
      offset: request.offset,
      maxDistance: _fuzzyDistance(request.distance),
      order: request.order,
      matchNikud: request.matchNikud,
      matchTaamim: request.matchTaamim,
      grouping: request.grouping,
    );
  }

  @override
  Stream<List<SearchResult>> searchExactStream(
    SearchEngineRequest request, {
    required int chunkSize,
  }) {
    final gapped = _exactWithParametersAsAdvanced(request);
    if (gapped != null) {
      return searchAdvancedStream(gapped, chunkSize: chunkSize);
    }
    return _engine.searchExactStream(
      query: request.query,
      facets: request.facets,
      limit: request.limit,
      offset: request.offset,
      order: request.order,
      chunkSize: chunkSize,
      matchNikud: request.matchNikud,
      matchTaamim: request.matchTaamim,
      grouping: request.grouping,
    );
  }

  @override
  Stream<List<SearchResult>> searchAdvancedStream(
    SearchEngineRequest request, {
    required int chunkSize,
  }) {
    return _engine.searchAdvancedStream(
      query: request.query,
      negativeQuery: request.negativeQuery,
      facets: request.facets,
      limit: request.limit,
      offset: request.offset,
      distance: request.distance,
      negativeDistance: request.negativeDistance,
      customSpacing: request.customSpacing,
      negativeCustomSpacing: request.negativeCustomSpacing,
      alternativeWords: request.alternativeWords,
      negativeAlternativeWords: request.negativeAlternativeWords,
      searchOptions: request.searchOptions,
      negativeSearchOptions: request.negativeSearchOptions,
      order: request.order,
      chunkSize: chunkSize,
      matchNikud: request.matchNikud,
      matchTaamim: request.matchTaamim,
      scope: request.scope,
      negativeScope: request.negativeScope,
      grouping: request.grouping,
      wordMatchMode: request.wordMatchMode,
      wordMatchCount: request.wordMatchCount,
    );
  }

  @override
  Stream<List<SearchResult>> searchFuzzyStream(
    SearchEngineRequest request, {
    required int chunkSize,
  }) {
    return _engine.searchFuzzyStream(
      query: request.query,
      facets: request.facets,
      limit: request.limit,
      offset: request.offset,
      maxDistance: _fuzzyDistance(request.distance),
      order: request.order,
      chunkSize: chunkSize,
      matchNikud: request.matchNikud,
      matchTaamim: request.matchTaamim,
      grouping: request.grouping,
    );
  }

  @override
  Future<int> countExact(SearchEngineRequest request) {
    final gapped = _exactWithParametersAsAdvanced(request);
    if (gapped != null) return countAdvanced(gapped);
    return _engine.countExact(
      query: request.query,
      facets: request.facets,
      matchNikud: request.matchNikud,
      matchTaamim: request.matchTaamim,
    );
  }

  @override
  Future<int> countAdvanced(SearchEngineRequest request) {
    return _engine.countAdvanced(
      query: request.query,
      negativeQuery: request.negativeQuery,
      facets: request.facets,
      distance: request.distance,
      negativeDistance: request.negativeDistance,
      customSpacing: request.customSpacing,
      negativeCustomSpacing: request.negativeCustomSpacing,
      alternativeWords: request.alternativeWords,
      negativeAlternativeWords: request.negativeAlternativeWords,
      searchOptions: request.searchOptions,
      negativeSearchOptions: request.negativeSearchOptions,
      matchNikud: request.matchNikud,
      matchTaamim: request.matchTaamim,
      scope: request.scope,
      negativeScope: request.negativeScope,
      wordMatchMode: request.wordMatchMode,
      wordMatchCount: request.wordMatchCount,
    );
  }

  @override
  Future<int> countFuzzy(SearchEngineRequest request) {
    return _engine.countFuzzy(
      query: request.query,
      facets: request.facets,
      maxDistance: _fuzzyDistance(request.distance),
      matchNikud: request.matchNikud,
      matchTaamim: request.matchTaamim,
    );
  }

  @override
  Future<Map<String, int>> countByBookExact(SearchEngineRequest request) {
    final gapped = _exactWithParametersAsAdvanced(request);
    if (gapped != null) return countByBookAdvanced(gapped);
    return _engine.countByBookExact(
      query: request.query,
      facets: request.facets,
      matchNikud: request.matchNikud,
      matchTaamim: request.matchTaamim,
    );
  }

  @override
  Future<Map<String, int>> countByBookAdvanced(SearchEngineRequest request) {
    return _engine.countByBookAdvanced(
      query: request.query,
      negativeQuery: request.negativeQuery,
      facets: request.facets,
      distance: request.distance,
      negativeDistance: request.negativeDistance,
      customSpacing: request.customSpacing,
      negativeCustomSpacing: request.negativeCustomSpacing,
      alternativeWords: request.alternativeWords,
      negativeAlternativeWords: request.negativeAlternativeWords,
      searchOptions: request.searchOptions,
      negativeSearchOptions: request.negativeSearchOptions,
      matchNikud: request.matchNikud,
      matchTaamim: request.matchTaamim,
      scope: request.scope,
      negativeScope: request.negativeScope,
      wordMatchMode: request.wordMatchMode,
      wordMatchCount: request.wordMatchCount,
    );
  }

  @override
  Future<Map<String, int>> countByBookFuzzy(SearchEngineRequest request) {
    return _engine.countByBookFuzzy(
      query: request.query,
      facets: request.facets,
      maxDistance: _fuzzyDistance(request.distance),
      matchNikud: request.matchNikud,
      matchTaamim: request.matchTaamim,
    );
  }

  @override
  Future<List<FacetCount>> getFacetCountsExact(
    SearchEngineRequest request, {
    required String facetPrefix,
  }) {
    final gapped = _exactWithParametersAsAdvanced(request);
    if (gapped != null) {
      return getFacetCountsAdvanced(gapped, facetPrefix: facetPrefix);
    }
    return _engine.getFacetCountsExact(
      query: request.query,
      facets: request.facets,
      facetPrefix: facetPrefix,
      matchNikud: request.matchNikud,
      matchTaamim: request.matchTaamim,
    );
  }

  @override
  Future<List<FacetCount>> getFacetCountsAdvanced(
    SearchEngineRequest request, {
    required String facetPrefix,
  }) {
    return _engine.getFacetCountsAdvanced(
      query: request.query,
      facets: request.facets,
      facetPrefix: facetPrefix,
      distance: request.distance,
      negativeQuery: request.negativeQuery,
      negativeDistance: request.negativeDistance,
      customSpacing: request.customSpacing,
      negativeCustomSpacing: request.negativeCustomSpacing,
      alternativeWords: request.alternativeWords,
      negativeAlternativeWords: request.negativeAlternativeWords,
      searchOptions: request.searchOptions,
      negativeSearchOptions: request.negativeSearchOptions,
      matchNikud: request.matchNikud,
      matchTaamim: request.matchTaamim,
      scope: request.scope,
      negativeScope: request.negativeScope,
      wordMatchMode: request.wordMatchMode,
      wordMatchCount: request.wordMatchCount,
    );
  }

  @override
  Future<List<FacetCount>> getFacetCountsFuzzy(
    SearchEngineRequest request, {
    required String facetPrefix,
  }) {
    return _engine.getFacetCountsFuzzy(
      query: request.query,
      facets: request.facets,
      facetPrefix: facetPrefix,
      maxDistance: _fuzzyDistance(request.distance),
      matchNikud: request.matchNikud,
      matchTaamim: request.matchTaamim,
    );
  }

  /// המימוש האמיתי של ה-stream המשולב: קריאה אחת למנוע, שמריצה את השאילתה
  /// פעם אחת ומחזירה ספירות + תוצאות מאותו מעבר אינדקס.
  @override
  Stream<SearchStreamUpdate> searchStreamWithCounts(
    SearchEngineRequest request, {
    required int chunkSize,
  }) {
    final gapped = _exactWithParametersAsAdvanced(request);
    if (gapped != null) {
      return searchStreamWithCounts(gapped, chunkSize: chunkSize);
    }
    switch (request.searchMode) {
      case SearchMode.exact:
        return _engine.searchExactStreamWithCounts(
          query: request.query,
          facets: request.facets,
          limit: request.limit,
          offset: request.offset,
          order: request.order,
          chunkSize: chunkSize,
          matchNikud: request.matchNikud,
          matchTaamim: request.matchTaamim,
          grouping: request.grouping,
        );
      case SearchMode.advanced:
        return _engine.searchAdvancedStreamWithCounts(
          query: request.query,
          negativeQuery: request.negativeQuery,
          facets: request.facets,
          limit: request.limit,
          offset: request.offset,
          distance: request.distance,
          negativeDistance: request.negativeDistance,
          customSpacing: request.customSpacing,
          negativeCustomSpacing: request.negativeCustomSpacing,
          alternativeWords: request.alternativeWords,
          negativeAlternativeWords: request.negativeAlternativeWords,
          searchOptions: request.searchOptions,
          negativeSearchOptions: request.negativeSearchOptions,
          order: request.order,
          chunkSize: chunkSize,
          matchNikud: request.matchNikud,
          matchTaamim: request.matchTaamim,
          scope: request.scope,
          negativeScope: request.negativeScope,
          grouping: request.grouping,
          wordMatchMode: request.wordMatchMode,
          wordMatchCount: request.wordMatchCount,
        );
      case SearchMode.fuzzy:
        return _engine.searchFuzzyStreamWithCounts(
          query: request.query,
          facets: request.facets,
          limit: request.limit,
          offset: request.offset,
          maxDistance: _fuzzyDistance(request.distance),
          order: request.order,
          chunkSize: chunkSize,
          matchNikud: request.matchNikud,
          matchTaamim: request.matchTaamim,
          grouping: request.grouping,
        );
    }
  }

  static int _fuzzyDistance(int distance) {
    return distance.clamp(0, 2).toInt();
  }

  /// מזין מראש את תבנית ההדגשה מבוססת-האינדקס (ראה
  /// `text_manipulation.primeHighlightPattern`). מפתח המטמון נגזר מאותם
  /// פרמטרים ש-`utils.highLight` ישתמש בהם ברינדור, כך שהתבנית תימצא שם.
  ///
  /// במצב exact אין פער להשלים: החיפוש מתאים רק את הטוקנים המדויקים, ותבנית
  /// ה-fallback הסינכרונית כבר מדגישה בדיוק אותם. חריג: מדויק עם מרווח
  /// בין מילים רץ בפועל דרך המסלול המתקדם, ותבנית ההדגשה של הספר הפתוח
  /// צריכה לשאת את אותו מרווח — לכן הוא מוזן כבקשה מתקדמת.
  @override
  void primeHighlightPattern(SearchEngineRequest request) {
    final gapped = _exactWithParametersAsAdvanced(request);
    if (gapped != null) return primeHighlightPattern(gapped);
    if (request.query.trim().isEmpty ||
        request.searchMode == SearchMode.exact) {
      return;
    }
    unawaited(
      text_utils.primeHighlightPattern(
        searchQuery: request.query,
        searchOptions: request.searchOptions,
        alternativeWords: request.alternativeWords,
        spacingValues: request.customSpacing,
        searchDistance: request.distance,
        isFuzzy: request.searchMode == SearchMode.fuzzy,
        fetch: () => switch (request.searchMode) {
          SearchMode.advanced => _engine.generateIndexHighlightPattern(
            query: request.query,
            distance: request.distance < 0 ? 0 : request.distance,
            customSpacing: request.customSpacing,
            alternativeWords: request.alternativeWords,
            searchOptions: request.searchOptions,
          ),
          SearchMode.fuzzy => _engine.generateIndexFuzzyHighlightPattern(
            query: request.query,
            maxDistance: _fuzzyDistance(request.distance),
          ),
          SearchMode.exact => Future.value(null),
        },
      ),
    );
  }
}

class SearchEngineGateway {
  const SearchEngineGateway();

  Future<List<SearchResult>> search(
    SearchEngineOperations engine,
    SearchEngineRequest request,
  ) async {
    // בזמן שהחיפוש רץ, תבנית ההדגשה לספר-פתוח נבנית ברקע מאותם פרמטרים —
    // עד שהמשתמש יפתח תוצאה היא כבר במטמון.
    engine.primeHighlightPattern(request);
    switch (request.searchMode) {
      case SearchMode.exact:
        return engine.searchExact(request);
      case SearchMode.advanced:
        return engine.searchAdvanced(request);
      case SearchMode.fuzzy:
        return engine.searchFuzzy(request);
    }
  }

  Future<SearchPageResult> searchAndCount(
    SearchEngineOperations engine,
    SearchEngineRequest request,
  ) async {
    engine.primeHighlightPattern(request);
    switch (request.searchMode) {
      case SearchMode.exact:
        return engine.searchAndCountExact(request);
      case SearchMode.advanced:
        return engine.searchAndCountAdvanced(request);
      case SearchMode.fuzzy:
        return engine.searchAndCountFuzzy(request);
    }
  }

  Stream<List<SearchResult>> searchStream(
    SearchEngineOperations engine,
    SearchEngineRequest request, {
    required int chunkSize,
  }) {
    engine.primeHighlightPattern(request);
    switch (request.searchMode) {
      case SearchMode.exact:
        return engine.searchExactStream(request, chunkSize: chunkSize);
      case SearchMode.advanced:
        return engine.searchAdvancedStream(request, chunkSize: chunkSize);
      case SearchMode.fuzzy:
        return engine.searchFuzzyStream(request, chunkSize: chunkSize);
    }
  }

  /// Stream משולב (תוצאות + ספירה כוללת + ספירה לפי ספר במעבר אחד);
  /// ראה [SearchEngineOperations.searchStreamWithCounts].
  Stream<SearchStreamUpdate> searchStreamWithCounts(
    SearchEngineOperations engine,
    SearchEngineRequest request, {
    required int chunkSize,
  }) {
    engine.primeHighlightPattern(request);
    return engine.searchStreamWithCounts(request, chunkSize: chunkSize);
  }

  Future<int> count(
    SearchEngineOperations engine,
    SearchEngineRequest request,
  ) async {
    switch (request.searchMode) {
      case SearchMode.exact:
        return engine.countExact(request);
      case SearchMode.advanced:
        return engine.countAdvanced(request);
      case SearchMode.fuzzy:
        return engine.countFuzzy(request);
    }
  }

  Future<Map<String, int>> countByBook(
    SearchEngineOperations engine,
    SearchEngineRequest request,
  ) async {
    switch (request.searchMode) {
      case SearchMode.exact:
        return engine.countByBookExact(request);
      case SearchMode.advanced:
        return engine.countByBookAdvanced(request);
      case SearchMode.fuzzy:
        return engine.countByBookFuzzy(request);
    }
  }

  Future<List<FacetCount>> getFacetCounts(
    SearchEngineOperations engine,
    SearchEngineRequest request, {
    required String facetPrefix,
  }) async {
    switch (request.searchMode) {
      case SearchMode.exact:
        return engine.getFacetCountsExact(
          request,
          facetPrefix: facetPrefix,
        );
      case SearchMode.advanced:
        return engine.getFacetCountsAdvanced(
          request,
          facetPrefix: facetPrefix,
        );
      case SearchMode.fuzzy:
        return engine.getFacetCountsFuzzy(
          request,
          facetPrefix: facetPrefix,
        );
    }
  }
}
