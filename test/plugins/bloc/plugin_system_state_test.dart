import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/bloc/plugin_system_state.dart';
import 'package:otzaria/plugins/models/installed_plugin.dart';
import 'package:otzaria/plugins/models/plugin_manifest.dart';

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
  required bool enabled,
  required bool pinned,
  required bool pinnedToNavRail,
  bool showInTools = true,
}) {
  return InstalledPlugin(
    pluginId: id,
    name: id,
    version: '1.0.0',
    installPath: '/x/$id',
    entrypointPath: 'index.html',
    enabled: enabled,
    pinned: pinned,
    pinnedToNavRail: pinnedToNavRail,
    showInTools: showInTools,
    manifest: _manifest(id),
    installedAt: DateTime.utc(2026, 1, 1),
    updatedAt: DateTime.utc(2026, 1, 1),
  );
}

void main() {
  group('PluginSystemLoaded.pluginsPinnedToNavRail', () {
    test('returns empty list when there are no plugins', () {
      const state = PluginSystemLoaded([]);
      expect(state.pluginsPinnedToNavRail, isEmpty);
    });

    test('excludes disabled plugins even if pinnedToNavRail is true', () {
      final state = PluginSystemLoaded([
        _plugin(id: 'a', enabled: false, pinned: true, pinnedToNavRail: true),
      ]);
      expect(state.pluginsPinnedToNavRail, isEmpty);
    });

    test('excludes plugins where pinnedToNavRail is false', () {
      final state = PluginSystemLoaded([
        _plugin(id: 'a', enabled: true, pinned: true, pinnedToNavRail: false),
      ]);
      expect(state.pluginsPinnedToNavRail, isEmpty);
    });

    test('includes only enabled plugins with pinnedToNavRail = true', () {
      final state = PluginSystemLoaded([
        _plugin(
          id: 'enabled-pinned',
          enabled: true,
          pinned: false,
          pinnedToNavRail: true,
        ),
        _plugin(
          id: 'disabled-pinned',
          enabled: false,
          pinned: false,
          pinnedToNavRail: true,
        ),
        _plugin(
          id: 'enabled-not-pinned',
          enabled: true,
          pinned: true,
          pinnedToNavRail: false,
        ),
      ]);
      final ids = state.pluginsPinnedToNavRail.map((p) => p.pluginId).toList();
      expect(ids, ['enabled-pinned']);
    });

    test(
      'pinnedToNavRail=true excludes a plugin from pinnedPlugins even when '
      'it is also tab-pinned — no duplicate place in "כלים"',
      () {
        final state = PluginSystemLoaded([
          // מוצמד-ללשוניות-בלבד (pinned)
          _plugin(
            id: 'tabs-only',
            enabled: true,
            pinned: true,
            pinnedToNavRail: false,
          ),
          // מוצמד-לסרגל-ניווט-בלבד (pinnedToNavRail)
          _plugin(
            id: 'rail-only',
            enabled: true,
            pinned: false,
            pinnedToNavRail: true,
          ),
          // שניהם — מוצמד ללשוניות אך גם לסרגל: הסרגל "מנצח" ומונע כפילות
          _plugin(
            id: 'both',
            enabled: true,
            pinned: true,
            pinnedToNavRail: true,
          ),
        ]);

        expect(
          state.pinnedPlugins.map((p) => p.pluginId),
          equals(['tabs-only']),
          reason:
              'תוסף שהוצמד לסרגל הניווט לא אמור לתפוס גם לשונית במסך כלים, '
              'גם אם הוא מסומן pinned',
        );

        expect(
          state.pluginsPinnedToNavRail.map((p) => p.pluginId),
          containsAll(['rail-only', 'both']),
        );
        expect(
          state.pluginsPinnedToNavRail.map((p) => p.pluginId),
          isNot(contains('tabs-only')),
        );
      },
    );

    test(
      'showInTools=false excludes plugin from pinnedPlugins but NOT from nav rail',
      () {
        final state = PluginSystemLoaded([
          _plugin(
            id: 'hidden-from-tools',
            enabled: true,
            pinned: true,
            pinnedToNavRail: false,
            showInTools: false,
          ),
          _plugin(
            id: 'visible',
            enabled: true,
            pinned: true,
            pinnedToNavRail: false,
          ),
        ]);
        expect(
          state.pinnedPlugins.map((p) => p.pluginId),
          equals(['visible']),
          reason:
              'plugin with showInTools=false must not appear as tools-tab tab',
        );
      },
    );
  });
}
