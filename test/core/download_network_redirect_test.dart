import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:otzaria/core/download_http_client.dart';
import 'package:otzaria/core/download_network_policy.dart';
import 'package:otzaria/utils/http_redirect_download.dart';

void main() {
  for (final automatic in [false, true]) {
    test(
      'אובדן WiFi אחרי redirect סוגר את ה־socket (automatic=$automatic)',
      () async {
        final network = StreamController<bool>.broadcast(sync: true);
        final policy = DownloadNetworkPolicy(
          isAndroid: true,
          wifiOnlyReader: () => true,
          wifiChanges: () => network.stream,
        );
        final ready = policy.refresh();
        network.add(true);
        await ready;
        final client = DownloadHttpClient(http.Client(), policy: policy);
        final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
        final secondRequest = Completer<void>();
        final secondClosed = Completer<void>();
        final sockets = <Socket>[];
        server.listen((socket) {
          sockets.add(socket);
          var header = '';
          var handled = false;
          var isSecond = false;
          socket.listen(
            (bytes) {
              header += ascii.decode(bytes);
              if (handled || !header.contains('\r\n\r\n')) return;
              handled = true;
              if (header.startsWith('GET /first ')) {
                socket.write(
                  'HTTP/1.1 302 Found\r\nLocation: http://127.0.0.1:${server.port}/second\r\nContent-Length: 0\r\nConnection: close\r\n\r\n',
                );
                unawaited(socket.flush().then((_) => socket.close()));
              } else {
                isSecond = true;
                secondRequest.complete();
              }
            },
            onDone: () {
              if (isSecond && !secondClosed.isCompleted) {
                secondClosed.complete();
              }
            },
          );
        });
        try {
          final first = Uri.parse('http://127.0.0.1:${server.port}/first');
          final Future<Object?> result = automatic
              ? client.get(first).whenComplete(client.close)
              : sendGetFollowingRedirects(client, first);
          final expected = expectLater(
            result.timeout(const Duration(seconds: 5)),
            throwsA(isA<DownloadNetworkPaused>()),
          );
          await secondRequest.future.timeout(const Duration(seconds: 5));
          network.add(false);
          await expected;
          await secondClosed.future.timeout(const Duration(seconds: 5));
        } finally {
          client.close();
          for (final socket in sockets) {
            socket.destroy();
          }
          await server.close();
          await policy.dispose();
          await network.close();
        }
      },
    );
  }

  test(
    'ניתן לבטל המתנה לפני תמונת הרשת הנייטיבית הראשונה',
    () async {
      final network = StreamController<bool>.broadcast(sync: true);
      final policy = DownloadNetworkPolicy(
        isAndroid: true,
        wifiOnlyReader: () => true,
        wifiChanges: () => network.stream,
      );
      var cancelled = false;
      final started = Stopwatch()..start();
      try {
        final result = policy.waitUntilAllowed(
          checkCancelled: () {
            if (cancelled) throw const _Cancelled();
          },
        );
        final expected = expectLater(result, throwsA(isA<_Cancelled>()));
        cancelled = true;
        await expected;
        expect(started.elapsed, lessThan(const Duration(seconds: 1)));
      } finally {
        await policy.dispose();
        await network.close();
      }
    },
  );
}

class _Cancelled implements Exception {
  const _Cancelled();
}
