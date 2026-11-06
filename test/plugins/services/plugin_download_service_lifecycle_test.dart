import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:http/testing.dart';
import 'package:otzaria/core/http_client_registry.dart';
import 'package:otzaria/plugins/services/plugin_download_service.dart';

class _RecordingClient extends MockClient {
  _RecordingClient({this.throwOnClose = false})
    : super((_) async => http.Response('archive', 200));

  final bool throwOnClose;
  int closeCount = 0;

  @override
  void close() {
    closeCount++;
    super.close();
    if (throwOnClose) throw StateError('close failed');
  }
}

class _BodyObservingClient extends http.BaseClient {
  _BodyObservingClient(this.onDownloadBody);

  final void Function() onDownloadBody;
  final _inner = IOClient();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final response = await _inner.send(request);
    return http.StreamedResponse(
      response.stream.map((chunk) {
        if (request.url.path != '/other') onDownloadBody();
        return chunk;
      }),
      response.statusCode,
      headers: response.headers,
      contentLength: response.contentLength,
    );
  }

  @override
  void close() => _inner.close();
}

class _FailingCleanupDirectory implements Directory {
  _FailingCleanupDirectory(this.directory, this.failure);

  final Directory directory;
  final FileSystemException failure;

  @override
  String get path => directory.path;

  @override
  Future<bool> exists() => directory.exists();

  @override
  Future<Directory> createTemp([String? prefix]) async =>
      _FailingCleanupDirectory(await directory.createTemp(prefix), failure);

  @override
  Future<Directory> delete({bool recursive = false}) => Future.error(failure);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _DeferredTempDirectory implements Directory {
  _DeferredTempDirectory(this.directory, {this.failure});

  final Directory directory;
  final FileSystemException? failure;
  final creating = Completer<void>();
  final release = Completer<void>();

  @override
  Future<Directory> createTemp([String? prefix]) async {
    creating.complete();
    await release.future;
    if (failure != null) throw failure!;
    return directory.createTemp(prefix);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<({Uri uri, Future<void> disconnected})> _servePendingDownload() async {
  final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final peers = <Socket>[];
  final disconnected = Completer<void>();
  addTearDown(() async {
    for (final peer in peers) {
      peer.destroy();
    }
    await server.close();
  });
  server.listen((socket) {
    peers.add(socket);
    final request = StringBuffer();
    var replied = false;
    var download = false;
    void closed() {
      if (download && !disconnected.isCompleted) disconnected.complete();
      socket.destroy();
    }

    Future<void> respond() async {
      try {
        if (download) {
          socket.write('HTTP/1.1 200 OK\r\nContent-Length: 100000\r\n\r\nx');
          await socket.flush();
        } else {
          socket.write(
            'HTTP/1.1 200 OK\r\nContent-Length: 15\r\n'
            'Connection: close\r\n\r\nstill connected',
          );
          await socket.flush();
          await socket.close();
        }
      } on SocketException {
        closed();
      }
    }

    socket.listen(
      (bytes) {
        if (replied) return;
        request.write(String.fromCharCodes(bytes));
        if (!request.toString().contains('\r\n\r\n')) return;
        replied = true;
        download = !request.toString().startsWith('GET /other ');
        unawaited(respond());
      },
      onDone: closed,
      onError: (Object _) => closed(),
    );
  });
  return (
    uri: Uri.parse('http://127.0.0.1:${server.port}/plugin.otzplugin'),
    disconnected: disconnected.future,
  );
}

Future<HttpServer> _serve(void Function(HttpRequest) handle) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen(handle);
  addTearDown(() => server.close(force: true));
  return server;
}

Uri _uri(HttpServer server, [String path = '/plugin.otzplugin']) =>
    Uri.parse('http://127.0.0.1:${server.port}$path');

int? _descriptorCount(String targetPrefix) {
  if (!Platform.isLinux) return null;
  final directory = Directory('/proc/self/fd');
  if (!directory.existsSync()) return null;
  return directory.listSync(followLinks: false).whereType<Link>().where((link) {
    try {
      return link.targetSync().startsWith(targetPrefix);
    } on FileSystemException {
      return false;
    }
  }).length;
}

void main() {
  late Directory downloads;
  late int registryBefore;

  setUp(() async {
    registryBefore = HttpClientRegistry.registeredCount;
    downloads = await Directory.systemTemp.createTemp('plugin_lifecycle_test_');
  });

  tearDown(() async {
    // Deleting an archive is not enough on Unix: a leaked IOSink can keep its
    // native file descriptor alive even after the path has been removed.
    final openFiles = _descriptorCount(
      '${downloads.path}${Platform.pathSeparator}',
    );
    if (openFiles != null) expect(openFiles, 0);
    await downloads.delete(recursive: true);
    expect(HttpClientRegistry.registeredCount, registryBefore);
  });

  Future<T> inDownloads<T>(Future<T> Function() body) =>
      IOOverrides.runZoned(body, getSystemTempDirectory: () => downloads);

  test('owned client unregisters and closes exactly once', () async {
    final client = _RecordingClient();
    final service = http.runWithClient(PluginDownloadService.new, () => client);
    addTearDown(service.dispose);

    expect(HttpClientRegistry.registeredCount, registryBefore + 1);
    service.dispose();
    service.dispose();

    expect(HttpClientRegistry.registeredCount, registryBefore);
    expect(client.closeCount, 1);
    await expectLater(
      service.downloadPluginArchive(Uri.parse('https://example.com/plugin')),
      throwsStateError,
    );
  });

  test('injected client is neither registered nor closed', () async {
    final client = _RecordingClient();
    addTearDown(client.close);
    final service = PluginDownloadService(client: client);
    addTearDown(service.dispose);

    expect(HttpClientRegistry.registeredCount, registryBefore);
    await HttpClientRegistry.closeAll();
    service.dispose();
    service.dispose();

    expect(client.closeCount, 0);
    expect(
      (await client.get(Uri.parse('https://example.com/other'))).body,
      'archive',
    );
  });

  test(
    'registry shutdown retires the service and removes its callback',
    () async {
      final client = _RecordingClient();
      final service = http.runWithClient(
        PluginDownloadService.new,
        () => client,
      );
      addTearDown(service.dispose);

      await HttpClientRegistry.closeAll();
      await HttpClientRegistry.closeAll();
      service.dispose();

      expect(client.closeCount, 1);
      expect(HttpClientRegistry.registeredCount, registryBefore);
      await expectLater(
        service.downloadPluginArchive(Uri.parse('https://example.com/plugin')),
        throwsStateError,
      );
    },
  );

  test('a failing client close still unregisters the service', () {
    final client = _RecordingClient(throwOnClose: true);
    final service = http.runWithClient(PluginDownloadService.new, () => client);

    expect(service.dispose, throwsStateError);
    expect(HttpClientRegistry.registeredCount, registryBefore);
    service.dispose();
    expect(client.closeCount, 1);
  });

  test('each finished download releases its abort listeners', () async {
    final signals = <Future<void>>[];
    final client = MockClient.streaming((request, _) async {
      expect(request, isA<http.AbortableRequest>());
      signals.add((request as http.AbortableRequest).abortTrigger!);
      return http.StreamedResponse(Stream.value([1, 2, 3]), 200);
    });
    addTearDown(client.close);
    final service = PluginDownloadService(client: client);
    addTearDown(service.dispose);

    await inDownloads(() async {
      for (var cycle = 0; cycle < 30; cycle++) {
        final path = await service.downloadPluginArchive(
          Uri.parse('https://example.com/plugin'),
        );
        expect(await File(path).readAsBytes(), [1, 2, 3]);
        await signals.last.timeout(const Duration(seconds: 2));
        await service.cleanupDownloadedArchive(path);
      }
    });

    expect(signals, hasLength(30));
    expect(await downloads.list().isEmpty, isTrue);
  });

  test('HTTP rejection cancels an otherwise unconsumed body', () async {
    final cancelled = Completer<void>();
    final body = StreamController<List<int>>(onCancel: cancelled.complete);
    addTearDown(body.close);
    final client = MockClient.streaming((_, _) async {
      return http.StreamedResponse(body.stream, 500);
    });
    addTearDown(client.close);
    final service = PluginDownloadService(client: client);
    addTearDown(service.dispose);

    await expectLater(
      service.downloadPluginArchive(Uri.parse('https://example.com/plugin')),
      throwsException,
    );
    await cancelled.future.timeout(const Duration(seconds: 2));
    expect(await downloads.list().isEmpty, isTrue);
  });

  test('a response arriving after the header timeout is cancelled', () async {
    final response = Completer<http.StreamedResponse>();
    final cancelled = Completer<void>();
    final body = StreamController<List<int>>(onCancel: cancelled.complete);
    addTearDown(body.close);
    final client = MockClient.streaming((_, _) => response.future);
    addTearDown(client.close);
    final service = PluginDownloadService(
      client: client,
      stallTimeout: const Duration(milliseconds: 20),
    );
    addTearDown(service.dispose);

    await expectLater(
      service.downloadPluginArchive(Uri.parse('https://example.com/plugin')),
      throwsA(isA<TimeoutException>()),
    );
    response.complete(http.StreamedResponse(body.stream, 200));
    await cancelled.future.timeout(const Duration(seconds: 2));
  });

  test('file creation failure removes its temporary directory', () async {
    final client = MockClient((_) async => http.Response('archive', 200));
    addTearDown(client.close);
    final service = PluginDownloadService(client: client);
    addTearDown(service.dispose);

    await inDownloads(() async {
      await expectLater(
        service.downloadPluginArchive(
          Uri.parse('https://example.com/${'a' * 400}'),
        ),
        throwsA(isA<FileSystemException>()),
      );
    });
    expect(await downloads.list().isEmpty, isTrue);
  });

  test(
    'a body failure preserves its cause and removes the partial file',
    () async {
      final failure = StateError('body failed');
      final client = MockClient.streaming((_, _) async {
        Stream<List<int>> body() async* {
          yield [1, 2, 3];
          throw failure;
        }

        return http.StreamedResponse(body(), 200);
      });
      addTearDown(client.close);
      final service = PluginDownloadService(client: client);
      addTearDown(service.dispose);

      await inDownloads(() async {
        await expectLater(
          service.downloadPluginArchive(
            Uri.parse('https://example.com/plugin'),
          ),
          throwsA(same(failure)),
        );
      });
      expect(await downloads.list().isEmpty, isTrue);
    },
  );

  test(
    'disposal does not disguise a temporary-directory cleanup failure',
    () async {
      const failure = FileSystemException('cleanup denied');
      late final PluginDownloadService service;
      final client = MockClient.streaming((_, _) async {
        Stream<List<int>> body() async* {
          yield [1, 2, 3];
          service.dispose();
          throw http.ClientException('connection closed');
        }

        return http.StreamedResponse(body(), 200);
      });
      addTearDown(client.close);
      service = PluginDownloadService(client: client);
      addTearDown(service.dispose);

      await IOOverrides.runZoned(
        () => expectLater(
          service.downloadPluginArchive(
            Uri.parse('https://example.com/plugin'),
          ),
          throwsA(same(failure)),
        ),
        getSystemTempDirectory: () =>
            _FailingCleanupDirectory(downloads, failure),
      );
      expect(await downloads.list().isEmpty, isFalse);
    },
  );

  test('dispose aborts a real request waiting for response headers', () async {
    final received = Completer<void>();
    final server = await _serve((_) => received.complete());
    final service = PluginDownloadService();
    addTearDown(service.dispose);

    await inDownloads(() async {
      final result = service.downloadPluginArchive(_uri(server));
      final aborted = expectLater(
        result,
        throwsA(isA<http.RequestAbortedException>()),
      );
      await received.future.timeout(const Duration(seconds: 5));
      service.dispose();
      await aborted.timeout(const Duration(seconds: 5));
    });

    expect(HttpClientRegistry.registeredCount, registryBefore);
    expect(await downloads.list().isEmpty, isTrue);
  });

  test('dispose cancels only its download on a shared HTTP client', () async {
    final downloadSent = Completer<void>();
    final downloadRead = Completer<void>();
    final otherReceived = Completer<HttpRequest>();
    final server = await _serve((request) async {
      if (request.uri.path == '/other') {
        otherReceived.complete(request);
        return;
      }
      request.response.bufferOutput = false;
      request.response.add(List.filled(8192, 1));
      await request.response.flush();
      downloadSent.complete();
    });
    final client = _BodyObservingClient(() {
      if (!downloadRead.isCompleted) downloadRead.complete();
    });
    addTearDown(client.close);
    final service = PluginDownloadService(client: client);
    addTearDown(service.dispose);

    await inDownloads(() async {
      final result = service.downloadPluginArchive(_uri(server));
      final aborted = expectLater(
        result,
        throwsA(isA<http.RequestAbortedException>()),
      );
      final other = client.get(_uri(server, '/other'));
      await downloadSent.future.timeout(
        const Duration(seconds: 5),
        onTimeout: () =>
            throw TimeoutException('server did not flush download'),
      );
      await downloadRead.future.timeout(
        const Duration(seconds: 5),
        onTimeout: () => throw TimeoutException('client did not read download'),
      );
      expect(await downloads.list().length, 1);
      final otherRequest = await otherReceived.future.timeout(
        const Duration(seconds: 5),
        onTimeout: () => throw TimeoutException('other request not received'),
      );
      service.dispose();
      await aborted.timeout(
        const Duration(seconds: 5),
        onTimeout: () => throw TimeoutException('download did not abort'),
      );
      otherRequest.response.write('still connected');
      await otherRequest.response.close();
      expect((await other).body, 'still connected');
    });

    expect(HttpClientRegistry.registeredCount, registryBefore);
    expect(await downloads.list().isEmpty, isTrue);
  });

  for (final failCreate in [false, true]) {
    test(
      failCreate
          ? 'temporary directory creation failure closes an unread response'
          : 'dispose before the file is ready closes only its response',
      () async {
        final failure = FileSystemException('cannot create directory');
        final deferred = _DeferredTempDirectory(
          downloads,
          failure: failCreate ? failure : null,
        );
        final server = await _servePendingDownload();
        final client = IOClient();
        addTearDown(client.close);
        final service = PluginDownloadService(client: client);
        addTearDown(service.dispose);
        final result = IOOverrides.runZoned(
          () => service.downloadPluginArchive(server.uri),
          getSystemTempDirectory: () => deferred,
        );
        final failed = expectLater(
          result,
          throwsA(
            failCreate ? same(failure) : isA<http.RequestAbortedException>(),
          ),
        );
        try {
          await deferred.creating.future.timeout(const Duration(seconds: 5));
          if (failCreate) {
            deferred.release.complete();
          } else {
            service.dispose();
          }
          // The peer must disconnect before the blocked mkdir is released,
          // without closing the caller's client to free the connection.
          await server.disconnected.timeout(const Duration(seconds: 5));
          final other = await client
              .get(server.uri.resolve('/other'))
              .timeout(const Duration(seconds: 5));
          expect(other.body, 'still connected');
        } finally {
          if (!deferred.release.isCompleted) deferred.release.complete();
          await failed.timeout(const Duration(seconds: 5));
        }
        expect(await downloads.list().isEmpty, isTrue);
      },
    );
  }

  test(
    'dispose aborts all concurrent downloads owned by the service',
    () async {
      final received = Completer<void>();
      var requests = 0;
      final server = await _serve((request) async {
        request.response.add([1, 2, 3]);
        await request.response.flush();
        if (++requests == 2) received.complete();
      });
      final service = PluginDownloadService();
      addTearDown(service.dispose);

      await inDownloads(() async {
        final aborted = [
          for (var index = 0; index < 2; index++)
            expectLater(
              service.downloadPluginArchive(_uri(server, '/plugin-$index')),
              throwsA(isA<http.RequestAbortedException>()),
            ),
        ];
        await received.future.timeout(const Duration(seconds: 5));
        service.dispose();
        await Future.wait(aborted).timeout(const Duration(seconds: 5));
      });

      expect(HttpClientRegistry.registeredCount, registryBefore);
      expect(await downloads.list().isEmpty, isTrue);
    },
  );

  test(
    '30 real client lifetimes release sockets, callbacks and temp files',
    () async {
      final payload = List.filled(65536, 42);
      final server = await _serve((request) {
        request.response.add(payload);
        unawaited(request.response.close());
      });

      await inDownloads(() async {
        Future<void> cycle() async {
          final service = PluginDownloadService();
          try {
            final path = await service.downloadPluginArchive(_uri(server));
            expect(await File(path).readAsBytes(), payload);
            await service.cleanupDownloadedArchive(path);
          } finally {
            service.dispose();
          }
        }

        await cycle();
        await pumpEventQueue();
        final before = _descriptorCount('socket:');
        for (var index = 0; index < 30; index++) {
          await cycle();
          expect(HttpClientRegistry.registeredCount, registryBefore);
        }
        await pumpEventQueue();
        if (before != null) {
          var after = _descriptorCount('socket:');
          // pumpEventQueue does not wait for server-side I/O to close.
          final closeWait = Stopwatch()..start();
          while (after != null &&
              after > before &&
              closeWait.elapsed < const Duration(seconds: 2)) {
            await Future<void>.delayed(const Duration(milliseconds: 20));
            after = _descriptorCount('socket:');
          }
          expect(after, lessThanOrEqualTo(before));
        }
      });

      expect(await downloads.list().isEmpty, isTrue);
    },
  );
}
