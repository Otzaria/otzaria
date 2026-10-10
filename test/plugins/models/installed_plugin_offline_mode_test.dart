import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/models/installed_plugin.dart';
import 'package:otzaria/plugins/models/plugin_manifest.dart';

PluginManifest _manifestFor({
  required String id,
  required String name,
  bool networkEnabled = false,
}) {
  return PluginManifest(
    schemaVersion: 1,
    id: id,
    name: name,
    version: '1.0.0',
    description: 'test',
    author: 'tester',
    homepage: '',
    entrypoint: 'index.html',
    minAppVersion: '1.0.0',
    sdkVersion: '1.x',
    permissions: const [],
    networkEnabled: networkEnabled,
    networkAllowlist: const [],
    toolTabTitle: name,
    toolTabOrder: 100,
    defaultPinned: true,
    publishedDataTypes: const [],
  );
}

InstalledPlugin _pluginFor({
  required String id,
  required String name,
  bool networkEnabled = false,
  bool networkAccessGranted = false,
}) {
  return InstalledPlugin(
    pluginId: id,
    name: name,
    version: '1.0.0',
    installPath: '/tmp/$id',
    entrypointPath: '/tmp/$id/index.html',
    enabled: true,
    pinned: true,
    networkAccessGranted: networkAccessGranted,
    manifest: _manifestFor(
      id: id,
      name: name,
      networkEnabled: networkEnabled,
    ),
    installedAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
  );
}

void main() {
  group('OfflineModePluginFilter extension', () {
    test('במצב מקוון מחזיר את הרשימה ללא שינוי', () {
      final plugins = [
        _pluginFor(id: 'a', name: 'A'),
        _pluginFor(id: 'b', name: 'B', networkEnabled: true),
      ];
      expect(plugins.filterForOfflineMode(false), equals(plugins));
    });

    test('במצב מנותק מסנן רק תוספי רשת שהרשאתם הוענקה בפועל', () {
      final local = _pluginFor(id: 'a', name: 'A');
      final cloud = _pluginFor(
        id: 'b',
        name: 'B',
        networkEnabled: true,
        networkAccessGranted: true,
      );
      final filtered = [local, cloud].filterForOfflineMode(true);
      expect(filtered, [local]);
    });

    test('במצב מנותק תוסף רשת ללא הרשאת רשת מוענקת אינו מסונן', () {
      final local = _pluginFor(id: 'a', name: 'A');
      final cloudRevoked = _pluginFor(
        id: 'b',
        name: 'B',
        networkEnabled: true,
        networkAccessGranted: false,
      );
      final filtered = [local, cloudRevoked].filterForOfflineMode(true);
      expect(filtered, [local, cloudRevoked]);
    });

    test('רשימה ריקה מוחזרת כרשימה ריקה', () {
      expect(<InstalledPlugin>[].filterForOfflineMode(true), isEmpty);
      expect(<InstalledPlugin>[].filterForOfflineMode(false), isEmpty);
    });
  });

  group('InstalledPlugin.requiresNetwork', () {
    test('מחזיר true כאשר manifest.networkEnabled=true', () {
      final plugin = _pluginFor(id: 'a', name: 'A', networkEnabled: true);
      expect(plugin.requiresNetwork, isTrue);
    });

    test('מחזיר false כאשר manifest.networkEnabled=false', () {
      final plugin = _pluginFor(id: 'a', name: 'A');
      expect(plugin.requiresNetwork, isFalse);
    });
  });

  group('InstalledPlugin.blockedInOfflineMode', () {
    test('true כשהתוסף דורש רשת והרשאתו הוענקה', () {
      final plugin = _pluginFor(
        id: 'a',
        name: 'A',
        networkEnabled: true,
        networkAccessGranted: true,
      );
      expect(plugin.blockedInOfflineMode, isTrue);
    });

    test('false כשהתוסף דורש רשת אך הרשאתו כובתה — חייב להיפתח במנותק', () {
      final plugin = _pluginFor(
        id: 'a',
        name: 'A',
        networkEnabled: true,
        networkAccessGranted: false,
      );
      expect(plugin.blockedInOfflineMode, isFalse);
    });

    test('false כשהתוסף אינו דורש רשת כלל', () {
      final plugin = _pluginFor(id: 'a', name: 'A');
      expect(plugin.blockedInOfflineMode, isFalse);
    });
  });
}
