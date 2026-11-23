import 'dart:async';

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

  test('a server returning 200 is not read beyond the header', () async {
    var cancelled = false;
    final body = StreamController<List<int>>(onCancel: () => cancelled = true);
    addTearDown(body.close);
    body.add([..._header(4418928640), 0, 0, 0, 0, 0]);
    final client = MockClient.streaming(
      (_, _) async => http.StreamedResponse(body.stream, 200),
    );
    addTearDown(client.close);

    expect(
      await probeZstdFrameContentSize(
        'https://example.invalid/part-000',
        client: client,
      ),
      4418928640,
    );
    expect(cancelled, isTrue);
  });

  testWidgets('slow chunks cannot extend the deadline for the probe', (
    tester,
  ) async {
    var cancelled = false;
    final body = StreamController<List<int>>(onCancel: () => cancelled = true);
    addTearDown(body.close);
    final client = MockClient.streaming(
      (_, _) async => http.StreamedResponse(body.stream, 206),
    );
    addTearDown(client.close);

    var finished = false;
    final probe =
        probeZstdFrameContentSize(
          'https://example.invalid/part-000',
          client: client,
          timeout: const Duration(milliseconds: 60),
        ).then((size) {
          finished = true;
          return size;
        });
    await tester.pump();
    body.add([0x28]);
    await tester.pump(const Duration(milliseconds: 30));
    body.add([0xB5]);
    await tester.pump(const Duration(milliseconds: 30));

    expect(finished, isTrue);
    expect(await probe, isNull);
    expect(cancelled, isTrue);
  });
}
