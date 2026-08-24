import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/services/plugin_store_link_parser.dart';
import 'package:otzaria/plugins/bridge/plugin_bridge_adapter.dart';
import 'package:otzaria/plugins/bridge/plugin_bridge_handler.dart';
import 'package:otzaria/plugins/models/installed_plugin.dart';
import 'package:otzaria/plugins/models/plugin_manifest.dart';
import 'package:otzaria/plugins/repository/plugin_registry_repository.dart';
import 'package:otzaria/plugins/services/plugin_extended_validator.dart';

class _FakeAdapter implements PluginBridgeAdapter {
  int executeCalls = 0;

  @override
  Future<dynamic> execute(
    String domain,
    String action,
    Map<String, dynamic> args, {
    PluginRpcEventSink? eventSink,
  }) async {
    executeCalls++;
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _GrantAllRegistry extends PluginRegistryRepository {
  @override
  Future<bool?> getPermission(String pluginId, String permission) async => true;
}

InstalledPlugin _plugin(List<String> permissions) => InstalledPlugin(
  pluginId: 'test.plugin',
  name: 'Test Plugin',
  version: '1.0.0',
  installPath: '/',
  entrypointPath: 'index.html',
  enabled: true,
  pinned: true,
  manifest: PluginManifest(
    schemaVersion: 1,
    id: 'test.plugin',
    name: 'Test Plugin',
    version: '1.0.0',
    description: '',
    author: '',
    homepage: '',
    entrypoint: 'index.html',
    minAppVersion: '1.0.0',
    sdkVersion: '1.x',
    permissions: permissions,
    networkEnabled: false,
    networkAllowlist: const [],
    toolTabTitle: 'Test Plugin',
    toolTabOrder: 1,
    defaultPinned: true,
    publishedDataTypes: const [],
  ),
  installedAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

void main() {
  _storeOriginGuardTests();
  group('טבלת ההרשאות של הגשר', () {
    const table = PluginBridgeHandler.methodPermissions;

    test('לכל method מוכר יש רישום מפורש בטבלה', () {
      final missing =
          PluginExtendedValidator.knownApiMethods
              .where((m) => !table.containsKey(m))
              .toList()
            ..sort();
      expect(
        missing,
        isEmpty,
        reason:
            'methods ללא רישום ב-methodPermissions: $missing. חסר רישום '
            'מפורש (הרשאה או noManifestPermission).',
      );
    });

    test('הטבלה תואמת את מפת ההרשאות של הוולידטור', () {
      final validator = PluginExtendedValidator.methodRequiredPermissions;
      final mismatched = <String>[];
      for (final entry in validator.entries) {
        // network.* נאכפת באדפטר לפי היעד, ולכן היא noManifestPermission בגשר.
        if (entry.key.startsWith('network.')) continue;
        if (table[entry.key] != entry.value) mismatched.add(entry.key);
      }
      expect(mismatched, isEmpty);
    });

    test('כל ערך בטבלה הוא הרשאה מוכרת או הסמן המפורש', () {
      for (final entry in table.entries) {
        expect(
          entry.value.isNotEmpty,
          isTrue,
          reason: 'רישום ריק עבור ${entry.key}',
        );
      }
      expect(
        table['fs.extractZip'],
        PluginBridgeHandler.noManifestPermission,
      );
      expect(table['fs.deleteFile'], PluginBridgeHandler.noManifestPermission);
      expect(
        table['feedback.report'],
        PluginBridgeHandler.noManifestPermission,
      );
      expect(
        table['feedback.hasReporterEmail'],
        PluginBridgeHandler.noManifestPermission,
      );
      // המרחב הפרטי: השורש הוא הגבול, ולכן אין הרשאת manifest — אבל הרישום
      // חייב להיות מפורש, אחרת הטבלה fail-closed הופכת אותו לבלתי-נגיש.
      for (final method in const [
        'fs.writeFile',
        'fs.readFile',
        'fs.listDir',
        'fs.makeDir',
        'fs.deleteEntry',
        'fs.stat',
      ]) {
        expect(
          table[method],
          PluginBridgeHandler.noManifestPermission,
          reason: method,
        );
      }
      expect(table['plugin.listInstalled'], 'app.info.read');
      expect(table['plugin.requestInstall'], 'app.info.read');
    });

    test('method שאינו בטבלה נדחה ב-error.unknown_method', () async {
      final adapter = _FakeAdapter();
      final handler = PluginBridgeHandler(
        _plugin(const []),
        adapter: adapter,
        registry: _GrantAllRegistry(),
      );

      final response =
          await handler.handleRpcForTesting([
                {'method': 'fs.writeAnything', 'payload': const {}},
              ])
              as Map;

      expect(response['success'], isFalse);
      expect(response['error']['code'], 'error.unknown_method');
      expect(adapter.executeCalls, 0);
    });
  });

  group('nonce של הגשר', () {
    test('קריאה ללא nonce נדחית ב-error.forbidden', () async {
      final adapter = _FakeAdapter();
      final handler = PluginBridgeHandler(
        _plugin(const []),
        adapter: adapter,
        registry: _GrantAllRegistry(),
      );

      final response =
          await handler.handleRpcForTesting([
                {'method': 'app.getInfo', 'payload': const {}},
              ], nonce: '')
              as Map;

      expect(response['error']['code'], 'error.forbidden');
      expect(adapter.executeCalls, 0);
    });

    test('nonce שגוי נדחה גם כשההרשאה קיימת', () async {
      final adapter = _FakeAdapter();
      final handler = PluginBridgeHandler(
        _plugin(const []),
        adapter: adapter,
        registry: _GrantAllRegistry(),
      );

      final response =
          await handler.handleRpcForTesting([
                {'method': 'app.getInfo', 'payload': const {}},
              ], nonce: 'deadbeef')
              as Map;

      expect(response['error']['code'], 'error.forbidden');
      expect(adapter.executeCalls, 0);
    });

    test('nonce תקין מעביר את הקריאה ל-adapter', () async {
      final adapter = _FakeAdapter();
      final handler = PluginBridgeHandler(
        _plugin(const []),
        adapter: adapter,
        registry: _GrantAllRegistry(),
      );

      final response =
          await handler.handleRpcForTesting([
                {'method': 'app.getInfo', 'payload': const {}},
              ])
              as Map;

      expect(response['success'], isTrue);
      expect(adapter.executeCalls, 1);
    });

    test('לכל מופע גשר nonce משלו', () {
      final a = PluginBridgeHandler(
        _plugin(const []),
        adapter: _FakeAdapter(),
        registry: _GrantAllRegistry(),
      );
      final b = PluginBridgeHandler(
        _plugin(const []),
        adapter: _FakeAdapter(),
        registry: _GrantAllRegistry(),
      );
      expect(a.bridgeNonce, isNot(b.bridgeNonce));
      expect(a.bridgeNonce.length, 32);
    });
  });
}

void _storeOriginGuardTests() {
  group('plugin.requestInstall מוגבל למארחי החנות הרשמית', () {
    test('כתובת החנות מתקבלת', () {
      expect(
        PluginStoreLinkParser.isStoreDownloadUri(
          Uri.parse('https://otzaria.org/api/plugins/x/download'),
        ),
        isTrue,
      );
      expect(
        PluginStoreLinkParser.isStoreDownloadUri(
          Uri.parse('https://WWW.Otzaria.org/api/plugins/x/download'),
        ),
        isTrue,
      );
    });

    test('מארח זר נדחה — זהו ערוץ ההורדה שרץ לפני דיאלוג ההרשאות', () {
      for (final url in <String>[
        'https://evil.example.com/p.otzplugin',
        'https://otzaria.org.evil.com/p.otzplugin',
        'https://nototzaria.org/p.otzplugin',
        'file:///C:/p.otzplugin',
        'ftp://otzaria.org/p.otzplugin',
        // http פתוח ל-MITM, והמניפסט בדיאלוג ההרשאות מגיע מתוך הארכיון.
        'http://otzaria.org/api/plugins/x/download',
      ]) {
        expect(
          PluginStoreLinkParser.isStoreDownloadUri(Uri.parse(url)),
          isFalse,
          reason: url,
        );
      }
    });
  });
}
