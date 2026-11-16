import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:otzaria/core/download_http_client.dart';
import 'package:otzaria/core/download_network_policy.dart';
import 'package:seforim_library_updater/seforim_library_updater.dart';

void main() {
  late StreamController<bool> network;
  late DownloadNetworkPolicy policy;
  late http.Client client;
  late HttpServer server;

  setUp(() async {
    network = StreamController<bool>.broadcast(sync: true);
    policy = DownloadNetworkPolicy(
      isAndroid: true,
      wifiOnlyReader: () => true,
      wifiChanges: () => network.stream,
    );
    client = DownloadHttpClient(http.Client(), policy: policy);
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  });
  tearDown(() async {
    client.close();
    await server.close(force: true);
    await policy.dispose();
    await network.close();
  });

  Future<void> wifi(bool available) async {
    final refresh = policy.refresh();
    network.add(available);
    await refresh;
  }

  Uri url([String path = '/download']) =>
      Uri.http('127.0.0.1:${server.port}', path);

  void serve(Future<void> Function(HttpRequest request) handler) {
    server.listen((request) {
      unawaited(handler(request).catchError((Object _) {}));
    });
  }

  test('התחלה בסלולר אינה שולחת בקשת HTTP', () async {
    var requests = 0;
    serve((request) async {
      requests++;
      await request.response.close();
    });
    await wifi(false);
    await expectLater(client.get(url()), throwsA(isA<DownloadNetworkPaused>()));
    expect(requests, 0);
  });

  test('ביטול הקורא בזמן המתנה לכותרות אינו מומר להמתנת WiFi', () async {
    final accepted = Completer<void>();
    final release = Completer<void>();
    serve((request) async {
      accepted.complete();
      await release.future;
      await request.response.close();
    });
    addTearDown(() {
      if (!release.isCompleted) release.complete();
    });
    await wifi(true);
    final abort = Completer<void>();
    final result = client.send(
      http.AbortableRequest('GET', url(), abortTrigger: abort.future),
    );
    final expectation = expectLater(
      result,
      throwsA(isA<http.RequestAbortedException>()),
    );
    await accepted.future;
    abort.complete();
    await expectation;
  });

  test(
    'מעבר לסלולר קוטע גוף, משמר חלקים ומתחדש ב־Range עם חזרת WiFi',
    () async {
      final bytes = Uint8List.fromList(
        List.generate(256 * 1024, (i) => i % 251),
      );
      final ranges = <String?>[];
      serve((request) async {
        final range = request.headers.value(HttpHeaders.rangeHeader);
        ranges.add(range);
        final start = range == null
            ? 0
            : int.parse(RegExp(r'bytes=(\d+)-').firstMatch(range)!.group(1)!);
        final response = request.response;
        response.headers.set(HttpHeaders.etagHeader, '"download-v1"');
        response.contentLength = bytes.length - start;
        if (start > 0) {
          response.statusCode = HttpStatus.partialContent;
          response.headers.set(
            HttpHeaders.contentRangeHeader,
            'bytes $start-${bytes.length - 1}/${bytes.length}',
          );
        }
        for (var offset = start; offset < bytes.length; offset += 16384) {
          response.add(
            bytes.sublist(offset, (offset + 16384).clamp(0, bytes.length)),
          );
          await response.flush();
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
        await response.close();
      });
      await wifi(true);
      final directory = await Directory.systemTemp.createTemp(
        'download-wifi-test-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final target = File('${directory.path}/asset.bin');
      final waiting = Completer<void>();
      var interrupted = false;
      final downloader = PatchDownloader(
        decompress: (_) async => null,
        httpClient: client,
      );
      final download = policy.runResumable(
        () => downloader.downloadToFile(
          url: url().toString(),
          destPath: target.path,
          expectedSize: bytes.length,
          expectedSha256: sha256.convert(bytes).toString(),
          resumeToken: 'same-release',
          onProgress: (received, _) {
            if (!interrupted && received > 0 && received < bytes.length) {
              interrupted = true;
              network.add(false);
            }
          },
        ),
        onWaiting: () {
          if (!waiting.isCompleted) waiting.complete();
        },
      );
      await waiting.future;
      final partial = await target.length();
      expect(partial, greaterThan(0));
      expect(partial, lessThan(bytes.length));
      expect(
        File(PatchDownloader.resumeSidecarPath(target.path)).existsSync(),
        isTrue,
      );
      expect(ranges, [null]);
      network.add(true);
      await download;
      expect(await target.readAsBytes(), orderedEquals(bytes));
      expect(ranges.length, 2);
      expect(ranges.last, 'bytes=$partial-');
    },
  );
  for (final listensToBody in [false, true]) {
    test(
      'שינוי רשת סוגר socket גם לפני צריכת הגוף (מאזין: $listensToBody)',
      () async {
        final disconnected = Completer<void>();
        final socketServer = await ServerSocket.bind(
          InternetAddress.loopbackIPv4,
          0,
        );
        addTearDown(socketServer.close);
        socketServer.listen((socket) {
          var started = false;
          Timer? timer;
          void disconnectedSocket() {
            timer?.cancel();
            socket.destroy();
            if (!disconnected.isCompleted) disconnected.complete();
          }

          socket.listen(
            (_) {
              if (started) return;
              started = true;
              socket.write(
                'HTTP/1.1 200 OK\r\nContent-Length: 16777216\r\n\r\n',
              );
              timer = Timer.periodic(const Duration(milliseconds: 10), (_) {
                socket.add(List.filled(1024, 1));
              });
            },
            onDone: disconnectedSocket,
            onError: (Object _) => disconnectedSocket(),
          );
          addTearDown(disconnectedSocket);
        });
        await wifi(true);
        final response = await client.send(
          http.Request(
            'GET',
            Uri.http('127.0.0.1:${socketServer.port}', '/download'),
          ),
        );
        if (listensToBody) {
          final body = response.stream.listen((_) {}, onError: (Object _) {})
            ..pause();
          addTearDown(body.cancel);
        } else {
          addTearDown(
            () =>
                response.stream.listen((_) {}, onError: (Object _) {}).cancel(),
          );
        }
        network.add(false);
        await disconnected.future.timeout(const Duration(seconds: 1));
      },
    );
  }
}
