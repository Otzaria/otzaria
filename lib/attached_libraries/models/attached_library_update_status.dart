import 'dart:convert';
import 'dart:typed_data';

import 'package:equatable/equatable.dart';
import 'package:otzaria/attached_libraries/models/attached_update_manifest.dart';

/// עדכון שנמצא ואומת בחתימה — ממתין לאישור המשתמש.
class AttachedUpdateOffer extends Equatable {
  final AttachedUpdateManifest manifest;

  /// The signed bytes exactly as downloaded, kept to re-verify before install.
  final Uint8List manifestBytes;
  final Uint8List signature;

  /// Host of the pinned manifest URL, shown in the confirmation dialog.
  final String domain;

  /// גודל ההורדה של הארטיפקט שנבחר בפועל — תיקון דלתא קטן מהקובץ המלא.
  final int? plannedDownloadSize;

  const AttachedUpdateOffer({
    required this.manifest,
    required this.manifestBytes,
    required this.signature,
    required this.domain,
    this.plannedDownloadSize,
  });

  AttachedUpdateOffer withPlannedDownloadSize(int size) => AttachedUpdateOffer(
    manifest: manifest,
    manifestBytes: manifestBytes,
    signature: signature,
    domain: domain,
    plannedDownloadSize: size,
  );

  int get dbVersion => manifest.dbVersion;
  int get downloadSize => plannedDownloadSize ?? manifest.full.compressedSize;
  String? get releaseNotes => manifest.releaseNotes;

  Map<String, dynamic> toJson() => {
    'manifest': base64.encode(manifestBytes),
    'signature': base64.encode(signature),
  };

  @override
  List<Object?> get props => [dbVersion, manifestBytes, signature, domain];
}

/// Why a check or an install did not complete.
enum AttachedUpdateError {
  offline,
  updatesDisabled,
  noSource,
  sourceMismatch,
  network,
  hostRejected,
  badSignature,
  badManifest,
  notApplicable,
  fileMissing,
  readOnly,
  noSpace,
  fileLocked,
  downloadCorrupt,
  verifyFailed,
  unknown,
}

enum AttachedUpdatePhase { download, waitingForWifi, assemble, install }

/// מצב העדכון של מסד מצורף אחד, כפי שמוצג בכרטיס.
sealed class AttachedUpdateStatus extends Equatable {
  const AttachedUpdateStatus();

  /// The offer that is still installable from this state, if any.
  AttachedUpdateOffer? get offer => null;

  bool get isRunning => false;

  @override
  List<Object?> get props => [];
}

class AttachedUpdateIdle extends AttachedUpdateStatus {
  const AttachedUpdateIdle();
}

class AttachedUpdateChecking extends AttachedUpdateStatus {
  const AttachedUpdateChecking();

  @override
  bool get isRunning => true;
}

class AttachedUpdateUpToDate extends AttachedUpdateStatus {
  const AttachedUpdateUpToDate();
}

class AttachedUpdateAvailable extends AttachedUpdateStatus {
  @override
  final AttachedUpdateOffer offer;

  const AttachedUpdateAvailable(this.offer);

  @override
  List<Object?> get props => [offer];
}

class AttachedUpdateInProgress extends AttachedUpdateStatus {
  @override
  final AttachedUpdateOffer offer;
  final AttachedUpdatePhase phase;
  final int received;
  final int total;

  const AttachedUpdateInProgress(
    this.offer, {
    required this.phase,
    this.received = 0,
    this.total = 0,
  });

  @override
  bool get isRunning => true;

  /// 0..1 during the download; null when the phase has no byte count.
  double? get fraction => phase == AttachedUpdatePhase.download && total > 0
      ? (received / total).clamp(0.0, 1.0)
      : null;

  @override
  List<Object?> get props => [offer, phase, received, total];
}

class AttachedUpdateInstalled extends AttachedUpdateStatus {
  final int dbVersion;

  const AttachedUpdateInstalled(this.dbVersion);

  @override
  List<Object?> get props => [dbVersion];
}

class AttachedUpdateFailed extends AttachedUpdateStatus {
  final AttachedUpdateError error;

  /// Kept so the card can offer "update" again after a failed install.
  @override
  final AttachedUpdateOffer? offer;

  /// Bytes needed, for [AttachedUpdateError.noSpace].
  final int? requiredBytes;

  const AttachedUpdateFailed(this.error, {this.offer, this.requiredBytes});

  @override
  List<Object?> get props => [error, offer, requiredBytes];
}
