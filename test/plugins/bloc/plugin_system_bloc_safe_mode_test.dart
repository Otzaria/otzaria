import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/plugins/bloc/plugin_system_bloc.dart';
import 'package:otzaria/plugins/bloc/plugin_system_event.dart';
import 'package:otzaria/plugins/bloc/plugin_system_state.dart';
import 'package:otzaria/plugins/declarative/models/declarative_program.dart';
import 'package:otzaria/plugins/declarative/services/declarative_plugin_host_service.dart';
import 'package:otzaria/plugins/models/installed_plugin.dart';
import 'package:otzaria/plugins/models/plugin_manifest.dart';
import 'package:otzaria/plugins/repository/plugin_registry_repository.dart';
import 'package:otzaria/plugins/utils/plugin_safe_mode.dart';
import 'package:otzaria/plugins/services/plugin_search_dialog_registry.dart';
import 'package:otzaria/plugins/services/plugin_runtime_dispatcher.dart';
import 'package:otzaria/plugins/services/plugin_external_editions_registry.dart';
import 'package:otzaria/plugins/services/plugin_lazy_activation_service.dart';
import 'package:otzaria/plugins/services/plugin_new_tab_page_registry.dart';

InstalledPlugin _plugin() => InstalledPlugin(
  pluginId: 'p1',
  name: 'P1',
  version: '1.0.0',
  installPath: '/tmp/p1',
  entrypointPath: 'index.html',
  enabled: false,
  pinned: false,
  manifest: PluginManifest.fromJson({
    'id': 'p1',
    'name': 'P1',
    'version': '1.0.0',
    'entrypoint': 'index.html',
  }),
  installedAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

class _FakeRepo implements PluginRegistryRepository {
  final saved = <InstalledPlugin>[];
  final choices = <(String, bool)>[];

  @override
  Future<void> saveEnabledChoice(String pluginId, bool enabled) async =>
      choices.add((pluginId, enabled));

  @override
  Future<List<InstalledPlugin>> getAllPlugins() async => [_plugin()];

  @override
  Future<InstalledPlugin?> getPlugin(String id) async => _plugin();

  @override
  Future<void> savePlugin(InstalledPlugin plugin) async => saved.add(plugin);

  @override
  Future<List<InstalledPlugin>> getDevelopmentPlugins() async => [];

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FakeDeclarativeHost implements DeclarativePluginHost {
  int syncs = 0;

  @override
  Future<void> syncPlugins(List<InstalledPlugin> plugins) async => syncs++;

  @override
  void removePlugin(String pluginId) {}

  @override
  Future<void> readerBookChanged(Book? book, {required String context}) async {}

  @override
  Future<void> dispatchAction(
    String pluginId,
    CompiledDeclarativeAction action,
  ) async {}

  @override
  Future<void> dispatchSelectionAction(
    String pluginId,
    Map<String, dynamic> actionTemplate,
    Map<String, dynamic> selectionPayload,
  ) async {}

  @override
  Future<void> dispatchLibraryBookAction(
    String pluginId,
    Map<String, dynamic> actionTemplate,
    Map<String, dynamic> bookPayload,
  ) async {}

  @override
  void dispose() {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeRepo repo;
  late _FakeDeclarativeHost host;
  late PluginSystemBloc bloc;

  setUp(() {
    PluginSafeMode.active.value = true;
    repo = _FakeRepo();
    host = _FakeDeclarativeHost();
    bloc = PluginSystemBloc(repository: repo, declarativeHost: host);
  });

  tearDown(() async {
    await bloc.close();
    PluginSafeMode.resetForTesting();
  });

  Future<void> send(PluginSystemEvent event) async {
    bloc.add(event);
    await pumpEventQueue(times: 200);
  }

  test(
    'safe restart removes search, editions and lazy registrations without unpublishing data',
    () async {
      final newTabs = PluginNewTabPageRegistry.instance;
      newTabs.register('p1');
      addTearDown(() => newTabs.remove('p1'));
      expect(newTabs.activePluginId, 'p1');
      final registry = PluginSearchDialogRegistry.instance;
      registry.registerPayload('p1', {
        'id': 'review-search',
        'type': 'checkbox',
        'title': 'חיפוש תוסף',
      });
      addTearDown(() => registry.removeAll('p1'));
      final editions = PluginExternalEditionsRegistry.instance;
      editions.registerPayload(
        _plugin().copyWith(
          enabled: true,
          manifest: PluginManifest.fromJson({
            'id': 'p1',
            'name': 'P1',
            'version': '1.0.0',
            'entrypoint': 'index.html',
            'contributes': {
              'databaseSources': [
                {'id': 'external'},
              ],
            },
          }),
        ),
        {
          'id': 'editions',
          'provider': 'external',
          'sourceId': 'external',
          'table': 'editions',
          'externalIdColumn': 'external_id',
          'otzariaIdColumn': 'otzaria_id',
        },
      );
      addTearDown(() => editions.removePlugin('p1'));
      final lazy = PluginLazyActivationService.instance;
      lazy.syncPlugin(
        'p1',
        broadcastTopics: {'reader.changed'},
        scheduleStartup: false,
      );
      final generation = lazy.activationGeneration('p1');
      expect(lazy.isActivationCurrent('p1', generation), isTrue);
      expect(registry.getAll(), hasLength(1));
      await PluginRuntimeDispatcher.instance.prepareForAppRestart();
      await send(LoadPlugins());
      expect(editions.configs, isEmpty);
      expect(newTabs.hasActiveRegistration, isFalse);
      expect(lazy.isActivationCurrent('p1', generation), isFalse);
      expect(repo.saved, isEmpty);
      expect(host.syncs, 0);
      expect(
        registry.getAll(),
        isEmpty,
        reason: 'No plugin controls should survive restarting into safe mode',
      );
    },
  );

  test('load and seed cannot run before the crash decision', () async {
    final decision = Completer<void>();
    PluginSafeMode.ready = decision.future;
    PluginSafeMode.active.value = false;
    await send(LoadPlugins());
    await send(const SeedBundledPlugins());
    expect(bloc.state, isA<PluginSystemLoading>());
    expect(host.syncs, 0);
    PluginSafeMode.active.value = true;
    decision.complete();
    await pumpEventQueue(times: 200);
    expect(bloc.state, isA<PluginSystemLoaded>());
    expect(host.syncs, 0);
  });

  test('loading lists the plugins without syncing them', () async {
    await send(LoadPlugins());

    expect(bloc.state, isA<PluginSystemLoaded>());
    expect((bloc.state as PluginSystemLoaded).plugins, hasLength(1));
    // A sync would treat the disabled plugins as removed and unpublish data.
    expect(host.syncs, 0);
  });

  test('enable and disable requests only store the user choice', () async {
    await send(const EnablePluginRequested('p1'));
    await send(const DisablePluginRequested('p1'));

    expect(repo.choices, [('p1', true), ('p1', false)]);
    expect(repo.saved, isEmpty);
    expect(host.syncs, 0);
  });
}
