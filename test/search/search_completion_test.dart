import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/services/plugin_search_completed_publisher.dart';
import 'package:otzaria/search/bloc/search_bloc.dart';
import 'package:otzaria/search/bloc/search_event.dart';
import 'package:otzaria/search/models/search_completion.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/search/search_repository.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/tabs/models/searching_tab.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart';

import '../test_helpers/memory_cache_provider.dart';

SearchResult _result(int id) => SearchResult(
  id: BigInt.from(id),
  title: 'ספר $id',
  reference: 'סימן $id',
  text: 'שיעור הילוך מיל',
  segment: BigInt.one,
  isPdf: false,
  filePath: 'id:$id',
  mergedCount: 1,
  merged: const [],
  textStatus: TextStatus.ok,
  continuesToNextLine: false,
);

/// repository שבו כל קריאה לחיפוש מחזירה את ה-controller שהטסט שולט בו, כך
/// שהטסט קובע מתי החיפוש מסתיים, ואם הוא נכשל.
class _ScriptedRepository extends SearchRepository {
  final List<StreamController<SearchStreamUpdate>> streams = [];
  int loadMoreCalls = 0;

  StreamController<SearchStreamUpdate> get last => streams.last;

  @override
  Stream<SearchStreamUpdate> searchTextsStreamWithCounts(
    SearchEngineRequest request, {
    int chunkSize = 50,
  }) {
    final controller = StreamController<SearchStreamUpdate>();
    streams.add(controller);
    return controller.stream;
  }

  @override
  Future<List<SearchResult>> searchTexts(SearchEngineRequest request) async {
    loadMoreCalls++;
    return const [];
  }
}

/// מסיים חיפוש: מונה סופי ותוצאות, ואז סוגר את הזרם.
Future<void> _finish(
  StreamController<SearchStreamUpdate> stream, {
  required int total,
  List<SearchResult> results = const [],
  int? groups,
  bool truncated = false,
}) async {
  stream.add(
    SearchStreamUpdate(
      totalCount: total,
      groupCount: groups,
      results: results,
      truncated: truncated,
    ),
  );
  await stream.close();
  await pumpEventQueue();
}

Future<void> main() async {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  SearchConfiguration config({
    List<String> facets = const ['/'],
    ResultGroupingMode grouping = ResultGroupingMode.none,
  }) => SearchConfiguration(
    currentFacets: facets,
    searchScopeFacets: facets,
    // מונה שקטן מ-numResults מיושר למה שהוחזר בפועל; מעל הסף הוא נשמר.
    numResults: 1,
    resultGrouping: grouping,
  );

  group('SearchBloc.completions', () {
    late _ScriptedRepository repository;
    late SearchBloc bloc;
    late List<SearchCompletion> completions;

    setUp(() {
      repository = _ScriptedRepository();
      completions = [];
    });

    SearchBloc build({SearchConfiguration? configuration}) {
      bloc = SearchBloc(
        initialConfiguration: configuration ?? config(),
        repository: repository,
      );
      bloc.completions.listen(completions.add);
      addTearDown(bloc.close);
      return bloc;
    }

    test('נפלט פעם אחת עם המונה הסופי, אחרי שהתוצאות נכנסו ל-state', () async {
      build().add(UpdateSearchQuery('מיל'));
      await pumpEventQueue();
      expect(completions, isEmpty, reason: 'החיפוש עוד רץ');

      await _finish(repository.last, total: 7, results: [_result(1)]);

      expect(completions, hasLength(1));
      final completion = completions.single;
      expect(completion.query, 'מיל');
      expect(completion.total, 7);
      expect(completion.countsGroups, isFalse);
      expect(completion.truncated, isFalse);
      expect(completion.returned, 1);
      expect(completion.facets, ['/']);
      expect(bloc.state.isLoading, isFalse);
    });

    test('אפס תוצאות נפלט כהשלמה', () async {
      build().add(UpdateSearchQuery('אין כזה'));
      await pumpEventQueue();
      await _finish(repository.last, total: 0);

      expect(completions.single.total, 0);
      expect(completions.single.returned, 0);
    });

    test('במצב איחוד המונה סופר קבוצות', () async {
      build(
        configuration: config(grouping: ResultGroupingMode.sameSection),
      ).add(UpdateSearchQuery('מיל'));
      await pumpEventQueue();
      await _finish(
        repository.last,
        total: 40,
        groups: 3,
        results: [_result(1), _result(2), _result(3)],
      );

      expect(completions.single.total, 3);
      expect(completions.single.countsGroups, isTrue);
    });

    test('ספירה חלקית מסומנת truncated', () async {
      build().add(UpdateSearchQuery('מיל'));
      await pumpEventQueue();
      await _finish(repository.last, total: 100000, truncated: true);

      expect(completions.single.truncated, isTrue);
    });

    test('שאילתה ריקה או בלי קטגוריות אינן חיפוש שהסתיים', () async {
      build()
        ..add(UpdateSearchQuery(''))
        ..close();
      await pumpEventQueue();

      final noFacets = SearchBloc(
        initialConfiguration: config(facets: const []),
        repository: repository,
      );
      addTearDown(noFacets.close);
      final received = <SearchCompletion>[];
      noFacets.completions.listen(received.add);
      noFacets.add(UpdateSearchQuery('מיל'));
      await pumpEventQueue();

      expect(completions, isEmpty);
      expect(received, isEmpty);
      expect(repository.streams, isEmpty, reason: 'לא רץ חיפוש במנוע');
    });

    test('חיפוש שהוחלף באמצע אינו נפלט, רק האחרון', () async {
      build().add(UpdateSearchQuery('ראשון'));
      await pumpEventQueue();
      final first = repository.last;

      bloc.add(UpdateSearchQuery('שני'));
      await pumpEventQueue();
      final second = repository.last;

      await _finish(second, total: 2, results: [_result(2)]);
      await _finish(first, total: 99, results: [_result(1)]);

      expect(completions.map((c) => c.query), ['שני']);
      expect(completions.single.total, 2);
    });

    test('כשל בחיפוש אינו נפלט', () async {
      build().add(UpdateSearchQuery('מיל'));
      await pumpEventQueue();
      repository.last.addError(StateError('boom'));
      await pumpEventQueue();

      expect(completions, isEmpty);
      expect(bloc.state.errorMessage, isNotNull);
    });

    test('סגירת ה-bloc באמצע חיפוש אינה פולטת', () async {
      build().add(UpdateSearchQuery('מיל'));
      await pumpEventQueue();
      await bloc.close();
      await _finish(repository.last, total: 5, results: [_result(1)]);

      expect(completions, isEmpty);
    });

    test('"טען עוד" הוא המשך של אותו חיפוש ואינו נפלט שוב', () async {
      build().add(UpdateSearchQuery('מיל'));
      await pumpEventQueue();
      await _finish(repository.last, total: 3, results: [_result(1)]);
      expect(completions, hasLength(1));

      bloc.add(LoadMoreResults());
      await pumpEventQueue();

      expect(repository.loadMoreCalls, 1);
      expect(completions, hasLength(1));
    });

    test('שינוי הגדרה שמריץ חיפוש מחדש הוא חיפוש חדש ונפלט שוב', () async {
      build().add(UpdateSearchQuery('מיל'));
      await pumpEventQueue();
      await _finish(repository.last, total: 1, results: [_result(1)]);

      bloc.add(UpdateNumResults(50));
      await pumpEventQueue();
      await _finish(repository.last, total: 1, results: [_result(1)]);

      expect(completions, hasLength(2));
      expect(
        completions[1].requestId,
        greaterThan(completions[0].requestId),
        reason: 'requestId עולה בכל חיפוש',
      );
    });
  });

  group('SearchingTab → search.completed', () {
    late _ScriptedRepository repository;
    late List<(String, Map<String, dynamic>)> sent;
    late PluginSearchCompletedPublisher publisher;

    setUp(() {
      repository = _ScriptedRepository();
      sent = [];
      publisher = PluginSearchCompletedPublisher(
        sink: (topic, payload) async => sent.add((topic, payload)),
      );
    });

    SearchingTab buildTab({SearchConfiguration? configuration}) {
      final tab = SearchingTab(
        'חיפוש',
        null,
        searchBloc: SearchBloc(
          initialConfiguration: configuration ?? config(),
          repository: repository,
        ),
        completedPublisher: publisher,
      );
      // הבדיקה 'סגירת הטאב' סוגרת אותו בעצמה, ולכן ה-teardown סלחני.
      addTearDown(() {
        try {
          tab.dispose();
        } catch (_) {}
      });
      return tab;
    }

    test('האירוע נושא את הטאב, החיפוש והמונה', () async {
      final tab = buildTab();
      tab.searchBloc.add(UpdateSearchQuery('מיל'));
      await pumpEventQueue();
      await _finish(repository.last, total: 12, results: [_result(1)]);

      expect(sent, hasLength(1));
      final (topic, payload) = sent.single;
      expect(topic, 'search.completed');
      expect(payload['tabId'], tab.pluginTabId);
      expect(payload['query'], 'מיל');
      expect(payload['mode'], 'advanced');
      expect(payload['total'], 12);
      expect(payload['totalKind'], 'matches');
      expect(payload['truncated'], isFalse);
      expect(payload['returned'], 1);
      final request = payload['request'] as Map<String, dynamic>;
      expect(request['query'], 'מיל');
      expect(request['facets'], ['/']);
    });

    test('כל טאב מזהה את עצמו', () async {
      final first = buildTab();
      final second = buildTab();
      expect(first.pluginTabId, isNot(second.pluginTabId));
    });

    test('סגירת הטאב מפסיקה למסור אירועים', () async {
      final tab = buildTab();
      tab.searchBloc.add(UpdateSearchQuery('מיל'));
      await pumpEventQueue();
      tab.dispose();
      await _finish(repository.last, total: 3, results: [_result(1)]);

      expect(sent, isEmpty);
    });

    test('כשל במסירה לתוסף אינו מפיל את החיפוש', () async {
      final failing = PluginSearchCompletedPublisher(
        sink: (_, _) async => throw StateError('plugin down'),
      );
      final tab = SearchingTab(
        'חיפוש',
        null,
        searchBloc: SearchBloc(
          initialConfiguration: config(),
          repository: repository,
        ),
        completedPublisher: failing,
      );
      addTearDown(tab.dispose);
      tab.searchBloc.add(UpdateSearchQuery('מיל'));
      await pumpEventQueue();
      await _finish(repository.last, total: 1, results: [_result(1)]);

      expect(tab.searchBloc.state.isLoading, isFalse);
      expect(tab.searchBloc.state.errorMessage, isNull);
    });
  });
}
