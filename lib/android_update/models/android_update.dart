import 'dart:async';

enum AndroidUpdateDistribution { direct, play }

enum AndroidUpdateFailure {
  network,
  metadataMissing,
  invalidMetadata,
  packageMismatch,
  signatureMismatch,
  incompatibleDevice,
  notNewer,
  sizeMismatch,
  hashMismatch,
  storage,
  permissionDenied,
  installerFailed,
  interrupted,
  playUnavailable,
  disabled,
  busy,
}

class AndroidUpdateException implements Exception {
  const AndroidUpdateException(this.failure);
  final AndroidUpdateFailure failure;
  @override
  String toString() => 'AndroidUpdateException(${failure.name})';
}

class AndroidDownloadCancelled implements Exception {
  const AndroidDownloadCancelled();
}

class AndroidDownloadCancellation {
  final _cancelled = Completer<void>();
  bool get isCancelled => _cancelled.isCompleted;
  Future<void> get whenCancelled => _cancelled.future;
  void cancel() {
    if (!isCancelled) _cancelled.complete();
  }

  void throwIfCancelled() {
    if (isCancelled) throw const AndroidDownloadCancelled();
  }
}

class AndroidUpdateEnvironment {
  const AndroidUpdateEnvironment({
    required this.distribution,
    required this.applicationId,
    required this.versionCode,
    required this.versionName,
    required this.sdkInt,
    required this.abis,
  });

  final AndroidUpdateDistribution distribution;
  final String applicationId;
  final int versionCode;
  final String versionName;
  final int sdkInt;
  final List<String> abis;

  factory AndroidUpdateEnvironment.fromMap(Map<Object?, Object?> map) =>
      AndroidUpdateEnvironment(
        distribution: switch (map['distribution']) {
          'direct' => AndroidUpdateDistribution.direct,
          'play' => AndroidUpdateDistribution.play,
          _ => throw const AndroidUpdateException(
            AndroidUpdateFailure.invalidMetadata,
          ),
        },
        applicationId: map['applicationId'] as String,
        versionCode: map['versionCode'] as int,
        versionName: map['versionName'] as String,
        sdkInt: map['sdkInt'] as int,
        abis: (map['abis'] as List).cast<String>(),
      );
}

class AndroidApkRelease {
  const AndroidApkRelease({
    required this.tag,
    required this.displayVersion,
    required this.downloadUri,
    required this.size,
    required this.sha256,
    this.versionCode,
    this.applicationId,
    this.signingCertificateSha256,
  });

  final String tag;
  final String displayVersion;
  final Uri downloadUri;
  final int size;
  final String sha256;
  final int? versionCode;
  final String? applicationId;
  final List<String>? signingCertificateSha256;
}

class PreparedAndroidUpdate {
  const PreparedAndroidUpdate({
    required this.path,
    required this.size,
    required this.sha256,
    required this.applicationId,
    required this.versionCode,
    required this.versionName,
    required this.signingCertificateSha256,
  });

  final String path;
  final int size;
  final String sha256;
  final String applicationId;
  final int versionCode;
  final String versionName;
  final List<String> signingCertificateSha256;

  Map<String, Object?> toMap() => {
    'path': path,
    'size': size,
    'sha256': sha256,
    'applicationId': applicationId,
    'versionCode': versionCode,
    'versionName': versionName,
    'signingCertificateSha256': signingCertificateSha256,
  };

  factory PreparedAndroidUpdate.fromMap(Map<Object?, Object?> map) =>
      PreparedAndroidUpdate(
        path: map['path'] as String,
        size: map['size'] as int,
        sha256: map['sha256'] as String,
        applicationId: map['applicationId'] as String,
        versionCode: map['versionCode'] as int,
        versionName: map['versionName'] as String,
        signingCertificateSha256: (map['signingCertificateSha256'] as List)
            .cast<String>(),
      );
}

class AndroidNativeUpdateStatus {
  const AndroidNativeUpdateStatus({
    required this.stage,
    this.versionCode,
    this.bytesDownloaded = 0,
    this.totalBytes = 0,
    this.errorCode = 0,
  });

  final String stage;
  final int? versionCode;
  final int bytesDownloaded;
  final int totalBytes;
  final int errorCode;

  factory AndroidNativeUpdateStatus.fromMap(Map<Object?, Object?> map) =>
      AndroidNativeUpdateStatus(
        stage: map['stage'] as String,
        versionCode: map['versionCode'] as int?,
        bytesDownloaded: map['bytesDownloaded'] as int? ?? 0,
        totalBytes: map['totalBytes'] as int? ?? 0,
        errorCode: map['errorCode'] as int? ?? 0,
      );
}
