import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive.dart' show ZipDecoder;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:http/http.dart' as http;
import 'package:otzaria/data/constants/database_constants.dart';
import 'package:otzaria/library_update/services/companion_assets_service.dart';
import 'package:otzaria/library_update/services/github_rate_limit.dart';
import 'package:otzaria/search/search_engine_gateway.dart'
    show SemanticSearchRequest;
import 'package:otzaria/search_feedback/search_feedback_api.dart';
import 'package:otzaria/search_feedback/search_feedback_service.dart';
import 'package:otzaria/semantic_search/engine/semantic_engine_backend.dart';
import 'package:otzaria/semantic_search/models/semantic_availability.dart';
import 'package:otzaria/semantic_search/models/semantic_engine_models.dart';
import 'package:otzaria/semantic_search/models/semantic_failure.dart';
import 'package:otzaria/semantic_search/models/semantic_model_identity.dart';
import 'package:otzaria/semantic_search/models/semantic_model_release.dart';
import 'package:otzaria/semantic_search/models/semantic_paths.dart';
import 'package:otzaria/semantic_search/models/semantic_vectors_family.dart';
import 'package:otzaria/semantic_search/models/semantic_vectors_release.dart';
import 'package:otzaria/semantic_search/onnx_runtime_locator.dart';
import 'package:otzaria/semantic_search/repository/semantic_data_ownership.dart';
import 'package:otzaria/semantic_search/repository/semantic_download_client.dart';
import 'package:otzaria/semantic_search/repository/semantic_platform_support.dart';
import 'package:otzaria/semantic_search/repository/semantic_release_locator.dart';
import 'package:otzaria/semantic_search/repository/semantic_settings_store.dart';
import 'package:otzaria/semantic_search/repository/semantic_staged_import.dart';
import 'package:otzaria/services/data_collection_service.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/utils/file/disk_free_space.dart';
import 'package:otzaria/utils/file/native_sha256.dart';
import 'package:otzaria/utils/file/zip_entry_io.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart'
    show
        SemanticHighlightTarget,
        SemanticPassageHighlight,
        SemanticRetrievalMode;
import 'package:path/path.dart' as p;
import 'package:seforim_library_updater/seforim_library_updater.dart'
    show PatchDownloadCancelled, PatchDownloadException, PatchNetworkException;

/// בתיקיית הוקטורים: ה-identity digest של סט ממשפחת החלונות.
const String kSemanticWindowsIdentityFileName = '.otzaria-windows-identity';

/// חיפוש החימום שאחרי הפתיחה: החיפוש המסונן הראשון בתהליך אורך כשנייה.
const String kSemanticWarmUpQuery = 'בריאת העולם';
const String kSemanticWarmUpFacet = '/תנ״ך';

/// הורדת קובץ עם resume ואימות SHA-256, כמו
/// [CompanionAssetsService.downloadVerifiedFile].
typedef SemanticFileDownloader =
    Future<void> Function({
      required String url,
      required String destPath,
      required String resumeIdentity,
      int? expectedSize,
      String? expectedSha256,
      void Function(int received, int? total)? onProgress,
      bool Function()? isCancelled,
    });

/// מחזור החיים של החיפוש הסמנטי: זמינות, הורדה והתקנה, פתיחה עצלה וחיפוש.
///
/// שום דבר כאן אינו רץ בעליית התוכנה: [instance] נוצר בגישה הראשונה, והמנוע
/// נפתח רק ב-[ensureOpen] או ב-[search]. ההורדה הראשונה רק דרך
/// [enableAndDownload]; אחריה הוקטורים מתעדכנים ברקע ([scheduleVectorsUpdate]).
class SemanticSearchRepository {
  SemanticSearchRepository({
    SemanticEngineBackend? backend,
    SearchFeedbackConsentStore Function()? consent,
    SemanticSettingsStore? settings,
    Future<SemanticPaths> Function()? paths,
    Future<String> Function(SemanticVectorsFamily family)? identityLoader,
    SemanticVectorsReleaseLocator? locator,
    SemanticFileDownloader? download,
    Future<int?> Function()? libraryVersion,
    String? Function()? onnxRuntimePath,
    bool Function()? isPlatformSupported,
    Future<DiskSpaceInfo> Function(String path)? diskSpace,
    this._modelReleases = kSemanticModelReleases,
    this._busyRetryDelay = const Duration(minutes: 2),
  }) : _backend = backend ?? createSemanticEngineBackend(),
       _consentFactory = consent ?? (() => SearchFeedbackService.instance),
       _settings = settings ?? const SettingsSemanticSettingsStore(),
       _paths = paths ?? _defaultPaths,
       _identityLoader =
           identityLoader ??
           ((family) => rootBundle.loadString(family.identityAsset)),
       _locator = locator ?? SemanticVectorsReleaseLocator(),
       _download =
           download ??
           CompanionAssetsService(
             clientFactory: SemanticDownloadClient.new,
           ).downloadVerifiedFile,
       _libraryVersion = libraryVersion ?? _defaultLibraryVersion,
       _onnxRuntimePath = onnxRuntimePath ?? bundledOnnxRuntimePath,
       _isPlatformSupported =
           isPlatformSupported ?? isSemanticSearchPlatformSupported,
       _diskSpace = diskSpace ?? getDiskSpaceInfo;

  static SemanticSearchRepository? _instance;

  /// המופע המשותף; נוצר בגישה הראשונה.
  static SemanticSearchRepository get instance =>
      _instance ??= SemanticSearchRepository();

  static final StreamController<SemanticAvailability> _sharedChanges =
      StreamController<SemanticAvailability>.broadcast();

  /// שינויי המצב של [instance], בלי ליצור אותו: האזנה כאן אינה עבודה בעלייה.
  static Stream<SemanticAvailability> get sharedAvailabilityChanges =>
      _sharedChanges.stream;

  final SemanticEngineBackend _backend;
  final SearchFeedbackConsentStore Function() _consentFactory;
  final SemanticSettingsStore _settings;
  final Future<SemanticPaths> Function() _paths;
  final Future<String> Function(SemanticVectorsFamily family) _identityLoader;
  final SemanticVectorsReleaseLocator _locator;
  final SemanticFileDownloader _download;
  final Future<int?> Function() _libraryVersion;
  final String? Function() _onnxRuntimePath;
  final bool Function() _isPlatformSupported;
  final Future<DiskSpaceInfo> Function(String path) _diskSpace;
  final Map<SemanticQuantization, SemanticModelRelease?> _modelReleases;
  final Duration _busyRetryDelay;

  final StreamController<SemanticAvailability> _changes =
      StreamController<SemanticAvailability>.broadcast();
  SemanticAvailability _availability = SemanticAvailability.initial;

  late final SearchFeedbackConsentStore _consent = _consentFactory();

  /// נתונים שמסייע ההורדה הכין מחליפים הורדה, רק בתוך עבודה שעברה את ההסכמה.
  late final SemanticStagedImport _staged = SemanticStagedImport(_paths);
  late final SemanticFileDownloader _fetch = _staged.wrap(
    _download,
    isOffline: () => _settings.isOfflineMode,
    onChecking: _showChecking,
    onSource: _showSource,
  );
  StreamSubscription<SearchFeedbackConsent>? _consentSubscription;
  final Map<SemanticVectorsFamily, SemanticModelIdentity> _identities = {};
  SemanticVectorsSummary? _vectors;

  Future<void>? _job;
  SemanticCancelHandle _jobCancel = SemanticCancelHandle();
  Future<void>? _compaction;
  SemanticCancelHandle _compactCancel = SemanticCancelHandle();

  /// ה-base שהשרשרת אליו נכשלה; אליו מורידים base בלבד.
  String? _deltaChainFailedFor;
  SemanticAvailabilityPhase? _jobPhase;
  SemanticDownloadProgress? _jobProgress;

  /// השלבים שהעבודה הנוכחית תעבור, וסך הבתים שלה — להתקדמות כוללת אחת.
  List<SemanticDownloadItem> _jobSteps = const [];
  int _jobTotalBytes = 0;
  int _jobModelBytes = 0;
  bool _jobFromStaged = false;
  SemanticFailure? _lastFailure;
  int? _unpublishedVersion;

  /// בקשת משתמש שהצטרפה לעבודה שרצה מקבלת גם היא את הכשל.
  bool _reportJobFailures = false;
  bool _moveInProgress = false;
  bool _needsRepair = false;
  String? _libraryTagHint;
  Timer? _busyRetry;

  Future<void>? _opening;
  int _lifecycleEpoch = 0;
  bool _repairModel = false;
  bool _updateRequested = false;
  bool _restartCancelledJob = false;
  SemanticQuantization? _openQuantization;
  final SemanticSearchSession _defaultSession = SemanticSearchSession();
  final Set<SemanticCancelHandle> _activeSearches = {};

  /// המצב האחרון שחושב.
  SemanticAvailability get availability => _availability;

  /// משדר כל שינוי במצב.
  Stream<SemanticAvailability> get availabilityChanges => _changes.stream;

  /// הדיוקים שיש להם release להורדה; הממשק מציע רק אותם.
  List<SemanticQuantization> get availableQuantizations => [
    for (final quantization in SemanticQuantization.values)
      if (_modelReleases[quantization] != null) quantization,
  ];

  /// דיוק מודל השאילתות בפועל: הבחירה השמורה, או int8 כשאין לה release.
  SemanticQuantization get quantization {
    final chosen = _settings.quantization;
    return _modelReleases[chosen] != null ? chosen : SemanticQuantization.int8;
  }

  /// טקסט רישיון המודל שהורד, או `null` כשהמודל לא הורד.
  Future<String?> readModelLicense() async {
    final file = File((await _paths()).licenseFile);
    return await file.exists() ? file.readAsString() : null;
  }

  /// מחשב מחדש את מצב הזמינות. לעולם אינו זורק.
  Future<SemanticAvailability> refresh() async {
    _listenToConsent();
    final consentGranted = _isConsentGranted();
    SemanticAvailability next;
    try {
      next = await _compute(consentGranted);
    } catch (error, stackTrace) {
      _log('refresh', error, stackTrace);
      next = SemanticAvailability(
        phase: SemanticAvailabilityPhase.failed,
        consentGranted: consentGranted,
        failure: SemanticFailure(SemanticFailureKind.internal, '$error'),
      );
    }
    _emit(next);
    return next;
  }

  /// הפעלה מפורשת של המשתמש: מוריד ומתקין את המודל ואת הוקטורים. מחייב
  /// הסכמה. התוצאה מתבטאת ב-[availability]; אינו זורק.
  Future<void> enableAndDownload() async {
    _lastFailure = null;
    _unpublishedVersion = null;
    if (!_isConsentGranted()) {
      await refresh();
      return;
    }
    await _settings.setDataEnabled(true);
    await _settings.setDownloadPaused(false);
    await _runJob(userInitiated: true);
  }

  /// עדכון ברקע אחרי עדכון ספרייה; לא פועל בלי הורדה קודמת, אחרי עצירה
  /// ידנית או בהעברת ספרייה. [libraryTag] חוסך סריקת releases.
  void scheduleVectorsUpdate({String? libraryTag}) {
    try {
      if (!_settings.dataEnabled ||
          _settings.downloadPaused ||
          _moveInProgress) {
        return;
      }
    } catch (error, stackTrace) {
      _log('scheduleVectorsUpdate', error, stackTrace);
      return;
    }
    if (libraryTag != null) _libraryTagHint = libraryTag;
    unawaited(_runJob(userInitiated: false));
  }

  /// מסתיים כשההורדה או ההתקנה שרצות מסתיימות.
  @visibleForTesting
  Future<void> get pendingJob => _job ?? Future.value();

  /// עוצר הורדה או התקנה שרצות; קובץ חלקי נשמר להמשך. עדכוני ספרייה לא
  /// מחדשים את ההורדה עד [enableAndDownload].
  Future<void> cancelDownload() async {
    _jobCancel.cancel();
    _compactCancel.cancel();
    await _settings.setDownloadPaused(true);
    await refresh();
  }

  /// בוחר את דיוק המודל; מוריד את החבילה החסרה אם הנתונים מופעלים.
  Future<void> setQuantization(SemanticQuantization value) async {
    if (value == quantization || _modelReleases[value] == null) return;
    await _settings.setQuantization(value);
    await _closeSession();
    _lastFailure = null;
    if (_settings.dataEnabled && _isConsentGranted()) {
      await _runJob(userInitiated: true);
    } else {
      await refresh();
    }
  }

  /// מוחק את המודל, הוקטורים וההורדות, ומפסיק את העדכון ברקע.
  Future<void> removeData() async {
    _jobCancel.cancel();
    _busyRetry?.cancel();
    await _job;
    await _stopCompaction();
    _busyRetry?.cancel();
    _cancelAllSearches();
    await _closeSession();
    await _settings.setDataEnabled(false);
    await _settings.setDownloadPaused(false);
    _vectors = null;
    _lastFailure = null;
    _unpublishedVersion = null;
    _needsRepair = false;
    _repairModel = false;
    try {
      final paths = await _paths();
      // רק תיקיות שלנו: תיקיית vectors של המשתמש באותו שם לא נמחקת.
      for (final dir in [
        paths.modelDirectory,
        paths.vectorsDirectory,
        paths.vectorsDownloadDirectory,
      ]) {
        await deleteSemanticOwnedDirectory(dir);
      }
    } on FileSystemException catch (error) {
      _lastFailure = SemanticFailure(SemanticFailureKind.internal, '$error');
    }
    await refresh();
  }

  /// פותח את הוקטורים והמודל בשימוש הראשון, ומריץ חימום ברקע.
  ///
  /// זורק [SemanticFailure]: [SemanticFailureKind.consentRequired] בלי הסכמה,
  /// [SemanticFailureKind.notReady] כשחסרים נתונים, או את כשל המנוע.
  Future<void> ensureOpen() =>
      _opening ??= _open().whenComplete(() => _opening = null);

  /// חיפוש סמנטי. מבטל רק את החיפוש הקודם של אותו [session].
  ///
  /// מחזיר `null` כשחיפוש חדש יותר החליף את זה (ביטול אינו כשל). זורק
  /// [SemanticFailure] בכל כשל אחר.
  Future<SemanticSearchOutcome?> search(
    SemanticSearchRequest request, {
    SemanticRankingConfig? ranking,
    SemanticSearchSession? session,
  }) async {
    final handle = (session ?? _defaultSession)._next();
    _activeSearches.add(handle);
    try {
      await ensureOpen();
      if (handle.isCancelled) return null;
      return await _backend.search(request, cancel: handle, ranking: ranking);
    } on SemanticFailure catch (failure) {
      if (handle.isCancelled || failure.kind == SemanticFailureKind.cancelled) {
        return null;
      }
      rethrow;
    } finally {
      _activeSearches.remove(handle);
    }
  }

  /// מסמן בכל יעד את הקטע הקרוב ל-[query]; רק אחרי חיפוש, ולכן אינו פותח.
  /// [cancel] מבוטל גם כשה-session נסגר. זורק [SemanticFailure] בכשל.
  Future<List<SemanticPassageHighlight>> passageHighlights(
    String query,
    List<SemanticHighlightTarget> targets,
    SemanticCancelHandle cancel,
  ) async {
    if (targets.isEmpty) return const [];
    _activeSearches.add(cancel);
    try {
      return await _backend.passageHighlights(query, targets, cancel: cancel);
    } finally {
      _activeSearches.remove(cancel);
    }
  }

  /// מבטל את החיפוש הרץ של [session] (ברירת המחדל: מי שלא העביר session).
  void cancelSearch({SemanticSearchSession? session}) =>
      (session ?? _defaultSession).cancel();

  void _cancelAllSearches() {
    for (final handle in List.of(_activeSearches)) {
      handle.cancel();
    }
  }

  /// לפני העברת הספרייה: עוצר הורדה/התקנה וחיפושים וסוגר את ה-session.
  /// הוא נפתח שוב מעצמו בחיפוש הבא, מהמיקום החדש.
  /// עד [finishLibraryMove] לא מתחילות הורדות והתקנות חדשות.
  Future<void> releaseForLibraryMove() async {
    _moveInProgress = true;
    _busyRetry?.cancel();
    _jobCancel.cancel();
    await _job;
    await _stopCompaction();
    _busyRetry?.cancel();
    _cancelAllSearches();
    await _closeSession();
    _vectors = null;
  }

  /// סוף העברת הספרייה (בהצלחה או בכשל): מתיר שוב הורדות והתקנות.
  void finishLibraryMove() {
    _moveInProgress = false;
    _vectors = null;
  }

  /// מה מותקן בתיקיית הוקטורים.
  Future<SemanticVectorsSummary> vectorsInfo() async =>
      _vectors = await _backend.vectorsInfo((await _paths()).vectorsDirectory);

  /// בדיקת שלמות מלאה של הוקטורים; זורק [SemanticFailure] על נזק.
  Future<void> verifyVectors({SemanticCancelHandle? cancel}) async =>
      _backend.verifyVectors(
        (await _paths()).vectorsDirectory,
        cancel: cancel ?? SemanticCancelHandle(),
      );

  /// כמה משורות האינדקס הפתוח מכוסות בוקטורים.
  Future<SemanticCoverageSummary> coverage({
    SemanticCancelHandle? cancel,
  }) async => _backend.coverage(
    (await _paths()).vectorsDirectory,
    cancel: cancel ?? SemanticCancelHandle(),
  );

  /// תמונת המנוע לטלמטריה: מצב, זהות המודל, החבילה והוקטורים המותקנים.
  Future<SemanticEngineSnapshot> engineSnapshot() async {
    final status = await _safeStatus();
    var vectors = _vectors;
    if (vectors == null) {
      try {
        vectors = await vectorsInfo();
      } catch (error, stackTrace) {
        _log('engineSnapshot', error, stackTrace);
      }
    }
    final installed = vectors != null && vectors.present ? vectors : null;
    final family = await _installedFamily(installed);
    SemanticModelIdentity? identity;
    try {
      identity = await _loadIdentity(family);
    } catch (error, stackTrace) {
      _log('engineSnapshot', error, stackTrace);
    }
    final quantization = this.quantization;
    return SemanticEngineSnapshot(
      state: status.rawState,
      modelFamilyId: identity?.familyId,
      modelQuantization: quantization.name,
      modelPackageChecksum: identity?.packageFor(quantization)?.checksum,
      embeddingDim: identity?.embeddingDim,
      vectorsReleaseTag:
          installed == null || installed.libraryReleaseTag.isEmpty
          ? null
          : '${family.releaseTagPrefix}${installed.libraryReleaseTag}',
      vectorsLibraryVersion: installed?.libraryVersion,
      vectorSegments: installed?.segments.length,
    );
  }

  // ── זמינות ──────────────────────────────────────────────────────────────

  Future<SemanticAvailability> _compute(bool consentGranted) async {
    SemanticAvailability of(
      SemanticAvailabilityPhase phase, {
      SemanticHiddenReason? hiddenReason,
      SemanticFailure? failure,
      bool stagedDataFound = false,
    }) => SemanticAvailability(
      phase: phase,
      consentGranted: consentGranted,
      hiddenReason: hiddenReason,
      progress: _jobProgress,
      failure: failure,
      unpublishedLibraryVersion: _unpublishedVersion,
      pausedByUser: _settings.downloadPaused,
      stagedDataFound: stagedDataFound,
    );

    if (!_isPlatformSupported()) {
      return of(
        SemanticAvailabilityPhase.hidden,
        hiddenReason: SemanticHiddenReason.unsupportedPlatform,
      );
    }
    final status = await _safeStatus();
    if (status.state == SemanticBackendState.notInBuild) {
      return of(
        SemanticAvailabilityPhase.hidden,
        hiddenReason: SemanticHiddenReason.engineNotInBuild,
      );
    }
    if (!consentGranted) return of(SemanticAvailabilityPhase.consentRequired);
    final jobPhase = _jobPhase;
    if (jobPhase != null) return of(jobPhase);
    final failure = _lastFailure;
    if (failure != null) {
      return of(SemanticAvailabilityPhase.failed, failure: failure);
    }
    final installed = await _isInstalled();
    // _isInstalled מגלה סט פגום ורושם אותו ככשל.
    final found = _lastFailure;
    if (found != null) {
      return of(SemanticAvailabilityPhase.failed, failure: found);
    }
    if (installed) return of(SemanticAvailabilityPhase.ready);
    if (_unpublishedVersion != null) {
      return of(SemanticAvailabilityPhase.vectorsNotPublished);
    }
    return of(
      SemanticAvailabilityPhase.needsDownload,
      stagedDataFound: await _staged.hasData(),
    );
  }

  Future<bool> _isInstalled() async {
    final paths = await _paths();
    final quantization = this.quantization;
    if (!await File(paths.modelFile(quantization)).exists() ||
        !await File(paths.tokenizerFile).exists()) {
      return false;
    }
    try {
      final vectors = _vectors = await _backend.vectorsInfo(
        paths.vectorsDirectory,
      );
      // סט שנפסל בפתיחה אינו מותקן עד שיוחלף; אחרת "מוכן" ונכשל שוב בחיפוש.
      return vectors.present && !_needsRepair;
    } on SemanticFailure catch (failure) {
      if (failure.kind != SemanticFailureKind.artifactCorrupt) rethrow;
      _needsRepair = true;
      _lastFailure = failure;
      return false;
    }
  }

  void _emit(SemanticAvailability next) {
    if (next == _availability) return;
    _availability = next;
    _changes.add(next);
    if (identical(this, _instance)) {
      _sharedChanges.add(next);
    }
  }

  bool _isConsentGranted() {
    try {
      return _consent.consent == SearchFeedbackConsent.granted;
    } catch (error, stackTrace) {
      _log('consent', error, stackTrace);
      return false;
    }
  }

  void _listenToConsent() {
    if (_consentSubscription != null) return;
    try {
      _consentSubscription = _consent.changes.listen((consent) async {
        if (consent != SearchFeedbackConsent.granted) {
          _jobCancel.cancel();
          _compactCancel.cancel();
          _cancelAllSearches();
          await _closeSession();
        }
        await refresh();
      });
    } catch (error, stackTrace) {
      _log('consent', error, stackTrace);
    }
  }

  // ── פתיחה ───────────────────────────────────────────────────────────────

  Future<void> _open() async {
    final epoch = _lifecycleEpoch;
    if (_moveInProgress) {
      throw const SemanticFailure(SemanticFailureKind.libraryMoving);
    }
    final availability = await refresh();
    if (!availability.consentGranted) {
      throw const SemanticFailure(SemanticFailureKind.consentRequired);
    }
    if (availability.phase != SemanticAvailabilityPhase.ready) {
      throw SemanticFailure(
        availability.failure?.kind ?? SemanticFailureKind.notReady,
      );
    }
    final quantization = this.quantization;
    // פתיחה מחדש של האינדקס יוצרת מנוע חדש בלי session; בלי הבדיקה כל
    // חיפוש נופל למילולי עד הפעלה מחדש של התוכנה.
    if (_openQuantization == quantization &&
        (await _safeStatus()).state != SemanticBackendState.notConfigured) {
      return;
    }
    await _closeSession(waitForOpening: false, invalidateOpening: false);
    final paths = await _paths();
    final identity = await _loadIdentity(await _installedFamily(_vectors));
    if (epoch != _lifecycleEpoch || !_isConsentGranted() || _moveInProgress) {
      throw const SemanticFailure(SemanticFailureKind.cancelled);
    }
    try {
      await _backend.open(
        SemanticOpenRequest(
          vectorsDir: paths.vectorsDirectory,
          modelPath: paths.modelFile(quantization),
          modelIdentityJson: identity.rawJson,
          onnxRuntimePath: _onnxRuntimePath(),
        ),
      );
    } on SemanticFailure catch (failure) {
      // סט פגום, או של מתכון שהמנוע כבר לא קורא, מוחלף בהורדת ה-base מחדש.
      if (failure.kind == SemanticFailureKind.artifactCorrupt ||
          failure.kind == SemanticFailureKind.artifactIncompatible) {
        _needsRepair = true;
      }
      if ({
        SemanticFailureKind.modelInvalid,
        SemanticFailureKind.modelIdentityMismatch,
        SemanticFailureKind.tokenizerMissing,
      }.contains(failure.kind)) {
        _repairModel = true;
      }
      if (epoch == _lifecycleEpoch) {
        _lastFailure = failure;
        await refresh();
      }
      rethrow;
    }
    if (epoch != _lifecycleEpoch || !_isConsentGranted() || _moveInProgress) {
      await _backend.disable();
      throw const SemanticFailure(SemanticFailureKind.cancelled);
    }
    _openQuantization = quantization;
    unawaited(_warmUp());
  }

  Future<void> _warmUp() async {
    final handle = SemanticCancelHandle();
    _activeSearches.add(handle);
    try {
      await _backend.search(
        const SemanticSearchRequest(
          query: kSemanticWarmUpQuery,
          facets: [kSemanticWarmUpFacet],
          limit: 1,
          retrievalMode: SemanticRetrievalMode.semanticOnly,
        ),
        cancel: handle,
      );
    } catch (error, stackTrace) {
      _log('warmUp', error, stackTrace);
    } finally {
      _activeSearches.remove(handle);
    }
  }

  Future<void> _closeSession({
    bool waitForOpening = true,
    bool invalidateOpening = true,
  }) async {
    if (invalidateOpening) _lifecycleEpoch++;
    if (waitForOpening) {
      try {
        await _opening;
      } catch (_) {
        /* הפותח כבר קיבל את הכשל. */
      }
    }
    if (_openQuantization == null) return;
    _openQuantization = null;
    try {
      await _backend.disable();
    } catch (error, stackTrace) {
      _log('disable', error, stackTrace);
    }
  }

  // ── הורדה והתקנה ────────────────────────────────────────────────────────

  Future<void> _runJob({required bool userInitiated}) {
    if (userInitiated) _reportJobFailures = true;
    if (_job != null) {
      _updateRequested = true;
      if (userInitiated && _jobCancel.isCancelled) _restartCancelledJob = true;
      return _job!;
    }
    return _job = _jobBody().whenComplete(() => _job = null);
  }

  Future<void> _jobBody() async {
    _jobCancel = SemanticCancelHandle();
    try {
      do {
        _updateRequested = false;
        _restartCancelledJob = false;
        try {
          await _performJob();
          _lastFailure = null;
        } on PatchDownloadCancelled {
          // ביטול מפורש אינו כשל.
        } catch (error, stackTrace) {
          final failure = _failureOf(error);
          if (failure.kind == SemanticFailureKind.vectorsBusy) {
            _scheduleBusyRetry();
          } else if (failure.kind != SemanticFailureKind.cancelled) {
            _log('download', error, stackTrace);
            // כשל ברקע לא מציף את הממשק; בקשה חדשה מריצה את הגרסה העדכנית.
            if (_reportJobFailures) _lastFailure = failure;
          }
        }
        _jobPhase = null;
        _jobProgress = null;
        await refresh();
        if (_restartCancelledJob &&
            !_settings.downloadPaused &&
            !_moveInProgress &&
            _isConsentGranted()) {
          _jobCancel = SemanticCancelHandle();
        }
      } while (_updateRequested &&
          !_jobCancel.isCancelled &&
          !_settings.downloadPaused &&
          !_moveInProgress &&
          _isConsentGranted());
    } finally {
      _staged.clearVerification();
      _jobPhase = null;
      _jobProgress = null;
      _jobSteps = const [];
      _jobTotalBytes = 0;
      _jobModelBytes = 0;
      _jobFromStaged = false;
      _reportJobFailures = false;
    }
  }

  /// התקנה אחרת של הסט רצה: מנסים שוב מאוחר יותר, בלי כשל.
  void _scheduleBusyRetry() {
    _busyRetry?.cancel();
    _busyRetry = Timer(_busyRetryDelay, scheduleVectorsUpdate);
  }

  /// ברקע מדלג בשקט; בבקשת משתמש זורק [kind].
  void _skipOrThrow(SemanticFailureKind kind) {
    if (_reportJobFailures) throw SemanticFailure(kind);
  }

  Future<void> _performJob() async {
    if (!_isPlatformSupported()) return;
    if (!_isConsentGranted()) {
      return _skipOrThrow(SemanticFailureKind.consentRequired);
    }
    final offline = _settings.isOfflineMode;
    _jobFromStaged = await _staged.hasData();
    if (offline && !_jobFromStaged) {
      return _skipOrThrow(SemanticFailureKind.offline);
    }
    if (_moveInProgress) return _skipOrThrow(SemanticFailureKind.libraryMoving);
    if ((await _safeStatus()).state == SemanticBackendState.notInBuild) return;

    final paths = await _paths();
    final modelIdentity = await _loadIdentity(SemanticVectorsFamily.anchor);
    final version = await _libraryVersion();
    if (version == null) {
      throw const SemanticFailure(SemanticFailureKind.libraryVersionUnknown);
    }
    SemanticVectorsSummary installed;
    try {
      installed = await _backend.vectorsInfo(paths.vectorsDirectory);
    } on SemanticFailure catch (failure) {
      if (failure.kind != SemanticFailureKind.artifactCorrupt) rethrow;
      installed = SemanticVectorsSummary.absent;
      _needsRepair = true;
    }
    _vectors = installed;

    // ה-release נמצא לפני הורדת המודל: בלי וקטורים לגרסה הזו אין מה להוריד.
    SemanticVectorsRelease? release;
    SemanticVectorsRelease? onlineRelease;
    final installedFamily = await _installedFamily(installed);
    final upToDate =
        installed.present &&
        installed.libraryVersion == version &&
        installedFamily == _preferredFamily &&
        !_needsRepair;
    if (!upToDate) {
      final candidates = await _vectorsCandidates(installedFamily);
      release = await _staged.locate(
        version,
        offline: offline,
        candidates: candidates,
        online: () async =>
            onlineRelease = await _locator.findForLibraryVersion(
              version,
              libraryTag: _libraryTagHint,
              candidates: candidates,
            ),
      );
      if (release == null) {
        _unpublishedVersion = version;
      } else {
        _unpublishedVersion = null;
        if (release.releaseTag == _settings.skippedVectorsRelease) {
          release = null;
        } else if (_isInstalledRelease(installed, release)) {
          // המשפחה המועדפת לא פורסמה, והסט של זו שפורסמה כבר מותקן.
          release = null;
        }
      }
    }
    if (release == null && !installed.present) return;

    // deltas רק מהרשת: נתונים מוכנים של מסייע ההורדה הם base, והוא גובר.
    final chain =
        release != null &&
            identical(release, onlineRelease) &&
            !_jobFromStaged &&
            _deltaChainFailedFor != release.releaseTag &&
            !_needsRepair &&
            installed.present &&
            installedFamily == release.family &&
            installed.identityDigest == release.identityDigest
        ? await _locator.findDeltaChain(
            target: release,
            installedVersion: installed.libraryVersion,
          )
        : null;
    final model = await _missingModelFiles(paths, quantization);
    _jobModelBytes = model.missing.fold(0, (sum, t) => sum + t.file.size);
    _jobTotalBytes = _jobModelBytes + _downloadSizeOf(chain ?? [?release]);
    _jobSteps = [
      if (model.missing.isNotEmpty) SemanticDownloadItem.model,
      if (release != null) ...[
        SemanticDownloadItem.vectors,
        SemanticDownloadItem.install,
      ],
    ];
    await _ensureModel(paths, modelIdentity, quantization, model);
    if (_jobCancel.isCancelled) return;
    if (release != null) {
      await _installRelease(paths, release, chain: chain);
      if (_jobCancel.isCancelled) return;
    }
    _compactIfNeeded();
  }

  /// מתקין את [base], או את [chain] — ה-deltas אליו — כשיש. delta שהמנוע
  /// דוחה מחזיר ל-[base]; [vectorsStart] הוא מה שכבר נספר בהתקדמות.
  Future<void> _installRelease(
    SemanticPaths paths,
    SemanticVectorsRelease base, {
    List<SemanticVectorsRelease>? chain,
    int? vectorsStart,
  }) async {
    final plan = chain ?? [base];
    await _stopCompaction();
    if (_jobCancel.isCancelled) return;
    await _ensureOwnedOrAbsent(paths.vectorsDirectory, allowEmpty: true);
    await _ensureOwnedOrAbsent(paths.vectorsDownloadDirectory);
    await markSemanticDirectory(paths.vectorsDownloadDirectory);
    final downloadDir = Directory(paths.vectorsDownloadDirectory);
    await _removeForeignDownloads(downloadDir, plan);
    var done = vectorsStart ?? _jobModelBytes;
    await _ensureDiskSpace(downloadDir.path, plan, done);
    for (final release in plan) {
      bool installed;
      try {
        final segment = await _downloadVectors(downloadDir.path, release, done);
        if (_jobCancel.isCancelled) return;
        installed = await _installStep(paths, release, segment, done);
      } catch (error, stackTrace) {
        if (chain == null || !_isBrokenDelta(error)) rethrow;
        _log('delta ${release.releaseTag}', error, stackTrace);
        installed = false;
      }
      if (!installed) {
        // בלי זה כל עבודה הייתה מחשבת שוב את אותה שרשרת ונכשלת בה.
        _deltaChainFailedFor = base.releaseTag;
        _jobTotalBytes = done + base.downloadSize;
        return _installRelease(paths, base, vectorsStart: done);
      }
      done += release.downloadSize;
      // צעד שהותקן אינו נחוץ עוד; ההורדות החלקיות של הבאים נשמרות.
      if (plan.length > 1) {
        await _removeForeignDownloads(
          downloadDir,
          plan.sublist(plan.indexOf(release) + 1),
        );
      }
    }
    try {
      await deleteSemanticOwnedDirectory(downloadDir.path);
    } on FileSystemException catch (error, stackTrace) {
      _log('cleanup', error, stackTrace);
    }
  }

  /// מתקין release אחד מ-[segment]; `false` כש-delta אינו ממשיך את הסט.
  /// [before] — הבתים שנספרו לפני ההורדה של [release].
  Future<bool> _installStep(
    SemanticPaths paths,
    SemanticVectorsRelease release,
    String segment,
    int before,
  ) async {
    final family = release.family;
    final identity = await _loadIdentity(family);
    _setJob(
      SemanticAvailabilityPhase.installing,
      _progressOf(SemanticDownloadItem.install, before + release.downloadSize),
    );
    final repair = _needsRepair;
    // ב-Windows אי אפשר להחליף קובץ ממופה, ומשפחה אחרת נפתחת עם model.json אחר.
    final familyChanges =
        _vectors?.present == true && family != await _installedFamily(_vectors);
    if (repair || familyChanges) {
      _cancelAllSearches();
      await _closeSession();
    }
    // לפני ההתקנה: קריסה אחריה לא תשאיר סט חלונות בלי סימון.
    if (family == SemanticVectorsFamily.windows &&
        release.identityDigest.isNotEmpty) {
      await markSemanticDirectory(paths.vectorsDirectory);
      await File(
        _windowsIdentityFile(paths),
      ).writeAsString(release.identityDigest, flush: true);
    }
    try {
      await _backend.installVectors(
        SemanticInstallRequest(
          vectorsDir: paths.vectorsDirectory,
          segmentPath: segment,
          manifestJson: release.manifestJson,
          publishedManifestSha256: release.publishedManifestSha256,
          modelIdentityJson: identity.rawJson,
        ),
        cancel: _jobCancel,
      );
    } on SemanticFailure catch (failure) {
      if (failure.kind != SemanticFailureKind.artifactIncompatible) rethrow;
      // delta שאינו ממשיך את הסט (delta.*, או פרסום חוזר): ה-base מחליף אותו.
      if (release.isDelta) {
        _log('install', failure, StackTrace.current);
        return false;
      }
      // פרסום חוזר, או chunking/store שהמנוע לא קורא: לא מורידים שוב.
      if (!const {
        'segment_id',
        'model.chunking_identity',
        'store.store_format_version',
        'store.vector_precision',
      }.contains(failure.field)) {
        rethrow;
      }
      _log('install', failure, StackTrace.current);
      await _settings.setSkippedVectorsRelease(release.releaseTag);
    }
    _needsRepair = false;
    if (repair) _lastFailure = null;
    _vectors = await _backend.vectorsInfo(paths.vectorsDirectory);
    return true;
  }

  /// מאחד ברקע סט שהמנוע מבקש לאחד (אחרי deltas); לעולם לא בעליית התוכנה.
  void _compactIfNeeded() {
    if (_vectors?.needsCompaction != true ||
        _compaction != null ||
        _moveInProgress) {
      return;
    }
    final cancel = _compactCancel = SemanticCancelHandle();
    _compaction = _compact(cancel).whenComplete(() => _compaction = null);
  }

  Future<void> _compact(SemanticCancelHandle cancel) async {
    try {
      final dir = (await _paths()).vectorsDirectory;
      // גרסת המסד אינה מוכיחה שהאינדקס מלא ועדכני; בלי גרסת אינדקס מאומתת
      // מאחדים בלי לנפות רשומות מול האינדקס, שעשוי להיות חלקי.
      await _backend.compactVectors(dir, cancel: cancel);
      if (!cancel.isCancelled) _vectors = await _backend.vectorsInfo(dir);
    } on SemanticFailure catch (failure) {
      if (failure.kind == SemanticFailureKind.vectorsBusy) {
        _scheduleBusyRetry();
      } else if (failure.kind != SemanticFailureKind.cancelled) {
        _log('compact', failure, StackTrace.current);
      }
    } catch (error, stackTrace) {
      _log('compact', error, stackTrace);
    }
  }

  /// מבטל איחוד שרץ וממתין לו: התקנה, מחיקה והעברה צריכות את הסט פנוי.
  Future<void> _stopCompaction() async {
    _compactCancel.cancel();
    await _compaction;
  }

  /// delta פגום או נדחה: ה-base מחליף אותו. רשת, מקום וביטול — לא.
  static bool _isBrokenDelta(Object error) => switch (error) {
    PatchDownloadException() => true,
    SemanticFailure(:final kind) => !const {
      SemanticFailureKind.cancelled,
      SemanticFailureKind.vectorsBusy,
      SemanticFailureKind.insufficientDiskSpace,
      SemanticFailureKind.offline,
      SemanticFailureKind.network,
      SemanticFailureKind.rateLimited,
    }.contains(kind),
    _ => false,
  };

  static int _downloadSizeOf(List<SemanticVectorsRelease> plan) =>
      plan.fold(0, (sum, release) => sum + release.downloadSize);

  /// לא כותבים לתוך תיקייה באותו שם שאינה שלנו.
  static Future<void> _ensureOwnedOrAbsent(
    String dir, {
    bool allowEmpty = false,
  }) async {
    final directory = Directory(dir);
    if (!await directory.exists() || await isSemanticOwnedDirectory(dir)) {
      return;
    }
    if (allowEmpty && await directory.list().isEmpty) return;
    throw SemanticFailure(
      SemanticFailureKind.internal,
      '$dir exists and does not belong to semantic search',
    );
  }

  /// קבצי רכיב החיפוש שחסרים (או פגומים בתיקון) ל-[quantization].
  Future<_ModelPlan> _missingModelFiles(
    SemanticPaths paths,
    SemanticQuantization quantization,
  ) async {
    final release = _modelReleases[quantization];
    if (release == null) {
      throw SemanticFailure(
        SemanticFailureKind.modelSourceNotConfigured,
        'no release for ${quantization.name}',
      );
    }
    final targets = [
      (file: release.graph, dest: paths.modelFile(quantization)),
      (file: release.tokenizer, dest: paths.tokenizerFile),
      (file: release.license, dest: paths.licenseFile),
      if (!await File(paths.identityFile).exists())
        (file: release.identity, dest: paths.identityFile),
    ];
    final missing = <({SemanticModelFile file, String dest})>[];
    for (final target in targets) {
      if (!await File(target.dest).exists() ||
          (_repairModel &&
              !await _verifyModelFile(
                target.dest,
                target.file.size,
                target.file.sha256,
              ))) {
        missing.add(target);
      }
    }
    return (release: release, missing: missing);
  }

  Future<void> _ensureModel(
    SemanticPaths paths,
    SemanticModelIdentity identity,
    SemanticQuantization quantization,
    _ModelPlan model,
  ) async {
    final release = model.release;
    final missing = model.missing;
    await _ensureOwnedOrAbsent(paths.modelDirectory, allowEmpty: true);
    await markSemanticDirectory(paths.modelDirectory);
    final identityFile = File(paths.identityFile);
    var done = 0;
    for (final target in missing) {
      // הורדה לשם זמני: קובץ חלקי בשם הסופי היה נחשב מותקן.
      final partial = '${target.dest}.part';
      final before = done;
      _reportProgress(SemanticDownloadItem.model, before, force: true);
      await _fetchModelFile(release, target.file, partial, before);
      done += target.file.size;
      if (target.file == release.identity) {
        await _checkPublishedIdentity(partial, identity);
        await CompanionAssetsService.discardDownload(partial);
      } else {
        await File(partial).rename(target.dest);
        await CompanionAssetsService.discardDownload(partial);
      }
    }
    _repairModel = false;
    // המנוע מקבל את הנכס המצורף; העותק שבתיקייה תמיד זהה לו.
    if (!await identityFile.exists() ||
        await identityFile.readAsString() != identity.rawJson) {
      await identityFile.writeAsString(identity.rawJson, flush: true);
    }
  }

  /// [file] אל [partial]; אם הורדתו נכשלה (לא בביטול) ויש לו zip — ממנו.
  Future<void> _fetchModelFile(
    SemanticModelRelease release,
    SemanticModelFile file,
    String partial,
    int before,
  ) async {
    void progress(int received, int? _) =>
        _reportProgress(SemanticDownloadItem.model, before + received);
    bool cancelled() => _jobCancel.isCancelled;
    try {
      await _fetch(
        url: release.urlOf(file),
        destPath: partial,
        resumeIdentity: file.sha256,
        expectedSize: file.size,
        expectedSha256: file.sha256,
        onProgress: progress,
        isCancelled: cancelled,
      );
      return;
    } catch (error, stackTrace) {
      final zipped = file.zipped;
      if (zipped == null || cancelled() || _isCancellation(error)) rethrow;
      _log('download ${file.name}; trying ${zipped.name}', error, stackTrace);
    }
    final zipped = file.zipped!;
    await CompanionAssetsService.discardDownload(partial);
    final archive = '${p.withoutExtension(partial)}.zip.part';
    await _fetch(
      url: release.urlOf(zipped),
      destPath: archive,
      resumeIdentity: zipped.sha256,
      expectedSize: zipped.size,
      expectedSha256: zipped.sha256,
      onProgress: progress,
      isCancelled: cancelled,
    );
    try {
      await _unzipModelFile(archive, file, partial);
    } finally {
      await CompanionAssetsService.discardDownload(archive);
    }
  }

  static bool _isCancellation(Object error) =>
      error is PatchDownloadCancelled ||
      (error is SemanticFailure && error.kind == SemanticFailureKind.cancelled);

  /// ה-model.json שב-release אמור להיות זהה לנכס המצורף; אם לא — הנכס גובר.
  static Future<void> _checkPublishedIdentity(
    String downloaded,
    SemanticModelIdentity bundled,
  ) async {
    final published = await File(downloaded).readAsString();
    if (published != bundled.rawJson) {
      debugPrint(
        '[SemanticSearch] model.json in the release differs from the bundled '
        'asset; using the bundled copy',
      );
    }
  }

  /// [before] — מה שכבר נספר: רכיב החיפוש וצעדים קודמים בשרשרת.
  Future<String> _downloadVectors(
    String downloadDir,
    SemanticVectorsRelease release,
    int before,
  ) async {
    var done = before;
    final parts = <String>[];
    _reportProgress(SemanticDownloadItem.vectors, done, force: true);
    for (final file in release.files) {
      final dest = p.join(downloadDir, file.name);
      final start = done;
      await _fetch(
        url: file.downloadUrl,
        destPath: dest,
        resumeIdentity:
            '${release.releaseTag}|${file.name}|${file.assetId}|${file.sha256}',
        expectedSize: file.size,
        expectedSha256: file.sha256,
        onProgress: (received, _) =>
            _reportProgress(SemanticDownloadItem.vectors, start + received),
        isCancelled: () => _jobCancel.isCancelled,
      );
      done += file.size;
      parts.add(dest);
    }
    if (parts.length == 1) return parts.single;

    // segment מפוצל: החלקים מחוברים לפי סדר המניפסט ונמחקים בדרך.
    final segment = p.join(downloadDir, release.segmentFileName);
    final sink = File(segment).openWrite();
    try {
      for (final part in parts) {
        await sink.addStream(File(part).openRead());
        await CompanionAssetsService.discardDownload(part);
      }
    } finally {
      await sink.close();
    }
    return segment;
  }

  /// מוחק מתיקיית ההורדות כל מה שאינו של [plan]; הורדות חלקיות שלו נשמרות.
  Future<void> _removeForeignDownloads(
    Directory dir,
    List<SemanticVectorsRelease> plan,
  ) async {
    final names = [
      for (final release in plan) ...release.files.map((file) => file.name),
    ];
    await for (final entity in dir.list()) {
      final name = p.basename(entity.path);
      if (name == kSemanticOwnerMarker || names.any(name.startsWith)) continue;
      try {
        await entity.delete(recursive: true);
      } on FileSystemException catch (error, stackTrace) {
        _log('cleanup', error, stackTrace);
      }
    }
  }

  /// צריך מקום להורדות שנותרו ול-segments הפרוסים שההתקנות יכתבו.
  Future<void> _ensureDiskSpace(
    String downloadDir,
    List<SemanticVectorsRelease> plan,
    int done,
  ) async {
    final info = await _diskSpace(downloadDir);
    if (info.freeBytes < 0) return;
    _reportProgress(SemanticDownloadItem.vectors, done, force: true);
    var remaining = 0;
    for (final file in plan.expand((release) => release.files)) {
      // קובץ מוכן באותו כונן עובר ב-rename ואינו תופס מקום נוסף.
      final staged = await _staged.stagedFile(file.name);
      if (staged != null &&
          info.volumeId != null &&
          (await _diskSpace(p.dirname(staged.path))).volumeId ==
              info.volumeId &&
          await _staged.verifiedStagedFile(
                file.name,
                file.size,
                file.sha256,
                onChecking: _showChecking,
                isCancelled: () => _jobCancel.isCancelled,
              ) !=
              null) {
        continue;
      }
      final partial = File(p.join(downloadDir, file.name));
      final have = await partial.exists() ? await partial.length() : 0;
      remaining += (file.size - have).clamp(0, file.size);
    }
    final needed =
        remaining +
        plan.fold(0, (sum, release) => sum + release.segmentUncompressedSize);
    if (info.freeBytes < needed) {
      throw SemanticFailure(
        SemanticFailureKind.insufficientDiskSpace,
        'needs $needed bytes, ${info.freeBytes} free',
      );
    }
  }

  void _setJob(
    SemanticAvailabilityPhase phase,
    SemanticDownloadProgress? progress,
  ) {
    _jobPhase = phase;
    _jobProgress = progress;
    _emit(
      SemanticAvailability(
        phase: phase,
        consentGranted: true,
        progress: progress,
        unpublishedLibraryVersion: _unpublishedVersion,
      ),
    );
  }

  /// בדיקת קובץ מוכן: אותו שלב, בלי מדידה.
  void _showChecking(bool checking) {
    final progress = _jobProgress;
    if (progress == null) return;
    _setJob(
      SemanticAvailabilityPhase.downloading,
      progress.withChecking(checking),
    );
  }

  void _showSource(bool staged) {
    if (_jobFromStaged == staged) return;
    _jobFromStaged = staged;
    final progress = _jobProgress;
    if (progress != null) {
      _reportProgress(progress.item, progress.receivedBytes, force: true);
    }
  }

  /// ההתקדמות הכוללת של העבודה בשלב [item], אחרי [received] בתים.
  SemanticDownloadProgress _progressOf(
    SemanticDownloadItem item,
    int received,
  ) {
    final index = _jobSteps.indexOf(item);
    return SemanticDownloadProgress(
      item: item,
      receivedBytes: received,
      totalBytes: _jobTotalBytes > 0 ? _jobTotalBytes : null,
      step: index < 0 ? 1 : index + 1,
      stepCount: _jobSteps.isEmpty ? 1 : _jobSteps.length,
      staged: _jobFromStaged,
    );
  }

  /// מעדכן את ההתקדמות בצעדים של חצי אחוז, לא בכל chunk.
  void _reportProgress(
    SemanticDownloadItem item,
    int received, {
    bool force = false,
  }) {
    final previous = _jobProgress;
    final total = _jobTotalBytes;
    final step = total > 0 ? total ~/ 200 : 1 << 20;
    if (!force &&
        previous != null &&
        previous.item == item &&
        received - previous.receivedBytes < step &&
        received != total) {
      return;
    }
    _setJob(SemanticAvailabilityPhase.downloading, _progressOf(item, received));
  }

  // ── עזרים ───────────────────────────────────────────────────────────────

  Future<SemanticBackendStatus> _safeStatus() async {
    try {
      return await _backend.status();
    } catch (error, stackTrace) {
      _log('status', error, stackTrace);
      return const SemanticBackendStatus(
        state: SemanticBackendState.other,
        rawState: 'unknown',
      );
    }
  }

  Future<SemanticModelIdentity> _loadIdentity(
    SemanticVectorsFamily family,
  ) async => _identities[family] ??= SemanticModelIdentity.parse(
    await _identityLoader(family),
  );

  SemanticVectorsFamily get _preferredFamily => _backend.supportsLongLineWindows
      ? SemanticVectorsFamily.windows
      : SemanticVectorsFamily.anchor;

  /// המשפחות שמחפשים להן release, המועדפת ראשונה. מי שכבר מחזיק סט של
  /// המשפחה המועדפת ממתין לה, ולא יורד בינתיים לסט הישן.
  Future<List<SemanticVectorsCandidate>> _vectorsCandidates(
    SemanticVectorsFamily installed,
  ) async => [
    for (final family in {
      _preferredFamily,
      if (installed != _preferredFamily) SemanticVectorsFamily.anchor,
    })
      (
        family: family,
        chunkingIdentity: (await _loadIdentity(family)).chunkingIdentity,
      ),
  ];

  /// ה-identity digest של משפחת החלונות, בתוך תיקיית הסט: עובר איתה בהעברה
  /// ואינו תלוי בהגדרות.
  static String _windowsIdentityFile(SemanticPaths paths) =>
      p.join(paths.vectorsDirectory, kSemanticWindowsIdentityFileName);

  /// משפחת הסט המותקן; סט שלא סומן כסט חלונות הוא מהמשפחה הישנה.
  Future<SemanticVectorsFamily> _installedFamily(
    SemanticVectorsSummary? vectors,
  ) async {
    if (vectors == null || vectors.identityDigest.isEmpty) {
      return SemanticVectorsFamily.anchor;
    }
    final marker = File(_windowsIdentityFile(await _paths()));
    final windows =
        await marker.exists() &&
        (await marker.readAsString()).trim() == vectors.identityDigest;
    return windows
        ? SemanticVectorsFamily.windows
        : SemanticVectorsFamily.anchor;
  }

  /// [installed] הוא כבר הסט של [release]: אותה גרסה ואותה זהות.
  bool _isInstalledRelease(
    SemanticVectorsSummary installed,
    SemanticVectorsRelease release,
  ) =>
      !_needsRepair &&
      installed.present &&
      installed.libraryVersion == release.toLibraryVersion &&
      installed.identityDigest.isNotEmpty &&
      installed.identityDigest == release.identityDigest;

  static SemanticFailure _failureOf(Object error) => switch (error) {
    final SemanticFailure failure => failure,
    GithubRateLimitException() => SemanticFailure(
      SemanticFailureKind.rateLimited,
      '$error',
    ),
    PatchDownloadException() => SemanticFailure(
      SemanticFailureKind.checksumMismatch,
      '$error',
    ),
    PatchNetworkException() ||
    http.ClientException() ||
    SocketException() ||
    TimeoutException() => SemanticFailure(
      SemanticFailureKind.network,
      '$error',
    ),
    _ => SemanticFailure(SemanticFailureKind.internal, '$error'),
  };

  static Future<SemanticPaths> _defaultPaths() async {
    final library =
        Settings.getValue<String>(SettingsRepository.keyLibraryPath) ?? '.';
    return SemanticPaths(
      DatabaseConstants.getDatabaseDirectoryPath(),
      root: p.dirname(library),
    );
  }

  static Future<int?> _defaultLibraryVersion() async =>
      int.tryParse(await DataCollectionService().readLibraryVersion());

  static void _log(String step, Object error, StackTrace stackTrace) {
    debugPrint('[SemanticSearch] $step: $error\n$stackTrace');
  }
}

/// release של רכיב החיפוש והקבצים ממנו שחסרים במכשיר.
typedef _ModelPlan = ({
  SemanticModelRelease release,
  List<({SemanticModelFile file, String dest})> missing,
});

/// ערוץ חיפוש של צרכן אחד (למשל כרטיסייה): חיפוש חדש מבטל רק את הקודם בו.
class SemanticSearchSession {
  SemanticCancelHandle? _current;

  SemanticCancelHandle _next() {
    _current?.cancel();
    return _current = SemanticCancelHandle();
  }

  /// מבטל את החיפוש הרץ בערוץ, אם יש.
  void cancel() => _current?.cancel();
}

Future<bool> _verifyModelFile(
  String path,
  int expectedSize,
  String expectedSha,
) => Isolate.run(() async {
  final file = File(path);
  if (!await file.exists() || await file.length() != expectedSize) return false;
  return await sha256OfFileFast(path) == expectedSha;
});

/// [file] מתוך ה-zip [archive] אל [dest]: רשומה יחידה בשמו ובגודלו, ואז ה-SHA-256 שלו.
Future<void> _unzipModelFile(
  String archive,
  SemanticModelFile file,
  String dest,
) async {
  final name = file.name;
  final size = file.size;
  final extracted = await Isolate.run(() async {
    final input = openZipInput(archive);
    try {
      final entries = ZipDecoder().decodeStream(input).files;
      if (entries.length != 1) return false;
      final entry = entries.single;
      if (!entry.isFile || entry.name != name || entry.size != size) {
        return false;
      }
      await writeZipEntry(entry, dest);
      File(dest).openSync(mode: FileMode.append)
        ..flushSync()
        ..closeSync();
      return File(dest).lengthSync() == size;
    } on FileSystemException {
      rethrow;
    } catch (_) {
      // zip פגום (גם RangeError של נתונים קטועים) אינו מחזיק את הקובץ.
      return false;
    } finally {
      input.closeSync();
    }
  });
  if (!extracted || !await _verifyModelFile(dest, size, file.sha256)) {
    await CompanionAssetsService.discardDownload(dest);
    throw SemanticFailure(
      SemanticFailureKind.checksumMismatch,
      '${p.basename(archive)} does not hold the published $name',
    );
  }
}
