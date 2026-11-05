import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/data_providers/file_system_data_provider.dart';
import 'package:otzaria/data/data_providers/tantivy_data_provider.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/search/bloc/search_bloc.dart';
import 'package:otzaria/search/bloc/search_event.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/search/search_engine_gateway.dart';
import 'package:otzaria/search/search_repository.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart';

import '../helpers/memory_settings_cache.dart';
import '../support/recording_search_engine.dart';
import '../support/search_engine_test_init.dart';

Future<void> main() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  final ready = await tryInitSearchEngine();

  group('SearchRepository snapshots', () {
    late _SnapshotEngine engine;
    late SearchRepository repository;

    setUp(() {
      engine = _SnapshotEngine();
      repository = SearchRepository(engineProvider: () async => engine);
    });
    tearDown(() => engine.finishPending());

    test('העדכון הראשון שומר ספירות וקבוצות בלי להוסיף מנה', () async {
      final updates = repository
          .searchTextsStreamWithCounts(_request())
          .toList();
      await _until(() => engine.streams.isNotEmpty);
      const first = SearchStreamUpdate(
        totalCount: 7,
        groupCount: 3,
        bookCounts: {'id:1': 7},
        results: [],
        truncated: true,
      );
      final chunk = _chunk('first');
      engine.streams.single.controller.add(first);
      engine.streams.single.controller.add(chunk);
      await engine.streams.single.controller.close();
      final received = await updates;
      expect(received, hasLength(2));
      final captured = received.first as SearchSnapshotUpdate;
      expect(captured.snapshot, 'one');
      expect(captured.update, same(first));
      expect(captured.totalCount, 7);
      expect(captured.groupCount, 3);
      expect(captured.bookCounts, {'id:1': 7});
      expect(captured.truncated, isTrue);
      expect(received.last, same(chunk));
    });

    test('זרם ריק, כמו זרם שבוטל, אינו מקבל אירוע snapshot', () async {
      final updates = repository
          .searchTextsStreamWithCounts(_request())
          .toList();
      await _until(() => engine.streams.isNotEmpty);
      await engine.streams.single.controller.close();
      expect(await updates, isEmpty);
    });

    test('דור שהשתנה לפני הדפדוף עוצר לפני קריאת העמוד', () async {
      engine.snapshot = 'two';
      engine.immediatePage = [_result('must-not-append')];
      await expectLater(
        repository.searchTexts(_request(snapshot: 'one')),
        throwsA(isA<SearchSnapshotChanged>()),
      );
      expect(engine.pages, isEmpty);
    });

    test('דור שהשתנה בזמן הדפדוף פוסל גם עמוד שכבר חזר', () async {
      final page = repository.searchTexts(_request(snapshot: 'one'));
      final rejected = expectLater(page, throwsA(isA<SearchSnapshotChanged>()));
      await _until(() => engine.pages.isNotEmpty);
      engine.snapshot = 'two';
      engine.pages.single.result.complete([_result('must-not-append')]);
      await rejected;
    });

    test('מנוע בלי snapshot ממשיך חיפוש רגיל אך אינו מאשר עמוד נתון', () async {
      final legacy = RecordingSearchEngine();
      final repository = SearchRepository(engineProvider: () async => legacy);
      await expectLater(
        repository.searchTexts(_request(snapshot: 'one')),
        throwsA(isA<SearchSnapshotChanged>()),
      );
      expect(legacy.lastRequest, isNull);
      expect(await repository.searchTexts(_request()), isEmpty);
      final updates = await repository
          .searchTextsStreamWithCounts(_request())
          .toList();
      expect(updates.single, isNot(isA<SearchSnapshotUpdate>()));
    });
  }, skip: ready ? false : searchEngineSkipReason);

  group('SearchBloc paging snapshots', () {
    late _SnapshotEngine engine;
    late _CountingIndex index;
    SearchBloc? bloc;

    setUpAll(() async {
      await Settings.init(cacheProvider: MemorySettingsCache());
      // Install the file-system fake before DataRepository captures its source;
      // neither production singleton should start catalogue or index I/O here.
      FileSystemData.instance = _SnapshotFileSystem();
    });

    setUp(() {
      engine = _SnapshotEngine();
      TantivyDataProvider.instance = index = _CountingIndex();
      DataRepository.instance.library = Future.value(
        Library(categories: [])
          ..books.add(TextBook(id: 1, title: 'ספר', categoryPath: '/scope')),
      );
    });
    tearDown(() async {
      final closed = bloc?.close();
      await engine.finishPending();
      for (final count in index.counts) {
        if (!count.isCompleted) count.complete({});
      }
      await closed;
      bloc = null;
      DataRepository.instance.invalidateLibraryCache();
    });

    SearchBloc create([
      SearchConfiguration configuration = const SearchConfiguration(
        numResults: 1,
      ),
    ]) => bloc = SearchBloc(
      repository: SearchRepository(engineProvider: () async => engine),
      initialConfiguration: configuration,
    );

    Future<void> finish(int stream, String text, {int total = 3}) async {
      await _finish(engine.streams[stream], text, total: total);
      await _until(() => !bloc!.state.isLoading);
    }

    test('דור יציב מצרף את העמוד הבא באותו offset', () async {
      final search = create();
      search.add(UpdateSearchQuery('שלום'));
      await _until(() => engine.streams.length == 1);
      await finish(0, 'first');
      search.add(LoadMoreResults());
      await _until(() => engine.pages.length == 1);
      expect(engine.pages.single.request.expectedSnapshot, 'one');
      expect(engine.pages.single.request.offset, 1);
      engine.pages.single.result.complete([_result('second')]);
      await _until(() => !search.state.isLoading);
      expect(search.state.results.map((r) => r.text), ['first', 'second']);
      expect(engine.streams, hasLength(1));
    });

    test('commit לפני המנה הראשונה אינו מחבר אליה עמוד מדור חדש', () async {
      final search = create();
      search.add(UpdateSearchQuery('שלום'));
      await _until(() => engine.streams.length == 1);
      // ה-snapshot כבר נלכד, אבל העדכון הראשון עדיין לא נמסר ל-BLoC.
      engine.snapshot = 'two';
      await finish(0, 'first-generation');
      search.add(LoadMoreResults());
      await _until(() => engine.streams.length == 2);
      expect(engine.pages, isEmpty);
      expect(search.state.results, isEmpty);
      await finish(1, 'fresh-first');
      search.add(LoadMoreResults());
      await _until(() => engine.pages.length == 1);
      expect(engine.pages.single.request.expectedSnapshot, 'two');
      engine.pages.single.result.complete([_result('fresh-second')]);
      await _until(() => !search.state.isLoading);
      expect(search.state.results.map((r) => r.text), [
        'fresh-first',
        'fresh-second',
      ]);
    });

    test(
      'commit בזמן העמוד מרענן פעם אחת ושומר את כל אפשרויות השאילתה',
      () async {
        const configuration = SearchConfiguration(
          numResults: 1,
          distance: 4,
          sortBy: ResultsOrder.catalogue,
          anyOrder: true,
          wordMatchMode: WordMatchMode.atLeast,
          wordMatchCount: 2,
          resultGrouping: ResultGroupingMode.sameSection,
        );
        final search = create(configuration);
        search.add(
          UpdateSearchQuery(
            'אור עולם',
            negativeQuery: 'חשך',
            customSpacing: {'0-1': '3'},
            alternativeWords: {
              0: ['אורה'],
            },
            searchOptions: {
              'אור_0': {'קידומות': true},
            },
            negativeCustomSpacing: {'0-1': '2'},
            negativeAlternativeWords: {
              0: ['חושך'],
            },
            negativeSearchOptions: {
              'חשך_0': {'סיומות': true},
            },
          ),
        );
        await _until(() => engine.streams.length == 1);
        await finish(0, 'old-first');
        final original = engine.streams.first.request;
        search.add(LoadMoreResults());
        await _until(() => engine.pages.length == 1);
        engine.snapshot = 'two';
        engine.pages.single.result.complete([_result('discarded-page')]);
        await _until(() => engine.streams.length == 2);
        final retry = engine.streams.last.request;
        expect(_inputs(retry), _inputs(original));
        expect(retry.cancelRequestId, isNot(original.cancelRequestId));
        expect(engine.cancelled, contains(original.cancelRequestId));
        expect(search.state.configuration, configuration);
        // אינדוקס ממשיך גם בזמן הרענון. לא מתחילה לולאת rerun אוטומטית.
        engine.snapshot = 'three';
        await finish(1, 'refreshed-first');
        await pumpEventQueue(times: 50);
        expect(engine.streams, hasLength(2));
        expect(search.state.results.map((r) => r.text), ['refreshed-first']);
        expect(search.state.errorMessage, isNull);
      },
    );

    test('שינוי דור מנקה מטמון facets וספירה ישנה אינה מחזירה אותו', () async {
      final search = create(
        const SearchConfiguration(
          numResults: 1,
          currentFacets: ['/scope/id:1'],
          searchScopeFacets: ['/scope'],
        ),
      );
      search.add(UpdateSearchQuery('שלום'));
      await _until(
        () => engine.streams.length == 1 && index.counts.length == 1,
      );
      index.counts.first.complete({'id:1': 9});
      await _until(() => search.state.facetCounts['/scope'] == 9);
      final cachedSignature = search.facetCountsSignatureForTesting;
      expect(cachedSignature, isNotNull);
      await finish(0, 'first');

      engine.snapshot = 'two';
      search.add(LoadMoreResults());
      await _until(
        () => engine.streams.length == 2 && index.counts.length == 2,
      );
      expect(search.state.facetCounts, isEmpty);
      expect(search.facetCountsSignatureForTesting, isNull);
      search.add(
        ReplaceFacetCounts(
          {'/scope': 99},
          requestId: 1,
          signature: cachedSignature!,
        ),
      );
      await pumpEventQueue();
      expect(search.state.facetCounts, isEmpty);
      expect(search.facetCountsSignatureForTesting, isNull);
      index.counts.last.complete({'id:1': 2});
      await _until(() => search.state.facetCounts['/scope'] == 2);
      await finish(1, 'fresh-first', total: 2);
      expect(search.state.facetCounts['/scope'], 2);
    });

    test('שאילתה חדשה בזמן הדפדוף גוברת גם על שגיאת snapshot ישנה', () async {
      final search = create();
      search.add(UpdateSearchQuery('ישן'));
      await _until(() => engine.streams.length == 1);
      await finish(0, 'old-first');
      search.add(LoadMoreResults());
      await _until(() => engine.pages.length == 1);
      engine.snapshot = 'two';
      search.add(UpdateSearchQuery('חדש'));
      await _until(() => engine.streams.length == 2);
      engine.streams.last.controller.add(_chunk('new-first'));
      await _until(() => search.state.results.isNotEmpty);
      engine.pages.single.result.complete([_result('old-page')]);
      await pumpEventQueue(times: 50);
      expect(engine.streams, hasLength(2));
      expect(search.state.searchQuery, 'חדש');
      expect(search.state.results.single.text, 'new-first');
      expect(search.state.isLoading, isTrue);
      await engine.streams.last.controller.close();
      await _until(() => !search.state.isLoading);
    });

    test(
      'snapshot ראשוני שהתעכב אינו מחליף את snapshot השאילתה החדשה',
      () async {
        final search = create();
        final delayed = engine.nextSnapshot = Completer<String>();
        search.add(UpdateSearchQuery('ישן'));
        await _until(() => engine.snapshotCalls == 1);
        engine.snapshot = 'two';
        search.add(UpdateSearchQuery('חדש'));
        await _until(() => engine.streams.length == 1);
        await finish(0, 'new-first');
        delayed.complete('one');
        await _until(() => engine.streams.length == 2);
        await _finish(engine.streams.last, 'old-first');
        expect(search.state.results.single.text, 'new-first');
        search.add(LoadMoreResults());
        await _until(() => engine.pages.length == 1);
        expect(engine.pages.single.request.expectedSnapshot, 'two');
        engine.pages.single.result.complete([_result('new-second')]);
        await _until(() => !search.state.isLoading);
        expect(search.state.results.map((r) => r.text), [
          'new-first',
          'new-second',
        ]);
      },
    );

    test('עטיפת snapshot אינה הופכת ספירת התקדמות לספירה סופית', () async {
      final search = create();
      search.add(UpdateSearchQuery('שלום'));
      await _until(() => engine.streams.length == 1);
      engine.streams.single.controller.add(
        const SearchCountProgress(foundSoFar: 2, truncated: false),
      );
      await _until(() => search.state.totalResults == 2);
      expect(search.state.isCounting, isTrue);
      await finish(0, 'first');
      expect(search.state.totalResults, 3);
      expect(search.state.isCounting, isFalse);
    });
  }, skip: ready ? false : searchEngineSkipReason);

  test(
    'commit במנוע האמיתי משנה snapshot ופוסל offset מהתוצאות הקודמות',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'search-snapshot-',
      );
      final engine = await SearchEngine.newInstance(path: directory.path);
      addTearDown(() async {
        engine.dispose();
        if (!Platform.isWindows) await directory.delete(recursive: true);
      });
      Future<void> add(int ordinal) => engine.addDocument(
        ordinal: ordinal,
        title: 'ספר',
        reference: 'שורה $ordinal',
        topics: '/scope',
        text: 'שלום $ordinal',
        segment: BigInt.from(ordinal),
        isPdf: false,
        filePath: 'id:1',
      );
      await add(10);
      await add(20);
      await engine.commit();
      final operations = RustSearchEngineOperations(engine);
      final repository = SearchRepository(
        engineProvider: () async => operations,
      );
      final initial = await repository
          .searchTextsStreamWithCounts(_request())
          .toList();
      final snapshot = (initial.first as SearchSnapshotUpdate).snapshot;
      await add(0);
      await engine.commit();
      final current = await operations.searchSnapshot();
      expect(current, isNot(snapshot));
      await expectLater(
        repository.searchTexts(_request(snapshot: snapshot)),
        throwsA(isA<SearchSnapshotChanged>()),
      );
      expect(
        await repository.searchTexts(_request(snapshot: current)),
        hasLength(1),
      );
    },
    skip: ready ? false : searchEngineSkipReason,
  );
}

SearchEngineRequest _request({String? snapshot}) => SearchEngineRequest(
  query: 'שלום',
  facets: const ['/'],
  limit: 1,
  offset: snapshot == null ? 0 : 1,
  expectedSnapshot: snapshot,
);

Future<void> _until(bool Function() predicate) async {
  for (var i = 0; i < 100 && !predicate(); i++) {
    await pumpEventQueue();
  }
  expect(predicate(), isTrue);
}

Future<void> _finish(_StreamCall call, String text, {int total = 3}) async {
  call.controller.add(
    SearchStreamUpdate(
      totalCount: total,
      groupCount: call.request.grouping == null ? null : total,
      results: [],
      truncated: false,
    ),
  );
  call.controller.add(_chunk(text));
  await call.controller.close();
}

SearchStreamUpdate _chunk(String text) =>
    SearchStreamUpdate(results: [_result(text)], truncated: false);

SearchResult _result(String text) => SearchResult(
  id: BigInt.from(text.hashCode.abs()),
  title: 'ספר',
  reference: 'שורה',
  text: text,
  segment: BigInt.zero,
  isPdf: false,
  filePath: 'id:1',
  mergedCount: 1,
  merged: const [],
  textStatus: TextStatus.ok,
  continuesToNextLine: false,
);

List<Object?> _inputs(SearchEngineRequest r) => [
  r.query,
  r.facets,
  r.limit,
  r.offset,
  r.order,
  r.searchMode,
  r.distance,
  r.negativeQuery,
  r.negativeDistance,
  r.scope,
  r.negativeScope,
  r.wordMatchMode,
  r.wordMatchCount,
  r.customSpacing,
  r.negativeCustomSpacing,
  r.alternativeWords,
  r.negativeAlternativeWords,
  r.searchOptions,
  r.negativeSearchOptions,
  r.matchNikud,
  r.matchTaamim,
  r.grouping,
  r.anyOrder,
];

class _StreamCall {
  final SearchEngineRequest request;
  final controller = StreamController<SearchStreamUpdate>();
  _StreamCall(this.request);
}

class _PageCall {
  final SearchEngineRequest request;
  final result = Completer<List<SearchResult>>();
  _PageCall(this.request);
}

class _SnapshotEngine extends RecordingSearchEngine
    implements SearchSnapshotEngineOperations {
  String snapshot = 'one';
  int snapshotCalls = 0;
  Completer<String>? nextSnapshot;
  List<SearchResult>? immediatePage;
  final streams = <_StreamCall>[];
  final pages = <_PageCall>[];
  final cancelled = <int>[];

  @override
  Future<String> searchSnapshot() {
    snapshotCalls++;
    final pending = nextSnapshot;
    nextSnapshot = null;
    return pending?.future ?? Future.value(snapshot);
  }

  @override
  Stream<SearchStreamUpdate> searchStreamWithCounts(
    SearchEngineRequest request, {
    required int chunkSize,
  }) {
    final call = _StreamCall(request);
    streams.add(call);
    return call.controller.stream;
  }

  Future<List<SearchResult>> _page(SearchEngineRequest request) {
    final call = _PageCall(request);
    pages.add(call);
    if (immediatePage case final results?) call.result.complete(results);
    return call.result.future;
  }

  @override
  Future<List<SearchResult>> searchExact(SearchEngineRequest request) =>
      _page(request);
  @override
  Future<List<SearchResult>> searchAdvanced(SearchEngineRequest request) =>
      _page(request);
  @override
  Future<List<SearchResult>> searchFuzzy(SearchEngineRequest request) =>
      _page(request);
  @override
  Future<void> cancelLexicalSearch(int requestId) async =>
      cancelled.add(requestId);

  Future<void> finishPending() async {
    for (final page in pages) {
      if (!page.result.isCompleted) page.result.complete([]);
    }
    for (final stream in streams) {
      await stream.controller.close();
    }
  }
}

class _SnapshotFileSystem extends Fake implements FileSystemData {
  @override
  Future<Library> getLibrary() async => Library(categories: []);
}

class _CountingIndex extends Fake implements TantivyDataProvider {
  final counts = <Completer<Map<String, int>>>[];

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #countByBook) {
      final count = Completer<Map<String, int>>();
      counts.add(count);
      return count.future;
    }
    return super.noSuchMethod(invocation);
  }
}
