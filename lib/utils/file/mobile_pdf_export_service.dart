import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'mobile_pdf_export_core.dart';
import 'mobile_pdf_export_models.dart';

export 'mobile_pdf_export_models.dart';

/// Mobile save-as-copy with a dedicated app-private PDF for each operation.
abstract class MobilePdfExportService {
  const MobilePdfExportService();

  /// Uses the real host OS, independent of Flutter's theme/test platform.
  static final MobilePdfExportService instance = _MobilePdfExportService(
    MobilePdfExportCoordinator(
      platform: Platform.isAndroid
          ? MobilePdfExportPlatform.android
          : Platform.isIOS
          ? MobilePdfExportPlatform.ios
          : MobilePdfExportPlatform.unsupported,
      backend: const MethodChannelMobilePdfExportBackend(),
      temporaryDirectory: getTemporaryDirectory,
    ),
  );

  /// Tests and other hosts inject the transport/cache while keeping the real
  /// producer, cancellation, staging and terminal-cleanup implementation.
  factory MobilePdfExportService.withBackend({
    required MobilePdfExportPlatform platform,
    required MobilePdfExportBackend backend,
    required Future<Directory> Function() temporaryDirectory,
  }) => _MobilePdfExportService(
    MobilePdfExportCoordinator(
      platform: platform,
      backend: backend,
      temporaryDirectory: temporaryDirectory,
    ),
  );

  MobilePdfExportPlatform get platform;
  bool get isSupported;

  MobilePdfExportOperation start({
    required String fileName,
    required Future<void> Function(String stagingPath) producer,
    void Function()? onCancelRequested,
  });
}

class _MobilePdfExportService extends MobilePdfExportService {
  const _MobilePdfExportService(this._coordinator);

  final MobilePdfExportCoordinator _coordinator;

  @override
  MobilePdfExportPlatform get platform => _coordinator.platform;

  @override
  bool get isSupported => _coordinator.isSupported;

  @override
  MobilePdfExportOperation start({
    required String fileName,
    required Future<void> Function(String stagingPath) producer,
    void Function()? onCancelRequested,
  }) => _coordinator.start(
    fileName: fileName,
    producer: producer,
    onCancelRequested: onCancelRequested,
  );
}

/// Both methods share the same channel. Native registers an operation before
/// awaiting a picker/worker, and completes exportFile only at its terminal
/// boundary (including cleanup after engine teardown).
class MethodChannelMobilePdfExportBackend implements MobilePdfExportBackend {
  const MethodChannelMobilePdfExportBackend({
    this._channel = const MethodChannel('otzaria/pdf_file_export'),
  });

  final MethodChannel _channel;

  @override
  Future<MobilePdfExportResult> exportFile(
    MobilePdfExportRequest request,
  ) async {
    final value = await _channel.invokeMethod<Object?>(
      'exportFile',
      request.toMap(),
    );
    return MobilePdfExportResult.fromMap(
      value,
      operationId: request.operationId,
    );
  }

  @override
  Future<bool> cancelExport(String operationId) async {
    final value = await _channel.invokeMethod<Object?>('cancelExport', {
      'version': 1,
      'operationId': operationId,
    });
    if (value is! Map ||
        value['operationId'] != operationId ||
        value['accepted'] is! bool) {
      throw const FormatException('Invalid mobile PDF cancel acknowledgement');
    }
    return value['accepted'] as bool;
  }
}
