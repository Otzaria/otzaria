import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/find_ref/find_ref_preference_store.dart';
import 'package:otzaria/find_ref/bloc/find_ref_bloc.dart';
import 'package:otzaria/find_ref/bloc/find_ref_event.dart';
import 'package:otzaria/find_ref/bloc/find_ref_state.dart';
import 'package:otzaria/find_ref/repository/db_reference_result.dart';
import 'package:otzaria/find_ref/repository/find_ref_repository.dart';
import 'package:otzaria/plugins/models/plugin_library_book_provider.dart';
import 'package:otzaria/plugins/services/plugin_find_ref_service.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import '../helpers/memory_settings_cache.dart';

const provider = PluginLibraryBookProvider(
  pluginId: 'barilan',
  id: 'refs',
  provider: 'barilanrefs',
  title: 'בר אילן',
  referenceSearch: true,
);
const rows = [
  {'reference': 'בראשית א ב', 'choiceIndex': 0},
];

class _Repository implements FindRefRepository {
  @override
  bool get respectHiddenLibrary => false;
  @override
  Stream<void> get userBooksChanges => const Stream.empty();
  @override
  Future<List<DbReferenceResult>> findRefs(
    String ref, {
    bool includePersonalBooks = false,
    FindRefPreferences? preferences,
  }) async => [
    DbReferenceResult(title: ref, reference: ref, segment: 1),
  ];
  @override
  void cancelPendingSearch() {}
  @override
  void dispose() {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => Settings.init(cacheProvider: MemorySettingsCache()));

  test('referenceSearch is explicit boolean opt-in', () {
    final payload = {
      'id': 'refs',
      'provider': 'barilanrefs',
      'title': 'בר אילן',
    };
    expect(
      PluginLibraryBookProvider.parse('p', payload).referenceSearch,
      false,
    );
    expect(
      PluginLibraryBookProvider.parse('p', {
        ...payload,
        'referenceSearch': true,
      }).referenceSearch,
      true,
    );
    expect(
      () => PluginLibraryBookProvider.parse('p', {
        ...payload,
        'referenceSearch': 'true',
      }),
      throwsA(isA<PluginLibraryBooksException>()),
    );
  });

  test('request ownership, duplicates and exact open payload', () async {
    final events =
        <({String plugin, String topic, Map<String, dynamic> data})>[];
    final service = PluginFindRefService.forTesting(
      providers: () => [provider],
      dispatch: (plugin, topic, data) async {
        events.add((plugin: plugin, topic: topic, data: data));
      },
    );
    final future = service.search('בראשית א ב');
    final id = events.single.data['requestId'] as String;
    expect(service.respond('other', id, results: rows), false);
    expect(
      service.respond(
        'barilan',
        id,
        results: [
          ...rows,
          ...rows,
          {'reference': 'bad', 'choiceIndex': -1},
        ],
      ),
      true,
    );
    expect(service.respond('barilan', id, results: rows), false);
    final hits = await future;
    expect(hits, hasLength(1));
    await service.open(hits.single);
    expect(events.last.topic, PluginFindRefService.openTopic);
    expect(events.last.data['expectedChoice'], 'בראשית א ב');
    expect(events.last.data.containsKey('bookId'), false);
  });

  test(
    'timeout, cancellation and provider removal reject late responses',
    () async {
      var providers = [provider];
      final ids = <String>[];
      final service = PluginFindRefService.forTesting(
        providers: () => providers,
        timeout: const Duration(milliseconds: 20),
        dispatch: (_, topic, data) async {
          if (topic == PluginFindRefService.requestTopic) {
            ids.add(data['requestId'] as String);
          }
        },
      );
      final owner = Object();
      final cancelled = service.search('בראשית', owner: owner);
      service.cancel(owner);
      expect(await cancelled, isEmpty);
      expect(service.respond('barilan', ids.last, results: rows), false);
      final removed = service.search('בראשית');
      providers = [];
      expect(service.respond('barilan', ids.last, results: rows), false);
      expect(await removed, isEmpty);
      providers = [provider];
      expect(await service.search('בראשית'), isEmpty);
      expect(service.respond('barilan', ids.last, results: rows), false);
    },
  );

  test(
    'legacy providers never receive reference requests; errors are contained',
    () async {
      var calls = 0;
      final legacy = PluginFindRefService.forTesting(
        providers: () => [
          const PluginLibraryBookProvider(
            pluginId: 'old',
            id: 'books',
            provider: 'legacy',
            title: 'old',
          ),
        ],
        dispatch: (_, _, _) async {
          calls++;
        },
      );
      expect(await legacy.search('בראשית'), isEmpty);
      expect(calls, 0);
      final broken = PluginFindRefService.forTesting(
        providers: () => [provider],
        dispatch: (_, _, _) async {
          throw StateError('disconnected');
        },
      );
      expect(await broken.search('בראשית'), isEmpty);
    },
  );

  test(
    'local results arrive first; new query rejects stale external reply',
    () async {
      final requests = <Map<String, dynamic>>[];
      final service = PluginFindRefService.forTesting(
        providers: () => [provider],
        timeout: const Duration(seconds: 5),
        dispatch: (_, topic, data) async {
          if (topic == PluginFindRefService.requestTopic) requests.add(data);
        },
      );
      final bloc = FindRefBloc(
        findRefRepository: _Repository(),
        externalService: service,
      );
      addTearDown(bloc.close);
      bloc.add(const SearchRefRequested('בראשית'));
      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect((bloc.state as FindRefSuccess).refs.single.title, 'בראשית');
      expect((bloc.state as FindRefSuccess).externalPending, true);
      expect(requests, isEmpty);
      await Future<void>.delayed(const Duration(milliseconds: 650));
      final old = requests.single['requestId'] as String;
      bloc.add(const SearchRefRequested('ברכות'));
      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(service.respond('barilan', old, results: rows), false);
      await Future<void>.delayed(const Duration(milliseconds: 650));
      expect(
        service.respond(
          'barilan',
          requests.last['requestId'] as String,
          results: const [
            {'reference': 'ברכות ב א', 'choiceIndex': 0},
          ],
        ),
        true,
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final result = bloc.state as FindRefSuccess;
      expect(result.refs.single.title, 'ברכות');
      expect(result.externalRefs.single.reference, 'ברכות ב א');
      expect(result.externalPending, false);
    },
  );

  test('reusing a normalized query keeps its pending provider reply', () async {
    final requested = Completer<Map<String, dynamic>>();
    var requests = 0;
    final service = PluginFindRefService.forTesting(
      providers: () => [provider],
      dispatch: (_, topic, data) async {
        if (topic == PluginFindRefService.requestTopic) {
          requests++;
          requested.complete(data);
        }
      },
    );
    final bloc = FindRefBloc(
      findRefRepository: _Repository(),
      externalService: service,
    );
    addTearDown(bloc.close);
    bloc.add(const SearchRefRequested('בראשית'));
    final request = await requested.future.timeout(const Duration(seconds: 5));
    final cached = bloc.state;
    bloc.add(const SearchRefRequested('בראשית '));
    await pumpEventQueue();
    expect(bloc.state, same(cached));
    final completed = bloc.stream.firstWhere(
      (state) => state is FindRefSuccess && !state.externalPending,
    );
    expect(
      service.respond('barilan', request['requestId'] as String, results: rows),
      true,
    );
    final result =
        await completed.timeout(const Duration(seconds: 5)) as FindRefSuccess;
    expect(result.refs.single.title, 'בראשית');
    expect(result.externalRefs.single.reference, 'בראשית א ב');
    expect(requests, 1);
  });
}
