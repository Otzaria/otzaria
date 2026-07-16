import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/search/search_engine_gateway.dart';
import 'package:otzaria/search/search_query_builder.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart';

import '../support/search_engine_test_init.dart';

Future<void> main() async {
  // sanitizeQuery/splitQueryWords מאצילים למנוע ה-Rust; הטסטים שלהם דורשים
  // את הספרייה הנייטיבית ומדולגים כשאין build זמין.
  final engineReady = await tryInitSearchEngine();

  group('SearchQueryBuilder - אחריות UI בלבד', () {
    test('sanitizeQuery מנקה תווים שמגיעים מהקלט בלי לבנות שאילתת מנוע', () {
      expect(SearchQueryBuilder.sanitizeQuery('תורה, ומצוות'), 'תורה ומצוות');
      expect(SearchQueryBuilder.sanitizeQuery('אל־משה'), 'אל משה');
      expect(SearchQueryBuilder.sanitizeQuery('!?.,*'), '');
    }, skip: engineReady ? false : searchEngineSkipReason);

    test('splitQueryWords שומר תאימות לטוקנייזר עבור ראשי תיבות', () {
      // גרשיים וגרש בין אותיות הם חלק מהמילה; ״/׳ וזוג גרשים ('')
      // מנורמלים ל-"/' ASCII — כמו בטוקנייזר של האינדקס.
      expect(SearchQueryBuilder.splitQueryWords('רמב"ם משה'), [
        'רמב"ם',
        'משה',
      ]);
      expect(SearchQueryBuilder.splitQueryWords('רמב״ם'), ['רמב"ם']);
      expect(SearchQueryBuilder.splitQueryWords("רמב''ם"), ['רמב"ם']);
      expect(SearchQueryBuilder.splitQueryWords("ג'ורג'"), ["ג'ורג'"]);
      expect(SearchQueryBuilder.splitQueryWords("ה'"), ["ה'"]);
      // גרשיים בקצה מילה נשארות מפריד.
      expect(SearchQueryBuilder.splitQueryWords('אמר "שלום" לו'), [
        'אמר',
        'שלום',
        'לו',
      ]);
    }, skip: engineReady ? false : searchEngineSkipReason);

    test('queryWordSpans ממפה כל מילת-מנוע לטווח נפרד בטקסט הגולמי', () {
      // מקטע שמתפצל לכמה מילים (בית-דין): הסמן על `דין` חייב לבחור את
      // דין_1, לא את בית_0.
      final spans = SearchQueryBuilder.queryWordSpans('בית-דין צדק');
      expect(spans.map((s) => s.word).toList(), ['בית', 'דין', 'צדק']);
      expect(spans.map((s) => s.index).toList(), [0, 1, 2]);
      expect(spans[0].start, 0);
      expect(spans[0].end, 3);
      expect(spans[1].start, 4);
      expect(spans[1].end, 7);
      expect(spans[2].start, 8);
      expect(spans[2].end, 11);
    }, skip: engineReady ? false : searchEngineSkipReason);

    test('queryWordSpans מאתר מילים עם צורות גרש עבריות ומשני-אורך', () {
      // ״ עברי בשדה: קיפול שומר-אורך — טווח מדויק.
      final hebrew = SearchQueryBuilder.queryWordSpans('רמב״ם משה');
      expect(hebrew[0].word, 'רמב"ם');
      expect(hebrew[0].start, 0);
      expect(hebrew[0].end, 5);
      expect(hebrew[1].word, 'משה');
      expect(hebrew[1].index, 1);

      // גרשיים טיפוגרפיים (Word/OCR): מקופלים שומר-אורך כמו במנוע —
      // טווח מדויק גם עבור רמח”ל.
      final typographic = SearchQueryBuilder.queryWordSpans('רמח”ל משה');
      expect(typographic[0].word, 'רמח"ל');
      expect(typographic[0].start, 0);
      expect(typographic[0].end, 5);
      expect(typographic[1].word, 'משה');
      expect(typographic[1].index, 1);

      // '' שמאוחד ל-" משנה אורך — המילה מקבלת את גבולות המקטע כולו,
      // כך שהסמן בכל מקום בתוכו עדיין בוחר אותה.
      final doubled = SearchQueryBuilder.queryWordSpans("רמב''ם משה");
      expect(doubled[0].word, 'רמב"ם');
      expect(doubled[0].start, 0);
      expect(doubled[0].end, 6);
      expect(doubled[1].word, 'משה');
      expect(doubled[1].start, 7);
    }, skip: engineReady ? false : searchEngineSkipReason);

    test('queryWordSpans: מקטע מעורב — משנה-אורך שגם מתפצל לכמה מילים', () {
      // כישלון איתור של מילה אחת אינו גורר את שאר מילות המקטע: במקטע
      // רמב''ם-משה המילה רמב"ם מקבלת את הפער עד משה, ומשה מאותרת
      // במדויק — הסמן עליה בוחר אותה ולא את הראשונה.
      final spans = SearchQueryBuilder.queryWordSpans("רמב''ם-משה");
      expect(spans.map((s) => s.word).toList(), ['רמב"ם', 'משה']);
      expect(spans[0].start, 0);
      expect(spans[0].end, 7);
      expect(spans[1].start, 7);
      expect(spans[1].end, 10);

      // וגם בכיוון ההפוך: המילה הראשונה מאותרת, השנייה משנת-אורך.
      final reversed = SearchQueryBuilder.queryWordSpans("משה-רמב''ם");
      expect(reversed.map((s) => s.word).toList(), ['משה', 'רמב"ם']);
      expect(reversed[0].start, 0);
      expect(reversed[0].end, 3);
      expect(reversed[1].start, 3);
      expect(reversed[1].end, 10);
    }, skip: engineReady ? false : searchEngineSkipReason);

    test('restoredPerWordStateMatches מזהה state שנשמר על פיצול ישן', () {
      // state שנשמר כשרמב"ם היה שתי מילים ("רמב_0", "ם_1") חייב להיפסל,
      // אחרת המרווחים/החלופות זולגים למילה הלא-נכונה.
      expect(
        SearchQueryBuilder.restoredPerWordStateMatches(
          'רמב"ם משה',
          searchOptions: const {
            'רמב_0': {'קידומות': true},
            'ם_1': {'קידומות': true},
          },
          spacingValues: const {'1-2': '3'},
        ),
        isFalse,
      );
      expect(
        SearchQueryBuilder.restoredPerWordStateMatches(
          'רמב"ם משה',
          searchOptions: const {
            'רמב"ם_0': {'קידומות': true},
          },
          alternativeWords: const {
            1: ['רבינו'],
          },
          spacingValues: const {'0-1': '2'},
        ),
        isTrue,
      );
    }, skip: engineReady ? false : searchEngineSkipReason);

    test('effectiveSearchOptions מרחיב אפשרויות גלובליות לפי מילים', () {
      final options = SearchQueryBuilder.effectiveSearchOptions(
        query: 'חכמה בינה',
        useGlobalOptions: true,
        globalOptions: const {'קידומות': true},
        perWordOptions: const {},
      );

      expect(options, {
        'חכמה_0': {'קידומות': true},
        'בינה_1': {'קידומות': true},
      });
    }, skip: engineReady ? false : searchEngineSkipReason);

    test('normalizeParametersForMode משאיר פרמטרים ידניים רק במצב מתקדם', () {
      final advanced = SearchQueryBuilder.normalizeParametersForMode(
        SearchMode.advanced,
        customSpacing: const {'0-1': ' 5 ', '1-2': ' '},
        alternativeWords: const {
          0: [' שלום ', ''],
        },
        searchOptions: const {
          'חכמה_0': {'קידומות': true, 'סיומות': false},
        },
      );

      expect(advanced.customSpacing, {'0-1': '5'});
      expect(advanced.alternativeWords, {
        0: ['שלום'],
      });
      expect(advanced.searchOptions, {
        'חכמה_0': {'קידומות': true},
      });

      // מצב רגיל (מדויק): רק חמש אפשרויות המילה שלו (exactWordOptionKeys)
      // עוברות; מילים חלופיות ומרווחים ידניים נשארים בלעדיים למצב המתקדם.
      // "ניקוד"/"טעמים", קידומות/סיומות כלליות והאפשרויות הבלעדיות למתקדם
      // מסוננים — גם כשהם מגיעים ממצב משוחזר שה-UI כבר לא מציג.
      final exact = SearchQueryBuilder.normalizeParametersForMode(
        SearchMode.exact,
        customSpacing: advanced.customSpacing,
        alternativeWords: advanced.alternativeWords,
        searchOptions: const {
          'חכמה_0': {
            'קידומות דקדוקיות': true,
            'קידומות': true,
            'ניקוד': true,
            'ראשי תיבות': true,
          },
        },
      );

      expect(exact.customSpacing, isEmpty);
      expect(exact.alternativeWords, isEmpty);
      expect(exact.searchOptions, {
        'חכמה_0': {'קידומות דקדוקיות': true},
      });

      final fuzzy = SearchQueryBuilder.normalizeParametersForMode(
        SearchMode.fuzzy,
        searchOptions: advanced.searchOptions,
      );
      expect(fuzzy.searchOptions, isEmpty);
    });
  });

  group('SearchEngineGateway', () {
    test('search מפנה לפונקציה המתאימה לפי מצב החיפוש', () async {
      final engine = _RecordingSearchEngineOperations();
      const gateway = SearchEngineGateway();

      await gateway.search(engine, _request(SearchMode.exact));
      await gateway.search(engine, _request(SearchMode.advanced));
      await gateway.search(engine, _request(SearchMode.fuzzy));

      expect(engine.calls, [
        _EngineCall.searchExact,
        _EngineCall.searchAdvanced,
        _EngineCall.searchFuzzy,
      ]);
    });

    test('searchStream מפנה לפי מצב החיפוש', () async {
      final engine = _RecordingSearchEngineOperations();
      const gateway = SearchEngineGateway();

      await gateway
          .searchStream(engine, _request(SearchMode.exact), chunkSize: 10)
          .drain<void>();
      await gateway
          .searchStream(engine, _request(SearchMode.advanced), chunkSize: 10)
          .drain<void>();
      await gateway
          .searchStream(engine, _request(SearchMode.fuzzy), chunkSize: 10)
          .drain<void>();

      expect(engine.calls, [
        _EngineCall.searchExactStream,
        _EngineCall.searchAdvancedStream,
        _EngineCall.searchFuzzyStream,
      ]);
    });

    test('searchAndCount מפנה לפי מצב החיפוש', () async {
      final engine = _RecordingSearchEngineOperations();
      const gateway = SearchEngineGateway();

      await gateway.searchAndCount(engine, _request(SearchMode.exact));
      await gateway.searchAndCount(engine, _request(SearchMode.advanced));
      await gateway.searchAndCount(engine, _request(SearchMode.fuzzy));

      expect(engine.calls, [
        _EngineCall.searchAndCountExact,
        _EngineCall.searchAndCountAdvanced,
        _EngineCall.searchAndCountFuzzy,
      ]);
    });

    test('count מפנה לפי מצב החיפוש', () async {
      final engine = _RecordingSearchEngineOperations();
      const gateway = SearchEngineGateway();

      await gateway.count(engine, _request(SearchMode.exact));
      await gateway.count(engine, _request(SearchMode.advanced));
      await gateway.count(engine, _request(SearchMode.fuzzy));

      expect(engine.calls, [
        _EngineCall.countExact,
        _EngineCall.countAdvanced,
        _EngineCall.countFuzzy,
      ]);
    });

    test('countByBook מפנה לפי מצב החיפוש', () async {
      final engine = _RecordingSearchEngineOperations();
      const gateway = SearchEngineGateway();

      await gateway.countByBook(engine, _request(SearchMode.exact));
      await gateway.countByBook(engine, _request(SearchMode.advanced));
      await gateway.countByBook(engine, _request(SearchMode.fuzzy));

      expect(engine.calls, [
        _EngineCall.countByBookExact,
        _EngineCall.countByBookAdvanced,
        _EngineCall.countByBookFuzzy,
      ]);
    });

    test('getFacetCounts מפנה לפי מצב החיפוש', () async {
      final engine = _RecordingSearchEngineOperations();
      const gateway = SearchEngineGateway();

      await gateway.getFacetCounts(
        engine,
        _request(SearchMode.exact),
        facetPrefix: '/',
      );
      await gateway.getFacetCounts(
        engine,
        _request(SearchMode.advanced),
        facetPrefix: '/',
      );
      await gateway.getFacetCounts(
        engine,
        _request(SearchMode.fuzzy),
        facetPrefix: '/',
      );

      expect(engine.calls, [
        _EngineCall.getFacetCountsExact,
        _EngineCall.getFacetCountsAdvanced,
        _EngineCall.getFacetCountsFuzzy,
      ]);
    });

    test('count/countByBook/getFacetCounts משתמשים באותו dispatch', () async {
      final engine = _RecordingSearchEngineOperations();
      const gateway = SearchEngineGateway();

      await gateway.count(engine, _request(SearchMode.exact));
      await gateway.countByBook(engine, _request(SearchMode.advanced));
      await gateway.getFacetCounts(
        engine,
        _request(SearchMode.fuzzy),
        facetPrefix: '/',
      );

      expect(engine.calls, [
        _EngineCall.countExact,
        _EngineCall.countByBookAdvanced,
        _EngineCall.getFacetCountsFuzzy,
      ]);
    });
  });
}

SearchEngineRequest _request(SearchMode mode) {
  return SearchEngineRequest(
    query: 'שלום עולם',
    facets: const ['/'],
    limit: 20,
    offset: 0,
    order: ResultsOrder.relevance,
    searchMode: mode,
    distance: 2,
  );
}

enum _EngineCall {
  searchExact,
  searchAdvanced,
  searchFuzzy,
  searchAndCountExact,
  searchAndCountAdvanced,
  searchAndCountFuzzy,
  searchExactStream,
  searchAdvancedStream,
  searchFuzzyStream,
  countExact,
  countAdvanced,
  countFuzzy,
  countByBookExact,
  countByBookAdvanced,
  countByBookFuzzy,
  getFacetCountsExact,
  getFacetCountsAdvanced,
  getFacetCountsFuzzy,
}

// extends (ולא implements) כדי לרשת את מימושי ברירת המחדל של הממשק (searchStreamWithCounts).
class _RecordingSearchEngineOperations extends SearchEngineOperations {
  final List<_EngineCall> calls = [];

  @override
  Future<List<SearchResult>> searchExact(SearchEngineRequest request) async {
    calls.add(_EngineCall.searchExact);
    return const [];
  }

  @override
  Future<List<SearchResult>> searchAdvanced(SearchEngineRequest request) async {
    calls.add(_EngineCall.searchAdvanced);
    return const [];
  }

  @override
  Future<List<SearchResult>> searchFuzzy(SearchEngineRequest request) async {
    calls.add(_EngineCall.searchFuzzy);
    return const [];
  }

  @override
  Future<SearchPageResult> searchAndCountExact(
    SearchEngineRequest request,
  ) async {
    calls.add(_EngineCall.searchAndCountExact);
    return const SearchPageResult(totalCount: 0, results: [], truncated: false);
  }

  @override
  Future<SearchPageResult> searchAndCountAdvanced(
    SearchEngineRequest request,
  ) async {
    calls.add(_EngineCall.searchAndCountAdvanced);
    return const SearchPageResult(totalCount: 0, results: [], truncated: false);
  }

  @override
  Future<SearchPageResult> searchAndCountFuzzy(
    SearchEngineRequest request,
  ) async {
    calls.add(_EngineCall.searchAndCountFuzzy);
    return const SearchPageResult(totalCount: 0, results: [], truncated: false);
  }

  @override
  Stream<List<SearchResult>> searchExactStream(
    SearchEngineRequest request, {
    required int chunkSize,
  }) async* {
    calls.add(_EngineCall.searchExactStream);
    yield const [];
  }

  @override
  Stream<List<SearchResult>> searchAdvancedStream(
    SearchEngineRequest request, {
    required int chunkSize,
  }) async* {
    calls.add(_EngineCall.searchAdvancedStream);
    yield const [];
  }

  @override
  Stream<List<SearchResult>> searchFuzzyStream(
    SearchEngineRequest request, {
    required int chunkSize,
  }) async* {
    calls.add(_EngineCall.searchFuzzyStream);
    yield const [];
  }

  @override
  Future<int> countExact(SearchEngineRequest request) async {
    calls.add(_EngineCall.countExact);
    return 0;
  }

  @override
  Future<int> countAdvanced(SearchEngineRequest request) async {
    calls.add(_EngineCall.countAdvanced);
    return 0;
  }

  @override
  Future<int> countFuzzy(SearchEngineRequest request) async {
    calls.add(_EngineCall.countFuzzy);
    return 0;
  }

  @override
  Future<Map<String, int>> countByBookExact(
    SearchEngineRequest request,
  ) async {
    calls.add(_EngineCall.countByBookExact);
    return const {};
  }

  @override
  Future<Map<String, int>> countByBookAdvanced(
    SearchEngineRequest request,
  ) async {
    calls.add(_EngineCall.countByBookAdvanced);
    return const {};
  }

  @override
  Future<Map<String, int>> countByBookFuzzy(
    SearchEngineRequest request,
  ) async {
    calls.add(_EngineCall.countByBookFuzzy);
    return const {};
  }

  @override
  Future<List<FacetCount>> getFacetCountsExact(
    SearchEngineRequest request, {
    required String facetPrefix,
  }) async {
    calls.add(_EngineCall.getFacetCountsExact);
    return const [];
  }

  @override
  Future<List<FacetCount>> getFacetCountsAdvanced(
    SearchEngineRequest request, {
    required String facetPrefix,
  }) async {
    calls.add(_EngineCall.getFacetCountsAdvanced);
    return const [];
  }

  @override
  Future<List<FacetCount>> getFacetCountsFuzzy(
    SearchEngineRequest request, {
    required String facetPrefix,
  }) async {
    calls.add(_EngineCall.getFacetCountsFuzzy);
    return const [];
  }

  @override
  void primeHighlightPattern(SearchEngineRequest request) {}
}
