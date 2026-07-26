import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/models/installed_plugin.dart';
import 'package:otzaria/plugins/models/plugin_manifest.dart';
import 'package:otzaria/tools/tools_screen.dart';

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
  bool networkEnabled = false,
  bool networkAccessGranted = false,
  bool showInTools = true,
  bool pinnedToNavRail = false,
}) {
  return InstalledPlugin(
    pluginId: id,
    name: id,
    version: '1.0.0',
    installPath: '/tmp/$id',
    entrypointPath: '/tmp/$id/index.html',
    enabled: true,
    pinned: true,
    showInTools: showInTools,
    pinnedToNavRail: pinnedToNavRail,
    networkAccessGranted: networkAccessGranted,
    manifest: _manifestFor(id: id, name: id, networkEnabled: networkEnabled),
    installedAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
  );
}

void main() {
  group('pendingNavRailPluginToOpen', () {
    tearDown(() => pendingNavRailPluginToOpen = null);

    test('ברירת המחדל ריקה — כניסה רגילה לכלים לא פותחת תוסף', () {
      expect(pendingNavRailPluginToOpen, isNull);
    });

    test('נשמר עד שמסך הכלים ייבנה ויצרוך אותו', () {
      final plugin = _pluginFor(id: 'a', pinnedToNavRail: true);
      pendingNavRailPluginToOpen = plugin;
      expect(pendingNavRailPluginToOpen, same(plugin));
    });

  });

  group('shouldHideToolsTabBar', () {
    test('מוצג במצב רגיל', () {
      expect(
        shouldHideToolsTabBar(
          isImmersive: false,
          hiddenNavRailPluginId: null,
          selectedToolId: 'builtin.calendar',
        ),
        isFalse,
      );
    });

    test('מוסתר במסך מלא', () {
      expect(
        shouldHideToolsTabBar(
          isImmersive: true,
          hiddenNavRailPluginId: null,
          selectedToolId: 'builtin.calendar',
        ),
        isTrue,
      );
    });

    test('מוסתר כשמוצג תוסף שהוצמד לסרגל הניווט', () {
      expect(
        shouldHideToolsTabBar(
          isImmersive: false,
          hiddenNavRailPluginId: 'a',
          selectedToolId: 'a',
        ),
        isTrue,
      );
    });

    test('מוצג כשהתוסף המוצמד פתוח אך נבחר כלי אחר', () {
      expect(
        shouldHideToolsTabBar(
          isImmersive: false,
          hiddenNavRailPluginId: 'a',
          selectedToolId: 'builtin.calendar',
        ),
        isFalse,
      );
    });
  });

  group('resolveToolsTitlePluginName', () {
    test('אין כלי פעיל — כותרת רגילה', () {
      expect(
        resolveToolsTitlePluginName(
          activeToolId: null,
          plugins: [_pluginFor(id: 'a', pinnedToNavRail: true)],
        ),
        isNull,
      );
    });

    test('כלי מובנה — כותרת רגילה', () {
      expect(
        resolveToolsTitlePluginName(
          activeToolId: 'builtin.calendar',
          plugins: [_pluginFor(id: 'a', pinnedToNavRail: true)],
        ),
        isNull,
      );
    });

    test('תוסף עם לשונית — כותרת רגילה', () {
      expect(
        resolveToolsTitlePluginName(
          activeToolId: 'a',
          plugins: [_pluginFor(id: 'a')],
        ),
        isNull,
      );
    });

    test('תוסף מוצמד לסרגל הניווט — שם התוסף', () {
      expect(
        resolveToolsTitlePluginName(
          activeToolId: 'a',
          plugins: [_pluginFor(id: 'a', pinnedToNavRail: true)],
        ),
        'a',
      );
    });

    test('תוסף שאינו מוצג בכלים — שם התוסף', () {
      expect(
        resolveToolsTitlePluginName(
          activeToolId: 'a',
          plugins: [_pluginFor(id: 'a', showInTools: false)],
        ),
        'a',
      );
    });

    test('תוסף שאינו ברשימה — כותרת רגילה', () {
      expect(
        resolveToolsTitlePluginName(
          activeToolId: 'a',
          plugins: [_pluginFor(id: 'b', pinnedToNavRail: true)],
        ),
        isNull,
      );
    });
  });

  group('resolveTransientAfterPluginsLoaded', () {
    test('transient ריק נשאר ריק', () {
      expect(
        resolveTransientAfterPluginsLoaded(null, [
          _pluginFor(id: 'a'),
        ], isOfflineMode: true),
        isNull,
      );
    });

    test('מחזיר את הגרסה המעודכנת מהרשימה', () {
      final old = _pluginFor(id: 'a');
      final updated = _pluginFor(id: 'a', pinnedToNavRail: true);
      final result = resolveTransientAfterPluginsLoaded(old, [
        updated,
      ], isOfflineMode: false);
      expect(identical(result, updated), isTrue);
    });

    test('נסגר כשהתוסף הוסר גם מהכלים וגם מסרגל הניווט', () {
      final old = _pluginFor(id: 'a');
      final updated = _pluginFor(
        id: 'a',
        showInTools: false,
        pinnedToNavRail: false,
      );
      expect(
        resolveTransientAfterPluginsLoaded(old, [
          updated,
        ], isOfflineMode: false),
        isNull,
      );
    });

    test('רגרסיה: הענקת הרשאת רשת בזמן מצב מנותק סוגרת את התוסף', () {
      final openWithoutGrant = _pluginFor(
        id: 'a',
        networkEnabled: true,
        networkAccessGranted: false,
      );
      final grantedNow = _pluginFor(
        id: 'a',
        networkEnabled: true,
        networkAccessGranted: true,
      );
      expect(
        resolveTransientAfterPluginsLoaded(openWithoutGrant, [
          grantedNow,
        ], isOfflineMode: true),
        isNull,
      );
    });

    test('במצב מנותק תוסף רשת שהרשאתו כבויה נשאר פתוח', () {
      final plugin = _pluginFor(
        id: 'a',
        networkEnabled: true,
        networkAccessGranted: false,
      );
      expect(
        resolveTransientAfterPluginsLoaded(plugin, [
          plugin,
        ], isOfflineMode: true),
        same(plugin),
      );
    });

    test('במצב מקוון תוסף רשת עם הרשאה נשאר פתוח', () {
      final plugin = _pluginFor(
        id: 'a',
        networkEnabled: true,
        networkAccessGranted: true,
      );
      expect(
        resolveTransientAfterPluginsLoaded(plugin, [
          plugin,
        ], isOfflineMode: false),
        same(plugin),
      );
    });

    test(
      'תוסף שאינו ברשימה המעודכנת נשמר כפי שהוא, וגם עליו חל תנאי החסימה',
      () {
        final keep = _pluginFor(id: 'a');
        expect(
          resolveTransientAfterPluginsLoaded(keep, [
            _pluginFor(id: 'b'),
          ], isOfflineMode: true),
          same(keep),
        );

        final blocked = _pluginFor(
          id: 'a',
          networkEnabled: true,
          networkAccessGranted: true,
        );
        expect(
          resolveTransientAfterPluginsLoaded(blocked, [
            _pluginFor(id: 'b'),
          ], isOfflineMode: true),
          isNull,
        );
      },
    );
  });
}
