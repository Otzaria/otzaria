import 'dart:async';

import 'package:otzaria/android_update/models/android_update.dart';
import 'package:otzaria/android_update/repository/android_update_platform.dart';
import 'package:otzaria/android_update/repository/android_update_repository.dart';

const directEnvironment = AndroidUpdateEnvironment(
  distribution: AndroidUpdateDistribution.direct,
  applicationId: 'org.otzaria.otzaria',
  versionCode: 99803,
  versionName: '0.9.98',
  sdkInt: 35,
  abis: ['arm64-v8a'],
);
const playEnvironment = AndroidUpdateEnvironment(
  distribution: AndroidUpdateDistribution.play,
  applicationId: 'org.otzaria.otzaria',
  versionCode: 99803,
  versionName: '0.9.98',
  sdkInt: 35,
  abis: ['arm64-v8a'],
);
final fakeRelease = AndroidApkRelease(
  tag: '0.9.98.4',
  displayVersion: '0.9.98.4',
  downloadUri: Uri.parse(
    'https://github.com/Otzaria/otzaria/releases/download/0.9.98.4/otzaria-android.apk',
  ),
  size: 4,
  sha256: 'a' * 64,
  versionCode: 99804,
);
final fakePrepared = PreparedAndroidUpdate(
  path: '/cache/android-software-update/update.apk',
  size: 4,
  sha256: 'a' * 64,
  applicationId: 'org.otzaria.otzaria',
  versionCode: 99804,
  versionName: '0.9.98',
  signingCertificateSha256: ['b' * 64],
);

class FakeAndroidUpdatePlatform implements AndroidUpdatePlatform {
  AndroidUpdateEnvironment appEnvironment = directEnvironment;
  final calls = <String>[];
  final controller = StreamController<AndroidNativeUpdateStatus>.broadcast();
  Future<Map<Object?, Object?>> Function(Map<String, Object?>)? inspect;

  @override
  Stream<AndroidNativeUpdateStatus> get changes => controller.stream;
  @override
  Future<AndroidUpdateEnvironment> environment() async => appEnvironment;
  @override
  Future<Map<Object?, Object?>> inspectApk(
    Map<String, Object?> arguments,
  ) async {
    calls.add('inspect');
    if (inspect != null) return inspect!(arguments);
    return {
      'applicationId': 'org.otzaria.otzaria',
      'versionCode': 99804,
      'versionName': '0.9.98',
      'signingCertificateSha256': ['b' * 64],
    };
  }

  @override
  Future<AndroidNativeUpdateStatus> installApk(
    PreparedAndroidUpdate update,
  ) async {
    calls.add('install');
    return const AndroidNativeUpdateStatus(
      stage: 'confirmation',
      versionCode: 99804,
    );
  }

  @override
  Future<bool> canInstall() async => true;
  @override
  Future<bool> requestInstallPermission() async => true;
  @override
  Future<AndroidNativeUpdateStatus> status({bool resume = false}) async =>
      const AndroidNativeUpdateStatus(stage: 'idle');
  @override
  Future<AndroidNativeUpdateStatus> checkPlay() async =>
      const AndroidNativeUpdateStatus(stage: 'available');
  @override
  Future<AndroidNativeUpdateStatus> startPlay() async =>
      const AndroidNativeUpdateStatus(stage: 'confirmation');
  @override
  Future<AndroidNativeUpdateStatus> completePlay() async =>
      const AndroidNativeUpdateStatus(stage: 'installing');
  @override
  Future<void> dispose() => controller.close();
}

class FakeAndroidUpdateRepository implements AndroidUpdateRepository {
  AndroidUpdateEnvironment appEnvironment = directEnvironment;
  AndroidApkRelease? release = fakeRelease;
  PreparedAndroidUpdate? restored;
  AndroidNativeUpdateStatus native = const AndroidNativeUpdateStatus(
    stage: 'idle',
  );
  bool permission = true;
  bool permissionAnswer = true;
  Object? installError;
  Future<PreparedAndroidUpdate> Function(
    AndroidDownloadCancellation,
    void Function(int, int),
  )?
  downloadAction;
  Future<AndroidNativeUpdateStatus> Function()? statusAction;
  Future<AndroidNativeUpdateStatus> Function()? playStartAction;
  final calls = <String>[];
  final controller = StreamController<AndroidNativeUpdateStatus>.broadcast();

  @override
  Stream<AndroidNativeUpdateStatus> get changes => controller.stream;
  @override
  Future<AndroidUpdateEnvironment> environment() async => appEnvironment;
  @override
  Future<AndroidApkRelease?> checkDirect() async {
    calls.add('checkDirect');
    return release;
  }

  @override
  Future<PreparedAndroidUpdate?> restorePrepared() async {
    calls.add('restore');
    return restored;
  }

  @override
  Future<PreparedAndroidUpdate> download(
    AndroidApkRelease release,
    AndroidDownloadCancellation cancellation,
    void Function(int, int) onProgress,
  ) async {
    calls.add('download');
    return downloadAction == null
        ? fakePrepared
        : downloadAction!(cancellation, onProgress);
  }

  @override
  Future<bool> canInstall() async => permission;
  @override
  Future<bool> requestInstallPermission() async {
    calls.add('permission');
    return permissionAnswer;
  }

  @override
  Future<AndroidNativeUpdateStatus> install(
    PreparedAndroidUpdate update,
  ) async {
    calls.add('install');
    if (installError != null) throw installError!;
    return const AndroidNativeUpdateStatus(
      stage: 'confirmation',
      versionCode: 99804,
    );
  }

  @override
  Future<AndroidNativeUpdateStatus> status({bool resume = false}) async {
    calls.add(resume ? 'resume' : 'status');
    return statusAction == null ? native : statusAction!();
  }

  @override
  Future<AndroidNativeUpdateStatus> checkPlay() async {
    calls.add('checkPlay');
    return native;
  }

  @override
  Future<AndroidNativeUpdateStatus> startPlay() async {
    calls.add('startPlay');
    return playStartAction == null
        ? const AndroidNativeUpdateStatus(stage: 'confirmation')
        : playStartAction!();
  }

  @override
  Future<AndroidNativeUpdateStatus> completePlay() async {
    calls.add('completePlay');
    return const AndroidNativeUpdateStatus(stage: 'installing');
  }

  @override
  Future<void> discardPrepared() async {
    calls.add('discard');
  }

  @override
  Future<void> dispose() => controller.close();
}
