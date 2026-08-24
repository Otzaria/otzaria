import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:otzaria/plugins/services/plugin_download_service.dart';

void main() {
  group('PluginDownloadService.downloadPluginArchive', () {
    late List<Uri> requested;

    setUp(() => requested = []);

    PluginDownloadService serviceReturning(
      List<http.Response> responses,
    ) {
      var index = 0;
      return PluginDownloadService(
        client: MockClient((request) async {
          requested.add(request.url);
          return responses[index++];
        }),
      );
    }

    test('asks the store for a version matching the running app', () async {
      final service = serviceReturning([http.Response('archive-bytes', 200)]);

      final path = await service.downloadPluginArchive(
        Uri.parse('https://otzaria.org/api/plugins/abc123/download'),
        appVersion: '0.9.96',
      );
      addTearDown(() => service.cleanupDownloadedArchive(path));

      expect(requested.single.queryParameters['appVersion'], '0.9.96');
      expect(await File(path).readAsString(), 'archive-bytes');
    });

    test('reports incompatibility without a second download', () async {
      final service = serviceReturning([
        http.Response(
          '{"error":"No plugin version supports the requested app version",'
          '"appVersion":"0.9.90","latestVersion":"2.1.0",'
          '"compatibleWith":"1.0.0","maxAppVersion":null}',
          404,
        ),
      ]);

      await expectLater(
        service.downloadPluginArchive(
          Uri.parse('https://otzaria.org/api/plugins/abc123/download'),
          appVersion: '0.9.90',
        ),
        throwsA(
          isA<PluginStoreIncompatibleException>()
              .having((e) => e.minAppVersion, 'minAppVersion', '1.0.0')
              .having((e) => e.latestVersion, 'latestVersion', '2.1.0')
              .having((e) => e.isAboveCeiling, 'isAboveCeiling', isFalse),
        ),
      );
      expect(requested, hasLength(1));
    });

    test('keeps the lowest floor when it differs from the latest', () async {
      final service = serviceReturning([
        http.Response(
          '{"appVersion":"0.9.80","latestVersion":"2.1.0",'
          '"compatibleWith":"1.0.0","minSupportedAppVersion":"0.9.89"}',
          404,
        ),
      ]);

      await expectLater(
        service.downloadPluginArchive(
          Uri.parse('https://otzaria.org/api/plugins/abc123/download'),
          appVersion: '0.9.80',
        ),
        throwsA(
          isA<PluginStoreIncompatibleException>().having(
            (e) => e.minSupportedAppVersion,
            'minSupportedAppVersion',
            '0.9.89',
          ),
        ),
      );
    });

    test('drops a lowest floor identical to the latest requirement', () async {
      final service = serviceReturning([
        http.Response(
          '{"appVersion":"0.9.80","latestVersion":"2.1.0",'
          '"compatibleWith":"1.0.0","minSupportedAppVersion":"1.0.0"}',
          404,
        ),
      ]);

      await expectLater(
        service.downloadPluginArchive(
          Uri.parse('https://otzaria.org/api/plugins/abc123/download'),
          appVersion: '0.9.80',
        ),
        throwsA(
          isA<PluginStoreIncompatibleException>().having(
            (e) => e.minSupportedAppVersion,
            'minSupportedAppVersion',
            isNull,
          ),
        ),
      );
    });

    test('detects an app version above the plugin ceiling', () async {
      final service = serviceReturning([
        http.Response(
          '{"appVersion":"2.0.0","latestVersion":"1.4.0",'
          '"compatibleWith":"0.9.0","maxAppVersion":"1.5.0"}',
          404,
        ),
      ]);

      await expectLater(
        service.downloadPluginArchive(
          Uri.parse('https://otzaria.org/api/plugins/abc123/download'),
          appVersion: '2.0.0',
        ),
        throwsA(
          isA<PluginStoreIncompatibleException>().having(
            (e) => e.isAboveCeiling,
            'isAboveCeiling',
            isTrue,
          ),
        ),
      );
    });

    test('retries without appVersion when the refusal is unrelated', () async {
      final service = serviceReturning([
        http.Response(
          '{"error":"Cannot combine pending=1 with appVersion"}',
          400,
        ),
        http.Response('latest-bytes', 200),
      ]);

      final path = await service.downloadPluginArchive(
        Uri.parse('https://otzaria.org/api/plugins/abc123/download'),
        appVersion: '0.9.96',
      );
      addTearDown(() => service.cleanupDownloadedArchive(path));

      expect(requested, hasLength(2));
      expect(requested.last.queryParameters.containsKey('appVersion'), isFalse);
      expect(await File(path).readAsString(), 'latest-bytes');
    });

    test('storeOnly חוסם redirect מהחנות אל מארח זר', () async {
      final service = serviceReturning([
        http.Response(
          '',
          302,
          headers: {'location': 'https://evil.example.com/p.otzplugin'},
        ),
        http.Response('evil-bytes', 200),
      ]);

      await expectLater(
        service.downloadPluginArchive(
          Uri.parse('https://otzaria.org/api/plugins/abc/download'),
          storeOnly: true,
        ),
        throwsA(isA<Exception>()),
      );
      // הבקשה השנייה לא נשלחה כלל — היעד נפסל לפני היציאה לרשת.
      expect(requested, hasLength(1));
    });

    test('storeOnly עוקב אחרי redirect שנשאר בחנות', () async {
      final service = serviceReturning([
        http.Response(
          '',
          302,
          headers: {'location': 'https://www.otzaria.org/files/p.otzplugin'},
        ),
        http.Response('archive-bytes', 200),
      ]);

      final path = await service.downloadPluginArchive(
        Uri.parse('https://otzaria.org/api/plugins/abc/download'),
        storeOnly: true,
      );
      addTearDown(() => service.cleanupDownloadedArchive(path));

      expect(requested, hasLength(2));
      expect(await File(path).readAsString(), 'archive-bytes');
    });

    test('does not retry when no app version was added', () async {
      final service = serviceReturning([http.Response('missing', 404)]);

      await expectLater(
        service.downloadPluginArchive(
          Uri.parse('https://example.com/plugin.otzplugin'),
          appVersion: '0.9.96',
        ),
        throwsA(isA<Exception>()),
      );
      expect(requested, hasLength(1));
    });
  });
}
