import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:convert/convert.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../models/android_update.dart';
import 'android_release_repository.dart';
import 'android_update_platform.dart';

abstract interface class AndroidUpdateRepository {
  Stream<AndroidNativeUpdateStatus> get changes;
  Future<AndroidUpdateEnvironment> environment();
  Future<AndroidApkRelease?> checkDirect();
  Future<PreparedAndroidUpdate?> restorePrepared();
  Future<PreparedAndroidUpdate> download(
    AndroidApkRelease release,
    AndroidDownloadCancellation cancellation,
    void Function(int received, int total) onProgress,
  );
  Future<bool> canInstall();
  Future<bool> requestInstallPermission();
  Future<AndroidNativeUpdateStatus> install(PreparedAndroidUpdate update);
  Future<AndroidNativeUpdateStatus> status({bool resume = false});
  Future<AndroidNativeUpdateStatus> checkPlay();
  Future<AndroidNativeUpdateStatus> startPlay();
  Future<AndroidNativeUpdateStatus> completePlay();
  Future<void> discardPrepared();
  Future<void> dispose();
}

class DefaultAndroidUpdateRepository implements AndroidUpdateRepository {
  DefaultAndroidUpdateRepository({
    AndroidUpdatePlatform? platform,
    AndroidReleaseRepository? releases,
    http.Client Function()? clientFactory,
    Future<Directory> Function()? temporaryDirectory,
    this.connectTimeout = const Duration(seconds: 20),
    this.stallTimeout = const Duration(seconds: 30),
  }) : _platform = platform ?? MethodChannelAndroidUpdatePlatform(),
       _releases =
           releases ?? AndroidReleaseRepository(clientFactory: clientFactory),
       _clientFactory = clientFactory ?? http.Client.new,
       _temporaryDirectory = temporaryDirectory ?? getTemporaryDirectory;

  final AndroidUpdatePlatform _platform;
  final AndroidReleaseRepository _releases;
  final http.Client Function() _clientFactory;
  final Future<Directory> Function() _temporaryDirectory;
  final Duration connectTimeout;
  final Duration stallTimeout;
  Future<AndroidUpdateEnvironment>? _environment;

  @override
  Stream<AndroidNativeUpdateStatus> get changes => _platform.changes;
  @override
  Future<AndroidUpdateEnvironment> environment() =>
      _environment ??= _platform.environment();

  Future<void> _require(AndroidUpdateDistribution distribution) async {
    if ((await environment()).distribution != distribution) {
      throw const AndroidUpdateException(AndroidUpdateFailure.invalidMetadata);
    }
  }

  Future<Directory> _directory() async => Directory(
    p.join((await _temporaryDirectory()).path, 'android-software-update'),
  );

  @override
  Future<AndroidApkRelease?> checkDirect() async =>
      _releases.latest(await environment());

  @override
  Future<PreparedAndroidUpdate?> restorePrepared() async {
    await _require(AndroidUpdateDistribution.direct);
    final directory = await _directory();
    final receipt = File(p.join(directory.path, 'prepared.json'));
    if (!await receipt.exists()) return null;
    try {
      if (await receipt.length() > 16 * 1024) {
        throw const FormatException('Oversized update receipt');
      }
      final update = PreparedAndroidUpdate.fromMap(
        jsonDecode(await receipt.readAsString()) as Map,
      );
      if (update.path != p.join(directory.path, 'update.apk')) {
        throw const FormatException('Invalid update path');
      }
      if (update.versionCode <= (await environment()).versionCode) {
        await discardPrepared();
        return null;
      }
      await _platform.inspectApk(update.toMap());
      return update;
    } on Object {
      await discardPrepared();
      return null;
    }
  }

  @override
  Future<PreparedAndroidUpdate> download(
    AndroidApkRelease release,
    AndroidDownloadCancellation cancellation,
    void Function(int received, int total) onProgress,
  ) async {
    await _require(AndroidUpdateDistribution.direct);
    if (release.size <= 0 ||
        release.size > maxAndroidApkBytes ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(release.sha256)) {
      throw const AndroidUpdateException(AndroidUpdateFailure.invalidMetadata);
    }
    final directory = await _directory();
    await directory.create(recursive: true);
    final target = File(p.join(directory.path, 'update.apk'));
    final partial = File('${target.path}.part');
    final receipt = File(p.join(directory.path, 'prepared.json'));
    final client = _clientFactory();
    RandomAccessFile? output;
    var complete = false;
    try {
      cancellation.throwIfCancelled();
      await _delete(receipt);
      final request = http.AbortableRequest(
        'GET',
        release.downloadUri,
        abortTrigger: cancellation.whenCancelled,
      );
      final response = await client.send(request).timeout(connectTimeout);
      cancellation.throwIfCancelled();
      if (response.statusCode != 200) {
        throw const AndroidUpdateException(AndroidUpdateFailure.network);
      }
      if (response.contentLength != null &&
          response.contentLength != release.size) {
        throw const AndroidUpdateException(AndroidUpdateFailure.sizeMismatch);
      }
      output = await partial.open(mode: FileMode.write);
      final digests = AccumulatorSink<Digest>();
      final hash = sha256.startChunkedConversion(digests);
      var received = 0;
      final progressClock = Stopwatch()..start();
      onProgress(0, release.size);
      await for (final chunk in response.stream.timeout(stallTimeout)) {
        cancellation.throwIfCancelled();
        received += chunk.length;
        if (received > release.size) {
          throw const AndroidUpdateException(AndroidUpdateFailure.sizeMismatch);
        }
        hash.add(chunk);
        await output.writeFrom(chunk);
        if (progressClock.elapsedMilliseconds >= 150 ||
            received == release.size) {
          onProgress(received, release.size);
          progressClock.reset();
        }
      }
      cancellation.throwIfCancelled();
      hash.close();
      await output.flush();
      await output.close();
      output = null;
      if (received != release.size) {
        throw const AndroidUpdateException(AndroidUpdateFailure.sizeMismatch);
      }
      if (digests.events.single.toString() != release.sha256) {
        throw const AndroidUpdateException(AndroidUpdateFailure.hashMismatch);
      }
      await _delete(target);
      await partial.rename(target.path);
      final arguments = <String, Object?>{
        'path': target.path,
        'size': received,
        'sha256': release.sha256,
        'applicationId': release.applicationId,
        'versionCode': release.versionCode,
        if (release.signingCertificateSha256 != null)
          'signingCertificateSha256': release.signingCertificateSha256,
      };
      final info = await _platform.inspectApk(arguments);
      cancellation.throwIfCancelled();
      final prepared = PreparedAndroidUpdate(
        path: target.path,
        size: received,
        sha256: release.sha256,
        applicationId: info['applicationId'] as String,
        versionCode: info['versionCode'] as int,
        versionName: info['versionName'] as String,
        signingCertificateSha256: (info['signingCertificateSha256'] as List)
            .cast<String>(),
      );
      await receipt.writeAsString(jsonEncode(prepared.toMap()), flush: true);
      cancellation.throwIfCancelled();
      complete = true;
      return prepared;
    } on http.RequestAbortedException {
      throw const AndroidDownloadCancelled();
    } finally {
      client.close();
      try {
        await output?.close();
      } on FileSystemException {
        /* Preserve the original failure. */
      }
      await _delete(partial);
      if (!complete) {
        await _delete(target);
        await _delete(receipt);
      }
    }
  }

  static Future<void> _delete(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } on FileSystemException {
      /* The next attempt replaces leftover private files. */
    }
  }

  @override
  Future<bool> canInstall() async {
    await _require(AndroidUpdateDistribution.direct);
    return _platform.canInstall();
  }

  @override
  Future<bool> requestInstallPermission() async {
    await _require(AndroidUpdateDistribution.direct);
    return _platform.requestInstallPermission();
  }

  @override
  Future<AndroidNativeUpdateStatus> install(
    PreparedAndroidUpdate update,
  ) async {
    await _require(AndroidUpdateDistribution.direct);
    return _platform.installApk(update);
  }

  @override
  Future<AndroidNativeUpdateStatus> status({bool resume = false}) =>
      _platform.status(resume: resume);
  @override
  Future<AndroidNativeUpdateStatus> checkPlay() async {
    await _require(AndroidUpdateDistribution.play);
    return _platform.checkPlay();
  }

  @override
  Future<AndroidNativeUpdateStatus> startPlay() async {
    await _require(AndroidUpdateDistribution.play);
    return _platform.startPlay();
  }

  @override
  Future<AndroidNativeUpdateStatus> completePlay() async {
    await _require(AndroidUpdateDistribution.play);
    return _platform.completePlay();
  }

  @override
  Future<void> discardPrepared() async {
    await _require(AndroidUpdateDistribution.direct);
    final directory = await _directory();
    await _delete(File(p.join(directory.path, 'prepared.json')));
    await _delete(File(p.join(directory.path, 'update.apk')));
  }

  @override
  Future<void> dispose() => _platform.dispose();
}
