import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/bloc/plugin_system_bloc.dart';
import 'package:otzaria/plugins/bloc/plugin_system_event.dart';
import 'package:otzaria/plugins/bloc/plugin_system_state.dart';
import 'package:otzaria/plugins/models/installed_plugin.dart';
import 'package:otzaria/plugins/models/plugin_manifest.dart';
import 'package:otzaria/plugins/models/plugin_permission_grant.dart';
import 'package:otzaria/plugins/repository/plugin_registry_repository.dart';

PluginManifest _manifest(String id) {
  return PluginManifest.fromJson({
    'schemaVersion': 1,
    'id': id,
    'name': id,
    'version': '1.0.0',
    'entrypoint': 'index.html',
    'contributes': {
      'toolTab': {'title': id},
    },
  });
}

InstalledPlugin _plugin({
  required String id,
  bool showInTools = true,
}) {
  return InstalledPlugin(
    pluginId: id,
    name: id,
    version: '1.0.0',
    installPath: '/x/$id',
    entrypointPath: 'index.html',
    enabled: true,
    pinned: true,
    showInTools: showInTools,
    manifest: _manifest(id),
    installedAt: DateTime.utc(2026, 1, 1),
    updatedAt: DateTime.utc(2026, 1, 1),
  );
}

/// Fake repo: tracks showInTools writes and simulates them in subsequent reads.
class _FakeRepo implements PluginRegistryRepository {
  List<InstalledPlugin> plugins;
  final List<({String pluginId, bool showInTools})> showInToolsCalls = [];

  _FakeRepo(this.plugins);

  @override
  Future<void> updateShowInTools(String pluginId, bool showInTools) async {
    showInToolsCalls.add((pluginId: pluginId, showInTools: showInTools));
    plugins = plugins
        .map(
          (p) =>
              p.pluginId == pluginId ? p.copyWith(showInTools: showInTools) : p,
        )
        .toList();
  }

  @override
  Future<List<InstalledPlugin>> getAllPlugins() async => List.of(plugins);

  @override
  Future<List<InstalledPlugin>> getDevelopmentPlugins() async => [];

  @override
  Future<InstalledPlugin?> getPlugin(String id) async => null;

  @override
  Future<List<PluginPermissionGrant>> getPluginPermissions(String id) async =>
      [];

  @override
  Future<bool?> getPermission(String id, String perm) async => null;

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  group('PluginSystemBloc SetPluginShowInToolsRequested handler', () {
    test(
      'forwards (pluginId, false) to repository.updateShowInTools',
      () async {
        final repo = _FakeRepo([_plugin(id: 'p1'), _plugin(id: 'p2')]);
        final bloc = PluginSystemBloc(repository: repo);
        addTearDown(bloc.close);

        bloc.add(
          const SetPluginShowInToolsRequested(
            pluginId: 'p1',
            showInTools: false,
          ),
        );

        await expectLater(bloc.stream, emitsThrough(isA<PluginSystemLoaded>()));

        expect(repo.showInToolsCalls, hasLength(1));
        expect(repo.showInToolsCalls.single.pluginId, 'p1');
        expect(repo.showInToolsCalls.single.showInTools, isFalse);
      },
    );

    test('forwards (pluginId, true) — the "show again" direction', () async {
      final repo = _FakeRepo([_plugin(id: 'p1', showInTools: false)]);
      final bloc = PluginSystemBloc(repository: repo);
      addTearDown(bloc.close);

      bloc.add(
        const SetPluginShowInToolsRequested(
          pluginId: 'p1',
          showInTools: true,
        ),
      );

      await expectLater(bloc.stream, emitsThrough(isA<PluginSystemLoaded>()));

      expect(repo.showInToolsCalls.single.showInTools, isTrue);
    });

    test('after the event, the next PluginSystemLoaded reflects showInTools '
        'in the pinnedPlugins getter', () async {
      final repo = _FakeRepo([
        _plugin(id: 'visible'),
        _plugin(id: 'will-hide'),
      ]);
      final bloc = PluginSystemBloc(repository: repo);
      addTearDown(bloc.close);

      bloc.add(
        const SetPluginShowInToolsRequested(
          pluginId: 'will-hide',
          showInTools: false,
        ),
      );

      PluginSystemLoaded? lastLoaded;
      await for (final s in bloc.stream) {
        if (s is PluginSystemLoaded) {
          lastLoaded = s;
          if (!s.plugins.any(
            (p) => p.pluginId == 'will-hide' && p.showInTools,
          )) {
            break;
          }
        }
      }

      expect(lastLoaded, isNotNull);
      expect(
        lastLoaded!.pinnedPlugins.map((p) => p.pluginId),
        equals(['visible']),
        reason: 'plugin not shown in tools must drop out of pinnedPlugins',
      );
    });

    test(
      'toggling the same plugin twice writes both directions in order',
      () async {
        final repo = _FakeRepo([_plugin(id: 'p1')]);
        final bloc = PluginSystemBloc(repository: repo);
        addTearDown(bloc.close);

        bloc.add(
          const SetPluginShowInToolsRequested(
            pluginId: 'p1',
            showInTools: false,
          ),
        );
        bloc.add(
          const SetPluginShowInToolsRequested(
            pluginId: 'p1',
            showInTools: true,
          ),
        );

        await Future.delayed(const Duration(milliseconds: 50));

        expect(repo.showInToolsCalls.length, 2);
        expect(repo.showInToolsCalls[0].showInTools, isFalse);
        expect(repo.showInToolsCalls[1].showInTools, isTrue);
      },
    );
  });
}
