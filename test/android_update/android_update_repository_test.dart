import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:otzaria/android_update/models/android_update.dart';
import 'package:otzaria/android_update/repository/android_update_repository.dart';
import 'package:path/path.dart' as p;

import 'support.dart';

void main() {
  late Directory temporary;
  late FakeAndroidUpdatePlatform platform;
  final bytes = List<int>.generate(8192, (i) => i % 251);
  AndroidApkRelease release({
    String? hash,
    int? size,
    Uri? uri,
  }) => AndroidApkRelease(
    tag: '0.9.98.4',
    displayVersion: '0.9.98.4',
    downloadUri:
        uri ??
        Uri.parse(
          'https://github.com/Otzaria/otzaria/releases/download/0.9.98.4/otzaria-android.apk',
        ),
    size: size ?? bytes.length,
    sha256: hash ?? sha256.convert(bytes).toString(),
    applicationId: 'org.otzaria.otzaria',
    versionCode: 99804,
  );
  DefaultAndroidUpdateRepository repository(
    http.Client Function() clients, {
    Duration stallTimeout = const Duration(seconds: 1),
  }) => DefaultAndroidUpdateRepository(
    platform: platform,
    clientFactory: clients,
    temporaryDirectory: () async => temporary,
    stallTimeout: stallTimeout,
  );
  MockClient response(List<int> data, {int? contentLength}) =>
      MockClient.streaming(
        (request, body) async => http.StreamedResponse(
          Stream.fromIterable([
            for (var i = 0; i < data.length; i += 1024)
              data.sublist(i, (i + 1024).clamp(0, data.length)),
          ]),
          200,
          contentLength: contentLength,
        ),
      );
  Matcher failure(AndroidUpdateFailure expected) => throwsA(
    isA<AndroidUpdateException>().having((e) => e.failure, 'failure', expected),
  );
  Future<void> expectClean() async {
    final directory = Directory(
      p.join(temporary.path, 'android-software-update'),
    );
    expect(await directory.list().toList(), isEmpty);
  }

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('android-update-test-');
    platform = FakeAndroidUpdatePlatform();
  });
  tearDown(() async {
    await platform.dispose();
    await temporary.delete(recursive: true);
  });

  test(
    'streams to disk, verifies before native inspection and restores the receipt',
    () async {
      final repo = repository(
        () => response(bytes, contentLength: bytes.length),
      );
      final progress = <int>[];
      final prepared = await repo.download(
        release(),
        AndroidDownloadCancellation(),
        (n, total) => progress.add(n),
      );
      expect(await File(prepared.path).readAsBytes(), bytes);
      expect(progress.first, 0);
      expect(progress.last, bytes.length);
      expect(platform.calls, ['inspect']);
      final restored = await repo.restorePrepared();
      expect(restored!.sha256, prepared.sha256);
      expect(platform.calls, ['inspect', 'inspect']);
      expect(platform.calls, isNot(contains('install')));
    },
  );

  test(
    'oversized and truncated responses never reach native inspection',
    () async {
      for (final data in [
        bytes.sublist(1),
        [...bytes, 1],
      ]) {
        final repo = repository(() => response(data));
        await expectLater(
          repo.download(release(), AndroidDownloadCancellation(), (_, _) {}),
          failure(AndroidUpdateFailure.sizeMismatch),
        );
        expect(platform.calls, isEmpty);
        await expectClean();
      }
    },
  );

  test(
    'mismatched content length is rejected before the response is consumed',
    () async {
      final repo = repository(
        () => response(bytes, contentLength: bytes.length + 1),
      );
      await expectLater(
        repo.download(release(), AndroidDownloadCancellation(), (_, _) {}),
        failure(AndroidUpdateFailure.sizeMismatch),
      );
      expect(platform.calls, isEmpty);
      await expectClean();
    },
  );

  test(
    'hash mismatch deletes the file and never asks Android to inspect or install',
    () async {
      final repo = repository(() => response(bytes));
      await expectLater(
        repo.download(
          release(hash: '0' * 64),
          AndroidDownloadCancellation(),
          (_, _) {},
        ),
        failure(AndroidUpdateFailure.hashMismatch),
      );
      expect(platform.calls, isEmpty);
      await expectClean();
    },
  );

  test(
    'native signature rejection preserves its error and removes the staged APK',
    () async {
      platform.inspect = (_) async => throw const AndroidUpdateException(
        AndroidUpdateFailure.signatureMismatch,
      );
      final repo = repository(() => response(bytes));
      await expectLater(
        repo.download(release(), AndroidDownloadCancellation(), (_, _) {}),
        failure(AndroidUpdateFailure.signatureMismatch),
      );
      await expectClean();
    },
  );

  test(
    'cancellation during native inspection cannot publish a prepared receipt',
    () async {
      final token = AndroidDownloadCancellation();
      platform.inspect = (_) async {
        token.cancel();
        return fakePrepared.toMap();
      };
      final repo = repository(() => response(bytes));
      await expectLater(
        repo.download(release(), token, (_, _) {}),
        throwsA(isA<AndroidDownloadCancelled>()),
      );
      await expectClean();
    },
  );

  test('a stalled response times out and removes partial bytes', () async {
    final controller = StreamController<List<int>>();
    final repo = repository(
      () => MockClient.streaming(
        (_, _) async => http.StreamedResponse(controller.stream, 200),
      ),
      stallTimeout: const Duration(milliseconds: 20),
    );
    final result = repo.download(
      release(),
      AndroidDownloadCancellation(),
      (_, _) {},
    );
    controller.add(bytes.sublist(0, 100));
    await expectLater(result, throwsA(isA<TimeoutException>()));
    await controller.close();
    await expectClean();
  });

  test(
    'cancellation aborts a real HTTP response while it is stalled',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final held = Completer<void>();
      server.listen((request) async {
        try {
          request.response.contentLength = bytes.length;
          request.response.add(bytes.sublist(0, 100));
          await request.response.flush();
          await held.future;
          request.response.add(bytes.sublist(100));
          await request.response.close();
        } on SocketException {
          // The client deliberately aborts the stalled download.
        } on HttpException {
          // Closing the response after an abort may report an incomplete body.
        }
      });
      final token = AndroidDownloadCancellation();
      final repo = repository(http.Client.new);
      try {
        await expectLater(
          repo
              .download(
                release(
                  uri: Uri.parse('http://127.0.0.1:${server.port}/update.apk'),
                ),
                token,
                (_, _) => token.cancel(),
              )
              .timeout(const Duration(seconds: 3)),
          throwsA(isA<AndroidDownloadCancelled>()),
        );
        expect(platform.calls, isEmpty);
        await expectClean();
      } finally {
        held.complete();
        await server.close(force: true);
      }
    },
  );

  test(
    'receipt cannot redirect restoration outside the private update directory',
    () async {
      final directory = Directory(
        p.join(temporary.path, 'android-software-update'),
      );
      await directory.create();
      final outside = File(p.join(temporary.path, 'keep.apk'));
      await outside.writeAsBytes(bytes);
      await File(p.join(directory.path, 'prepared.json')).writeAsString(
        jsonEncode(fakePrepared.toMap()..['path'] = outside.path),
      );
      final repo = repository(
        () => throw StateError('No network during restore'),
      );
      expect(await repo.restorePrepared(), isNull);
      expect(await outside.exists(), isTrue);
      expect(platform.calls, isEmpty);
    },
  );

  test('Play rejects every direct APK entry point before I/O', () async {
    platform.appEnvironment = playEnvironment;
    final repo = repository(
      () => throw StateError('Play must not download APKs'),
    );
    await expectLater(
      repo.download(release(), AndroidDownloadCancellation(), (_, _) {}),
      failure(AndroidUpdateFailure.invalidMetadata),
    );
    await expectLater(
      repo.restorePrepared(),
      failure(AndroidUpdateFailure.invalidMetadata),
    );
    await expectLater(
      repo.install(fakePrepared),
      failure(AndroidUpdateFailure.invalidMetadata),
    );
    await expectLater(
      repo.requestInstallPermission(),
      failure(AndroidUpdateFailure.invalidMetadata),
    );
    expect(platform.calls, isEmpty);
  });
}
