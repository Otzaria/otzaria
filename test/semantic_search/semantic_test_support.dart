import 'dart:async';
import 'dart:io';

import 'package:otzaria/search/search_engine_gateway.dart';
import 'package:otzaria/search_feedback/search_feedback_api.dart';
import 'package:otzaria/semantic_search/engine/semantic_engine_backend.dart';
import 'package:otzaria/semantic_search/models/semantic_engine_models.dart';
import 'package:otzaria/semantic_search/models/semantic_failure.dart';
import 'package:otzaria/semantic_search/models/semantic_model_identity.dart';
import 'package:otzaria/semantic_search/models/semantic_model_release.dart';
import 'package:otzaria/semantic_search/models/semantic_paths.dart';
import 'package:otzaria/semantic_search/repository/semantic_search_repository.dart';
import 'package:otzaria/semantic_search/repository/semantic_data_ownership.dart';
import 'package:otzaria/semantic_search/repository/semantic_settings_store.dart';
import 'package:otzaria/semantic_search/repository/semantic_release_locator.dart';
import 'package:otzaria/semantic_search/models/semantic_vectors_release.dart';
import 'package:otzaria/utils/file/disk_free_space.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart';
import 'package:path/path.dart' as p;
import 'package:seforim_library_updater/seforim_library_updater.dart'
    show PatchDownloadCancelled;

/// ממתין עד ש-[condition] מתקיים (עבודת קבצים אמיתית אינה microtask).
Future<void> waitFor(bool Function() condition) async {
  for (var i = 0; i < 200 && !condition(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

/// טקסט ה-model.json שמצורף לאפליקציה.
String bundledModelJson() => File(
  'assets/semantic/meivin-round2-onnx/model.json',
).readAsStringSync();

class FakeConsentStore implements SearchFeedbackConsentStore {
  FakeConsentStore([this.current = SearchFeedbackConsent.granted]);

  final _controller = StreamController<SearchFeedbackConsent>.broadcast();
  SearchFeedbackConsent current;

  void set(SearchFeedbackConsent value) {
    current = value;
    _controller.add(value);
  }

  @override
  SearchFeedbackConsent get consent => current;

  @override
  Stream<SearchFeedbackConsent> get changes => _controller.stream;

  @override
  Future<void> grant() async => set(SearchFeedbackConsent.granted);

  @override
  Future<void> decline() async => set(SearchFeedbackConsent.declined);

  @override
  Future<void> revoke() async => set(SearchFeedbackConsent.declined);
}

class FakeSettingsStore implements SemanticSettingsStore {
  @override
  SemanticQuantization quantization = SemanticQuantization.int8;
  @override
  bool dataEnabled = false;
  @override
  bool isOfflineMode = false;
  @override
  bool downloadPaused = false;
  @override
  String? skippedVectorsRelease;

  @override
  Future<void> setDownloadPaused(bool value) async => downloadPaused = value;

  @override
  Future<void> setSkippedVectorsRelease(String? value) async =>
      skippedVectorsRelease = value;

  @override
  Future<void> setQuantization(SemanticQuantization value) async =>
      quantization = value;

  @override
  Future<void> setDataEnabled(bool value) async => dataEnabled = value;
}

/// מנוע מזויף שרושם קריאות. חיפוש ממתין ל-[searchGate] כשהוא מוגדר.
class FakeBackend implements SemanticEngineBackend {
  SemanticBackendStatus statusValue = const SemanticBackendStatus(
    state: SemanticBackendState.notConfigured,
    rawState: 'notConfigured',
  );
  SemanticVectorsSummary vectors = SemanticVectorsSummary.absent;
  SemanticFailure? openFailure;
  SemanticFailure? vectorsInfoFailure;

  /// כשלים להתקנות הבאות, לפי הסדר.
  final List<SemanticFailure> installFailures = [];
  Completer<void>? searchGate;
  Completer<void>? warmUpGate;
  final List<String> calls = [];
  final List<SemanticOpenRequest> openRequests = [];
  final List<SemanticInstallRequest> installRequests = [];
  final List<SemanticCancelHandle> searchHandles = [];

  @override
  Future<SemanticBackendStatus> status() async => statusValue;

  @override
  Future<SemanticVectorsSummary> vectorsInfo(String vectorsDir) async {
    final failure = vectorsInfoFailure;
    if (failure != null) throw failure;
    return vectors;
  }

  @override
  Future<SemanticInstallSummary> installVectors(
    SemanticInstallRequest request, {
    required SemanticCancelHandle cancel,
  }) async {
    calls.add('install');
    installRequests.add(request);
    if (installFailures.isNotEmpty) throw installFailures.removeAt(0);
    vectorsInfoFailure = null;
    vectors = const SemanticVectorsSummary(
      present: true,
      libraryVersion: 30,
      libraryReleaseTag: 'v30-20260930165019',
      segments: [
        SemanticSegmentSummary(
          id: 'f834cebcb6f8c72ece8884c9ce42a936',
          kind: 'base',
          fromLibraryVersion: 0,
          toLibraryVersion: 30,
          sizeBytes: 10,
        ),
      ],
    );
    return const SemanticInstallSummary(
      kind: 'base',
      libraryVersion: 30,
      segments: 1,
      bytesOnDisk: 10,
      needsCompaction: false,
      alreadyApplied: false,
    );
  }

  @override
  Future<void> verifyVectors(
    String vectorsDir, {
    required SemanticCancelHandle cancel,
  }) async => calls.add('verify');

  @override
  Future<SemanticCoverageSummary> coverage(
    String vectorsDir, {
    required SemanticCancelHandle cancel,
  }) async => throw UnimplementedError();

  @override
  Future<SemanticBackendStatus> open(SemanticOpenRequest request) async {
    calls.add('open');
    openRequests.add(request);
    final failure = openFailure;
    if (failure != null) throw failure;
    return statusValue = const SemanticBackendStatus(
      state: SemanticBackendState.ready,
      rawState: 'ready',
    );
  }

  @override
  Future<void> compactVectors(
    String vectorsDir, {
    int? liveLibraryVersion,
    required SemanticCancelHandle cancel,
  }) async => calls.add('compact');

  @override
  Future<void> disable() async => calls.add('disable');

  @override
  Future<SemanticSearchOutcome> search(
    SemanticSearchRequest request, {
    required SemanticCancelHandle cancel,
    SemanticRankingConfig? ranking,
  }) async {
    calls.add('search:${request.query}');
    searchHandles.add(cancel);
    final gate = request.query == kSemanticWarmUpQuery
        ? warmUpGate
        : searchGate;
    if (gate != null) await gate.future;
    if (cancel.isCancelled) {
      throw const SemanticFailure(SemanticFailureKind.cancelled);
    }
    return SemanticSearchOutcome(response: emptyResponse());
  }
}

SemanticSearchResponse emptyResponse() => SemanticSearchResponse(
  results: const [],
  totalCount: 0,
  lexicalTotalCount: 0,
  countsAreExact: false,
  requestedMode: SemanticRetrievalMode.hybrid,
  executedMode: SemanticExecutedMode.hybrid,
  semanticAvailable: true,
  latencyMs: BigInt.zero,
  candidateWindowTruncated: false,
  truncated: false,
);

/// מאתר מזויף: מחזיר [release] (או `null` = לא פורסם) ורושם את הגרסאות.
class FakeLocator extends SemanticVectorsReleaseLocator {
  FakeLocator([this.release]);

  SemanticVectorsRelease? release;
  final List<int> lookups = [];
  final List<String?> tags = [];

  @override
  Future<SemanticVectorsRelease?> findForLibraryVersion(
    int libraryVersion, {
    String? libraryTag,
  }) async {
    lookups.add(libraryVersion);
    tags.add(libraryTag);
    return release;
  }
}

/// הורדה מזויפת שכותבת קובץ קטן ורושמת את הכתובות.
class FakeDownloads {
  final List<String> urls = [];
  Object? error;

  /// ההורדה הבאה ממתינה לו; [isCancelled] האחרון נשמר לבדיקה.
  Completer<void>? gate;
  bool Function()? lastIsCancelled;

  Future<void> call({
    required String url,
    required String destPath,
    required String resumeIdentity,
    int? expectedSize,
    String? expectedSha256,
    void Function(int received, int? total)? onProgress,
    bool Function()? isCancelled,
  }) async {
    urls.add(url);
    lastIsCancelled = isCancelled;
    final pending = gate;
    if (pending != null) {
      gate = null;
      await pending.future;
    }
    if (isCancelled?.call() ?? false) throw const PatchDownloadCancelled();
    final failure = error;
    if (failure != null) throw failure;
    onProgress?.call(1, 1);
    await File(destPath).create(recursive: true);
    await File(destPath).writeAsString('x');
  }
}

/// בונה מאגר מעל תיקייה זמנית ו-fakes.
SemanticSearchRepository buildRepository({
  required Directory root,
  FakeBackend? backend,
  FakeConsentStore? consent,
  FakeSettingsStore? settings,
  SemanticVectorsReleaseLocator? locator,
  SemanticFileDownloader? download,
  int? libraryVersion = 30,
  bool platformSupported = true,
  int freeBytes = -1,
  Map<SemanticQuantization, SemanticModelRelease?>? modelReleases,
  bool secondaryWindow = false,
  Duration busyRetryDelay = const Duration(milliseconds: 20),
}) {
  return SemanticSearchRepository(
    backend: backend ?? FakeBackend(),
    consent: () => consent ?? FakeConsentStore(),
    settings: settings ?? FakeSettingsStore(),
    paths: () async => SemanticPaths(p.join(root.path, 'otzaria')),
    identityLoader: () async => bundledModelJson(),
    locator: locator ?? FakeLocator(),
    download: download ?? FakeDownloads().call,
    libraryVersion: () async => libraryVersion,
    onnxRuntimePath: () => '/app/onnxruntime/onnxruntime.dll',
    isPlatformSupported: () => platformSupported,
    diskSpace: (_) async => DiskSpaceInfo(volumeId: 'C', freeBytes: freeBytes),
    modelReleases: modelReleases ?? testModelReleases,
    isSecondaryWindow: () => secondaryWindow,
    busyRetryDelay: busyRetryDelay,
  );
}

/// ה-release האמיתי של int8, מכתובת בדיקה.
final Map<SemanticQuantization, SemanticModelRelease?> testModelReleases = {
  SemanticQuantization.int8: SemanticModelRelease(
    baseUrl: 'https://models.test/meivin',
    graph: kSemanticModelReleases[SemanticQuantization.int8]!.graph,
    tokenizer: kSemanticModelReleases[SemanticQuantization.int8]!.tokenizer,
    identity: kSemanticModelReleases[SemanticQuantization.int8]!.identity,
    license: kSemanticModelReleases[SemanticQuantization.int8]!.license,
  ),
  SemanticQuantization.fp32: null,
};

/// יוצר את קובצי המודל של [quantization] כאילו הורדו.
void installModelFiles(
  Directory root, [
  SemanticQuantization quantization = SemanticQuantization.int8,
]) {
  final paths = SemanticPaths(p.join(root.path, 'otzaria'));
  File(paths.modelFile(quantization)).createSync(recursive: true);
  File(paths.tokenizerFile).createSync(recursive: true);
  File(paths.licenseFile).createSync(recursive: true);
  File(paths.identityFile).writeAsStringSync(bundledModelJson());
  File(p.join(paths.modelDirectory, kSemanticOwnerMarker)).createSync();
}

const SemanticVectorsSummary installedV30 = SemanticVectorsSummary(
  present: true,
  libraryVersion: 30,
  libraryReleaseTag: 'v30-20260930165019',
  segments: [
    SemanticSegmentSummary(
      id: 'f834cebcb6f8c72ece8884c9ce42a936',
      kind: 'base',
      fromLibraryVersion: 0,
      toLibraryVersion: 30,
      sizeBytes: 1779752972,
    ),
  ],
);

SemanticVectorsRelease releaseV30({int parts = 1}) => SemanticVectorsRelease(
  libraryTag: 'v30-20260930165019',
  releaseTag: 'vectors-v30-20260930165019',
  toLibraryVersion: 30,
  kind: 'base',
  manifestJson: '{"kind":"base"}',
  publishedManifestSha256:
      '3dc43c8c9164753959a7aec16d25a8c3e93a04f9139d85f20a72a5ae91b5c5b2',
  files: [
    for (var i = 0; i < parts; i++)
      SemanticVectorsFile(
        name: parts == 1
            ? 'otzaria-vectors-0c3f95be-v30-base.oxv.zst'
            : 'otzaria-vectors-0c3f95be-v30-base.oxv.zst.part-00$i',
        downloadUrl: 'https://github.test/vectors/$i',
        size: 1,
        sha256: 'ab' * 32,
        assetId: '$i',
      ),
  ],
  segmentUncompressedSize: 10,
);
