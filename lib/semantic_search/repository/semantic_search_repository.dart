import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:http/http.dart' as http;
import 'package:otzaria/core/windowing/window_role.dart';
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
import 'package:otzaria/semantic_search/models/semantic_vectors_release.dart';
import 'package:otzaria/semantic_search/onnx_runtime_locator.dart';
import 'package:otzaria/semantic_search/repository/semantic_data_ownership.dart';
import 'package:otzaria/semantic_search/repository/semantic_platform_support.dart';
import 'package:otzaria/semantic_search/repository/semantic_release_locator.dart';
import 'package:otzaria/semantic_search/repository/semantic_settings_store.dart';
import 'package:otzaria/services/data_collection_service.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/utils/file/disk_free_space.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart'
    show SemanticRetrievalMode;
import 'package:path/path.dart' as p;
import 'package:seforim_library_updater/seforim_library_updater.dart'
    show PatchDownloadCancelled, PatchDownloadException, PatchNetworkException;

/// נתיב הנכס של `model.json` באפליקציה.
const String kSemanticModelIdentityAsset =
    'assets/semantic/meivin-round2-onnx/model.json';

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
    Future<String> Function()? identityLoader,
    SemanticVectorsReleaseLocator? locator,
    SemanticFileDownloader? download,
    Future<int?> Function()? libraryVersion,
    String? Function()? onnxRuntimePath,
    bool Function()? isPlatformSupported,
    Future<DiskSpaceInfo> Function(String path)? diskSpace,
    bool Function()? isSecondaryWindow,
    this._modelReleases = kSemanticModelReleases,
    this._busyRetryDelay = const Duration(minutes: 2),
  }) : _isSecondaryWindow = isSecondaryWindow ?? (() => WindowRole.isSecondary),
       _backend = backend ?? createSemanticEngineBackend(),
       _consentFactory = consent ?? (() => SearchFeedbackService.instance),
       _settings = settings ?? const SettingsSemanticSettingsStore(),
       _paths = paths ?? _defaultPaths,
       _identityLoader =
           identityLoader ??
           (() => rootBundle.loadString(kSemanticModelIdentityAsset)),
       _locator = locator ?? SemanticVectorsReleaseLocator(),
       _download = download ?? CompanionAssetsService().downloadVerifiedFile,
       _libraryVersion = libraryVersion ?? _defaultLibraryVersion,
       _onnxRuntimePath = onnxRuntimePath ?? bundledOnnxRuntimePath,
       _isPlatformSupported =
           isPlatformSupported ?? isSemanticSearchPlatformSupported,
       _diskSpace = diskSpace ?? getDiskSpaceInfo;

  static SemanticSearchRepository? _instance;

  /// המופע המשותף; נוצר בגישה הראשונה.
  static SemanticSearchRepository get instance =>
      _instance ??= SemanticSearchRepository();

  final SemanticEngineBackend _backend;
  final SearchFeedbackConsentStore Function() _consentFactory;
  final SemanticSettingsStore _settings;
  final Future<SemanticPaths> Function() _paths;
  final Future<String> Function() _identityLoader;
  final SemanticVectorsReleaseLocator _locator;
  final SemanticFileDownloader _download;
  final Future<int?> Function() _libraryVersion;
  final String? Function() _onnxRuntimePath;
  final bool Function() _isPlatformSupported;
  final Future<DiskSpaceInfo> Function(String path) _diskSpace;
  final Map<SemanticQuantization, SemanticModelRelease?> _modelReleases;
  final bool Function() _isSecondaryWindow;
  final Duration _busyRetryDelay;

  final StreamController<SemanticAvailability> _changes =
      StreamController<SemanticAvailability>.broadcast();
  SemanticAvailability _availability = SemanticAvailability.initial;

  late final SearchFeedbackConsentStore _consent = _consentFactory();
  StreamSubscription<SearchFeedbackConsent>? _consentSubscription;
  SemanticModelIdentity? _identity;
  SemanticVectorsSummary? _vectors;

  Future<void>? _job;
  SemanticCancelHandle _jobCancel = SemanticCancelHandle();
  SemanticAvailabilityPhase? _jobPhase;
  SemanticDownloadProgress? _jobProgress;
  SemanticFailure? _lastFailure;
  int? _unpublishedVersion;

  /// בקשת משתמש שהצטרפה לעבודה שרצה מקבלת גם היא את הכשל.
  bool _reportJobFailures = false;
  bool _moveInProgress = false;
  bool _needsRepair = false;
  String? _libraryTagHint;
  Timer? _busyRetry;

  Future<void>? _opening;
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
    if (_isSecondaryWindow()) {
      _lastFailure = const SemanticFailure(SemanticFailureKind.secondaryWindow);
      await refresh();
      return;
    }
    if (!_isConsentGranted()) {
      await refresh();
      return;
    }
    await _settings.setDataEnabled(true);
    await _settings.setDownloadPaused(false);
    await _runJob(userInitiated: true);
  }

  /// עדכון ברקע אחרי עדכון ספרייה; לא פועל בלי הורדה קודמת, אחרי עצירה
  /// ידנית, בחלון משני או בהעברת ספרייה. [libraryTag] חוסך סריקת releases.
  void scheduleVectorsUpdate({String? libraryTag}) {
    try {
      if (!_settings.dataEnabled ||
          _settings.downloadPaused ||
          _isSecondaryWindow() ||
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
    await _settings.setDownloadPaused(true);
    await refresh();
  }

  /// בוחר את דיוק המודל; מוריד את החבילה החסרה אם הנתונים מופעלים.
  Future<void> setQuantization(SemanticQuantization value) async {
    if (value == quantization || _modelReleases[value] == null) return;
    if (_isSecondaryWindow()) return;
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
    if (_isSecondaryWindow()) {
      _lastFailure = const SemanticFailure(SemanticFailureKind.secondaryWindow);
      await refresh();
      return;
    }
    _jobCancel.cancel();
    _busyRetry?.cancel();
    await _job;
    _cancelAllSearches();
    await _closeSession();
    await _settings.setDataEnabled(false);
    await _settings.setDownloadPaused(false);
    _vectors = null;
    _lastFailure = null;
    _unpublishedVersion = null;
    _needsRepair = false;
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
    SemanticModelIdentity? identity;
    try {
      identity = await _loadIdentity();
    } catch (error, stackTrace) {
      _log('engineSnapshot', error, stackTrace);
    }
    var vectors = _vectors;
    if (vectors == null) {
      try {
        vectors = await vectorsInfo();
      } catch (error, stackTrace) {
        _log('engineSnapshot', error, stackTrace);
      }
    }
    final installed = vectors != null && vectors.present ? vectors : null;
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
          : 'vectors-${installed.libraryReleaseTag}',
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
    }) => SemanticAvailability(
      phase: phase,
      consentGranted: consentGranted,
      hiddenReason: hiddenReason,
      progress: _jobProgress,
      failure: failure,
      unpublishedLibraryVersion: _unpublishedVersion,
      pausedByUser: _settings.downloadPaused,
      isSecondaryWindow: _isSecondaryWindow(),
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
    return of(
      _unpublishedVersion != null
          ? SemanticAvailabilityPhase.vectorsNotPublished
          : SemanticAvailabilityPhase.needsDownload,
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
      return vectors.present;
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
    if (_openQuantization == quantization) return;
    await _closeSession();
    final paths = await _paths();
    final identity = await _loadIdentity();
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
      // סט פגום מתוקן בהתקנה חוזרת של אותו release ("נסה שוב").
      if (failure.kind == SemanticFailureKind.artifactCorrupt) {
        _needsRepair = true;
      }
      _lastFailure = failure;
      await refresh();
      rethrow;
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

  Future<void> _closeSession() async {
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
    return _job ??= _jobBody();
  }

  Future<void> _jobBody() async {
    _jobCancel = SemanticCancelHandle();
    try {
      await _performJob();
    } on PatchDownloadCancelled {
      // ביטול מפורש אינו כשל.
    } catch (error, stackTrace) {
      final failure = _failureOf(error);
      if (failure.kind == SemanticFailureKind.vectorsBusy) {
        _scheduleBusyRetry();
      } else if (failure.kind != SemanticFailureKind.cancelled) {
        _log('download', error, stackTrace);
        // כשל ברקע לא מציף את הממשק; ההרצה הבאה תנסה שוב.
        if (_reportJobFailures) _lastFailure = failure;
      }
    } finally {
      _job = null;
      _jobPhase = null;
      _jobProgress = null;
      _reportJobFailures = false;
    }
    await refresh();
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
    if (_isSecondaryWindow()) {
      return _skipOrThrow(SemanticFailureKind.secondaryWindow);
    }
    if (!_isConsentGranted()) {
      return _skipOrThrow(SemanticFailureKind.consentRequired);
    }
    if (_settings.isOfflineMode) {
      return _skipOrThrow(SemanticFailureKind.offline);
    }
    if (_moveInProgress) return _skipOrThrow(SemanticFailureKind.libraryMoving);
    if ((await _safeStatus()).state == SemanticBackendState.notInBuild) return;

    final paths = await _paths();
    final identity = await _loadIdentity();
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
    final upToDate =
        installed.present &&
        installed.libraryVersion == version &&
        !_needsRepair;
    if (!upToDate) {
      release = await _locator.findForLibraryVersion(
        version,
        libraryTag: _libraryTagHint,
      );
      if (release == null) {
        _unpublishedVersion = version;
      } else {
        _unpublishedVersion = null;
        if (release.releaseTag == _settings.skippedVectorsRelease) {
          release = null;
        }
      }
    }
    if (release == null && !installed.present) return;

    await _ensureModel(paths, identity, quantization);
    if (_jobCancel.isCancelled || release == null) return;
    await _installRelease(paths, identity, release);
  }

  Future<void> _installRelease(
    SemanticPaths paths,
    SemanticModelIdentity identity,
    SemanticVectorsRelease release,
  ) async {
    await _ensureOwnedOrAbsent(paths.vectorsDirectory, allowEmpty: true);
    await _ensureOwnedOrAbsent(paths.vectorsDownloadDirectory);
    await markSemanticDirectory(paths.vectorsDownloadDirectory);
    final downloadDir = Directory(paths.vectorsDownloadDirectory);
    await _removeForeignDownloads(downloadDir, release);
    await _ensureDiskSpace(downloadDir.path, release);
    final segment = await _downloadVectors(downloadDir.path, release);
    if (_jobCancel.isCancelled) return;

    _setJob(SemanticAvailabilityPhase.installing, null);
    final repair = _needsRepair;
    if (repair) {
      // ב-Windows אי אפשר להחליף קובץ ממופה: התיקון מחייב לסגור את ה-session.
      _cancelAllSearches();
      await _closeSession();
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
      // פרסום חוזר בבתים אחרים של גרסה מותקנת: הסט תקין, ולא מורידים שוב.
      if (failure.kind != SemanticFailureKind.artifactIncompatible ||
          failure.field != 'segment_id') {
        rethrow;
      }
      _log('install', failure, StackTrace.current);
      await _settings.setSkippedVectorsRelease(release.releaseTag);
    }
    _needsRepair = false;
    if (repair) _lastFailure = null;
    _vectors = await _backend.vectorsInfo(paths.vectorsDirectory);
    try {
      await deleteSemanticOwnedDirectory(downloadDir.path);
    } on FileSystemException catch (error, stackTrace) {
      _log('cleanup', error, stackTrace);
    }
  }

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

  Future<void> _ensureModel(
    SemanticPaths paths,
    SemanticModelIdentity identity,
    SemanticQuantization quantization,
  ) async {
    final release = _modelReleases[quantization];
    if (release == null) {
      throw SemanticFailure(
        SemanticFailureKind.modelSourceNotConfigured,
        'no release for ${quantization.name}',
      );
    }
    await markSemanticDirectory(paths.modelDirectory);
    final identityFile = File(paths.identityFile);
    final targets = [
      (file: release.graph, dest: paths.modelFile(quantization)),
      (file: release.tokenizer, dest: paths.tokenizerFile),
      (file: release.license, dest: paths.licenseFile),
      if (!await identityFile.exists())
        (file: release.identity, dest: paths.identityFile),
    ];
    final missing = [
      for (final target in targets)
        if (!await File(target.dest).exists()) target,
    ];
    final total = missing.fold(0, (sum, target) => sum + target.file.size);
    var done = 0;
    for (final target in missing) {
      // הורדה לשם זמני: קובץ חלקי בשם הסופי היה נחשב מותקן.
      final partial = '${target.dest}.part';
      final before = done;
      _reportProgress(SemanticDownloadItem.model, before, total, force: true);
      await _download(
        url: release.urlOf(target.file),
        destPath: partial,
        resumeIdentity: target.file.sha256,
        expectedSize: target.file.size,
        expectedSha256: target.file.sha256,
        onProgress: (received, _) => _reportProgress(
          SemanticDownloadItem.model,
          before + received,
          total,
        ),
        isCancelled: () => _jobCancel.isCancelled,
      );
      done += target.file.size;
      if (target.file == release.identity) {
        await _checkPublishedIdentity(partial, identity);
        await CompanionAssetsService.discardDownload(partial);
      } else {
        await File(partial).rename(target.dest);
        await CompanionAssetsService.discardDownload(partial);
      }
    }
    // המנוע מקבל את הנכס המצורף; העותק שבתיקייה תמיד זהה לו.
    if (!await identityFile.exists() ||
        await identityFile.readAsString() != identity.rawJson) {
      await identityFile.writeAsString(identity.rawJson, flush: true);
    }
  }

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

  Future<String> _downloadVectors(
    String downloadDir,
    SemanticVectorsRelease release,
  ) async {
    final total = release.downloadSize;
    var done = 0;
    final parts = <String>[];
    _setJob(
      SemanticAvailabilityPhase.downloading,
      SemanticDownloadProgress(
        item: SemanticDownloadItem.vectors,
        receivedBytes: 0,
        totalBytes: total,
      ),
    );
    for (final file in release.files) {
      final dest = p.join(downloadDir, file.name);
      final before = done;
      await _download(
        url: file.downloadUrl,
        destPath: dest,
        resumeIdentity:
            '${release.releaseTag}|${file.name}|${file.assetId}|${file.sha256}',
        expectedSize: file.size,
        expectedSha256: file.sha256,
        onProgress: (received, _) => _reportProgress(
          SemanticDownloadItem.vectors,
          before + received,
          total,
        ),
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

  Future<void> _removeForeignDownloads(
    Directory dir,
    SemanticVectorsRelease release,
  ) async {
    final names = release.files.map((file) => file.name).toList();
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

  /// צריך מקום להורדה שנותרה ול-segment הפרוס שההתקנה תכתוב.
  Future<void> _ensureDiskSpace(
    String downloadDir,
    SemanticVectorsRelease release,
  ) async {
    final info = await _diskSpace(downloadDir);
    if (info.freeBytes < 0) return;
    var remaining = 0;
    for (final file in release.files) {
      final partial = File(p.join(downloadDir, file.name));
      final have = await partial.exists() ? await partial.length() : 0;
      remaining += (file.size - have).clamp(0, file.size);
    }
    final needed = remaining + release.segmentUncompressedSize;
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

  /// מעדכן את ההתקדמות בצעדים של חצי אחוז, לא בכל chunk.
  void _reportProgress(
    SemanticDownloadItem item,
    int received,
    int? total, {
    bool force = false,
  }) {
    final previous = _jobProgress;
    final step = total != null && total > 0 ? total ~/ 200 : 1 << 20;
    if (!force &&
        previous != null &&
        previous.item == item &&
        received - previous.receivedBytes < step &&
        received != total) {
      return;
    }
    _setJob(
      SemanticAvailabilityPhase.downloading,
      SemanticDownloadProgress(
        item: item,
        receivedBytes: received,
        totalBytes: total,
      ),
    );
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

  Future<SemanticModelIdentity> _loadIdentity() async =>
      _identity ??= SemanticModelIdentity.parse(await _identityLoader());

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
