/// The mobile platform that owns the destination picker.
enum MobilePdfExportPlatform { android, ios, unsupported }

enum MobilePdfExportStatus { saved, cancelled, failed }

/// Cleanup of a newly created destination, not of the private staging file.
enum MobilePdfExportCleanupStatus {
  notNeeded,
  deleted,
  unsupported,
  failed,
  unknown,
}

/// Native uses this diagnostic prefix when it cannot safely clean its staging
/// file/directory (including identity replacement). Dart must not override that
/// refusal with path-based deletion. It is independent of destination cleanup.
const mobilePdfStagingCleanupFailurePrefix = 'staging_cleanup_failed:';

/// One private, completed PDF handed to native code for copying/exporting.
class MobilePdfExportRequest {
  const MobilePdfExportRequest({
    required this.operationId,
    required this.sourcePath,
    required this.fileName,
  });

  final String operationId;
  final String sourcePath;
  final String fileName;

  Map<String, Object> toMap() => {
    'version': 1,
    'operationId': operationId,
    'sourcePath': sourcePath,
    'fileName': fileName,
  };
}

/// The original export's terminal outcome, including an undeleted destination.
///
/// Names come only from the provider/returned URL. A missing name stays null;
/// the requested name is not evidence of the name actually saved.
class MobilePdfExportResult {
  const MobilePdfExportResult({
    required this.operationId,
    required this.status,
    this.documentUri,
    this.displayName,
    this.errorCode,
    this.errorMessage,
    this.residualDocument,
    this.residualDisplayName,
    this.cleanupStatus = MobilePdfExportCleanupStatus.notNeeded,
    this.cleanupError,
  });

  factory MobilePdfExportResult.fromMap(
    Object? value, {
    required String operationId,
  }) {
    if (value is! Map || value['version'] is! int || value['version'] != 1) {
      throw const FormatException('Invalid mobile PDF export result version');
    }
    String? optionalString(String key) {
      final field = value[key];
      if (field == null) return null;
      if (field is! String) {
        throw FormatException('Invalid mobile PDF export field: $key');
      }
      return field.isEmpty ? null : field;
    }

    final id = optionalString('operationId');
    final status = MobilePdfExportStatus.values.where(
      (item) => item.name == value['status'],
    );
    final cleanup = MobilePdfExportCleanupStatus.values.where(
      (item) => item.name == value['cleanupStatus'],
    );
    if (id == null || status.length != 1 || cleanup.length != 1) {
      throw const FormatException('Invalid mobile PDF export outcome');
    }
    return MobilePdfExportResult(
      operationId: id,
      status: status.single,
      documentUri: optionalString('documentUri'),
      displayName: optionalString('displayName'),
      errorCode: optionalString('errorCode'),
      errorMessage: optionalString('errorMessage'),
      residualDocument: optionalString('residualDocument'),
      residualDisplayName: optionalString('residualDisplayName'),
      cleanupStatus: cleanup.single,
      cleanupError: optionalString('cleanupError'),
    ).checkedFor(operationId);
  }

  final String operationId;
  final MobilePdfExportStatus status;
  final String? documentUri;
  final String? displayName;
  final String? errorCode;
  final String? errorMessage;
  final String? residualDocument;
  final String? residualDisplayName;
  final MobilePdfExportCleanupStatus cleanupStatus;

  /// Destination cleanup details, or a secondary `staging:` cleanup diagnostic.
  /// A staging failure never changes [status] or invents [residualDocument].
  final String? cleanupError;

  bool get hasNativeStagingCleanupFailure =>
      cleanupError?.contains(mobilePdfStagingCleanupFailurePrefix) ?? false;

  MobilePdfExportResult checkedFor(String expectedId) {
    if (operationId != expectedId ||
        (residualDisplayName != null && residualDocument == null) ||
        (status == MobilePdfExportStatus.saved && residualDocument != null) ||
        (residualDocument != null &&
            (cleanupStatus == MobilePdfExportCleanupStatus.notNeeded ||
                cleanupStatus == MobilePdfExportCleanupStatus.deleted))) {
      throw const FormatException('Inconsistent mobile PDF export outcome');
    }
    return this;
  }

  MobilePdfExportResult withStagingCleanupError(Object error) =>
      MobilePdfExportResult(
        operationId: operationId,
        status: status,
        documentUri: documentUri,
        displayName: displayName,
        errorCode: errorCode,
        errorMessage: errorMessage,
        residualDocument: residualDocument,
        residualDisplayName: residualDisplayName,
        cleanupStatus: cleanupStatus,
        cleanupError: [
          ?cleanupError,
          'staging: $error',
        ].join('\n'),
      );

  Map<String, Object?> toMap() => {
    'version': 1,
    'operationId': operationId,
    'status': status.name,
    'documentUri': documentUri,
    'displayName': displayName,
    'errorCode': errorCode,
    'errorMessage': errorMessage,
    'residualDocument': residualDocument,
    'residualDisplayName': residualDisplayName,
    'cleanupStatus': cleanupStatus.name,
    'cleanupError': cleanupError,
  };
}

/// Native must finish closing handles and destination cleanup before completing
/// [exportFile], including exceptional completion. A cancel acknowledgement is
/// not terminal. A save committed before a late cancel remains saved.
abstract interface class MobilePdfExportBackend {
  Future<MobilePdfExportResult> exportFile(MobilePdfExportRequest request);

  Future<bool> cancelExport(String operationId);
}

abstract interface class MobilePdfExportOperation {
  String get id;

  bool get isCancellationRequested;

  /// Completes once, after the producer, original native result and staging
  /// cleanup. Native residual-document information survives cancellation.
  Future<MobilePdfExportResult> get result;

  /// Idempotent request, not permission to release the source file. This future
  /// acknowledges the request only; always observe [result] as well.
  Future<void> cancel();
}
