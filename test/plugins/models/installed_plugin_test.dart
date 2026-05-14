import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/models/installed_plugin.dart';
import 'package:otzaria/plugins/models/plugin_manifest.dart';

PluginManifest _manifest({String id = 'test.plugin'}) {
  return PluginManifest.fromJson({
    'schemaVersion': 1,
    'id': id,
    'name': 'Test',
    'version': '1.0.0',
    'entrypoint': 'index.html',
    'contributes': {
      'toolTab': {'title': 'T'},
    },
  });
}

InstalledPlugin _plugin({
  bool enabled = true,
  bool pinned = true,
  bool pinnedToNavRail = false,
}) {
  return InstalledPlugin(
    pluginId: 'test.plugin',
    name: 'Test',
    version: '1.0.0',
    installPath: '/tmp/test',
    entrypointPath: 'index.html',
    enabled: enabled,
    pinned: pinned,
    pinnedToNavRail: pinnedToNavRail,
    manifest: _manifest(),
    installedAt: DateTime.utc(2026, 5, 10, 12, 0),
    updatedAt: DateTime.utc(2026, 5, 10, 12, 0),
  );
}

void main() {
  group('InstalledPlugin', () {
    test('default value of pinnedToNavRail is false', () {
      final plugin = InstalledPlugin(
        pluginId: 'p',
        name: 'p',
        version: '1.0.0',
        installPath: '/x',
        entrypointPath: 'i.html',
        enabled: true,
        pinned: true,
        // pinnedToNavRail intentionally omitted
        manifest: _manifest(),
        installedAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 1),
      );
      expect(plugin.pinnedToNavRail, isFalse);
    });

    test('toDbMap serializes pinnedToNavRail as 0/1', () {
      expect(
          _plugin(pinnedToNavRail: false).toDbMap()['pinned_to_nav_rail'], 0);
      expect(
          _plugin(pinnedToNavRail: true).toDbMap()['pinned_to_nav_rail'], 1);
    });

    test('fromDbMap reads pinned_to_nav_rail = 1 as true', () {
      final original = _plugin(pinnedToNavRail: true);
      final restored = InstalledPlugin.fromDbMap(original.toDbMap());
      expect(restored.pinnedToNavRail, isTrue);
    });

    test('fromDbMap reads pinned_to_nav_rail = 0 as false', () {
      final original = _plugin(pinnedToNavRail: false);
      final restored = InstalledPlugin.fromDbMap(original.toDbMap());
      expect(restored.pinnedToNavRail, isFalse);
    });

    test(
        'fromDbMap defaults pinnedToNavRail to false when column is absent '
        '(legacy DB before migration)', () {
      // מדמה רשומה משורת DB ישנה לפני שהמיגרציה רצה — אין כלל מפתח כזה.
      final legacyMap = _plugin(pinnedToNavRail: true).toDbMap();
      legacyMap.remove('pinned_to_nav_rail');
      final restored = InstalledPlugin.fromDbMap(legacyMap);
      expect(restored.pinnedToNavRail, isFalse,
          reason: 'A pre-migration row must not crash and must default to false');
    });

    test('round-trip toDbMap → fromDbMap preserves both pin flags', () {
      final original = _plugin(pinned: true, pinnedToNavRail: true);
      final restored = InstalledPlugin.fromDbMap(original.toDbMap());
      expect(restored.pinned, isTrue);
      expect(restored.pinnedToNavRail, isTrue);
    });

    test('round-trip preserves the two flags independently', () {
      // pinned=false, navRail=true
      final a = _plugin(pinned: false, pinnedToNavRail: true);
      final restoredA = InstalledPlugin.fromDbMap(a.toDbMap());
      expect(restoredA.pinned, isFalse);
      expect(restoredA.pinnedToNavRail, isTrue);

      // pinned=true, navRail=false
      final b = _plugin(pinned: true, pinnedToNavRail: false);
      final restoredB = InstalledPlugin.fromDbMap(b.toDbMap());
      expect(restoredB.pinned, isTrue);
      expect(restoredB.pinnedToNavRail, isFalse);
    });

    test('copyWith updates pinnedToNavRail without touching pinned', () {
      final original = _plugin(pinned: true, pinnedToNavRail: false);
      final updated = original.copyWith(pinnedToNavRail: true);
      expect(updated.pinned, isTrue, reason: 'pinned must be unchanged');
      expect(updated.pinnedToNavRail, isTrue);
    });

    test('copyWith without pinnedToNavRail preserves the existing value', () {
      final original = _plugin(pinnedToNavRail: true);
      final updated = original.copyWith(pinned: false);
      expect(updated.pinnedToNavRail, isTrue,
          reason: 'omitted parameter should keep current value');
      expect(updated.pinned, isFalse);
    });
  });
}
