import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:otzaria/core/download_network_policy.dart';
import 'package:otzaria/library/services/hebrew_books_download_service.dart';

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

void main() {
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
