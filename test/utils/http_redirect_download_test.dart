import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:otzaria/utils/http_redirect_download.dart';

void main() {
  group('sendGetFollowingRedirects', () {
    test('עוקב אחרי 302 ומשמר את ה-Range בכל hop', () async {
      final ranges = <String?>[];
      final client = MockClient((request) async {
        ranges.add(request.headers['range']);
        if (request.url.path.endsWith('/original')) {
          return http.Response(
            '',
            302,
            headers: {'location': 'https://cdn.example.com/signed'},
          );
        }
        return http.Response.bytes(
          [1, 2, 3],
          206,
          headers: {'content-range': 'bytes 10-12/13'},
        );
      });

      final response = await sendGetFollowingRedirects(
        client,
        Uri.parse('https://example.com/original'),
        headers: {'Range': 'bytes=10-'},
      );

      expect(response.statusCode, 206);
      // ה-Range נשלח בבקשה המקורית וגם בבקשה המחודשת אחרי ה-redirect.
      expect(ranges, ['bytes=10-', 'bytes=10-']);
    });

    test('Location יחסי מפוענח מול ה-URI הנוכחי', () async {
      final requested = <Uri>[];
      final client = MockClient((request) async {
        requested.add(request.url);
        if (request.url.path == '/a/original') {
          return http.Response('', 302, headers: {'location': '/b/final'});
        }
        return http.Response.bytes([1], 200);
      });

      final response = await sendGetFollowingRedirects(
        client,
        Uri.parse('https://example.com/a/original'),
      );

      expect(response.statusCode, 200);
      expect(requested.last.toString(), 'https://example.com/b/final');
    });

    test('חריגה ממספר ה-redirects המרבי → זורק', () async {
      final client = MockClient(
        (_) async => http.Response(
          '',
          302,
          headers: {'location': 'https://example.com/next'},
        ),
      );

      expect(
        () => sendGetFollowingRedirects(
          client,
          Uri.parse('https://example.com/start'),
          maxRedirects: 2,
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('redirect ללא Location → זורק', () async {
      final client = MockClient((_) async => http.Response('', 302));
      expect(
        () => sendGetFollowingRedirects(
          client,
          Uri.parse('https://example.com/start'),
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('גוף redirect ארוך ננטש מיד', () async {
      var chunksServed = 0;
      Stream<List<int>> longBody() async* {
        for (var i = 0; i < 100; i++) {
          chunksServed++;
          yield const [0];
        }
      }

      final client = _StreamingClient((request) async {
        if (request.url.path == '/start') {
          return http.StreamedResponse(
            longBody(),
            302,
            headers: const {'location': '/final'},
          );
        }
        return http.StreamedResponse(Stream.value(const [1]), 200);
      });

      final response = await sendGetFollowingRedirects(
        client,
        Uri.parse('https://example.com/start'),
      );

      expect(response.statusCode, 200);
      expect(chunksServed, lessThan(10));
    });

    test('stallTimeout חל גם על גוף התגובה הסופית', () async {
      final controller = StreamController<List<int>>();
      addTearDown(controller.close);
      final client = _StreamingClient(
        (_) async => http.StreamedResponse(controller.stream, 200),
      );

      final response = await sendGetFollowingRedirects(
        client,
        Uri.parse('https://example.com/final'),
        stallTimeout: const Duration(milliseconds: 10),
      );

      await expectLater(
        response.stream.drain<void>(),
        throwsA(isA<TimeoutException>()),
      );
    });
  });
}

class _StreamingClient extends http.BaseClient {
  _StreamingClient(this.handler);

  final Future<http.StreamedResponse> Function(http.BaseRequest request)
  handler;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      handler(request);
}
