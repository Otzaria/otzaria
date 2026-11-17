import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/find_ref/bloc/find_ref_bloc.dart';
import 'package:otzaria/find_ref/bloc/find_ref_event.dart';
import 'package:otzaria/find_ref/bloc/find_ref_state.dart';
import 'package:otzaria/find_ref/repository/db_reference_result.dart';
import 'package:otzaria/find_ref/repository/find_ref_repository.dart';
import 'package:otzaria/plugins/models/plugin_when_condition.dart';
import 'package:otzaria/plugins/repository/plugin_registry_repository.dart';
import 'package:otzaria/plugins/services/plugin_condition_evaluator.dart';
import 'package:otzaria/plugins/services/plugin_find_ref_service.dart';
import 'package:otzaria/plugins/services/plugin_lazy_activation_service.dart';
import 'package:otzaria/plugins/services/plugin_library_books_registry.dart';
import 'package:otzaria/plugins/services/plugin_page_launcher.dart';
import 'package:otzaria/plugins/services/plugin_runtime.dart';
import 'package:otzaria/plugins/services/plugin_runtime_dispatcher.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';

import '../helpers/memory_settings_cache.dart';

class _FindRefRepository extends Fake implements FindRefRepository {
  @override
  bool get respectHiddenLibrary => false;
  @override
  Stream<void> get userBooksChanges => const Stream.empty();
  @override
  Future<List<DbReferenceResult>> findRefs(
    String ref, {
    bool includePersonalBooks = false,
  }) async => [DbReferenceResult(title: ref, reference: ref, segment: 1)];
  @override
  void cancelPendingSearch() {}
  @override
  void dispose() {}
}

class _Repository extends Fake implements PluginRegistryRepository {
  @override
  Future<String?> getKV(String pluginId, String namespace, String key) async =>
      null;
  @override
  Future<bool> getIsEnabled(String pluginId) async => true;
}

class _Runtime extends Fake implements PluginRuntime {
  final events = <String>[];
  bool suspended = false;
  @override
  bool get freezesWhenSuspended => true;
  @override
  Future<void> evaluate(String source) async => events.add(source);
  @override
  Future<Object?> dispatchEventWithAck(String topic, String detailJson) async {
    expect(suspended, false);
    events.add('$topic $detailJson');
    return true;
  }

  @override
  Future<bool> setSuspended(
    bool suspended, {
    required bool Function() isCurrent,
    required bool Function() isShown,
  }) async {
    if (!isCurrent()) return false;
    this.suspended = suspended;
    return true;
  }

  @override
  Future<void> cancelPendingSuspend() async => suspended = false;
  Iterable<String> forTopic(String topic) =>
      events.where((event) => event.contains(topic));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const plugin = 'findref.dispatch.provider';
  const request = PluginFindRefService.requestTopic;
  const cancel = PluginFindRefService.cancelTopic;
  const rows = [
    {'reference': 'בראשית א ב', 'choiceIndex': 0},
  ];
  final dispatcher = PluginRuntimeDispatcher.instance;
  final lazy = PluginLazyActivationService.instance;
  final registry = PluginLibraryBooksRegistry.forTesting(
    conditions: PluginConditionEvaluator.forTesting(),
    repository: _Repository(),
  );
  late PluginLibraryBooksRegistry originalRegistry;
  late PluginFindRefService service;
  late List<String> opened;
  final owners = <Object>[];
  Object owner() {
    final value = Object();
    owners.add(value);
    return value;
  }

  String requestId(String event) =>
      RegExp(r'"requestId":"([^"]+)"').firstMatch(event)!.group(1)!;
  setUpAll(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
    originalRegistry = PluginLibraryBooksRegistry.instance;
    PluginLibraryBooksRegistry.instance = registry;
    service = PluginFindRefService.instance;
  });
  tearDownAll(() => PluginLibraryBooksRegistry.instance = originalRegistry);
  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    dispatcher.resetVisibilityForTesting();
    dispatcher.repositoryForTesting = _Repository();
    dispatcher.invalidatePlugin(plugin);
    opened = [];
    PluginPageLauncher.instance.navigator = opened.add;
    registry.registerPayload(plugin, {
      'id': 'refs',
      'provider': 'dispatchrefs',
      'title': 'מראי מקומות',
      'referenceSearch': true,
    });
  });
  tearDown(() async {
    for (final value in owners) {
      service.cancel(value);
    }
    owners.clear();
    registry.removePlugin(plugin);
    lazy.removePlugin(plugin);
    lazy.backgroundActivator = null;
    lazy.deliverOverride = null;
    for (final id in ['foreground', 'background']) {
      dispatcher.unregisterController(plugin, instanceId: id);
    }
    await pumpEventQueue();
    dispatcher.resetVisibilityForTesting();
    PluginPageLauncher.instance.navigator = null;
    PluginPageLauncher.instance.markPageClosed(plugin);
    debugDefaultTargetPlatformOverride = null;
  });
  test(
    'passive search and cancellation never launch a provider page',
    () async {
      final firstOwner = owner();
      final future = service.search('בראשית', owner: firstOwner);
      await pumpEventQueue();
      expect(opened, isEmpty);
      expect(await future.timeout(const Duration(seconds: 1)), isEmpty);
      service.cancel(firstOwner);
      expect(await future, isEmpty);
      await pumpEventQueue();
      expect(opened, isEmpty);
      final earlyOwner = owner();
      final early = service.search('בראשית', owner: earlyOwner);
      service.cancel(earlyOwner);
      expect(await early, isEmpty);
      await pumpEventQueue();
      expect(opened, isEmpty);
    },
  );
  test(
    'unavailable provider clears pending and keeps native results',
    () async {
      final bloc = FindRefBloc(
        findRefRepository: _FindRefRepository(),
        externalService: service,
      );
      addTearDown(bloc.close);
      final native = bloc.stream.firstWhere((state) => state is FindRefSuccess);
      bloc.add(const SearchRefRequested('בראשית'));
      final initial = await native as FindRefSuccess;
      expect(initial.refs.single.title, 'בראשית');
      expect(initial.externalPending, true);
      final completed =
          await bloc.stream
                  .firstWhere(
                    (state) =>
                        state is FindRefSuccess && !state.externalPending,
                  )
                  .timeout(const Duration(seconds: 2))
              as FindRefSuccess;
      expect(completed.refs, initial.refs);
      expect(completed.externalRefs, isEmpty);
      expect(opened, isEmpty);
    },
  );
  test(
    'explicit selection may launch the page after its runtime closes',
    () async {
      final runtime = _Runtime();
      dispatcher.registerRuntime(plugin, runtime, instanceId: 'foreground');
      final future = service.search('בראשית', owner: owner());
      await pumpEventQueue();
      expect(runtime.forTopic(request), hasLength(1));
      expect(
        service.respond(
          plugin,
          requestId(runtime.forTopic(request).single),
          results: rows,
        ),
        true,
      );
      final hit = (await future).single;
      dispatcher.unregisterController(plugin, instanceId: 'foreground');
      await service.open(hit);
      expect(opened, [plugin]);
    },
  );
  test(
    'blocked activation finishes passive search and preserves default delivery',
    () async {
      lazy.syncPlugin(
        plugin,
        broadcastTopics: {},
        scheduleStartup: false,
        activationConditions: {
          request: PluginWhenCondition.fromJson({
            'storage': {'key': 'enabled', 'equals': true},
          }),
        },
      );
      expect(
        await service
            .search('בראשית', owner: owner())
            .timeout(const Duration(seconds: 1)),
        isEmpty,
      );
      await expectLater(
        dispatcher.dispatchEventToPlugin(
          plugin,
          request,
          {},
          preferBackground: true,
          allowPageLaunch: false,
        ),
        throwsStateError,
      );
      await dispatcher.dispatchEventToPlugin(
        plugin,
        request,
        {},
        preferBackground: true,
      );
      expect(opened, isEmpty);
    },
  );
  test('background wins over foreground; cancellation stays passive', () async {
    final background = _Runtime();
    final foreground = _Runtime();
    dispatcher.registerRuntime(plugin, foreground, instanceId: 'foreground');
    dispatcher.registerRuntime(plugin, background, instanceId: 'background');
    final firstOwner = owner();
    final future = service.search('בראשית', owner: firstOwner);
    await pumpEventQueue();
    expect(background.forTopic(request), hasLength(1));
    expect(foreground.forTopic(request), isEmpty);
    final id = requestId(background.forTopic(request).single);
    dispatcher.unregisterController(plugin, instanceId: 'background');
    dispatcher.unregisterController(plugin, instanceId: 'foreground');
    service.cancel(firstOwner);
    expect(await future, isEmpty);
    await pumpEventQueue();
    expect(opened, isEmpty);
    expect(service.respond(plugin, id, results: rows), false);
  });
  test('suspended foreground handles search without page navigation', () async {
    final runtime = _Runtime();
    dispatcher.registerRuntime(plugin, runtime, instanceId: 'foreground');
    dispatcher.setVisiblePluginInstances({
      (pluginId: plugin, instanceId: 'foreground'),
    });
    await dispatcher.onForegroundInstanceReady(
      plugin,
      instanceId: 'foreground',
    );
    dispatcher.setVisiblePluginInstances({});
    await pumpEventQueue();
    expect(runtime.suspended, true);
    final future = service.search('בראשית', owner: owner());
    await pumpEventQueue();
    final event = runtime.forTopic(request).single;
    expect(service.respond(plugin, requestId(event), results: rows), true);
    expect(await future, hasLength(1));
    expect(opened, isEmpty);
  });
  for (final cancelFirst in [true, false]) {
    test(
      'late boot drops ${cancelFirst ? 'initial' : 'boot-pending'} work and preserves another dialog',
      () async {
        final activated = <String>[];
        lazy.syncPlugin(plugin, broadcastTopics: {}, scheduleStartup: false);
        lazy.backgroundActivator = (id) async => activated.add(id);
        final delivered = <({String topic, Map<String, dynamic> payload})>[];
        lazy.deliverOverride = (_, topic, payload) async =>
            delivered.add((topic: topic, payload: payload));
        final firstOwner = owner();
        final secondOwner = owner();
        final first = service.search('בראשית', owner: firstOwner);
        await pumpEventQueue();
        final second = service.search('ברכות', owner: secondOwner);
        await pumpEventQueue();
        service.cancel(cancelFirst ? firstOwner : secondOwner);
        expect(await (cancelFirst ? first : second), isEmpty);
        await pumpEventQueue();
        await lazy.onBackgroundInstanceReady(plugin);
        expect(activated, [plugin]);
        final requests = delivered
            .where((event) => event.topic == request)
            .toList();
        expect(requests, hasLength(1));
        expect(
          requests.single.payload['query'],
          cancelFirst ? 'ברכות' : 'בראשית',
        );
        expect(delivered.where((event) => event.topic == cancel), hasLength(1));
        final id = requests.single.payload['requestId'] as String;
        expect(service.respond('another.plugin', id, results: rows), false);
        expect(service.respond(plugin, id, results: rows), true);
        expect(await (cancelFirst ? second : first), hasLength(1));
        expect(service.respond(plugin, id, results: rows), false);
        expect(opened, isEmpty);
      },
    );
  }
  test(
    'provider removal invalidates work waiting for background boot',
    () async {
      lazy.syncPlugin(plugin, broadcastTopics: {}, scheduleStartup: false);
      lazy.backgroundActivator = (_) async {};
      final delivered = <String>[];
      lazy.deliverOverride = (_, topic, _) async => delivered.add(topic);
      final future = service.search('בראשית', owner: owner());
      await pumpEventQueue();
      registry.removePlugin(plugin);
      expect(await future, isEmpty);
      await lazy.onBackgroundInstanceReady(plugin);
      expect(delivered, isEmpty);
      expect(opened, isEmpty);
    },
  );
}
