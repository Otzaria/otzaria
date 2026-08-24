import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:otzaria/plugins/models/installed_plugin.dart';
import 'package:otzaria/plugins/models/plugin_manifest.dart';
import 'package:otzaria/plugins/services/plugin_update_check_service.dart';

InstalledPlugin buildPlugin({
  required String pluginId,
  String version = '1.0.0',
  String sourceType = 'packaged',
}) => InstalledPlugin(
  pluginId: pluginId,
  name: pluginId,
  version: version,
  installPath: '/plugins/$pluginId',
  entrypointPath: 'index.html',
  enabled: true,
  pinned: false,
  sourceType: sourceType,
  devRootPath: sourceType == 'development' ? '/dev/$pluginId' : null,
  manifest: PluginManifest(
    schemaVersion: 1,
    id: pluginId,
    name: pluginId,
    version: version,
    description: 'test',
    author: 'tester',
    homepage: '',
    entrypoint: 'index.html',
    minAppVersion: '1.0.0',
    sdkVersion: '1.x',
    permissions: const [],
    networkEnabled: false,
    networkAllowlist: const [],
    toolTabTitle: pluginId,
    toolTabOrder: 900,
    allowOrderBeforeBuiltIns: false,
    defaultPinned: false,
    publishedDataTypes: const [],
  ),
  installedAt: DateTime(2026, 1, 1),
  updatedAt: DateTime(2026, 1, 1),
);

void main() {
  group('eligiblePlugins', () {
    test('רק תוספי packaged נבדקים — תוספי פיתוח מוחרגים', () {
      final plugins = [
        buildPlugin(pluginId: 'org.a'),
        buildPlugin(pluginId: 'org.dev', sourceType: 'development'),
        buildPlugin(pluginId: 'org.local', sourceType: 'localhost_dev'),
      ];
      final eligible = PluginUpdateCheckService.eligiblePlugins(plugins);
      expect(eligible.map((p) => p.pluginId), ['org.a']);
    });
  });

  group('buildUpdatesUri', () {
    test('בונה כתובת batch עם uid@version לכל תוסף', () {
      final uri = PluginUpdateCheckService.buildUpdatesUri([
        buildPlugin(pluginId: 'org.a', version: '1.0.0'),
        buildPlugin(pluginId: 'org.b', version: '2.1.0'),
      ], appVersion: '0.9.97');
      expect(uri.host, 'otzaria.org');
      expect(uri.path, '/api/plugins/updates');
      expect(uri.queryParameters['appVersion'], '0.9.97');
      expect(uri.queryParameters['plugins'], 'org.a@1.0.0,org.b@2.1.0');
    });
  });

  group('parseUpdatesResponse', () {
    test('מחזירה רק תוספים עם hasUpdate, עם כתובת מוחלטת', () {
      final body = jsonEncode({
        'appVersion': '0.9.97',
        'updates': [
          {
            'uid': 'org.a',
            'hasUpdate': true,
            'version': '2.0.0',
            'downloadUrl': '/api/plugins/abc@2.0.0/download',
          },
          {'uid': 'org.b', 'hasUpdate': false, 'version': '1.0.0'},
        ],
      });
      final result = PluginUpdateCheckService.parseUpdatesResponse(body)!;
      expect(result.keys, ['org.a']);
      expect(result['org.a']!.version, '2.0.0');
      expect(
        result['org.a']!.downloadUrl,
        'https://otzaria.org/api/plugins/abc@2.0.0/download',
      );
    });

    test('גוף שאינו במבנה הצפוי → null', () {
      expect(PluginUpdateCheckService.parseUpdatesResponse('not json'), null);
      expect(PluginUpdateCheckService.parseUpdatesResponse('[]'), null);
      expect(PluginUpdateCheckService.parseUpdatesResponse('{}'), null);
    });

    test('רשומה פגומה מדולגת בלי להפיל את השאר', () {
      final body = jsonEncode({
        'updates': [
          {
            'uid': '',
            'hasUpdate': true,
            'version': '2.0.0',
            'downloadUrl': '/x',
          },
          {
            'uid': 'org.rel',
            'hasUpdate': true,
            'version': '2.0.0',
            'downloadUrl': 'http://evil/x',
          },
          {
            'uid': 'org.ok',
            'hasUpdate': true,
            'version': '2.0.0',
            'downloadUrl': '/dl',
          },
        ],
      });
      final result = PluginUpdateCheckService.parseUpdatesResponse(body)!;
      expect(result.keys, ['org.ok']);
    });
  });

  group('fetchUpdates', () {
    test('כשעדכונים חסומים (מצב מנותק) — אין קריאת רשת ומוחזר null', () async {
      var called = false;
      final service = PluginUpdateCheckService(
        client: MockClient((_) async {
          called = true;
          return http.Response('{}', 200);
        }),
        updatesAllowedReader: () => false,
      );
      final result = await service.fetchUpdates([
        buildPlugin(pluginId: 'org.a'),
      ], appVersion: '0.9.97');
      expect(result, null);
      expect(called, false);
    });

    test('ללא תוספי packaged — אין קריאת רשת ומוחזרת מפה ריקה', () async {
      var called = false;
      final service = PluginUpdateCheckService(
        client: MockClient((_) async {
          called = true;
          return http.Response('{}', 200);
        }),
        updatesAllowedReader: () => true,
      );
      final result = await service.fetchUpdates([
        buildPlugin(pluginId: 'org.dev', sourceType: 'development'),
      ], appVersion: '0.9.97');
      expect(result, const {});
      expect(called, false);
    });

    test('תשובת 200 תקינה מוחזרת מפורסרת', () async {
      final service = PluginUpdateCheckService(
        client: MockClient(
          (request) async => http.Response(
            jsonEncode({
              'updates': [
                {
                  'uid': 'org.a',
                  'hasUpdate': true,
                  'version': '2.0.0',
                  'downloadUrl': '/api/plugins/abc@2.0.0/download',
                },
              ],
            }),
            200,
          ),
        ),
        updatesAllowedReader: () => true,
      );
      final result = await service.fetchUpdates([
        buildPlugin(pluginId: 'org.a'),
      ], appVersion: '0.9.97');
      expect(result!['org.a']!.version, '2.0.0');
    });

    test('כשל שרת (503 של שבת, 500) → null בשקט', () async {
      for (final code in [500, 503, 429]) {
        final service = PluginUpdateCheckService(
          client: MockClient((_) async => http.Response('busy', code)),
          updatesAllowedReader: () => true,
        );
        final result = await service.fetchUpdates([
          buildPlugin(pluginId: 'org.a'),
        ], appVersion: '0.9.97');
        expect(result, null, reason: 'status $code');
      }
    });

    test('חריגת רשת → null בשקט', () async {
      final service = PluginUpdateCheckService(
        client: MockClient((_) async => throw Exception('no network')),
        updatesAllowedReader: () => true,
      );
      final result = await service.fetchUpdates([
        buildPlugin(pluginId: 'org.a'),
      ], appVersion: '0.9.97');
      expect(result, null);
    });
  });
}
