import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/bloc/plugin_system_bloc.dart';
import 'package:otzaria/plugins/bloc/plugin_system_event.dart';
import 'package:otzaria/plugins/bloc/plugin_system_state.dart';
import 'package:otzaria/plugins/models/installed_plugin.dart';
import 'package:otzaria/plugins/models/plugin_manifest.dart';
import 'package:otzaria/plugins/models/plugin_permission_grant.dart';
import 'package:otzaria/plugins/repository/plugin_registry_repository.dart';

InstalledPlugin _plugin(String id) => InstalledPlugin(
  pluginId: id,
  name: id,
  version: '1.0.0',
  installPath: '/plugins/$id',
  entrypointPath: 'index.html',
  enabled: true,
  pinned: true,
  manifest: PluginManifest.fromJson({
    'schemaVersion': 1,
    'id': id,
    'name': id,
    'version': '1.0.0',
    'entrypoint': 'index.html',
    'contributes': {
      'toolTab': {'title': id},
    },
  }),
  installedAt: DateTime.utc(2026, 1, 1),
  updatedAt: DateTime.utc(2026, 1, 1),
);

class _CountingRepo implements PluginRegistryRepository {
  List<InstalledPlugin> plugins;
  int fullReads = 0;

  _CountingRepo(this.plugins);

  @override
  Future<List<InstalledPlugin>> getAllPlugins() async {
    fullReads++;
    return List.of(plugins);
  }

  @override
  Future<List<InstalledPlugin>> getDevelopmentPlugins() async => [];

  @override
  Future<void> updateShowInTools(String pluginId, bool showInTools) async {
    plugins = [
      for (final p in plugins)
        p.pluginId == pluginId ? p.copyWith(showInTools: showInTools) : p,
    ];
  }

  @override
  Future<List<String>> getGrantedPermissionNames(String id) async => [];

  @override
  Future<List<PluginPermissionGrant>> getPluginPermissions(String id) async =>
      [];

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  // issue #3688: פעולה גורפת בניהול הכלים שולחת אירוע לכל תוסף, וכל אירוע
  // ביקש טעינה מלאה — N טעינות של N תוספים ברצף אחד על ה-UI.
  test('פעולה גורפת על N תוספים אינה מריצה N טעינות מלאות', () async {
    const count = 40;
    final repo = _CountingRepo([
      for (var i = 0; i < count; i++) _plugin('p$i'),
    ]);
    final bloc = PluginSystemBloc(repository: repo);
    addTearDown(bloc.close);

    bloc.add(LoadPlugins());
    await expectLater(bloc.stream, emitsThrough(isA<PluginSystemLoaded>()));
    await pumpEventQueue();
    repo.fullReads = 0;

    for (final p in repo.plugins) {
      bloc.add(
        SetPluginShowInToolsRequested(pluginId: p.pluginId, showInTools: false),
      );
    }
    await pumpEventQueue(times: 200);

    expect(repo.fullReads, lessThanOrEqualTo(2));
    final state = bloc.state;
    expect(state, isA<PluginSystemLoaded>());
    expect(
      (state as PluginSystemLoaded).plugins.where((p) => p.showInTools),
      isEmpty,
      reason: 'הטעינה האחרונה חייבת לראות את כל הכתיבות',
    );
  });
}
