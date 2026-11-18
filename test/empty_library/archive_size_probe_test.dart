import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:otzaria/empty_library/services/archive_size_probe.dart';

List<int> _header(int size) => [
  0x28,
  0xB5,
  0x2F,
  0xFD,
  0xC0,
  0,
  for (var i = 0; i < 8; i++) (size >> (8 * i)) & 0xFF,
];

void main() {
  test(
    'a split part returns its frame size via a bounded Range request',
    () async {
      final visited = <String>[];
      final client = MockClient((request) async {
        expect(request.headers['Range'], 'bytes=0-17');
        visited.add(request.url.path);
        if (request.url.path == '/manifest') {
          return http.Response('', 302, headers: {'location': '/part-000'});
        }
        return http.Response.bytes(_header(4418928640), 206);
      });
      addTearDown(client.close);

      expect(
        await probeZstdFrameContentSize(
          'https://example.invalid/manifest',
          client: client,
        ),
        4418928640,
      );
      expect(visited, ['/manifest', '/part-000']);
    },
  );

  test('missing FCS falls back instead of making installation fail', () async {
    final client = MockClient(
      (_) async => http.Response.bytes(
        [0x28, 0xB5, 0x2F, 0xFD, 0, 0],
        206,
      ),
    );
    addTearDown(client.close);

    expect(
      await probeZstdFrameContentSize(
        'https://example.invalid/part-000',
        client: client,
      ),
      isNull,
    );
  });

  test('failed Range request falls back without reading the archive', () async {
    final client = MockClient((_) async => http.Response('', 404));
    addTearDown(client.close);

    expect(
      await probeZstdFrameContentSize(
        'https://example.invalid/part-000',
        client: client,
      ),
      isNull,
    );
  });
}
