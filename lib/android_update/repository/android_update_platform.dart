import 'dart:async';

import 'package:flutter/services.dart';
import '../models/android_update.dart';

abstract interface class AndroidUpdatePlatform {
  Stream<AndroidNativeUpdateStatus> get changes;
  Future<AndroidUpdateEnvironment> environment();
  Future<AndroidNativeUpdateStatus> status({bool resume = false});
  Future<Map<Object?, Object?>> inspectApk(Map<String, Object?> arguments);
  Future<AndroidNativeUpdateStatus> installApk(PreparedAndroidUpdate update);
  Future<bool> canInstall();
  Future<bool> requestInstallPermission();
  Future<AndroidNativeUpdateStatus> checkPlay();
  Future<AndroidNativeUpdateStatus> startPlay();
  Future<AndroidNativeUpdateStatus> completePlay();
  Future<void> dispose();
}

class MethodChannelAndroidUpdatePlatform implements AndroidUpdatePlatform {
  MethodChannelAndroidUpdatePlatform({
    MethodChannel? channel,
  }) : _channel =
           channel ?? const MethodChannel('otzaria/android_software_update') {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'status' && !_changes.isClosed) {
        _changes.add(AndroidNativeUpdateStatus.fromMap(call.arguments as Map));
      }
    });
  }

  final MethodChannel _channel;
  final _changes = StreamController<AndroidNativeUpdateStatus>.broadcast();

  @override
  Stream<AndroidNativeUpdateStatus> get changes => _changes.stream;

  Future<T?> _invoke<T>(String method, [Object? arguments]) async {
    try {
      return await _channel
          .invokeMethod<T>(method, arguments)
          .timeout(
            Duration(minutes: method == 'requestInstallPermission' ? 5 : 2),
          );
    } on PlatformException catch (error) {
      throw AndroidUpdateException(switch (error.code) {
        'PACKAGE_MISMATCH' => AndroidUpdateFailure.packageMismatch,
        'SIGNATURE_MISMATCH' => AndroidUpdateFailure.signatureMismatch,
        'VERSION_NOT_NEWER' => AndroidUpdateFailure.notNewer,
        'INCOMPATIBLE_DEVICE' => AndroidUpdateFailure.incompatibleDevice,
        'HASH_MISMATCH' => AndroidUpdateFailure.hashMismatch,
        'SIZE_MISMATCH' => AndroidUpdateFailure.sizeMismatch,
        'INVALID_APK' ||
        'METADATA_MISMATCH' => AndroidUpdateFailure.invalidMetadata,
        'STORAGE_ERROR' => AndroidUpdateFailure.storage,
        'INSTALL_PERMISSION_REQUIRED' => AndroidUpdateFailure.permissionDenied,
        'PLAY_UNAVAILABLE' => AndroidUpdateFailure.playUnavailable,
        'UPDATE_BUSY' => AndroidUpdateFailure.busy,
        _ => AndroidUpdateFailure.installerFailed,
      });
    }
  }

  Future<AndroidNativeUpdateStatus> _status(
    String method, [
    Object? arguments,
  ]) async => AndroidNativeUpdateStatus.fromMap(
    (await _invoke<Map>(method, arguments))!,
  );

  @override
  Future<AndroidUpdateEnvironment> environment() async =>
      AndroidUpdateEnvironment.fromMap((await _invoke<Map>('environment'))!);

  @override
  Future<AndroidNativeUpdateStatus> status({bool resume = false}) =>
      _status(resume ? 'resume' : 'status');

  @override
  Future<Map<Object?, Object?>> inspectApk(
    Map<String, Object?> arguments,
  ) async =>
      (await _invoke<Map>('inspectApk', arguments))!.cast<Object?, Object?>();

  @override
  Future<AndroidNativeUpdateStatus> installApk(PreparedAndroidUpdate update) =>
      _status('installApk', update.toMap());

  @override
  Future<bool> canInstall() async => await _invoke<bool>('canInstall') ?? false;

  @override
  Future<bool> requestInstallPermission() async =>
      await _invoke<bool>('requestInstallPermission') ?? false;

  @override
  Future<AndroidNativeUpdateStatus> checkPlay() => _status('checkPlay');
  @override
  Future<AndroidNativeUpdateStatus> startPlay() => _status('startPlay');
  @override
  Future<AndroidNativeUpdateStatus> completePlay() => _status('completePlay');

  @override
  Future<void> dispose() async {
    _channel.setMethodCallHandler(null);
    await _changes.close();
  }
}
