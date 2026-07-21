import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:otzaria/plugins/models/plugin_manifest.dart';
import 'package:otzaria/plugins/services/plugin_network_access_resolver.dart';

PluginManifest _buildManifest({List<String> networkAllowlist = const []}) {
  return PluginManifest(
    schemaVersion: 1,
    id: 'test.plugin',
    name: 'Test Plugin',
    version: '1.0.0',
    description: '',
    author: '',
    homepage: '',
    entrypoint: 'index.html',
    minAppVersion: '0.0.0',
    sdkVersion: '1.x',
    permissions: const ['network.access'],
    networkEnabled: true,
    networkAllowlist: networkAllowlist,
    toolTabTitle: 'Test Plugin',
    toolTabOrder: 1,
    defaultPinned: true,
    publishedDataTypes: const [],
  );
}

void main() {
  group('PluginNetworkAccessResolver', () {
    test('מתיר URL מהרשימה הרשמית רק אם הוא הוצהר גם במניפסט', () async {
      var fetches = 0;
      final client = MockClient((request) async {
        fetches++;
        expect(request.url, PluginNetworkAccessResolver.officialAllowlistUri);
        return http.Response('https://nakdan.dicta.org.il/api\n', 200);
      });
      final resolver = PluginNetworkAccessResolver(client: client);
      final localUri = Uri.parse('https://nakdan.dicta.org.il/api?text=שלום');

      expect(
        await resolver.isUriAllowedForPlugin(
          localUri,
          _buildManifest(
            networkAllowlist: const ['https://nakdan.dicta.org.il/api'],
          ),
        ),
        isTrue,
      );

      expect(
        await resolver.isUriAllowedForPlugin(
          localUri,
          _buildManifest(),
        ),
        isFalse,
      );
      expect(fetches, 1);
    });

    test('הרשימה הרשמית יכולה לבטל כתובת שקיימת ברשימה המקומפלת', () async {
      final client = MockClient((_) async {
        return http.Response('https://approved.example.com/api\n', 200);
      });
      final resolver = PluginNetworkAccessResolver(client: client);
      final compiledUri = Uri.parse('https://nakdan.dicta.org.il/api');

      expect(
        await resolver.isUriAllowedForPlugin(
          compiledUri,
          _buildManifest(
            networkAllowlist: const ['https://nakdan.dicta.org.il/api'],
          ),
        ),
        isFalse,
      );
    });

    test('רשימה רשמית ריקה חוסמת גם כתובות מקומפלות', () async {
      final client = MockClient(
        (_) async => http.Response('# emergency\n', 200),
      );
      final resolver = PluginNetworkAccessResolver(client: client);

      expect(
        await resolver.isUriAllowedForPlugin(
          Uri.parse('https://nakdan.dicta.org.il/api'),
          _buildManifest(
            networkAllowlist: const ['https://nakdan.dicta.org.il/api'],
          ),
        ),
        isFalse,
      );
    });

    test('כשל בטעינת הרשימה הרשמית נופל לרשימה המקומפלת', () async {
      final client = MockClient((_) async => http.Response('unavailable', 503));
      final resolver = PluginNetworkAccessResolver(client: client);
      final compiledUri = Uri.parse('https://nakdan.dicta.org.il/api');

      expect(
        await resolver.isUriAllowedForPlugin(
          compiledUri,
          _buildManifest(
            networkAllowlist: const ['https://nakdan.dicta.org.il/api'],
          ),
        ),
        isTrue,
      );
    });

    test(
      'מתיר loopback מקומי כשהמניפסט מצהיר עליו, בלי allowlist גלובלי',
      () async {
        final resolver = PluginNetworkAccessResolver();
        final manifest = _buildManifest(
          networkAllowlist: const ['127.0.0.1', 'localhost'],
        );

        expect(
          await resolver.isUriAllowedForPlugin(
            Uri.parse('http://127.0.0.1:11434/api/tags'),
            manifest,
          ),
          isTrue,
        );
        expect(
          await resolver.isUriAllowedForPlugin(
            Uri.parse('http://localhost:1234/v1/models'),
            manifest,
          ),
          isTrue,
        );
      },
    );

    test('חוסם loopback אם המניפסט לא מצהיר עליו', () async {
      final resolver = PluginNetworkAccessResolver();

      expect(
        await resolver.isUriAllowedForPlugin(
          Uri.parse('http://127.0.0.1:11434/api/tags'),
          _buildManifest(),
        ),
        isFalse,
      );
    });

    test('הצהרת loopback עם פורט מתירה רק את אותו פורט', () async {
      final resolver = PluginNetworkAccessResolver();
      final manifest = _buildManifest(
        networkAllowlist: const ['http://127.0.0.1:11434'],
      );

      expect(
        await resolver.isUriAllowedForPlugin(
          Uri.parse('http://127.0.0.1:11434/api/tags'),
          manifest,
        ),
        isTrue,
      );
      expect(
        await resolver.isUriAllowedForPlugin(
          Uri.parse('http://127.0.0.1:1234/v1/models'),
          manifest,
        ),
        isFalse,
      );
    });

    test('מפרק את קובץ הטקסט הרשמי: הערות ושורות ריקות מדולגות', () async {
      final client = MockClient((_) async {
        // Response.bytes + utf8: הערות בעברית בקובץ האמיתי אינן latin1
        return http.Response.bytes(
          utf8.encode('''
# הערה
https://api.example.com/root

# עוד הערה
https://other.example.com
'''),
          200,
        );
      });
      final resolver = PluginNetworkAccessResolver(client: client);

      final allowed = await resolver.isUriAllowedForPlugin(
        Uri.parse('https://api.example.com/root/v1/items'),
        _buildManifest(
          networkAllowlist: const ['https://api.example.com/root'],
        ),
      );

      expect(allowed, isTrue);
    });

    test('חוסם URL מהרשימה הרשמית אם המניפסט לא הצהיר עליו', () async {
      final client = MockClient((_) async {
        return http.Response('https://api.example.com/root\n', 200);
      });
      final resolver = PluginNetworkAccessResolver(client: client);

      final allowed = await resolver.isUriAllowedForPlugin(
        Uri.parse('https://api.example.com/root/v1/items'),
        _buildManifest(
          networkAllowlist: const ['https://another.example.com'],
        ),
      );

      expect(allowed, isFalse);
    });

    test('שומר אישור מהרשימה הרשמית בזיכרון עד סוף הסשן', () async {
      var fetches = 0;
      final client = MockClient((_) async {
        fetches++;
        return http.Response('https://cached.example.com/api\n', 200);
      });
      final resolver = PluginNetworkAccessResolver(client: client);
      final manifest = _buildManifest(
        networkAllowlist: const ['https://cached.example.com/api'],
      );
      final uri = Uri.parse('https://cached.example.com/api/v1/check');

      expect(await resolver.isUriAllowedForPlugin(uri, manifest), isTrue);
      expect(await resolver.isUriAllowedForPlugin(uri, manifest), isTrue);
      expect(fetches, 1);
    });

    test('נכשל מהר אחרי כשל fetch ולא מנסה שוב עד שפג מטמון הכשל', () async {
      var fetches = 0;
      final client = MockClient((_) async {
        fetches++;
        return http.Response('unavailable', 503);
      });
      var now = DateTime(2026, 6, 3, 12, 0, 0);
      final resolver = PluginNetworkAccessResolver(
        client: client,
        nowProvider: () => now,
      );
      final manifest = _buildManifest(
        networkAllowlist: const ['https://blocked.example.com/api'],
      );
      final uri = Uri.parse('https://blocked.example.com/api/v1/check');

      expect(await resolver.isUriAllowedForPlugin(uri, manifest), isFalse);
      expect(await resolver.isUriAllowedForPlugin(uri, manifest), isFalse);
      expect(fetches, 1);

      now = now.add(const Duration(minutes: 6));
      expect(await resolver.isUriAllowedForPlugin(uri, manifest), isFalse);
      expect(fetches, 2);
    });

    test('כתובת הרשימה הרשמית מצביעה על הענף הייעודי', () {
      expect(
        PluginNetworkAccessResolver.officialAllowlistUri.toString(),
        'https://raw.githubusercontent.com/Otzaria/otzaria/'
        'plugin-network-allowlist/plugin_network_allowlist.txt',
      );
    });
  });
}
