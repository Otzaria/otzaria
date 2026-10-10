import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/search/bloc/search_bloc.dart';
import 'package:otzaria/search/bloc/search_event.dart';
import 'package:otzaria/search/bloc/search_state.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/search/search_repository.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart';

import '../support/search_engine_test_init.dart';

Future<void> main() async {
  // sanitizeQuery מאציל למנוע ה-Rust.
  final engineReady = await tryInitSearchEngine();

  TestWidgetsFlutterBinding.ensureInitialized();

  group('חיפוש שהוחלף בזמן ריצה', () {
    late _ControlledSearchRepository repository;
    late SearchBloc bloc;

    setUp(() {
      repository = _ControlledSearchRepository();
    });

    tearDown(() async {
      await bloc.close();
      await repository.stream.close();
    });

    Future<void> waitFor(bool Function(SearchState) predicate) =>
        bloc.stream.firstWhere(predicate).timeout(const Duration(seconds: 5));

    test('ניקוי השאילתה בזמן חיפוש רץ מחזיר isLoading ל-false', () async {
      bloc = SearchBloc(repository: repository);

      bloc.add(UpdateSearchQuery('שלום'));
      await waitFor((s) => s.isLoading);

      bloc.add(UpdateSearchQuery(''));
      await waitFor((s) => s.searchQuery.isEmpty);

      repository.stream.add(_chunk(['old-1']));
      await repository.stream.close();
      await pumpEventQueue();

      expect(bloc.state.searchQuery, isEmpty);
      expect(bloc.state.results, isEmpty);
      expect(bloc.state.isLoading, isFalse);
    });

    test('שגיאת חיפוש ישן אחרי ניקוי אינה משנה את המצב', () async {
      bloc = SearchBloc(repository: repository);

      bloc.add(UpdateSearchQuery('שלום'));
      await waitFor((s) => s.isLoading);

      bloc.add(UpdateSearchQuery(''));
      await waitFor((s) => s.searchQuery.isEmpty);

      repository.stream.addError(StateError('stale search failure'));
      await pumpEventQueue();

      expect(bloc.state.searchQuery, isEmpty);
      expect(bloc.state.results, isEmpty);
      expect(bloc.state.isLoading, isFalse);
      expect(bloc.state.errorMessage, isNull);
    });

    test(
      'LoadMoreResults שחוזר אחרי חיפוש חדש אינו מצרף עמוד ישן ואינו מאפס טעינה',
      () async {
        bloc = SearchBloc(repository: repository);
        bloc.emit(
          SearchState(
            searchQuery: 'ישן',
            results: [_result('old-1')],
            totalResults: 5,
            configuration: const SearchConfiguration(),
          ),
        );

        bloc.add(LoadMoreResults());
        await waitFor((s) => s.isLoading);
        expect(repository.loadMore, isNotNull);

        bloc.add(UpdateSearchQuery('חדש'));
        repository.stream.add(_chunk(['new-1']));
        await waitFor((s) => s.results.any((r) => r.text == 'new-1'));

        repository.loadMore!.complete([_result('stale-loadmore')]);
        await pumpEventQueue();

        expect(bloc.state.results.map((r) => r.text), ['new-1']);
        expect(bloc.state.isLoading, isTrue);

        await repository.stream.close();
        await pumpEventQueue();

        expect(bloc.state.results.map((r) => r.text), ['new-1']);
        expect(bloc.state.isLoading, isFalse);
      },
    );
  }, skip: engineReady ? false : searchEngineSkipReason);
}

SearchStreamUpdate _chunk(List<String> texts) => SearchStreamUpdate(
  results: [for (final text in texts) _result(text)],
  truncated: false,
);

SearchResult _result(String text) => SearchResult(
  id: BigInt.from(text.hashCode.abs()),
  title: 'ספר',
  reference: 'סימן',
  text: text,
  segment: BigInt.zero,
  isPdf: false,
  filePath: 'book.txt',
  mergedCount: 1,
  merged: const [],
  textStatus: TextStatus.ok,
  continuesToNextLine: false,
);

class _ControlledSearchRepository extends SearchRepository {
  final stream = StreamController<SearchStreamUpdate>();
  Completer<List<SearchResult>>? loadMore;

  @override
  Stream<SearchStreamUpdate> searchTextsStreamWithCounts(
    SearchEngineRequest request, {
    int chunkSize = 50,
  }) => stream.stream;

  @override
  Future<List<SearchResult>> searchTexts(SearchEngineRequest request) {
    loadMore = Completer<List<SearchResult>>();
    return loadMore!.future;
  }
}
