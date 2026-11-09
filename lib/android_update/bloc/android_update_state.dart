import 'package:equatable/equatable.dart';
import '../models/android_update.dart';

enum AndroidUpdatePhase {
  idle,
  initializing,
  checking,
  upToDate,
  available,
  downloading,
  cancelling,
  ready,
  awaitingPermission,
  confirmation,
  installing,
  completed,
  cancelled,
  failed,
}

class AndroidUpdateState extends Equatable {
  const AndroidUpdateState({
    this.phase = AndroidUpdatePhase.idle,
    this.environment,
    this.release,
    this.prepared,
    this.bytesDownloaded = 0,
    this.totalBytes = 0,
    this.failure,
  });

  final AndroidUpdatePhase phase;
  final AndroidUpdateEnvironment? environment;
  final AndroidApkRelease? release;
  final PreparedAndroidUpdate? prepared;
  final int bytesDownloaded;
  final int totalBytes;
  final AndroidUpdateFailure? failure;

  bool get isPlay =>
      environment?.distribution == AndroidUpdateDistribution.play;
  bool get busy => switch (phase) {
    AndroidUpdatePhase.initializing ||
    AndroidUpdatePhase.checking ||
    AndroidUpdatePhase.downloading ||
    AndroidUpdatePhase.cancelling ||
    AndroidUpdatePhase.awaitingPermission ||
    AndroidUpdatePhase.installing => true,
    _ => false,
  };
  bool get showIndicator => switch (phase) {
    AndroidUpdatePhase.available ||
    AndroidUpdatePhase.downloading ||
    AndroidUpdatePhase.cancelling ||
    AndroidUpdatePhase.ready ||
    AndroidUpdatePhase.awaitingPermission ||
    AndroidUpdatePhase.confirmation ||
    AndroidUpdatePhase.installing => true,
    _ => false,
  };

  double? get progress =>
      totalBytes > 0 ? (bytesDownloaded / totalBytes).clamp(0, 1) : null;

  AndroidUpdateState copyWith({
    AndroidUpdatePhase? phase,
    AndroidUpdateEnvironment? environment,
    AndroidApkRelease? release,
    PreparedAndroidUpdate? prepared,
    int? bytesDownloaded,
    int? totalBytes,
    AndroidUpdateFailure? failure,
    bool clearRelease = false,
    bool clearPrepared = false,
  }) => AndroidUpdateState(
    phase: phase ?? this.phase,
    environment: environment ?? this.environment,
    release: clearRelease ? null : release ?? this.release,
    prepared: clearPrepared ? null : prepared ?? this.prepared,
    bytesDownloaded: bytesDownloaded ?? this.bytesDownloaded,
    totalBytes: totalBytes ?? this.totalBytes,
    failure: failure,
  );

  @override
  List<Object?> get props => [
    phase,
    environment,
    release,
    prepared,
    bytesDownloaded,
    totalBytes,
    failure,
  ];
}
