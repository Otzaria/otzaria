import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:otzaria/update/latest_release_redirect.dart';

Future<String?> _fetch(MockClient client) => fetchLatestStableTagViaRedirect(
  owner: 'Otzaria',
  repository: 'otzaria',
  client: client,
  timeout: const Duration(seconds: 1),
);

void main() {
  test('מחלץ את התג מההפניה בלי לעקוב אחריה', () async {
    late http.BaseRequest seen;
    final client = MockClient((request) async {
      seen = request;
      return http.Response(
        '',
        302,
        headers: {
          'location':
              'https://github.com/Otzaria/otzaria/releases/tag/0.9.98.2%2B807',
        },
      );
    });
    expect(await _fetch(client), '0.9.98.2+807');
    expect(seen.url.host, 'github.com');
    expect(seen.followRedirects, isFalse);
  });

  test('תשובה שאינה הפניה לתג מחזירה null', () async {
    expect(await _fetch(MockClient((_) async => http.Response('', 200))), null);
    expect(
      await _fetch(
        MockClient(
          (_) async => http.Response('', 302, headers: {'location': '/login'}),
        ),
      ),
      null,
    );
  });

  test('הפניה לדומיין אחר מחזירה null', () async {
    expect(
      await _fetch(
        MockClient(
          (_) async => http.Response(
            '',
            302,
            headers: {'location': 'https://evil.example/releases/tag/9.9.9'},
          ),
        ),
      ),
      null,
    );
  });
}
