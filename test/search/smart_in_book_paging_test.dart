import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/search/in_book_search_settings.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/search/search_repository.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart';

import '../support/recording_search_engine.dart';
import '../support/search_engine_test_init.dart';

class _SmartEngine extends RecordingSearchEngine {
  final smartRequests = <SearchEngineRequest>[];
  Object? failure;

  @override
  Future<List<SearchResult>> searchSmartLexical(
    SearchEngineRequest request,
  ) async {
    smartRequests.add(request);
    if (failure case final error?) throw error;
    return const [];
  }
}

Future<void> main() async {
  final ready = await tryInitSearchEngine();
  const smart = InBookSearchSettings(
    searchMode: SearchMode.fuzzy,
    distance: 2,
    matchPolicy: SearchMatchPolicy.smart,
  );

  group('שליפה חכמה בסדר הספר', () {
    test('ציטוט מלא, חלקי וללא ציטוט מועברים למנוע עם גבול הקטלוג', () async {
      final engine = _SmartEngine();
      final repository = SearchRepository(engineProvider: () async => engine);
      for (final query in ['יקוק טוב', '"יקוק טוב"', '"יקוק טוב" ידוד']) {
        await searchBookWithEngine(
          repository,
          query: query,
          bookPath: '/book',
          limit: 5000,
          settings: smart,
        );
        final request = engine.smartRequests.last;
        expect(request.query, query);
        expect(request.facets, ['/book']);
        expect(request.order, ResultsOrder.catalogue);
        expect(request.limit, 5000);
        expect(request.offset, 0);
        expect(request.distance, 2);
      }
      expect(engine.smartRequests, hasLength(3));
      expect(engine.lastRequest, isNull);
    });

    test('מגבלה ריקה אינה מפעילה שליפה', () async {
      final engine = _SmartEngine();
      final repository = SearchRepository(engineProvider: () async => engine);
      for (final limit in [0, -1]) {
        expect(
          await searchBookWithEngine(
            repository,
            query: 'יקוק',
            bookPath: '/book',
            limit: limit,
            settings: smart,
          ),
          isEmpty,
        );
      }
      expect(engine.smartRequests, isEmpty);
    });

    test('offset שאחרי 5000 אינו מוחלף בחלון דירוג', () async {
      final engine = _SmartEngine();
      final repository = SearchRepository(engineProvider: () async => engine);
      await repository.searchSmartLexical(
        const SearchEngineRequest(
          query: '"יקוק טוב" ידוד',
          facets: ['/book'],
          limit: 17,
          offset: 7000,
          order: ResultsOrder.catalogue,
          searchMode: SearchMode.fuzzy,
        ),
      );
      expect(engine.smartRequests.single.offset, 7000);
      expect(engine.smartRequests.single.limit, 17);
      expect(engine.smartRequests.single.order, ResultsOrder.catalogue);
    });

    test('שגיאת המנוע אינה מפעילה שליפה רגילה חלופית', () async {
      final error = StateError('smart search failure');
      final engine = _SmartEngine()..failure = error;
      final repository = SearchRepository(engineProvider: () async => engine);
      await expectLater(
        searchBookWithEngine(
          repository,
          query: '"יקוק טוב" ידוד',
          bookPath: '/book',
          limit: 2,
          settings: smart,
        ),
        throwsA(same(error)),
      );
      expect(engine.smartRequests, hasLength(1));
      expect(engine.lastRequest, isNull);
    });

    test('חיפוש fuzzy רגיל ממשיך במסלול הקיים', () async {
      final engine = _SmartEngine();
      await searchBookWithEngine(
        SearchRepository(engineProvider: () async => engine),
        query: '"יקוק טוב"',
        bookPath: '/book',
        limit: 2,
        settings: const InBookSearchSettings(searchMode: SearchMode.fuzzy),
      );
      expect(engine.smartRequests, isEmpty);
      expect(engine.lastRequest!.query, '"יקוק טוב"');
      expect(engine.lastRequest!.order, ResultsOrder.catalogue);
    });
  }, skip: ready ? false : searchEngineSkipReason);
}
