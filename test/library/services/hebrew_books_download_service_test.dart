import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:otzaria/core/download_network_policy.dart';
import 'package:otzaria/library/services/hebrew_books_download_service.dart';
import 'package:path/path.dart' as path;

class _TrackedPolicy extends DownloadNetworkPolicy {
  _TrackedPolicy() : super(isAndroid: true, wifiOnlyReader: () => false);

  final tracked = StreamController<DownloadNetworkStatus>.broadcast(sync: true);

  @override
  Stream<DownloadNetworkStatus> get changes => tracked.stream;

  @override
  Future<void> dispose() async {
    await super.dispose();
    await tracked.close();
  }
}

class _LocalClient extends http.BaseClient {
  _LocalClient(this.uri);

  final Uri uri;
  final inner = http.Client();
  var closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) => inner.send(
    http.AbortableRequest(
      request.method,
      uri,
      abortTrigger: request is http.Abortable ? request.abortTrigger : null,
    ),
  );

  @override
  void close() {
    closed = true;
    inner.close();
  }
}

class _StreamClient extends http.BaseClient {
  _StreamClient(this.body, {this.contentLength});

  final Stream<List<int>> Function() body;
  final int? contentLength;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      http.StreamedResponse(body(), 200, contentLength: contentLength);
}

void main() {
  group('הורדת ספר בזרימה לתיקייה', () {
    late Directory folder;
    late File destination;

    setUp(() async {
      folder = await Directory.systemTemp.createTemp('hebrewbooks-stream-');
      final books = await Directory(path.join(folder.path, 'Books')).create();
      destination = File(path.join(books.path, '123.pdf'));
      await destination.writeAsBytes([9]);
    });

    tearDown(() => folder.delete(recursive: true));

    test('כותבת כל מקטע לפני הבא ומחליפה את הקובץ רק בסוף', () async {
      final progress = <(int, int?)>[];
      final first = List<int>.filled(64 * 1024, 17);
      final second = List<int>.filled(32 * 1024, 22);
      final total = first.length + second.length;

      Stream<List<int>> body() async* {
        yield first;
        final partial = await destination.parent
            .list(recursive: true)
            .where((entry) => entry is File && entry.path.endsWith('.part'))
            .cast<File>()
            .single;
        expect(await partial.length(), first.length);
        expect(await destination.readAsBytes(), [9]);
        yield second;
      }

      final service = HebrewBooksDownloadService(
        client: _StreamClient(body, contentLength: total),
      );
      addTearDown(service.dispose);
      final saved = await service.downloadToFolder(
        123,
        folder.path,
        onProgress: (received, total) => progress.add((received, total)),
      );

      expect(saved, destination.path);
      expect(await destination.readAsBytes(), [...first, ...second]);
      expect(progress, [(first.length, total), (total, total)]);
      expect(
        await destination.parent.list().map((entry) => entry.path).toList(),
        [destination.path],
      );
    });

    test('כשל בזרם מנקה את קובץ הביניים ומשאיר את הקובץ הקיים', () async {
      Stream<List<int>> body() async* {
        yield [1, 2, 3];
        throw const SocketException('stream interrupted');
      }

      final service = HebrewBooksDownloadService(client: _StreamClient(body));
      addTearDown(service.dispose);

      await expectLater(
        service.downloadToFolder(123, folder.path),
        throwsA(isA<SocketException>()),
      );
      expect(await destination.readAsBytes(), [9]);
      expect(
        await destination.parent.list().map((entry) => entry.path).toList(),
        [destination.path],
      );
    });

    test('ביטול לפני הפרסום מנקה את קובץ הביניים', () async {
      final service = HebrewBooksDownloadService(
        client: _StreamClient(() => Stream.value([1, 2, 3])),
      );
      addTearDown(service.dispose);

      await expectLater(
        service.downloadToFolder(
          123,
          folder.path,
          onProgress: (_, _) => service.dispose(),
        ),
        throwsA(isA<http.RequestAbortedException>()),
      );
      expect(await destination.readAsBytes(), [9]);
      expect(
        await destination.parent.list().map((entry) => entry.path).toList(),
        [destination.path],
      );
    });
  });
  for (final owned in [true, false]) {
    for (final status in [200, 404, 503]) {
      test('סטטוס $status משחרר מאזין רשת (לקוח בבעלות: $owned)', () async {
        final savedPolicy = DownloadNetworkPolicy.instance;
        final policy = _TrackedPolicy();
        DownloadNetworkPolicy.instance = policy;
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        var responseStatus = status;
        server.listen((request) async {
          request.response.statusCode = responseStatus;
          request.response.write('book body');
          await request.response.close();
        });
        final client = _LocalClient(
          Uri.http('127.0.0.1:${server.port}', '/book'),
        );
        try {
          await http.runWithClient(() async {
            final service = HebrewBooksDownloadService(
              client: owned ? null : client,
            );
            try {
              if (status == 200) {
                expect(
                  (await service.download(123)).bytes,
                  'book body'.codeUnits,
                );
              } else {
                await expectLater(
                  service.download(123),
                  throwsA(
                    isA<HebrewBookDownloadStatusException>().having(
                      (error) => error.statusCode,
                      'statusCode',
                      status,
                    ),
                  ),
                );
              }
              expect(policy.tracked.hasListener, isFalse);
              expect(client.closed, isFalse);

              responseStatus = 200;
              expect(
                (await service.download(124)).bytes,
                'book body'.codeUnits,
              );
              expect(policy.tracked.hasListener, isFalse);
            } finally {
              service.dispose();
            }
            expect(client.closed, owned);
            expect(policy.tracked.hasListener, isFalse);
          }, () => client);
        } finally {
          DownloadNetworkPolicy.instance = savedPolicy;
          client.close();
          await server.close(force: true);
          await policy.dispose();
        }
      });
    }
  }
}
