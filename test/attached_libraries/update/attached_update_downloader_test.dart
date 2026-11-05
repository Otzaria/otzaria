import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/attached_libraries/models/attached_update_manifest.dart';
import 'package:otzaria/attached_libraries/repository/update/attached_update_downloader.dart';
import 'package:otzaria/attached_libraries/repository/update/attached_update_fetcher.dart';
import 'package:otzaria/attached_libraries/repository/update/attached_update_host_policy.dart';
import 'package:path/path.dart' as p;

/// The worker isolate end to end: real HTTP on loopback, cancellation through
/// the control port, and assembly with the final sha256.
void main() {
  late HttpServer server;
  late Directory temp;
  final bodies = <String, List<int>>{};
  var stall = false;

  setUp(() async {
    stall = false;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final body = bodies[request.uri.path]!;
      request.response.contentLength = body.length;
      if (stall) {
        request.response.add(body.sublist(0, 1));
        await request.response.flush();
        await Future<void>.delayed(const Duration(seconds: 20));
        return;
      }
      request.response.add(body);
      await request.response.close();
    });
    temp = await Directory.systemTemp.createTemp('otzaria_upd_worker');
  });

  tearDown(() async {
    await server.close(force: true);
    try {
      await temp.delete(recursive: true);
    } catch (_) {}
  });

  AttachedUpdateArtifact artifact(List<List<int>> parts) {
    final all = [for (final part in parts) ...part];
    return AttachedUpdateArtifact(
      compression: AttachedUpdateCompression.none,
      size: all.length,
      sha256: sha256.convert(all).toString(),
      parts: [
        for (final (i, part) in parts.indexed)
          AttachedUpdatePart(
            url: 'http://127.0.0.1:${server.port}/p$i',
            size: part.length,
            sha256: sha256.convert(part).toString(),
          ),
      ],
    );
  }

  AttachedUpdateDownloader downloader() => AttachedUpdateDownloader(
    fetcher: AttachedUpdateFetcher(
      policy: AttachedUpdateHostPolicy.allowLoopbackForTesting({server.port}),
      readTimeout: const Duration(seconds: 10),
    ),
    certificates: () async => const [],
  );

  test('downloads the parts in an isolate and assembles the file', () async {
    final parts = [
      List.generate(70000, (i) => i % 251),
      List.generate(1000, (i) => i % 7),
    ];
    for (final (i, part) in parts.indexed) {
      bodies['/p$i'] = part;
    }
    final output = p.join(temp.path, 'out.db');
    final progress = <(int, int)>[];
    final extractionProgress = <(int, int)>[];
    await downloader().download(
      artifact(parts),
      combinedPath: p.join(temp.path, 'combined'),
      outputPath: output,
      onProgress: (received, total) => progress.add((received, total)),
      onExtractionProgress: (written, total) =>
          extractionProgress.add((written, total)),
    );
    expect(File(output).readAsBytesSync(), [...parts[0], ...parts[1]]);
    expect(progress.last, (0, 0));
    expect(progress, contains((71000, 71000)));
    expect(extractionProgress.last, (71000, 71000));
  });

  test('cancel reaches the worker isolate', () async {
    bodies['/p0'] = List.filled(5000, 1);
    stall = true;
    final cancel = AttachedUpdateCancelToken();
    final output = p.join(temp.path, 'out.db');
    final future = downloader().download(
      artifact([bodies['/p0']!]),
      combinedPath: p.join(temp.path, 'combined'),
      outputPath: output,
      cancel: cancel,
      onProgress: (received, total) {
        cancel.cancel();
      },
    );
    await expectLater(future, throwsA(isA<AttachedUpdateCancelled>()));
    expect(File(output).existsSync(), isFalse);
  });

  test(
    'cancel at final output progress keeps input and removes output before retry',
    () async {
      final bytes = List.generate(70000, (i) => i % 251);
      bodies['/p0'] = bytes;
      final cancel = AttachedUpdateCancelToken();
      final combined = p.join(temp.path, 'combined');
      final output = p.join(temp.path, 'out.db');
      await expectLater(
        downloader().download(
          artifact([bytes]),
          combinedPath: combined,
          outputPath: output,
          cancel: cancel,
          onExtractionProgress: (written, total) {
            if (written == total) cancel.cancel();
          },
        ),
        throwsA(isA<AttachedUpdateCancelled>()),
      );
      expect(File(output).existsSync(), isFalse);
      expect(await File(combined).readAsBytes(), bytes);
      await downloader().download(
        artifact([bytes]),
        combinedPath: combined,
        outputPath: output,
      );
      expect(await File(output).readAsBytes(), bytes);
      expect(File(combined).existsSync(), isFalse);
    },
  );

  test('throwing final extraction observer waits for worker cleanup', () async {
    final bytes = List.filled(70000, 3);
    bodies['/p0'] = bytes;
    final combined = p.join(temp.path, 'combined');
    final output = p.join(temp.path, 'out.db');
    await expectLater(
      downloader().download(
        artifact([bytes]),
        combinedPath: combined,
        outputPath: output,
        onExtractionProgress: (written, total) {
          if (written == total) throw StateError('observer failed');
        },
      ),
      throwsA(isA<StateError>()),
    );
    expect(File(output).existsSync(), isFalse);
    expect(await File(combined).readAsBytes(), bytes);
  });

  test(
    'staging and lock aliases cannot overwrite an installed source',
    () async {
      final installed = File(p.join(temp.path, 'installed.db'));
      await installed.writeAsString('installed');
      final data = artifact([
        [1, 2, 3],
      ]);
      for (final output in [installed.path, '${installed.path}.stage']) {
        final base = output == installed.path ? installed.path : '$output.lock';
        if (base != installed.path) await File(base).writeAsString('installed');
        await expectLater(
          downloader().download(
            data,
            combinedPath: p.join(temp.path, 'combined'),
            outputPath: output,
            basePath: base,
          ),
          throwsA(isA<ArgumentError>()),
        );
        expect(await File(base).readAsString(), 'installed');
      }
    },
  );
}
