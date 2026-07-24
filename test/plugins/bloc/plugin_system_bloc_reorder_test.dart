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
  int? userOrder,
}) {
  return InstalledPlugin(
    pluginId: id,
    name: id,
    version: '1.0.0',
    installPath: '/x/$id',
    entrypointPath: 'index.html',
    enabled: true,
    pinned: true,
    manifest: _manifest(id),
    installedAt: DateTime.utc(2026, 1, 1),
    updatedAt: DateTime.utc(2026, 1, 1),
    userOrder: userOrder,
  );
}

class _FakeRepo implements PluginRegistryRepository {
  List<InstalledPlugin> plugins;
  final List<List<String>> reorderCalls = [];

  _FakeRepo(this.plugins);

  @override
  Future<void> reorderPlugins(List<String> orderedPluginIds) async {
    reorderCalls.add(List.of(orderedPluginIds));
    // נדמה את התוצאה ב-DB: נעדכן userOrder לפי הסדר שהתקבל ונבנה את
    // ה-plugins מחדש כדי ש-getAllPlugins הבא יחזיר את הסדר החדש.
    final byId = {for (final p in plugins) p.pluginId: p};
    final reordered = <InstalledPlugin>[];
    for (var i = 0; i < orderedPluginIds.length; i++) {
      final p = byId[orderedPluginIds[i]];
      if (p == null) continue;
      reordered.add(p.copyWith(userOrder: i));
    }
    // תוספים שלא ברשימה — נשמרים כמו שהם בסוף.
    final remaining = plugins
        .where((p) => !orderedPluginIds.contains(p.pluginId))
        .toList();
    plugins = [...reordered, ...remaining];
  }

  @override
  Future<List<InstalledPlugin>> getAllPlugins() async {
    final sorted = List.of(plugins);
    sorted.sort(
      (a, b) => a.effectiveToolTabOrder.compareTo(b.effectiveToolTabOrder),
    );
    return sorted;
  }

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
  group('PluginSystemBloc ReorderPluginsRequested handler', () {
    test('forwards the ordered ids to repository.reorderPlugins', () async {
      final repo = _FakeRepo([
        _plugin(id: 'a'),
        _plugin(id: 'b'),
        _plugin(id: 'c'),
      ]);
      final bloc = PluginSystemBloc(repository: repo);
      addTearDown(bloc.close);

      // יצרן עם רשימת states שיופצו אחרי ה-event, עד ל-Loaded הסופי.
      final emitted = <PluginSystemState>[];
      final sub = bloc.stream.listen(emitted.add);
      addTearDown(sub.cancel);

      bloc.add(const ReorderPluginsRequested(['c', 'a', 'b']));

      // מחכים לעדכון ה-Bloc — Loaded יופץ אחרי LoadPlugins הפנימי.
      await expectLater(bloc.stream, emitsThrough(isA<PluginSystemLoaded>()));

      expect(repo.reorderCalls, hasLength(1));
      expect(repo.reorderCalls.single, ['c', 'a', 'b']);
    });

    test('after the reorder, PluginSystemLoaded reflects the new order via '
        'pinnedPlugins', () async {
      final repo = _FakeRepo([
        _plugin(id: 'a'),
        _plugin(id: 'b'),
        _plugin(id: 'c'),
      ]);
      final bloc = PluginSystemBloc(repository: repo);
      addTearDown(bloc.close);

      bloc.add(const ReorderPluginsRequested(['c', 'a', 'b']));

      // ממתינים ל-Loaded final.
      final loaded =
          await bloc.stream.firstWhere((s) => s is PluginSystemLoaded)
              as PluginSystemLoaded;

      expect(loaded.pinnedPlugins.map((p) => p.pluginId).toList(), [
        'c',
        'a',
        'b',
      ]);
    });

    test('an empty ordered list does not crash the bloc and still triggers '
        'a load cycle', () async {
      final repo = _FakeRepo([_plugin(id: 'a')]);
      final bloc = PluginSystemBloc(repository: repo);
      addTearDown(bloc.close);

      bloc.add(const ReorderPluginsRequested([]));

      await expectLater(bloc.stream, emitsThrough(isA<PluginSystemLoaded>()));

      expect(repo.reorderCalls.single, isEmpty);
    });
  });
}
