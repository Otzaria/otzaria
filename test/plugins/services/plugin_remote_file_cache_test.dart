import 'dart:async';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:otzaria/plugins/services/plugin_file_download_service.dart';
import 'package:otzaria/plugins/services/plugin_remote_file_cache.dart';
import 'package:path/path.dart' as p;

class _ObservedClient extends http.BaseClient {
  _ObservedClient(this.onBody);
  final void Function() onBody;
  final http.Client _client = http.Client();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final response = await _client.send(request);
    return http.StreamedResponse(
      response.stream.map((chunk) {
        onBody();
        return chunk;
      }),
      response.statusCode,
      headers: response.headers,
    );
  }

  @override
  void close() => _client.close();
}

void main() {
  late Directory tempDir;
  late PluginRemoteFileCache cache;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('plugin_remote_cache_');
    cache = PluginRemoteFileCache(
      root: Directory(p.join(tempDir.path, 'cache')),
      quotaBytes: 100,
    );
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  Future<bool> allowAll(Uri _) async => true;

  List<FileSystemEntity> leftovers(String pluginId) {
    final dir = Directory(p.join(cache.root.path, pluginId));
    return dir.existsSync() ? dir.listSync() : [];
  }

  Future<void> waitForCleanup(String pluginId) async {
    final dir = Directory(p.join(cache.root.path, pluginId));
    final deadline = DateTime.now().add(const Duration(seconds: 2));
    while (await dir.exists() && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(await dir.exists(), isFalse);
  }

  PluginFileDownloadService serving(List<int> body) =>
      PluginFileDownloadService(
        client: MockClient((_) async => http.Response.bytes(body, 200)),
      );

  Future<PluginRemoteFile> fetch(
    String name,
    int size, {
    String pluginId = 'p1',
    Duration timeout = PluginRemoteFileCache.defaultTimeout,
    PluginFileDownloadService? downloader,
  }) => cache.fetch(
    pluginId,
    Uri.parse('https://example.org/$name'),
    downloader: downloader ?? serving(List.filled(size, 7)),
    isAllowed: allowAll,
    timeout: timeout,
  );

  test('קובץ נשמר בשמו תחת תיקיית התוסף, עם גודלו', () async {
    final file = await fetch('a.pdf', 10);

    expect(file.name, 'a.pdf');
    expect(file.size, 10);
    expect(p.basename(file.path), 'a.pdf');
    expect(cache.owns(file.path), isTrue);
    expect(cache.owns(p.join(tempDir.path, 'a.pdf')), isFalse);
  });

  test('שני קבצים באותו שם אינם דורסים זה את זה', () async {
    final first = await fetch('a.pdf', 10);
    final second = await fetch('a.pdf', 20);

    expect(first.path, isNot(second.path));
    expect(await File(first.path).length(), 10);
    expect(await File(second.path).length(), 20);
  });

  test('חריגה מהמכסה מוחקת את הוותיק ביותר ולא את החדש', () async {
    // זמני הכתיבה נקבעים במפורש: הסדר אינו תלוי בדיוק השעון של מערכת הקבצים.
    final oldest = await fetch('1.bin', 40);
    File(oldest.path).setLastModifiedSync(DateTime(2026, 1, 1));
    final middle = await fetch('2.bin', 40);
    File(middle.path).setLastModifiedSync(DateTime(2026, 1, 2));
    final newest = await fetch('3.bin', 40);

    expect(File(oldest.path).existsSync(), isFalse);
    expect(File(middle.path).existsSync(), isTrue);
    expect(File(newest.path).existsSync(), isTrue);
  });

  test('הורדה שעדיין רצה נספרת במכסה אך אינה מפונה', () async {
    final running = Directory(p.join(cache.root.path, 'p1', 'running'))
      ..createSync(recursive: true);
    File(
      p.join(running.path, PluginFileDownloadService.partialFileName),
    ).writeAsBytesSync(List.filled(90, 1));
    final done = await fetch('1.bin', 40);
    File(done.path).setLastModifiedSync(DateTime(2026, 1, 2));
    final newest = await fetch('2.bin', 40);

    expect(running.existsSync(), isTrue);
    expect(File(done.path).existsSync(), isFalse);
    expect(File(newest.path).existsSync(), isTrue);
  });

  test('שם סופי שנגמר ב-.part אינו מתחזה להורדה שרצה', () async {
    final first = await fetch('big.part', 90);
    File(first.path).setLastModifiedSync(DateTime(2026, 1, 1));
    await fetch('2.bin', 40);

    expect(File(first.path).existsSync(), isFalse);
  });

  test('תקרת הורדות מקבילות לתוסף, ומתפנה עם סיום הורדה', () async {
    final gate = Completer<void>();
    final slow = PluginFileDownloadService(
      client: MockClient.streaming((request, _) async {
        Stream<List<int>> body() async* {
          await gate.future;
          yield [1];
        }

        return http.StreamedResponse(body(), 200);
      }),
    );
    final running = [
      for (
        var i = 0;
        i < PluginRemoteFileCache.maxConcurrentFetchesPerPlugin;
        i++
      )
        fetch('$i.bin', 1, downloader: slow),
    ];
    await Future<void>.delayed(const Duration(milliseconds: 20));

    await expectLater(
      fetch('extra.bin', 1),
      throwsA(
        isA<Exception>().having(
          (e) => e.toString(),
          'message',
          contains('error.too_many_requests'),
        ),
      ),
    );
    // תוסף אחר אינו מושפע.
    await fetch('other.bin', 1, pluginId: 'p2');

    gate.complete();
    await Future.wait(running);
    await fetch('after.bin', 1);
  });

  test('מזהה ריק או של נקודות בלבד אינו יוצא משורש המטמון', () async {
    final outside = File(p.join(tempDir.path, 'keep.txt'))
      ..writeAsStringSync('x');
    final file = await fetch('a.bin', 5, pluginId: '..');
    final blank = await fetch('b.bin', 5, pluginId: '');

    expect(cache.owns(file.path), isTrue);
    expect(p.isWithin(cache.root.path, file.path), isTrue);
    await cache.deleteForPlugin('..');
    await cache.deleteForPlugin('');

    expect(File(file.path).existsSync(), isFalse);
    expect(File(blank.path).existsSync(), isFalse);
    expect(outside.existsSync(), isTrue);
    expect(cache.root.existsSync(), isTrue);
  });

  test('המכסה היא לכל תוסף: הורדה של תוסף אחר אינה מפנה', () async {
    final mine = await fetch('1.bin', 90, pluginId: 'p1');
    final other = await fetch('2.bin', 90, pluginId: 'p2');

    expect(File(mine.path).existsSync(), isTrue);
    expect(File(other.path).existsSync(), isTrue);
  });

  test('כשל מוחק את תיקיית ההורדה ואינו משאיר דבר', () async {
    final failing = PluginFileDownloadService(
      client: MockClient((_) async => http.Response('nope', 404)),
    );

    await expectLater(fetch('x.pdf', 1, downloader: failing), throwsException);
    expect(leftovers('p1'), isEmpty, reason: 'אין תיקיית הורדה יתומה');
    expect(
      Directory(p.join(cache.root.path, 'p1')).existsSync(),
      isFalse,
      reason: 'גם תיקיית התוסף הריקה נמחקת',
    );
  });

  test(
    'timeout מחזיר TimeoutException ומנקה גם כשההורדה מסיימת אחריו',
    () async {
      final slow = PluginFileDownloadService(
        client: MockClient.streaming((request, _) async {
          Stream<List<int>> body() async* {
            await Future<void>.delayed(const Duration(milliseconds: 300));
            yield [1, 2, 3];
          }

          return http.StreamedResponse(body(), 200);
        }),
      );

      await expectLater(
        fetch(
          's.bin',
          1,
          downloader: slow,
          timeout: const Duration(milliseconds: 50),
        ),
        throwsA(isA<TimeoutException>()),
      );
      await waitForCleanup('p1');
      expect(leftovers('p1'), isEmpty);
    },
  );

  test(
    'timeout מחזיר RPC גם כש-send אינו בר ביטול ושומר את חסם ההורדות',
    () async {
      final headers = Completer<void>();
      final cancellations = <Future<void>>[];
      final downloader = PluginFileDownloadService(
        client: MockClient.streaming((_, _) async {
          final cancelled = Completer<void>();
          cancellations.add(cancelled.future);
          late StreamController<List<int>> body;
          body = StreamController<List<int>>(
            onListen: () {
              body.add([1]);
              unawaited(body.close());
            },
            onCancel: () {
              if (!cancelled.isCompleted) cancelled.complete();
            },
          );
          await headers.future;
          return http.StreamedResponse(body.stream, 200);
        }),
      );
      try {
        for (var i = 0; i < 3; i++) {
          await expectLater(
            fetch(
              'pending.bin',
              1,
              downloader: downloader,
              timeout: const Duration(milliseconds: 25),
            ),
            throwsA(isA<TimeoutException>()),
          ).timeout(const Duration(milliseconds: 200));
        }
        await expectLater(
          fetch('fourth.bin', 1),
          throwsA(
            isA<Exception>().having(
              (e) => e.toString(),
              'message',
              contains('error.too_many_requests'),
            ),
          ),
        );
      } finally {
        headers.complete();
        await Future.wait(cancellations).timeout(const Duration(seconds: 2));
        await waitForCleanup('p1');
        downloader.dispose();
      }
      await fetch('after.bin', 1);
    },
  );

  for (final phase in ['headers', 'redirect', 'error', 'body']) {
    for (final revoke in [
      false,
      if (phase == 'headers' || phase == 'body') true,
    ]) {
      test(
        '${revoke ? 'revoke' : 'timeout'} מבטל חיבור אמיתי בזמן $phase ומשחרר את המכסה',
        () async {
          final server = await ServerSocket.bind(
            InternetAddress.loopbackIPv4,
            0,
          );
          var receivedRequest = Completer<void>();
          final downloader = PluginFileDownloadService(
            client: _ObservedClient(() {
              if (phase != 'headers' && !receivedRequest.isCompleted) {
                receivedRequest.complete();
              }
            }),
          );
          final sockets = <Socket>{};
          final disconnected = <Future<void>>[];
          var requests = 0;
          server.listen((socket) {
            sockets.add(socket);
            final done = Completer<void>();
            disconnected.add(done.future);
            void disconnect() {
              sockets.remove(socket);
              socket.destroy();
              if (!done.isCompleted) done.complete();
            }

            void onError(Object error) {
              expect(error, isA<SocketException>());
              disconnect();
            }

            unawaited(socket.done.then<void>((_) {}, onError: onError));
            var received = false;
            socket.listen(
              (_) {
                if (received) return;
                received = true;
                requests++;
                if (phase == 'headers' && !receivedRequest.isCompleted) {
                  receivedRequest.complete();
                }
                if (phase == 'headers') return;
                final status = switch (phase) {
                  'redirect' => '302 Found',
                  'error' => '404 Not Found',
                  _ => '200 OK',
                };
                socket.write(
                  'HTTP/1.1 $status\r\nTransfer-Encoding: chunked\r\n'
                  '${phase == 'redirect' ? 'Location: /final.pdf\r\n' : ''}'
                  '\r\n1\r\nx\r\n',
                );
              },
              onDone: disconnect,
              onError: onError,
            );
          });
          addTearDown(() async {
            downloader.dispose();
            for (final socket in List.of(sockets)) {
              socket.destroy();
            }
            await server.close();
          });

          const requestTimeout = Duration(milliseconds: 60);
          final clock = FakeAsync();
          final timeoutZone = clock.run((_) => Zone.current);
          for (var i = 0; i < 4; i++) {
            receivedRequest = Completer<void>();
            // רק מועד ה-timeout נשלט. החיבור, הזרם והקבצים נשארים אמיתיים.
            final running = runZoned(
              () => cache.fetch(
                'p1',
                Uri.parse('http://127.0.0.1:${server.port}/slow.pdf'),
                downloader: downloader,
                isAllowed: allowAll,
                timeout: requestTimeout,
              ),
              zoneSpecification: ZoneSpecification(
                createTimer: (self, parent, zone, duration, callback) =>
                    duration == requestTimeout
                    ? timeoutZone.createTimer(duration, callback)
                    : parent.createTimer(zone, duration, callback),
              ),
            );
            final failed = expectLater(
              running,
              revoke
                  ? throwsA(
                      isA<Exception>().having(
                        (e) => e.toString(),
                        'message',
                        contains('error.unavailable'),
                      ),
                    )
                  : throwsA(isA<TimeoutException>()),
            );
            await receivedRequest.future;
            if (revoke) {
              await cache.deleteForPlugin('p1');
            } else {
              // עומס CI לא יכול לגרום לביטול לפני השלב שהטסט בודק.
              clock.elapse(requestTimeout);
            }
            await failed;
            await disconnected.last;
            await waitForCleanup('p1');
          }
          await Future.wait(disconnected);
          expect(requests, 4);
          expect(sockets, isEmpty);
          await waitForCleanup('p1');
          expect(leftovers('p1'), isEmpty);
          await fetch('after.bin', 1);
        },
      );
    }
  }

  for (final limit in ['bytes', 'files']) {
    test('פינוי שנחסם אינו עוקף את מכסת $limit', () async {
      cache = PluginRemoteFileCache(
        root: cache.root,
        quotaBytes: 100,
        maxFiles: 1,
      );
      final first = await fetch('locked.bin', limit == 'bytes' ? 100 : 0);
      final locked = await Process.run('chflags', ['uchg', first.path]);
      expect(locked.exitCode, 0);
      try {
        await expectLater(
          fetch('extra.bin', 1),
          throwsA(
            isA<Exception>().having(
              (e) => e.toString(),
              'message',
              contains('error.too_many_requests'),
            ),
          ),
        );
        expect(File(first.path).existsSync(), isTrue);
        expect(leftovers('p1'), hasLength(1));
      } finally {
        await Process.run('chflags', ['nouchg', first.path]);
      }
    }, skip: !Platform.isMacOS);
  }

  test('delete מוחק רק קובץ שהמטמון הוריד', () async {
    final file = await fetch('a.pdf', 10);
    final outside = File(p.join(tempDir.path, 'keep.txt'))
      ..writeAsStringSync('x');

    await cache.delete(outside.path);
    expect(outside.existsSync(), isTrue);

    await cache.delete(file.path);
    expect(File(file.path).existsSync(), isFalse);
    expect(File(file.path).parent.existsSync(), isFalse);
  });

  test('delete מסיר את תיקיית ההורדה ואת תיקיית התוסף כשהתרוקנה', () async {
    final only = await fetch('1.bin', 5);
    final pluginDir = Directory(p.join(cache.root.path, 'p1'));

    await cache.delete(only.path);
    expect(pluginDir.existsSync(), isFalse);

    // עם הורדה נוספת — תיקיית התוסף נשארת.
    final first = await fetch('1.bin', 5);
    final second = await fetch('2.bin', 5);
    await cache.delete(first.path);
    expect(pluginDir.existsSync(), isTrue);
    expect(File(second.path).existsSync(), isTrue);
    expect(pluginDir.listSync(), hasLength(1));
  });

  test('פינוי מהמכסה אינו משאיר תיקיות ריקות', () async {
    final oldest = await fetch('1.bin', 60);
    File(oldest.path).setLastModifiedSync(DateTime(2026, 1, 1));
    await fetch('2.bin', 60);

    final dirs = Directory(p.join(cache.root.path, 'p1')).listSync();
    expect(dirs, hasLength(1));
    expect((dirs.single as Directory).listSync(), hasLength(1));
  });

  test('הניקוי הראשוני מסיר תיקיות ריקות (לא צעירות מדי) ותוסף ריק', () async {
    final emptyDownload = Directory(p.join(cache.root.path, 'gone', 'empty'))
      ..createSync(recursive: true);
    final fresh = Directory(p.join(cache.root.path, 'p1', 'fresh'))
      ..createSync(recursive: true);

    // עם ברירת המחדל התיקייה הריקה הטרייה נשמרת: אולי הורדה שזה עתה התחילה.
    await fetch('a.bin', 1);
    expect(fresh.existsSync(), isTrue);
    expect(emptyDownload.existsSync(), isTrue);

    final strict = PluginRemoteFileCache(
      root: cache.root,
      emptyDirGrace: Duration.zero,
    );
    await strict.fetch(
      'p1',
      Uri.parse('https://example.org/b.bin'),
      downloader: serving([1]),
      isAllowed: allowAll,
    );

    expect(fresh.existsSync(), isFalse);
    expect(emptyDownload.existsSync(), isFalse);
    expect(emptyDownload.parent.existsSync(), isFalse);
  });

  test('deleteForPlugin מוחק את התוסף בלבד', () async {
    final mine = await fetch('1.bin', 10, pluginId: 'p1');
    final other = await fetch('2.bin', 10, pluginId: 'p2');

    await cache.deleteForPlugin('p1');

    expect(File(mine.path).existsSync(), isFalse);
    expect(File(other.path).existsSync(), isTrue);
  });

  test('בהורדה הראשונה נמחקות הורדות ישנות, ורק הן', () async {
    final stale = Directory(p.join(cache.root.path, 'p1', 'old'))
      ..createSync(recursive: true);
    File(p.join(stale.path, 'a.pdf')).writeAsStringSync('x');
    await Future<void>.delayed(const Duration(milliseconds: 400));
    final recent = Directory(p.join(cache.root.path, 'p1', 'recent'))
      ..createSync(recursive: true);
    File(p.join(recent.path, 'b.pdf')).writeAsStringSync('x');

    final aging = PluginRemoteFileCache(
      root: cache.root,
      staleAfter: const Duration(milliseconds: 300),
    );
    await aging.fetch(
      'p1',
      Uri.parse('https://example.org/c.bin'),
      downloader: serving([1]),
      isAllowed: allowAll,
    );

    expect(stale.existsSync(), isFalse);
    expect(recent.existsSync(), isTrue);
  });
}
