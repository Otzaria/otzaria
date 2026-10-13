import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/search/in_book_search_settings.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/search/search_repository.dart';
import 'package:otzaria/search/view/search_dialog.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart';

import '../support/search_engine_test_init.dart';

Future<void> main() async {
  // ספירת מילות השאילתה מאצילה למנוע ה-Rust.
  final engineReady = await tryInitSearchEngine();

  group('InBookSearchSettings', () {
    test('the default settings run as a simple search', () {
      const settings = InBookSearchSettings();
      expect(settings.requiresEngine, isFalse);
      expect(settings.isSimpleSearch, isTrue);
    });

    test('a distance or a per-word option needs the engine', () {
      expect(
        const InBookSearchSettings(distance: 2).isSimpleSearch,
        isFalse,
      );
      expect(
        const InBookSearchSettings(
          searchOptions: {
            'שלום_0': {'קידומות': true},
          },
        ).requiresEngine,
        isTrue,
      );
      expect(
        const InBookSearchSettings(
          alternativeWords: {
            0: ['שלם'],
          },
        ).requiresEngine,
        isTrue,
      );
    });

    test('advanced and fuzzy modes do not run as a simple search', () {
      expect(
        const InBookSearchSettings(
          searchMode: SearchMode.advanced,
        ).isSimpleSearch,
        isFalse,
      );
      expect(
        const InBookSearchSettings(searchMode: SearchMode.fuzzy).requiresEngine,
        isTrue,
      );
    });

    test(
      'any word order needs the engine only for a multi-word query',
      () {
        for (final optionsForEveryWord in [null, const <String, bool>{}]) {
          final settings = InBookSearchSettings(
            matchPolicy: const SearchMatchPolicy(anyOrder: true),
            optionsForEveryWord: optionsForEveryWord,
          );
          final multi = settings.forQuery('שלום עולם');
          expect(multi.matchPolicy.anyOrder, isTrue);
          expect(multi.requiresEngine, isTrue);

          final single = settings.forQuery('שלום');
          expect(single.matchPolicy.anyOrder, isFalse);
          expect(single.isSimpleSearch, isTrue);
          // הבחירה נשמרת: מילה שנייה מחזירה את "בכל סדר".
          expect(single.requestedMatchPolicy.anyOrder, isTrue);
          expect(
            single.forQuery('שלום עולם').matchPolicy.anyOrder,
            isTrue,
          );
        }
      },
      skip: !engineReady,
    );

    test('takes the dialog result with its mode, distance and policy', () {
      final settings = InBookSearchSettings.fromDialogResult(
        const SearchDialogResult(
          query: 'שלום',
          searchOptions: {
            'שלום_0': {'קידומות': true},
          },
          alternativeWords: {
            0: ['שלם'],
          },
          spacingValues: {},
          searchMode: SearchMode.advanced,
          distance: 3,
        ),
      );

      expect(settings.searchMode, SearchMode.advanced);
      expect(settings.distance, 3);
      expect(settings.matchPolicy, SearchMatchPolicy.standard);
      expect(settings.searchOptions['שלום_0'], {'קידומות': true});
      expect(settings.alternativeWords[0], ['שלם']);
    });
  });

  group('searchableInBookQuery', () {
    test('trims the query and drops nikud', () {
      expect(searchableInBookQuery('  שָׁלוֹם '), 'שלום');
    });

    test('a blank query has nothing to search for', () {
      expect(searchableInBookQuery(''), isNull);
      expect(searchableInBookQuery('   '), isNull);
    });
  });

  group('limitInBookResults', () {
    test('keeps every result up to the limit', () {
      final limited = limitInBookResults(List.generate(10, (i) => i));
      expect(limited.shown, hasLength(10));
      expect(limited.truncated, isFalse);
    });

    test('shows the first results and reports the rest', () {
      final limited = limitInBookResults(
        List.generate(kInBookResultsShown + 5, (i) => i),
      );
      expect(limited.shown, hasLength(kInBookResultsShown));
      expect(limited.shown.first, 0);
      expect(limited.truncated, isTrue);
    });
  });

  group('searchBookWithEngine', () {
    test('searches the book with the settings, in book order', () async {
      final repository = _RecordingSearchRepository();
      await searchBookWithEngine(
        repository,
        query: 'שלום',
        bookPath: '/תנך/בראשית',
        limit: 500,
        settings: const InBookSearchSettings(
          searchMode: SearchMode.fuzzy,
          distance: 2,
          alternativeWords: {
            0: ['שלם'],
          },
          matchPolicy: SearchMatchPolicy(
            proximityScope: SearchScope.sameParagraph,
          ),
        ),
      );

      final call = repository.calls.single;
      expect(call.query, 'שלום');
      expect(call.facets, ['/תנך/בראשית']);
      expect(call.limit, 500);
      expect(call.searchMode, SearchMode.fuzzy);
      // ברירות המחדל שהמאגר השלים פעם: שלילה יורשת מרחק וטווח
      expect(call.distance, 2);
      expect(call.negativeDistance, 2);
      expect(call.negativeScope, SearchScope.sameParagraph);
      expect(call.order, ResultsOrder.catalogue);
    });
  });
}

class _RecordingSearchRepository extends SearchRepository {
  final calls = <SearchEngineRequest>[];

  @override
  Future<List<SearchResult>> searchTexts(SearchEngineRequest request) async {
    calls.add(request);
    return const [];
  }
}
