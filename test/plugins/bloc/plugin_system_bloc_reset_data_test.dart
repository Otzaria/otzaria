import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/bloc/plugin_system_bloc.dart';
import 'package:otzaria/plugins/bloc/plugin_system_event.dart';
import 'package:otzaria/plugins/bloc/plugin_system_state.dart';
import 'package:otzaria/plugins/models/installed_plugin.dart';
import 'package:otzaria/plugins/models/plugin_manifest.dart';
import 'package:otzaria/plugins/models/plugin_permission_grant.dart';
import 'package:otzaria/plugins/models/plugin_toolbar_item.dart';
import 'package:otzaria/plugins/repository/plugin_registry_repository.dart';
import 'package:otzaria/plugins/services/plugin_external_search_service.dart';
import 'package:otzaria/plugins/services/plugin_installer_service.dart';
import 'package:otzaria/plugins/services/plugin_toolbar_registry.dart';

import '../../test_helpers/plugin_alerts_client.dart';

InstalledPlugin _plugin(String id) {
  return InstalledPlugin(
    pluginId: id,
    name: 'תוסף $id',
    version: '1.0.0',
    installPath: '/tmp/$id',
    entrypointPath: '/tmp/$id/index.html',
    enabled: true,
    pinned: true,
    manifest: PluginManifest(
      schemaVersion: 1,
      id: id,
      name: 'תוסף $id',
      version: '1.0.0',
      description: 'test',
      author: 'tester',
      homepage: '',
      entrypoint: 'index.html',
      minAppVersion: '1.0.0',
      sdkVersion: '1.x',
      permissions: const [],
      networkEnabled: false,
      networkAllowlist: const [],
      toolTabTitle: 'תוסף $id',
      toolTabOrder: 100,
      defaultPinned: true,
      publishedDataTypes: const [],
    ),
    installedAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
  );
}

class _FakeRepo implements PluginRegistryRepository {
  final Map<String, InstalledPlugin> plugins;
  _FakeRepo(this.plugins);

  @override
  Future<InstalledPlugin?> getPlugin(String pluginId) async =>
      plugins[pluginId];

  @override
  Future<String?> getKV(String a, String b, String c) async => null;

  @override
  Future<List<PluginPermissionGrant>> getPluginPermissions(String id) async =>
      [];

  @override
  Future<List<String>> getGrantedPermissionNames(String id) async => [];

  @override
  Future<String?> getNewTabPageOwner() async => null;

  @override
  Future<List<InstalledPlugin>> getAllPlugins() async =>
      plugins.values.toList();

  @override
  Future<List<InstalledPlugin>> getDevelopmentPlugins() async => [];

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

/// resetPluginData אינו נוגע בדיסק — הטסט בודק רק שהוא נקרא ולמי.
class _StubInstaller extends PluginInstallerService {
  final reset = <String>[];
  _StubInstaller(PluginRegistryRepository repo) : super(repository: repo);

  @override
  Future<void> resetPluginData(String pluginId) async => reset.add(pluginId);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const toolbarItem = PluginToolbarItem(
    id: 'button',
    title: 'Button',
    icon: 'apps_24_regular',
  );

  tearDown(() {
    PluginToolbarRegistry.instance.removeAll('p1');
    PluginExternalSearchService.instance.removePlugin('p1');
  });

  Future<_StubInstaller> reset(String pluginId) async {
    final repo = _FakeRepo({'p1': _plugin('p1')});
    final installer = _StubInstaller(repo);
    final bloc = PluginSystemBloc(
      repository: repo,
      alertsClient: pluginAlertsClientFor(repo),
      installerService: installer,
    );
    addTearDown(bloc.close);
    bloc.add(ResetPluginDataRequested(pluginId));
    if (repo.plugins.containsKey(pluginId)) {
      await expectLater(bloc.stream, emitsThrough(isA<PluginSystemLoaded>()));
    } else {
      await Future<void>.delayed(Duration.zero);
    }
    return installer;
  }

  test(
    'איפוס מוחק את נתוני התוסף דרך שירות ההתקנה וטוען את הרשימה מחדש',
    () async {
      final installer = await reset('p1');

      expect(installer.reset, ['p1']);
    },
  );

  test('איפוס מסיר את הרישומים החיים של התוסף (סרגל, ספקי חיפוש)', () async {
    PluginToolbarRegistry.instance.register('p1', toolbarItem);
    PluginExternalSearchService.instance.register('external-p1', 'p1');

    await reset('p1');

    expect(PluginToolbarRegistry.instance.getAll(), isEmpty);
    expect(
      PluginExternalSearchService.instance.hasProvider('external-p1'),
      isFalse,
    );
  });

  test('תוסף שאינו מותקן — לא נוגעים בכלום', () async {
    final installer = await reset('missing');

    expect(installer.reset, isEmpty);
  });
}
