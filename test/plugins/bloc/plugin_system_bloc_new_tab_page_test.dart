import 'dart:async';
import 'dart:io';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/plugins/bloc/plugin_system_bloc.dart';
import 'package:otzaria/plugins/bloc/plugin_system_event.dart';
import 'package:otzaria/plugins/bloc/plugin_system_state.dart';
import 'package:otzaria/plugins/models/installed_plugin.dart';
import 'package:otzaria/plugins/models/plugin_manifest.dart';
import 'package:otzaria/plugins/models/plugin_valid_permissions.dart';
import 'package:otzaria/plugins/repository/plugin_registry_repository.dart';
import 'package:otzaria/plugins/services/plugin_new_tab_page_registry.dart';
import 'package:otzaria/plugins/services/plugin_new_tab_page_service.dart';
import 'package:otzaria/plugins/services/plugin_page_launcher.dart';
import 'package:otzaria/plugins/storage/plugin_system_database.dart';
import 'package:otzaria/plugins/utils/plugin_safe_mode.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';

import '../../test_helpers/memory_cache_provider.dart';

InstalledPlugin _plugin(String id) => InstalledPlugin(
  pluginId: id,
  name: id,
  version: '1.0.0',
  installPath: '/plugins/$id',
  entrypointPath: 'index.html',
  enabled: true,
  pinned: false,
  manifest: PluginManifest.fromJson({
    'schemaVersion': 1,
    'id': id,
    'name': id,
    'version': '1.0.0',
    'entrypoint': 'index.html',
    'permissions': ['navigation.write'],
  }),
  installedAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const owner = 'test.new-tab.owner';
  const other = 'test.new-tab.other';
  final database = PluginSystemDatabase.instance;
  final registry = PluginNewTabPageRegistry.instance;
  final launcher = PluginPageLauncher.instance;
  late Directory tempDir;
  late PluginRegistryRepository repository;
  late List<String> opened;
  late void Function(String)? previousNavigator;

  setUp(() async {
    PluginSafeMode.resetForTesting();
    PluginNewTabPageService.instance.resetQueueForTesting();
    tempDir = await Directory.systemTemp.createTemp('plugin_new_tab_load_');
    await Settings.init(cacheProvider: MemoryCacheProvider());
    AppPaths.debugOverrideDataRootPath(tempDir.path);
    database.resetForTests();
    repository = PluginRegistryRepository(database: database);
    for (final id in [other, owner]) {
      await repository.savePluginWithPermissions(_plugin(id), {
        'navigation.write': true,
      });
    }
    expect(
      await repository.grantNewTabPage(
        owner,
        allowPreviouslyDenied: true,
        expectedOwner: null,
        onGranted: () {},
      ),
      isTrue,
    );
    await database.close();
    expect(registry.hasActiveRegistration, isFalse);
    opened = [];
    previousNavigator = launcher.navigator;
    launcher.navigator = opened.add;
  });

  tearDown(() async {
    launcher.navigator = previousNavigator;
    for (final id in [owner, other]) {
      launcher.markPageClosed(id);
      registry.remove(id);
    }
    PluginSafeMode.resetForTesting();
    await database.close();
    database.resetForTests();
    AppPaths.debugOverrideDataRootPath(null);
    await tempDir.delete(recursive: true);
  });

  Future<void> send(
    PluginSystemBloc bloc,
    PluginSystemEvent event,
  ) async {
    bloc.add(event);
    await pumpEventQueue(times: 100);
    expect(bloc.state, isA<PluginSystemLoaded>());
  }

  blocTest<PluginSystemBloc, PluginSystemState>(
    'טעינה ראשונה משחזרת בעלות שמורה ופותחת את התוסף הנכון בלי רישום חוזר',
    build: () => PluginSystemBloc(repository: repository),
    act: (bloc) => send(bloc, LoadPlugins()),
    expect: () => [isA<PluginSystemLoading>(), isA<PluginSystemLoaded>()],
    verify: (_) async {
      expect(registry.hasActiveRegistration, isTrue);
      expect(registry.activePluginId, owner);
      expect(opened, isEmpty);
      await registry.open();
      expect(opened, [owner]);
    },
  );

  blocTest<PluginSystemBloc, PluginSystemState>(
    'רענון מאמץ בעלות שהוחלפה במסד',
    build: () => PluginSystemBloc(repository: repository),
    act: (bloc) async {
      await send(bloc, LoadPlugins());
      expect(registry.activePluginId, owner);
      expect(
        await repository.grantNewTabPage(
          other,
          allowPreviouslyDenied: true,
          expectedOwner: owner,
          onGranted: () {},
        ),
        isTrue,
      );
      await send(bloc, LoadPlugins());
    },
    verify: (_) async {
      expect(registry.activePluginId, other);
      await registry.open();
      expect(opened, [other]);
    },
  );

  blocTest<PluginSystemBloc, PluginSystemState>(
    'השבתה מסירה את הפלוס והפעלה מחדש משחזרת את הבעלות השמורה',
    build: () => PluginSystemBloc(repository: repository),
    act: (bloc) async {
      await send(bloc, LoadPlugins());
      expect(registry.activePluginId, owner);
      await send(bloc, const DisablePluginRequested(owner));
      expect(registry.hasActiveRegistration, isFalse);
      await registry.open();
      expect(opened, isEmpty);
      expect(
        await repository.getPermission(owner, pluginNewTabPagePermission),
        isTrue,
      );
      await send(bloc, const EnablePluginRequested(owner));
    },
    verify: (_) => expect(registry.activePluginId, owner),
  );

  for (final permission in ['navigation.write', pluginNewTabPagePermission]) {
    blocTest<PluginSystemBloc, PluginSystemState>(
      'שלילת $permission מסירה בעלות ואינה משוחזרת ברענון',
      build: () => PluginSystemBloc(repository: repository),
      act: (bloc) async {
        await send(bloc, LoadPlugins());
        expect(registry.activePluginId, owner);
        await send(
          bloc,
          SetPluginPermissionRequested(
            pluginId: owner,
            permission: permission,
            granted: false,
          ),
        );
        await send(bloc, LoadPlugins());
      },
      verify: (_) async {
        expect(registry.hasActiveRegistration, isFalse);
        expect(await repository.getNewTabPageOwner(), isNull);
        await registry.open();
        expect(opened, isEmpty);
      },
    );
  }

  blocTest<PluginSystemBloc, PluginSystemState>(
    'החלטת מצב בטוח מעכבת שחזור בעלות ומשאירה את ההרשאות השמורות',
    build: () => PluginSystemBloc(repository: repository),
    act: (bloc) async {
      final decision = Completer<void>();
      PluginSafeMode.ready = decision.future;
      bloc.add(LoadPlugins());
      await pumpEventQueue();
      expect(bloc.state, isA<PluginSystemLoading>());
      expect(registry.hasActiveRegistration, isFalse);
      PluginSafeMode.active.value = true;
      decision.complete();
      await pumpEventQueue(times: 100);
      expect(bloc.state, isA<PluginSystemLoaded>());
      expect(registry.hasActiveRegistration, isFalse);
      expect((await database.getInstalledPlugin(owner))!.enabled, isTrue);
      expect(
        await repository.getPermission(owner, pluginNewTabPagePermission),
        isTrue,
      );
      PluginSafeMode.resetForTesting();
      await send(bloc, LoadPlugins());
    },
    verify: (_) => expect(registry.activePluginId, owner),
  );
}
