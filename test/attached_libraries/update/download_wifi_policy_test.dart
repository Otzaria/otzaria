import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/attached_libraries/models/attached_update_manifest.dart';
import 'package:otzaria/attached_libraries/repository/update/attached_update_downloader.dart';
import 'package:otzaria/attached_libraries/repository/update/attached_update_fetcher.dart';
import 'package:otzaria/attached_libraries/repository/update/attached_update_host_policy.dart';
import 'package:otzaria/core/download_network_policy.dart';

void main() {
  late HttpServer server;
  late Directory directory;
  late DownloadNetworkPolicy savedPolicy;
  late DownloadNetworkPolicy policy;
  late StreamController<bool> network;
  final bytes = List<int>.generate(256 * 1024, (i) => i % 251);
  late List<String?> ranges;

  setUp(() async {
    ranges = [];
    directory = await Directory.systemTemp.createTemp('attached-wifi-test-');
    savedPolicy = DownloadNetworkPolicy.instance;
    network = StreamController<bool>.broadcast(sync: true);
    policy = DownloadNetworkPolicy(
      isAndroid: true,
      wifiOnlyReader: () => true,
      wifiChanges: () => network.stream,
    );
    DownloadNetworkPolicy.instance = policy;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) {
      unawaited(
        () async {
          final range = request.headers.value(HttpHeaders.rangeHeader);
          ranges.add(range);
          final start = range == null
              ? 0
              : int.parse(RegExp(r'bytes=(\d+)-').firstMatch(range)!.group(1)!);
          request.response.contentLength = bytes.length - start;
          if (start > 0) {
            request.response.statusCode = HttpStatus.partialContent;
            request.response.headers.set(
              HttpHeaders.contentRangeHeader,
              'bytes $start-${bytes.length - 1}/${bytes.length}',
            );
          }
          for (var offset = start; offset < bytes.length; offset += 4096) {
            request.response.add(
              bytes.sublist(offset, (offset + 4096).clamp(0, bytes.length)),
            );
            await request.response.flush();
            await Future<void>.delayed(const Duration(milliseconds: 5));
          }
          await request.response.close();
        }().catchError((Object _) {}),
      );
    });
  });
  tearDown(() async {
    DownloadNetworkPolicy.instance = savedPolicy;
    await policy.dispose();
    await network.close();
    await server.close(force: true);
    await directory.delete(recursive: true);
  });

  Future<void> wifi(bool available) async {
    final ready = policy.refresh();
    network.add(available);
    await ready;
  }

  AttachedUpdateArtifact artifact() => AttachedUpdateArtifact(
    compression: AttachedUpdateCompression.none,
    size: bytes.length,
    sha256: sha256.convert(bytes).toString(),
    parts: [
      AttachedUpdatePart(
        url: 'http://127.0.0.1:${server.port}/asset.bin',
        size: bytes.length,
        sha256: sha256.convert(bytes).toString(),
      ),
    ],
  );
  AttachedUpdateDownloader downloader() => AttachedUpdateDownloader(
    fetcher: AttachedUpdateFetcher(
      policy: AttachedUpdateHostPolicy.allowLoopbackForTesting({server.port}),
    ),
    certificates: () async => const [],
    progressInterval: Duration.zero,
  );

  test('התחלה בסלולר ממתינה וניתנת לביטול לפני יצירת worker', () async {
    await wifi(false);
    final waiting = Completer<void>();
    final cancel = AttachedUpdateCancelToken();
    final future = downloader().download(
      artifact(),
      combinedPath: '${directory.path}/combined',
      outputPath: '${directory.path}/out',
      cancel: cancel,
      onWaitingForWifi: () => waiting.complete(),
    );
    final expectation = expectLater(
      future,
      throwsA(isA<AttachedUpdateCancelled>()),
    );
    await waiting.future;
    expect(ranges, isEmpty);
    cancel.cancel();
    await expectation;
    expect(ranges, isEmpty);
  });

  test('שינוי רשת מגיע ל־worker, משמר חלקי ומתחדש אחרי WiFi', () async {
    await wifi(true);
    final waiting = Completer<void>();
    var interrupted = false;
    final combined = '${directory.path}/combined';
    final output = '${directory.path}/out';
    final future = downloader().download(
      artifact(),
      combinedPath: combined,
      outputPath: output,
      onProgress: (received, total) {
        if (!interrupted && received > 0 && received < total) {
          interrupted = true;
          network.add(false);
        }
      },
      onWaitingForWifi: () {
        if (!waiting.isCompleted) waiting.complete();
      },
    );
    await waiting.future;
    final partial = await File(combined).length();
    expect(partial, greaterThan(0));
    expect(partial, lessThan(bytes.length));
    network.add(true);
    await future;
    expect(await File(output).readAsBytes(), bytes);
    expect(ranges.length, 2);
    expect(ranges.last, startsWith('bytes=$partial-'));
  });

  test(
    'מעבר לסלולר בזמן הרכבה מקומית אינו מפעיל הורדה או apply מחדש',
    () async {
      await wifi(true);
      var changed = false;
      final output = '${directory.path}/out';
      await downloader().download(
        artifact(),
        combinedPath: '${directory.path}/combined',
        outputPath: output,
        onExtractionProgress: (_, _) {
          if (!changed) {
            changed = true;
            network.add(false);
          }
        },
      );
      expect(changed, isTrue);
      expect(await File(output).readAsBytes(), bytes);
      expect(ranges.length, 1);
      expect(policy.status, DownloadNetworkStatus.waitingForWifi);
    },
  );
}
