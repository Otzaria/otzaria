import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/core/error_log_file.dart';
import 'package:otzaria/data/constants/database_constants.dart';
import 'package:otzaria/data/data_providers/database_library_provider.dart';
import 'package:otzaria/data/data_providers/db_read_worker.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:otzaria/data/sqlite/library_vfs.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/utils/file/disk_free_space.dart';
import 'package:otzaria/utils/file/zstd_stream_extractor.dart';
import 'package:path/path.dart' as p;
import 'package:otzaria/data/sqlite/sqlite3_api.dart' as sqlite3;
import 'package:seforim_library_updater/seforim_library_updater.dart';

import '../services/library_access_gate.dart';
import '../services/library_runtime_refresh_service.dart';
import '../services/library_zdb_install.dart';
import '../services/streaming_patch_downloader.dart';
import '../services/update_sqlite_setup.dart';

/// שלבי תהליך העדכון — לתצוגת הודעות למשתמש.
enum LibraryUpdatePhase {
  checking,
  downloading,
  verifying,
  applying,
  refreshing,

  /// ייעול אחסון ה-zdb אחרי עדכון: בסיס חדש או דחיסה (ראו [LibraryUpdateProgress.stage]).
  optimizing,
  done,
}

/// מצב התקדמות שמדווח במהלך העדכון.
class LibraryUpdateProgress {
  final LibraryUpdatePhase phase;
  final int stepIndex;
  final int totalSteps;
  final int? bytesDownloaded;
  final int? bytesTotal;

  /// תת-שלב גולמי בתוך ה-apply (מ-`PatchApplier.onStage`), לתצוגה מפורטת.
  final String? stage;

  /// יחס התקדמות (0..1) בתוך שלבי ה-apply הארוכים (שורות ב-upserts/deletes,
  /// בתים באימות ה-hash); null כשאין מדידה לשלב.
  final double? applyProgress;

  const LibraryUpdateProgress({
    required this.phase,
    this.stepIndex = 0,
    this.totalSteps = 0,
    this.bytesDownloaded,
    this.bytesTotal,
    this.stage,
    this.applyProgress,
  });
}

typedef LibraryUpdateProgressCallback =
    void Function(LibraryUpdateProgress progress);

/// נורה סינכרונית ברגע שבו ה-DB המלא החדש כבר החליף את הישן ואין עוד נקודת
/// ביטול בטוחה. המאזין חייב לבצע עבודה סינכרונית וקלה בלבד.
typedef FullDbReplacedCallback = void Function();

typedef FullDbExtractor =
    Future<void> Function(String archivePath, String outputPath);

/// אין מספיק מקום פנוי בדיסק לעדכון (הורדה מלאה או צעד דלתא) — נבדק לפני
/// תחילת ההורדה.
class LibraryUpdateDiskSpaceException implements Exception {
  final String message;
  const LibraryUpdateDiskSpaceException(this.message);

  @override
  String toString() => message;
}

/// הורדה מלאה בפורמט הישן (`seforim.db.zst`) כשהספרייה הפעילה היא seforim.zdb:
/// הארכיון מחולץ ל-SQLite רגיל, ובסיס zdb מוחלף רק דרך installZdb.
class LibraryUpdateZdbFullDownloadUnsupportedException implements Exception {
  const LibraryUpdateZdbFullDownloadUnsupportedException();

  @override
  String toString() =>
      'הורדה מלאה בפורמט הישן (seforim.db.zst) אינה נתמכת בספרייה דחוסה '
      '(seforim.zdb)';
}

/// תוצאת [LibraryStorageMaintainer.maintainLibraryStorage].
enum LibraryStorageMaintenance {
  /// אין zdb, או שה-overlay קטן מהסף.
  notNeeded,

  /// הותקן בסיס עדכני שהורד (ה-overlay נמחק).
  rebased,

  /// בסיס + overlay נדחסו מקומית לבסיס חדש.
  compacted,

  /// נדרש, אך נדחה לבדיקה הבאה (busy, אין מקום, המשתמש קורא, ביטול).
  deferred,
}

/// ייעול אחסון הספרייה אחרי עדכון. נפרד מ-[LibraryUpdateService] כי אינו
/// חלק מתוכנית העדכון, ולעולם אינו מכשיל אותה.
abstract interface class LibraryStorageMaintainer {
  Future<LibraryStorageMaintenance> maintainLibraryStorage({
    LibraryUpdateProgressCallback? onProgress,
    bool Function()? isCancelled,
  });
}

/// תוצאת מסלול דלתא ברמת האפליקציה.
///
/// מעבר למזהי הספרים, נשמר גם האם השתנו טבלאות שלא ניתן למפות לספרים
/// מסוימים. במקרה כזה נדרש reconcile מלא של אינדקס החיפוש.
class LibraryDeltaApplyResult {
  final Set<int> changedBookIds;
  final bool requiresFullIndexRefresh;
  final int appliedSteps;

  const LibraryDeltaApplyResult({
    this.changedBookIds = const {},
    this.requiresFullIndexRefresh = false,
    this.appliedSteps = 0,
  });

  bool get hasDatabaseChanges => appliedSteps > 0;

  LibraryDeltaApplyResult addStep(PatchApplyResult step) =>
      LibraryDeltaApplyResult(
        changedBookIds: {...changedBookIds, ...step.booksTouched},
        requiresFullIndexRefresh:
            requiresFullIndexRefresh || step.hasChangesOutsideBooksTouched,
        appliedSteps: appliedSteps + 1,
      );
}

/// העדכון הוחל בהצלחה, אך בבדיקה שאחרי ה-commit נמצאו טבלאות שאף צעד לא נגע
/// בהן ותוכנן סוטה מהצפוי — הספרייה המקומית אינה זהה לגרסה הרשמית.
class LibraryDeltaContentDriftException implements Exception {
  final List<String> driftedTables;
  final LibraryDeltaApplyResult appliedResult;

  const LibraryDeltaContentDriftException({
    required this.driftedTables,
    required this.appliedResult,
  });

  @override
  String toString() =>
      'LibraryDeltaContentDriftException(${driftedTables.join(', ')})';
}

/// כשל אחרי שלפחות צעד דלתא אחד כבר הושלם ונכתב ל-DB.
///
/// הצעד שנכשל עצמו אטומי ולא נכתב, אך הצעדים שקדמו לו נשארים תקינים ויש
/// לדווח עליהם ל-BLoC כדי שלא יאבד ריענון הספרייה/האינדקס.
class PartiallyAppliedLibraryDeltaException implements Exception {
  final Object cause;
  final LibraryDeltaApplyResult appliedResult;
  final Object? refreshError;

  const PartiallyAppliedLibraryDeltaException({
    required this.cause,
    required this.appliedResult,
    this.refreshError,
  });

  @override
  String toString() =>
      'PartiallyAppliedLibraryDeltaException('
      '${appliedResult.appliedSteps} steps): $cause'
      '${refreshError == null ? '' : '; refresh failed: $refreshError'}';
}

/// ממשק שירות עדכון הספרייה — מאפשר ל-BLoC להיבדק מול מימוש מזויף.
abstract interface class LibraryUpdateService {
  Future<RecoveryResult> recoverIfNeeded();
  Future<LibraryUpdatePlan> checkForUpdate({required bool allowPrerelease});

  /// מחזיר את השינויים שהוחלו — לריענון הספרייה ואינדקס החיפוש.
  Future<LibraryDeltaApplyResult> applyDeltaPlan(
    LibraryUpdatePlan plan, {
    LibraryUpdateProgressCallback? onProgress,
    bool Function()? isCancelled,
  });
  Future<void> applyFullDownload(
    LibraryUpdatePlan plan, {
    LibraryUpdateProgressCallback? onProgress,
    FullDbReplacedCallback? onDbReplaced,
    bool Function()? isCancelled,
  });
}

/// מתזמר את כל תהליך עדכון הספרייה: התאוששות, בדיקת עדכון, הורדה, החלת
/// patches (אטומית, ב-Isolate), וריענון runtime.
class LibraryUpdateRepository
    implements LibraryUpdateService, LibraryStorageMaintainer {
  final LibraryUpdateDiscovery discovery;
  final LibraryUpdatePlanner planner;
  final LocalDbVersionReader versionReader;
  final PatchDownloader downloader;
  final LibraryDbRecoveryService recovery;
  final LibraryRuntimeRefreshService refreshService;
  final FullDbExtractor fullDbExtractor;

  /// משעה את הספרייה בכל החלונות לפני החלפת קובץ המסד.
  final LibraryAccessGate accessGate;

  /// ניתנים להזרקה לצורך בדיקות.
  final String Function() dbPathProvider;
  final Future<String> Function() dataRootProvider;
  final String Function() nowTimestamp;
  final Future<DiskSpaceInfo> Function(String dirPath) diskSpaceProvider;
  final Future<PatchApplier> Function() applierProvider;
  final Future<void> Function() sqliteTempDirectoryInitializer;

  /// האם מותר להשעות את הספרייה לדקות לדחיסה מקומית (המשתמש אינו קורא).
  final bool Function() isLibraryIdle;

  /// נקרא אחרי ש-seforim.zdb החליף את seforim.db, להעברת הגדרת הנתיב.
  final Future<void> Function(String legacyPath, String zdbPath)
  onLegacyDbReplaced;

  LibraryUpdateRepository({
    required this.discovery,
    this.planner = const LibraryUpdatePlanner(
      supportedDbSchemaVersion: DatabaseConstants.readableDbSchemaVersion,
    ),
    this.versionReader = const LocalDbVersionReader(),
    required this.downloader,
    this.recovery = const LibraryDbRecoveryService(),
    this.refreshService = const LibraryRuntimeRefreshService(),
    FullDbExtractor? fullDbExtractor,
    LibraryAccessGate? accessGate,
    String Function()? dbPathProvider,
    Future<String> Function()? dataRootProvider,
    String Function()? nowTimestamp,
    Future<DiskSpaceInfo> Function(String dirPath)? diskSpaceProvider,
    Future<PatchApplier> Function()? applierProvider,
    Future<void> Function()? sqliteTempDirectoryInitializer,
    bool Function()? isLibraryIdle,
    Future<void> Function(String legacyPath, String zdbPath)?
    onLegacyDbReplaced,
  }) : isLibraryIdle = isLibraryIdle ?? _neverIdle,
       onLegacyDbReplaced = onLegacyDbReplaced ?? _retargetEffectiveDbPath,
       dbPathProvider = dbPathProvider ?? DatabaseConstants.getDatabasePath,
       dataRootProvider = dataRootProvider ?? AppPaths.getDataRootPath,
       nowTimestamp = nowTimestamp ?? (() => DateTime.now().toIso8601String()),
       fullDbExtractor = fullDbExtractor ?? _defaultFullDbExtractor,
       accessGate = accessGate ?? LibraryAccessGate.instance,
       diskSpaceProvider = diskSpaceProvider ?? getDiskSpaceInfo,
       applierProvider =
           applierProvider ??
           (() => LibraryUpdateSqliteSetup.instance.prepareApplier()),
       sqliteTempDirectoryInitializer =
           sqliteTempDirectoryInitializer ??
           _installSqliteTempDirectoryWhenQuiesced;

  static bool _neverIdle() => false;

  /// באנדרואיד המסד עשוי לשבת בעותק פנימי שנתיבו שמור בהגדרות.
  static Future<void> _retargetEffectiveDbPath(
    String legacyPath,
    String zdbPath,
  ) async {
    final key = SettingsRepository.keyDbEffectivePath;
    if (Settings.getValue<String>(key) != legacyPath) return;
    await Settings.setValue<String>(key, zdbPath);
  }

  // ה-plan אינו נושא את מניפסט ה-DB המלא; נשמר מהבדיקה האחרונה.
  ReleaseAsset? _latestFullDbAsset;
  FullDbManifest? _latestFullDbManifest;
  bool _lastAllowPrerelease = false;

  void _rememberDiscovery(LibraryDiscoveryResult result) {
    _latestFullDbAsset = result.latestFullDbAsset;
    _latestFullDbManifest = result.latestFullDbManifest;
  }

  static Future<void> _installSqliteTempDirectoryWhenQuiesced() async {
    final setup = LibraryUpdateSqliteSetup.instance;
    if (!setup.hasPendingTempDirectoryInstall) return;
    await SqliteDataProvider.instance.closeForExternalWrite();
    try {
      setup.installTempDirectoryWhenQuiesced();
    } finally {
      await SqliteDataProvider.instance.reopenAfterExternalWrite();
    }
  }

  /// ה-updater פותח את המסד בלי לציין VFS, ולכן zvfs חייב להיות ברירת המחדל.
  String _libraryDbPath() {
    final path = dbPathProvider();
    if (isZdbPath(path)) ensureLibraryVfs();
    return path;
  }

  /// גודל הקובץ, או null כשהוא חסר/ריק — ה-planner מתעלם מגודל לא ידוע.
  static int? _fileSizeOrNull(String path) {
    try {
      final file = File(path);
      if (!file.existsSync()) return null;
      final size = file.lengthSync();
      return size > 0 ? size : null;
    } catch (_) {
      return null;
    }
  }

  /// הגודל ש-SQLite רואה ב-zdb (הדחוס קטן פי ~4), כדי שה-planner ישווה
  /// patch למסד ולא לקובץ הדחוס. קריאת הכותרת משחזרת overlay — ב-isolate.
  static Future<int?> _zdbLogicalSizeOrNull(String path) async {
    try {
      return await Isolate.run(() => libraryZdbLogicalSize(path));
    } catch (_) {
      return null;
    }
  }

  static Future<void> _defaultFullDbExtractor(
    String archivePath,
    String outputPath,
  ) {
    return ZstdStreamExtractor.extractToFile(archivePath, outputPath);
  }

  /// נקרא בעליית האפליקציה, לפני פתיחת ה-DB, כדי לשחזר עדכון שנקטע.
  @override
  Future<RecoveryResult> recoverIfNeeded() =>
      recovery.recoverIfNeeded(_libraryDbPath());

  /// בודק אם יש עדכון זמין ומחזיר את התוכנית.
  @override
  Future<LibraryUpdatePlan> checkForUpdate({
    required bool allowPrerelease,
  }) async {
    final dbPath = _libraryDbPath();
    final local = await _readLocalVersion(versionReader, dbPath);
    _lastAllowPrerelease = allowPrerelease;
    final result = await discovery.discover(allowPrerelease: allowPrerelease);
    _rememberDiscovery(result);
    return planner.plan(
      localDbSizeBytes: isZdbPath(dbPath)
          ? await _zdbLogicalSizeOrNull(dbPath)
          : _fileSizeOrNull(dbPath),
      localVersion: local.dbVersion,
      localSchemaVersion: local.schemaVersion,
      hasLocalVersionMeta: local.hasVersionMeta,
      latestVersion: result.latestVersion,
      latestDbSchemaVersion: result.latestDbSchemaVersion,
      edges: result.edges,
      latestFullDbAsset: result.latestFullDbAsset,
      latestReleaseTag: result.latestReleaseTag,
    );
  }

  /// מבצע תוכנית דלתא: לכל step — הורדה, החלה אטומית, וריענון בסיום.
  ///
  /// כל apply רץ ב-Isolate (חוסם ~דקה עם חישוב hash) בתוך operationQueue, עם
  /// סגירת ה-DO לכתיבה חיצונית וגיבוי/שחזור.
  @override
  Future<LibraryDeltaApplyResult> applyDeltaPlan(
    LibraryUpdatePlan plan, {
    LibraryUpdateProgressCallback? onProgress,
    bool Function()? isCancelled,
  }) async {
    final dbPath = _libraryDbPath();
    final cacheDir = Directory(
      p.join(await dataRootProvider(), 'library_update_cache'),
    );

    // סך-הבתים של ה-hash מהריצה הקודמת — total מדויק למד ההתקדמות (גודל
    // הקובץ הוא הערכת-יתר של ~25%). בריצה הראשונה נופלים לגודל הקובץ.
    final hintFile = File(p.join(cacheDir.path, 'verify_total_bytes.txt'));
    var verifyTotalHint = _readIntQuietly(hintFile);
    var lastVerifyDone = 0;

    // רמז בתים לכל טבלה — נדרש כשהמניפסט מאפשר אימות חלקי, שאז ה-total הוא
    // סכום הטבלאות המאומתות בלבד ולא גודל הקובץ.
    final tableBytesFile = File(
      p.join(cacheDir.path, 'verify_table_bytes.json'),
    );
    var verifyTableBytes = _readTableBytesQuietly(tableBytesFile);

    // הטבלאות שאף צעד לא אימת — מועמדות לבדיקת סטייה אחרי סיום השרשרת.
    Set<String>? deferredIntersection;
    DeltaManifest? lastAppliedManifest;

    var result = const LibraryDeltaApplyResult();
    final steps = plan.deltaSteps;
    // לפני בדיקת המקום: patch של תוכנית אחרת שנשאר בקאש תופס גיגה-בייטים
    // שבלעדיהם הבדיקה תיכשל, והניקוי שבסוף לא היה מגיע לעולם.
    _deleteStalePatchFiles(cacheDir, steps);
    // מכינים את הנתיב כעת; מתקינים אותו רק אחרי השהיית חיבורי SQLite.
    final applier = await applierProvider();
    var sqliteTempDirectoryInitialized = false;
    try {
      for (var i = 0; i < steps.length; i++) {
        final step = steps[i];
        final patchFile = step.manifest.patchFiles.first;
        final url = step.patchFileUrls[patchFile.file];
        if (url == null) {
          throw StateError('חסר URL להורדת ${patchFile.file}');
        }

        final reusablePatchPath = downloader is StreamingPatchDownloader
            ? await (downloader as StreamingPatchDownloader)
                  .findReusableExtracted(
                    patchFile: patchFile,
                    destDir: cacheDir,
                    isCancelled: isCancelled,
                    onVerifyProgress: (done, total) => onProgress?.call(
                      LibraryUpdateProgress(
                        phase: LibraryUpdatePhase.verifying,
                        stepIndex: i,
                        totalSteps: steps.length,
                        applyProgress: total > 0
                            ? (done / total).clamp(0.0, 1.0)
                            : null,
                      ),
                    ),
                  )
            : null;

        // נבדק לכל צעד בנפרד: ה-patch נמחק בסיום, ולכן שיא הצרכן
        // הוא צעד בודד.
        await _ensureDiskSpaceForDeltaStep(
          cacheDir: cacheDir,
          patchFile: patchFile,
          dbDir: p.dirname(dbPath),
          reusableExtracted: reusablePatchPath != null,
        );

        onProgress?.call(
          LibraryUpdateProgress(
            phase: LibraryUpdatePhase.downloading,
            stepIndex: i,
            totalSteps: steps.length,
          ),
        );
        final patchPath =
            reusablePatchPath ??
            await downloader.downloadAndExtract(
              patchFile: patchFile,
              downloadUrl: url,
              destDir: cacheDir,
              isCancelled: isCancelled,
              onProgress: (downloaded, total) => onProgress?.call(
                LibraryUpdateProgress(
                  phase: LibraryUpdatePhase.downloading,
                  stepIndex: i,
                  totalSteps: steps.length,
                  bytesDownloaded: downloaded,
                  bytesTotal: total,
                ),
              ),
              // אימות patch פרוס של כמה GB נמשך עשרות שניות — בלי מד הוא נראה קפוא.
              onVerifyProgress: (done, total) => onProgress?.call(
                LibraryUpdateProgress(
                  phase: LibraryUpdatePhase.verifying,
                  stepIndex: i,
                  totalSteps: steps.length,
                  applyProgress: total > 0
                      ? (done / total).clamp(0.0, 1.0)
                      : null,
                ),
              ),
            );

        try {
          // ביטול בדיוק אחרי החילוץ ולפני ההחלה — עוצרים לפני שנוגעים ב-DB.
          _throwIfCancelled(isCancelled);
          onProgress?.call(
            LibraryUpdateProgress(
              phase: LibraryUpdatePhase.applying,
              stepIndex: i,
              totalSteps: steps.length,
            ),
          );
          // מד השורות מדווח בלי שם שלב; ה-onStage האחרון הוא השלב שבו הוא נמדד
          // ('upserts' או 'deletes'), וה-BLoC גוזר ממנו את ההודעה.
          String? currentStage;
          final stepResult = await _applyStepInQueue(
            applier: applier,
            initializeSqliteTempDirectory: () async {
              if (sqliteTempDirectoryInitialized) return;
              await sqliteTempDirectoryInitializer();
              sqliteTempDirectoryInitialized = true;
            },
            dbPath: dbPath,
            patchPath: patchPath,
            step: step,
            verifyTotalBytesHint: verifyTotalHint,
            verifyTableBytesHint: verifyTableBytes,
            onStage: (stage) {
              currentStage = stage;
              onProgress?.call(
                LibraryUpdateProgress(
                  phase: LibraryUpdatePhase.applying,
                  stepIndex: i,
                  totalSteps: steps.length,
                  stage: stage,
                ),
              );
            },
            onApplyProgress: (rowsDone, rowsTotal) => onProgress?.call(
              LibraryUpdateProgress(
                phase: LibraryUpdatePhase.applying,
                stepIndex: i,
                totalSteps: steps.length,
                stage: currentStage,
                applyProgress: rowsTotal > 0
                    ? (rowsDone / rowsTotal).clamp(0.0, 1.0)
                    : null,
              ),
            ),
            onVerifyProgress: (done, total) {
              lastVerifyDone = done;
              onProgress?.call(
                LibraryUpdateProgress(
                  phase: LibraryUpdatePhase.applying,
                  stepIndex: i,
                  totalSteps: steps.length,
                  stage: 'verifyToHash',
                  applyProgress: total > 0
                      ? (done / total).clamp(0.0, 1.0)
                      : null,
                ),
              );
            },
          );
          result = result.addStep(stepResult);
          lastAppliedManifest = step.manifest;
          final deferred = stepResult.deferredTables.toSet();
          final previousDeferred = deferredIntersection;
          deferredIntersection = previousDeferred == null
              ? deferred
              : previousDeferred.intersection(deferred);
          if (stepResult.verifyTableBytes.isNotEmpty) {
            final mergedTableBytes = {
              ...?verifyTableBytes,
              ...stepResult.verifyTableBytes,
            };
            verifyTableBytes = mergedTableBytes;
            _writeTableBytesQuietly(tableBytesFile, mergedTableBytes);
          }
          // באימות מלא הדיווח האחרון הוא ה-total המדויק לריצה הבאה.
          if (lastVerifyDone > 0 && deferred.isEmpty) {
            verifyTotalHint = lastVerifyDone;
            _writeIntQuietly(hintFile, lastVerifyDone);
          }
        } finally {
          _deleteQuietly(patchPath); // מנקה גם בכשל apply, לא רק בהצלחה.
        }
      }
    } catch (error, stackTrace) {
      if (!result.hasDatabaseChanges) rethrow;
      // הצעדים שכבר הושלמו נשארים ב-DB גם אם צעד מאוחר נכשל. מרעננים את
      // ה-runtime לפני שמחזירים שליטה ל-BLoC, ושומרים את פרטי השינוי כדי
      // שסירוב ל-fallback לא ישאיר קטלוג ואינדקס ישנים.
      onProgress?.call(
        const LibraryUpdateProgress(phase: LibraryUpdatePhase.refreshing),
      );
      Object? refreshError;
      try {
        await refreshService.refreshAfterDbUpdate();
      } catch (error) {
        // אסור שכשל ריענון יסתיר את העובדה שכבר נכתבו צעדים או את סיבת
        // הכשל המקורית; ה-BLoC עדיין יוכל להציע fallback ולרענן אחרי ההחלטה.
        refreshError = error;
      }
      final drifted = await _verifyDeferredTables(
        applier: applier,
        dbPath: dbPath,
        manifest: lastAppliedManifest,
        deferred: deferredIntersection,
        tableBytesHint: verifyTableBytes,
        onProgress: onProgress,
      );
      _throwIfContentDrifted(drifted, result);
      Error.throwWithStackTrace(
        PartiallyAppliedLibraryDeltaException(
          cause: error,
          appliedResult: result,
          refreshError: refreshError,
        ),
        stackTrace,
      );
    }

    onProgress?.call(
      const LibraryUpdateProgress(phase: LibraryUpdatePhase.refreshing),
    );
    await refreshService.refreshAfterDbUpdate();

    // אחרי שחיבור ה-RO נפתח מחדש והריענון הסתיים — מעבר קריאה
    // בלבד, בלי תור פעולות, כך שניתן להמשיך לקרוא בזמן הבדיקה.
    final drifted = await _verifyDeferredTables(
      applier: applier,
      dbPath: dbPath,
      manifest: lastAppliedManifest,
      deferred: deferredIntersection,
      tableBytesHint: verifyTableBytes,
      onProgress: onProgress,
    );

    _throwIfContentDrifted(drifted, result);

    onProgress?.call(
      const LibraryUpdateProgress(phase: LibraryUpdatePhase.done),
    );
    return result;
  }

  void _throwIfContentDrifted(
    List<String> drifted,
    LibraryDeltaApplyResult result,
  ) {
    if (drifted.isEmpty) return;
    try {
      ErrorLogFile.append(
        title: 'Library Update: content drift in untouched tables',
        error: 'tables: ${drifted.join(', ')}',
      );
    } catch (_) {}
    throw LibraryDeltaContentDriftException(
      driftedTables: drifted,
      appliedResult: result,
    );
  }

  /// בודק את הטבלאות שאף צעד לא נגע בהן מול ה-hash של הצעד האחרון, ומחזיר
  /// את אלה שסטו. כשל בבדיקה עצמה אינו הופך עדכון תקין לשגיאה.
  Future<List<String>> _verifyDeferredTables({
    required PatchApplier applier,
    required String dbPath,
    required DeltaManifest? manifest,
    required Set<String>? deferred,
    required Map<String, int>? tableBytesHint,
    LibraryUpdateProgressCallback? onProgress,
  }) async {
    final expected = manifest?.toTableContentHashes;
    if (manifest == null || expected == null) return const [];
    if (deferred == null || deferred.isEmpty) return const [];
    onProgress?.call(
      const LibraryUpdateProgress(
        phase: LibraryUpdatePhase.applying,
        stage: 'verifyDeferred',
      ),
    );
    try {
      return await _verifyTablesInIsolateWithProgress(
        applier: applier,
        dbPath: dbPath,
        schemaVersion: manifest.toSchemaVersion,
        expected: expected,
        tables: deferred.toList(),
        tableBytesHint: tableBytesHint,
        onVerifyProgress: (done, total) => onProgress?.call(
          LibraryUpdateProgress(
            phase: LibraryUpdatePhase.applying,
            stage: 'verifyDeferred',
            applyProgress: total > 0 ? (done / total).clamp(0.0, 1.0) : null,
          ),
        ),
      );
    } catch (error, stackTrace) {
      debugPrint('Deferred table verification failed: $error\n$stackTrace');
      try {
        ErrorLogFile.append(
          title: 'Library Update: deferred verification failed',
          error: error,
          stackTrace: stackTrace,
        );
      } catch (_) {}
      return const [];
    }
  }

  /// מוחק patch-ים מחולצים של תוכניות אחרות שנשארו בקאש מריצה שנקטעה;
  /// הקבצים של התוכנית הנוכחית נשמרים לשימוש חוזר.
  void _deleteStalePatchFiles(Directory cacheDir, List<PatchEdge> steps) {
    final planFiles = <String>{
      for (final step in steps)
        for (final patch in step.manifest.patchFiles)
          extractedPatchFileName(patch.file),
    };
    try {
      if (!cacheDir.existsSync()) return;
      for (final entity in cacheDir.listSync()) {
        if (entity is! File) continue;
        final name = p.basename(entity.path);
        if (!name.startsWith('patch-') || !name.endsWith('.db')) continue;
        if (planFiles.contains(name)) continue;
        _deleteQuietly(entity.path);
      }
    } catch (_) {}
  }

  /// זורק [LibraryUpdateDiskSpaceException] אם אין מקום ל-patch של הצעד:
  /// בקאש — הדחוס והמחולץ; ליד ה-DB — ה-WAL של טרנזקציית ההחלה היחידה.
  Future<void> _ensureDiskSpaceForDeltaStep({
    required Directory cacheDir,
    required PatchFileEntry patchFile,
    required String dbDir,
    required bool reusableExtracted,
  }) async {
    if (!cacheDir.existsSync()) cacheDir.createSync(recursive: true);
    int cacheNeeded = 0;
    if (!reusableExtracted) {
      final partial = File(p.join(cacheDir.path, patchFile.file));
      final resumed = _resumablePatchBytes(partial, patchFile);
      cacheNeeded =
          (patchFile.size - resumed).clamp(0, patchFile.size) +
          patchFile.uncompressedSize;
    }
    // כל דף שה-patch נוגע בו נכתב ל-WAL פעם אחת — נפח ה-patch הוא האומדן.
    final walNeeded = patchFile.uncompressedSize;

    final cacheInfo = await diskSpaceProvider(cacheDir.path);
    final dbInfo = await diskSpaceProvider(dbDir);
    String gb(int bytes) => (bytes / (1 << 30)).toStringAsFixed(1);

    final sameVolume =
        cacheInfo.volumeId != null && cacheInfo.volumeId == dbInfo.volumeId;
    if (sameVolume) {
      final needed = cacheNeeded + walNeeded;
      if (cacheInfo.freeBytes >= 0 && cacheInfo.freeBytes < needed) {
        throw LibraryUpdateDiskSpaceException(
          'אין מספיק מקום פנוי בכונן: נדרש ~${gb(needed)}GB להורדת עדכון '
          'הדלתא ולהחלתו, פנוי ${gb(cacheInfo.freeBytes)}GB',
        );
      }
      return;
    }
    if (cacheInfo.freeBytes >= 0 && cacheInfo.freeBytes < cacheNeeded) {
      throw LibraryUpdateDiskSpaceException(
        'אין מספיק מקום פנוי להורדת עדכון הדלתא: נדרש ~${gb(cacheNeeded)}GB, '
        'פנוי ${gb(cacheInfo.freeBytes)}GB',
      );
    }
    if (dbInfo.freeBytes >= 0 && dbInfo.freeBytes < walNeeded) {
      throw LibraryUpdateDiskSpaceException(
        'אין מספיק מקום פנוי להחלת עדכון הדלתא: נדרש ~${gb(walNeeded)}GB '
        'ליד הספרייה, פנוי ${gb(dbInfo.freeBytes)}GB',
      );
    }
  }

  int _resumablePatchBytes(File partial, PatchFileEntry patchFile) {
    try {
      if (!partial.existsSync()) return 0;
      final length = partial.lengthSync();
      final sidecar = File(PatchDownloader.resumeSidecarPath(partial.path));
      if (!sidecar.existsSync()) return 0;
      final lines = sidecar.readAsStringSync().split('\n');
      if (lines.first != patchFile.sha256) return 0;
      if (length == patchFile.size) return length;
      if (length <= 0 || length > patchFile.size || lines.length < 2) return 0;
      final etag = lines[1].trim();
      return etag.isNotEmpty && !etag.startsWith('W/') ? length : 0;
    } catch (_) {
      return 0;
    }
  }

  /// הורדה מלאה, רק אחרי אישור המשתמש (~2GB). zdb: אימות מול המניפסט והתקנה
  /// ב-installZdb (כך seforim.db עובר ל-zdb); zst: חילוץ, quick_check ו-rename.
  @override
  Future<void> applyFullDownload(
    LibraryUpdatePlan plan, {
    LibraryUpdateProgressCallback? onProgress,
    FullDbReplacedCallback? onDbReplaced,
    bool Function()? isCancelled,
  }) async {
    final asset = plan.fullDbAsset;
    if (asset == null) {
      throw StateError('אין DB מלא בתוכנית');
    }
    final dbPath = _libraryDbPath();
    if (asset.fullDbContainer == FullDbContainer.zdb) {
      final manifest = await _fullDbManifestFor(asset);
      final target = plan.targetVersion;
      if (target != null && manifest.dbVersion != target) {
        throw LibraryZdbVerificationException(
          'גרסת קובץ הספרייה (${manifest.dbVersion}) אינה הגרסה הצפויה '
          '($target)',
        );
      }
      await _downloadAndInstallZdb(
        activeDbPath: dbPath,
        asset: asset,
        manifest: manifest,
        onProgress: onProgress,
        isCancelled: isCancelled,
        onDbReplaced: onDbReplaced,
      );
      onProgress?.call(
        const LibraryUpdateProgress(phase: LibraryUpdatePhase.refreshing),
      );
      await refreshService.refreshAfterDbUpdate();
      onProgress?.call(
        const LibraryUpdateProgress(phase: LibraryUpdatePhase.done),
      );
      return;
    }
    // `$dbPath.new` הוא שם הזמני של הדחיסה ב-zvfs, ו-rename על הבסיס משאיר
    // -zovl שקשור לבסיס הישן. נחסם לפני כל הורדה או מחיקה.
    if (isZdbPath(dbPath)) {
      throw const LibraryUpdateZdbFullDownloadUnsupportedException();
    }
    final cacheDir = Directory(
      p.join(await dataRootProvider(), 'library_update_cache'),
    );
    if (!cacheDir.existsSync()) cacheDir.createSync(recursive: true);
    _deleteStalePatchFiles(cacheDir, const []);
    final archivePath = p.join(cacheDir.path, 'seforim.db.zst');
    final sidecarPath = PatchDownloader.resumeSidecarPath(archivePath);
    // מחולץ ליד ה-DB (אותו filesystem) כדי שה-rename יהיה אטומי.
    final newDbPath = '$dbPath.new';
    // digest מגיע מה-API בפורמט 'sha256:<hex>' — נחלץ ל-expectedSha256.
    final digestHex = asset.digest?.startsWith('sha256:') == true
        ? asset.digest!.substring('sha256:'.length)
        : null;

    await _ensureDiskSpaceForFullDownload(
      archivePath: archivePath,
      archiveSize: asset.size,
      dbDir: p.dirname(dbPath),
    );

    try {
      onProgress?.call(
        const LibraryUpdateProgress(phase: LibraryUpdatePhase.downloading),
      );
      await downloader.downloadToFile(
        url: asset.downloadUrl,
        destPath: archivePath,
        expectedSize: asset.size > 0 ? asset.size : null,
        expectedSha256: digestHex,
        // קושר את הקובץ החלקי ל-release — מונע resume על ארכיון מגרסה אחרת.
        resumeToken:
            '${asset.downloadUrl}|${asset.size}|${asset.id ?? ''}|${asset.updatedAt ?? ''}',
        isCancelled: isCancelled,
        onProgress: (downloaded, total) => onProgress?.call(
          LibraryUpdateProgress(
            phase: LibraryUpdatePhase.downloading,
            bytesDownloaded: downloaded,
            bytesTotal: total,
          ),
        ),
      );
      _throwIfCancelled(isCancelled);

      onProgress?.call(
        const LibraryUpdateProgress(phase: LibraryUpdatePhase.applying),
      );
      _deleteDbWithSidecarsQuietly(newDbPath);
      try {
        await fullDbExtractor(archivePath, newDbPath);
      } catch (_) {
        // ארכיון שלם-אך-פגום: בלי מחיקה ה-resume ידלג על ההורדה וייתקע בלולאה.
        _deleteDownloadStateQuietly(archivePath, sidecarPath);
        rethrow;
      }
      _deleteDownloadStateQuietly(archivePath, sidecarPath);
      _throwIfCancelled(isCancelled);

      onProgress?.call(
        const LibraryUpdateProgress(phase: LibraryUpdatePhase.verifying),
      );
      // האימות הכבד (quick_check על ~5.5GB) רץ ב-isolate כדי לא לחסום UI.
      await _verifyFullDbInIsolate(newDbPath, plan.targetVersion);
      _throwIfCancelled(isCancelled);

      await _replaceDbInQueue(
        dbPath: dbPath,
        newDbPath: newDbPath,
        plan: plan,
        isCancelled: isCancelled,
        onDbReplaced: onDbReplaced,
      );

      onProgress?.call(
        const LibraryUpdateProgress(phase: LibraryUpdatePhase.refreshing),
      );
      await refreshService.refreshAfterDbUpdate();

      onProgress?.call(
        const LibraryUpdateProgress(phase: LibraryUpdatePhase.done),
      );
    } catch (_) {
      // הארכיון החלקי נשמר בכוונה — ההורדה תתחדש ממנו בניסיון הבא.
      _deleteDbWithSidecarsQuietly(newDbPath);
      rethrow;
    }
  }

  /// המניפסט של [asset] מהבדיקה האחרונה; בלעדיו (plan ישן) — גילוי מחדש.
  Future<FullDbManifest> _fullDbManifestFor(ReleaseAsset asset) async {
    var manifest = _latestFullDbManifest;
    if (!_manifestMatches(manifest, asset)) {
      final result = await discovery.discover(
        allowPrerelease: _lastAllowPrerelease,
      );
      _rememberDiscovery(result);
      manifest = result.latestFullDbManifest;
    }
    if (manifest == null || !_manifestMatches(manifest, asset)) {
      throw FullDbManifestException(
        'אין מניפסט תואם ל-${asset.name}; לא ניתן לאמת את ההורדה',
      );
    }
    return manifest;
  }

  static bool _manifestMatches(FullDbManifest? manifest, ReleaseAsset asset) =>
      manifest != null &&
      manifest.file == asset.name &&
      manifest.size == asset.size;

  /// מוריד את ה-zdb ליד המסד, מאמת ומתקין אותו כ-seforim.zdb. [phase] — השלב
  /// לכל הדיווחים, כשזו אינה הורדה מלאה שהמשתמש ביקש.
  Future<void> _downloadAndInstallZdb({
    required String activeDbPath,
    required ReleaseAsset asset,
    required FullDbManifest manifest,
    LibraryUpdatePhase? phase,
    LibraryUpdateProgressCallback? onProgress,
    bool Function()? isCancelled,
    FullDbReplacedCallback? onDbReplaced,
  }) async {
    checkZdbManifestSupported(manifest);
    final dbDir = p.dirname(activeDbPath);
    final zdbPath = LibraryZdbFiles.zdbPathIn(dbDir);
    final downloadPath = LibraryZdbFiles.downloadPathFor(zdbPath);
    final sidecarPath = PatchDownloader.resumeSidecarPath(downloadPath);
    void report(
      LibraryUpdatePhase own,
      String stage, {
      int? downloaded,
      int? total,
      double? fraction,
    }) => onProgress?.call(
      LibraryUpdateProgress(
        phase: phase ?? own,
        stage: stage,
        bytesDownloaded: downloaded,
        bytesTotal: total,
        applyProgress: fraction,
      ),
    );

    await _ensureDiskSpaceForZdbDownload(
      downloadPath: downloadPath,
      size: manifest.size,
      dbDir: dbDir,
    );

    report(LibraryUpdatePhase.downloading, zdbStageDownload);
    await downloader.downloadToFile(
      url: asset.downloadUrl,
      destPath: downloadPath,
      expectedSize: manifest.size,
      expectedSha256: manifest.sha256,
      resumeToken:
          '${asset.downloadUrl}|${manifest.size}|${manifest.sha256}|'
          '${asset.id ?? ''}|${asset.updatedAt ?? ''}',
      isCancelled: isCancelled,
      onProgress: (downloaded, total) => report(
        LibraryUpdatePhase.downloading,
        zdbStageDownload,
        downloaded: downloaded,
        total: total,
      ),
    );
    _throwIfCancelled(isCancelled);

    report(LibraryUpdatePhase.verifying, zdbStageVerify);
    try {
      await verifyZdbCandidate(downloadPath, manifest: manifest);
      // הפענוח המלא רץ כאן, מחוץ לשער: הספרייה נשארת פתוחה לקריאה בזמנו.
      await verifyLibraryZdbFrames(
        downloadPath,
        onProgress: (done, total) => report(
          LibraryUpdatePhase.verifying,
          zdbStageVerify,
          fraction: total > 0 ? (done / total).clamp(0.0, 1.0) : null,
        ),
      );
    } on LibraryZdbVerificationException {
      _deleteDownloadStateQuietly(downloadPath, sidecarPath);
      rethrow;
    } on LibraryZdbException catch (error) {
      // קובץ פגום שנשמר היה נמצא שלם בריצה הבאה ונכשל שוב בלולאה.
      if (!error.isBusy) _deleteDownloadStateQuietly(downloadPath, sidecarPath);
      rethrow;
    }
    _throwIfCancelled(isCancelled);

    report(LibraryUpdatePhase.applying, zdbStageInstall);
    await _installZdbInQueue(
      activeDbPath: activeDbPath,
      zdbPath: zdbPath,
      candidatePath: downloadPath,
      isCancelled: isCancelled,
      onDbReplaced: onDbReplaced,
    );
    _deleteQuietly(sidecarPath);
  }

  /// תת-השלבים של הורדת zdb ושל הדחיסה, ב-[LibraryUpdateProgress.stage].
  static const String zdbStageDownload = 'zdbDownload';
  static const String zdbStageVerify = 'zdbVerify';
  static const String zdbStageInstall = 'zdbInstall';
  static const String zdbStageCompact = 'zdbCompact';

  /// מתקין כשהספרייה סגורה בכל החלונות. בלי גיבוי ה-updater: installZdb שומר
  /// את הבסיס הישן עד ה-rename, וקריסה משאירה בסיס עקבי — אין מה לשחזר.
  Future<void> _installZdbInQueue({
    required String activeDbPath,
    required String zdbPath,
    required String candidatePath,
    bool Function()? isCancelled,
    FullDbReplacedCallback? onDbReplaced,
  }) {
    return DatabaseLibraryProvider.operationQueue.enqueue(() async {
      _throwIfCancelled(isCancelled);
      await accessGate.runExclusive(
        dbPath: activeDbPath,
        body: (scope) async {
          _throwIfCancelled(isCancelled);
          final overlay = File('$zdbPath-zovl');
          final hadOverlay = overlay.existsSync();
          try {
            // הפענוח המלא כבר רץ ב-[_downloadAndInstallZdb], מחוץ לשער.
            await installLibraryZdb(zdbPath, candidatePath, verify: false);
          } on LibraryZdbException {
            // כשל אחרי המחיקות משאיר את הבסיס הישן בלי ה-overlay: תוכן אחר.
            if (hadOverlay && !overlay.existsSync()) scope.markDbReplaced();
            rethrow;
          }
          scope.markDbReplaced();
          try {
            onDbReplaced?.call();
          } catch (error, stackTrace) {
            debugPrint(
              'Full DB replacement callback failed: $error\n$stackTrace',
            );
          }
          if (activeDbPath != zdbPath) {
            await _retireLegacyDb(activeDbPath, zdbPath);
          }
        },
      );
    });
  }

  /// אחרי מעבר ל-zdb: מוחק את seforim.db הישן. כשל אינו מכשיל את ההתקנה —
  /// הרזולבר כבר בוחר ב-zdb, וניקוי העלייה ינסה שוב.
  Future<void> _retireLegacyDb(String legacyPath, String zdbPath) async {
    try {
      await onLegacyDbReplaced(legacyPath, zdbPath);
    } catch (error, stackTrace) {
      _logQuietly('Library Update: effective DB path', error, stackTrace);
    }
    recovery.clearStaleArtifacts(legacyPath);
    try {
      await deleteLegacyLibraryDb(p.dirname(legacyPath));
    } catch (error, stackTrace) {
      _logQuietly('Library Update: legacy DB cleanup', error, stackTrace);
    }
  }

  void _logQuietly(String title, Object error, StackTrace? stackTrace) {
    debugPrint('$title: $error');
    try {
      ErrorLogFile.append(title: title, error: error, stackTrace: stackTrace);
    } catch (_) {}
  }

  /// ה-zdb אינו מחולץ: המקום הנדרש הוא ההורדה בלבד, ליד המסד.
  Future<void> _ensureDiskSpaceForZdbDownload({
    required String downloadPath,
    required int size,
    required String dbDir,
  }) async {
    final partial = File(downloadPath);
    final resumed = partial.existsSync() ? partial.lengthSync() : 0;
    final needed = (size - resumed).clamp(0, size);
    final info = await diskSpaceProvider(dbDir);
    if (info.freeBytes >= 0 && info.freeBytes < needed) {
      String gb(int bytes) => (bytes / (1 << 30)).toStringAsFixed(1);
      throw LibraryUpdateDiskSpaceException(
        'אין מספיק מקום פנוי להורדת הספרייה: נדרש ~${gb(needed)}GB ליד '
        'הספרייה, פנוי ${gb(info.freeBytes)}GB',
      );
    }
  }

  /// overlay מעל [kZdbOverlayRebaseRatio]: מוריד בסיס עדכני, ובכשל דוחס מקומית.
  /// היחס בדיסק הוא הסימון לבדיקה הבאה; אינו זורק (busy וכו' — deferred).
  @override
  Future<LibraryStorageMaintenance> maintainLibraryStorage({
    LibraryUpdateProgressCallback? onProgress,
    bool Function()? isCancelled,
  }) async {
    try {
      final dbPath = _libraryDbPath();
      if (!isZdbPath(dbPath)) return LibraryStorageMaintenance.notNeeded;
      final ratio = await zdbOverlayRatio(dbPath);
      if (ratio == null || ratio <= kZdbOverlayRebaseRatio) {
        // אין הורדה מלאה שממתינה לה: שארית של ~2GB הייתה נשארת לתמיד.
        final download = LibraryZdbFiles.downloadPathFor(dbPath);
        _deleteDownloadStateQuietly(
          download,
          PatchDownloader.resumeSidecarPath(download),
        );
        return LibraryStorageMaintenance.notNeeded;
      }
      final rebase = await _rebaseFromLatestFullDb(
        dbPath,
        onProgress: onProgress,
        isCancelled: isCancelled,
      );
      if (rebase != null) return rebase;
      return await _compactOverlay(
        dbPath,
        onProgress: onProgress,
        isCancelled: isCancelled,
      );
    } catch (error, stackTrace) {
      _logQuietly('Library Update: storage maintenance', error, stackTrace);
      return LibraryStorageMaintenance.deferred;
    }
  }

  /// null — אין בסיס עדכני להתקין או שההורדה נכשלה, ולכן עוברים לדחיסה.
  Future<LibraryStorageMaintenance?> _rebaseFromLatestFullDb(
    String dbPath, {
    LibraryUpdateProgressCallback? onProgress,
    bool Function()? isCancelled,
  }) async {
    final asset = _latestFullDbAsset;
    final manifest = _latestFullDbManifest;
    if (asset == null ||
        manifest == null ||
        asset.fullDbContainer != FullDbContainer.zdb ||
        !_manifestMatches(manifest, asset)) {
      return null;
    }
    final local = (await _readLocalVersion(versionReader, dbPath)).dbVersion;
    // בסיס ישן מהמקומי היה מחזיר את הספרייה לאחור.
    if (manifest.dbVersion < local) return null;
    try {
      await _downloadAndInstallZdb(
        activeDbPath: dbPath,
        asset: asset,
        manifest: manifest,
        phase: LibraryUpdatePhase.optimizing,
        onProgress: onProgress,
        isCancelled: isCancelled,
      );
    } on PatchDownloadCancelled {
      return LibraryStorageMaintenance.deferred;
    } on LibraryZdbException catch (error, stackTrace) {
      if (!error.isBusy) {
        _logQuietly('Library Update: rebase failed', error, stackTrace);
        return null;
      }
      _logQuietly('Library Update: rebase deferred (busy)', error, stackTrace);
      return LibraryStorageMaintenance.deferred;
    } on LibrarySuspendFailed {
      return LibraryStorageMaintenance.deferred;
    } on LibraryStillOpenException {
      return LibraryStorageMaintenance.deferred;
    } catch (error, stackTrace) {
      _logQuietly('Library Update: rebase download failed', error, stackTrace);
      return null;
    }
    onProgress?.call(
      const LibraryUpdateProgress(phase: LibraryUpdatePhase.refreshing),
    );
    await refreshService.refreshAfterDbUpdate();
    return LibraryStorageMaintenance.rebased;
  }

  /// פתיחת zdb משחזרת את ה-overlay סינכרונית (מאות ms), ולכן לא על ה-UI isolate.
  /// static: ה-closure של Isolate.run לוכד את כל ה-scope, ו-this אינו sendable.
  static Future<LocalDbVersion> _readLocalVersion(
    LocalDbVersionReader reader,
    String dbPath,
  ) async {
    if (!isZdbPath(dbPath)) return reader.read(dbPath);
    return Isolate.run(() {
      ensureLibraryVfs();
      return reader.read(dbPath);
    });
  }

  /// הגיבוי לבסיס חדש: דוחס בסיס + overlay כשהמשתמש אינו קורא ויש מקום.
  /// הספרייה מושעית בכל החלונות לכל משך הדחיסה.
  Future<LibraryStorageMaintenance> _compactOverlay(
    String dbPath, {
    LibraryUpdateProgressCallback? onProgress,
    bool Function()? isCancelled,
  }) async {
    if (!isLibraryIdle()) return LibraryStorageMaintenance.deferred;
    final overlay = File('$dbPath-zovl');
    final needed =
        File(dbPath).lengthSync() +
        (overlay.existsSync() ? overlay.lengthSync() : 0);
    final space = await diskSpaceProvider(p.dirname(dbPath));
    if (space.freeBytes >= 0 && space.freeBytes < needed) {
      debugPrint('Library Update: no space to compact ($needed bytes)');
      return LibraryStorageMaintenance.deferred;
    }
    void report(double? fraction) => onProgress?.call(
      LibraryUpdateProgress(
        phase: LibraryUpdatePhase.optimizing,
        stage: zdbStageCompact,
        applyProgress: fraction,
      ),
    );
    report(null);
    try {
      await DatabaseLibraryProvider.operationQueue.enqueue(() async {
        _throwIfCancelled(isCancelled);
        // התוכן זהה, ולכן בלי markDbReplaced: החלונות רק פותחים מחדש.
        await accessGate.runExclusive(
          dbPath: dbPath,
          body: (_) => compactLibraryZdb(
            dbPath,
            onProgress: (done, total) =>
                report(total > 0 ? (done / total).clamp(0.0, 1.0) : null),
          ),
        );
      });
    } on PatchDownloadCancelled {
      return LibraryStorageMaintenance.deferred;
    } catch (error, stackTrace) {
      _logQuietly('Library Update: compaction deferred', error, stackTrace);
      return LibraryStorageMaintenance.deferred;
    }
    return LibraryStorageMaintenance.compacted;
  }

  /// מוחק קובץ DB יחד עם קובצי ה-wal/-shm שלו — בלעדיהם בדיקת ה-DB שהורד
  /// מותירה `seforim.db.new-wal`/`-shm` יתומים לצד הספרייה לתמיד.
  void _deleteDbWithSidecarsQuietly(String dbPath) {
    _deleteQuietly(dbPath);
    _deleteQuietly('$dbPath-wal');
    _deleteQuietly('$dbPath-shm');
  }

  /// אומדן גודל ה-DB המחולץ — ה-release מדווח רק את הגודל הדחוס, לכן קבוע
  /// עם מרווח ביטחון. יש להגדילו אם ה-DB יגדל מעבר לכך.
  static const int _extractedDbSizeEstimate = 6979321856; // 6.5GB

  /// זורק [LibraryUpdateDiskSpaceException] אם אין מקום להורדה ולחילוץ.
  /// מקום פנוי לא-ידוע (freeBytes==-1) אינו חוסם — עדיף לנסות מלחסום בטעות.
  Future<void> _ensureDiskSpaceForFullDownload({
    required String archivePath,
    required int archiveSize,
    required String dbDir,
  }) async {
    // ארכיון חלקי מהורדה קודמת מתחדש (resume) ואינו דורש מקום נוסף.
    final partial = File(archivePath);
    final resumed = partial.existsSync() ? partial.lengthSync() : 0;
    final archiveNeeded = (archiveSize - resumed).clamp(0, archiveSize);

    final archiveInfo = await diskSpaceProvider(p.dirname(archivePath));
    final extractInfo = await diskSpaceProvider(dbDir);
    String gb(int bytes) => (bytes / (1 << 30)).toStringAsFixed(1);

    final sameVolume =
        archiveInfo.volumeId != null &&
        archiveInfo.volumeId == extractInfo.volumeId;
    if (sameVolume) {
      final needed = archiveNeeded + _extractedDbSizeEstimate;
      if (archiveInfo.freeBytes >= 0 && archiveInfo.freeBytes < needed) {
        throw LibraryUpdateDiskSpaceException(
          'אין מספיק מקום פנוי בכונן: נדרש ~${gb(needed)}GB להורדה ולחילוץ '
          'הספרייה, פנוי ${gb(archiveInfo.freeBytes)}GB',
        );
      }
      return;
    }
    if (archiveInfo.freeBytes >= 0 && archiveInfo.freeBytes < archiveNeeded) {
      throw LibraryUpdateDiskSpaceException(
        'אין מספיק מקום פנוי להורדת הספרייה: נדרש ~${gb(archiveNeeded)}GB, '
        'פנוי ${gb(archiveInfo.freeBytes)}GB',
      );
    }
    if (extractInfo.freeBytes >= 0 &&
        extractInfo.freeBytes < _extractedDbSizeEstimate) {
      throw LibraryUpdateDiskSpaceException(
        'אין מספיק מקום פנוי לחילוץ הספרייה: '
        'נדרש ~${gb(_extractedDbSizeEstimate)}GB, '
        'פנוי ${gb(extractInfo.freeBytes)}GB',
      );
    }
  }

  void _deleteDownloadStateQuietly(String dataPath, String sidecarPath) {
    _deleteQuietly(dataPath);
    // אם מחיקת הארכיון נכשלה, ה-sidecar עדיין נחוץ כדי לאמת/לחדש אותו.
    if (!File(dataPath).existsSync()) _deleteQuietly(sidecarPath);
  }

  void _throwIfCancelled(bool Function()? isCancelled) {
    if (isCancelled != null && isCancelled()) {
      throw const PatchDownloadCancelled();
    }
  }

  /// מוודא שה-DB שחולץ תקין (quick_check) ובגרסה הצפויה לפני החלפה.
  /// static כדי שירוץ ב-Isolate (הפתיחה read-only — אין כתיבה לאימות).
  static void _verifyFullDb(String newDbPath, int? expectedVersion) {
    final db = sqlite3.sqlite3.open(newDbPath, mode: sqlite3.OpenMode.readOnly);
    try {
      final check = db.select('PRAGMA quick_check');
      final result = check.isEmpty ? '' : check.first.values.first?.toString();
      if (result != 'ok') {
        throw StateError('בדיקת תקינות ה-DB שהורד נכשלה: $result');
      }
    } finally {
      db.close();
    }
    final local = const LocalDbVersionReader().read(newDbPath);
    if (expectedVersion != null && local.dbVersion != expectedVersion) {
      throw StateError(
        'גרסת ה-DB שהורד (${local.dbVersion}) אינה הגרסה הצפויה '
        '($expectedVersion)',
      );
    }
    final schema = local.schemaVersion;
    const readable = DatabaseConstants.readableDbSchemaVersion;
    if (schema != null && schema > readable) {
      throw StateError(
        'ה-DB שהורד בסכמה $schema, חדשה מהנתמכת ($readable) — '
        'נדרש עדכון אפליקציה',
      );
    }
  }

  Future<void> _replaceDbInQueue({
    required String dbPath,
    required String newDbPath,
    required LibraryUpdatePlan plan,
    bool Function()? isCancelled,
    FullDbReplacedCallback? onDbReplaced,
  }) {
    return DatabaseLibraryProvider.operationQueue.enqueue(() async {
      // ייתכן שהפעולה המתינה זמן רב מאחורי כתיבה אחרת. ביטול שהגיע בזמן
      // ההמתנה חייב לעצור לפני סגירת ה-runtime ולפני יצירת גיבוי כבד.
      _throwIfCancelled(isCancelled);
      // חלון משני מחזיק handle משלו, ו-rename עליו נכשל ב-Windows.
      await accessGate.runExclusive(
        dbPath: dbPath,
        body: (scope) async {
          var recoveryStarted = false;
          try {
            _throwIfCancelled(isCancelled);
            recoveryStarted = true;
            await recovery.beginApply(
              dbPath: dbPath,
              fromVersion: plan.localVersion,
              toVersion: plan.targetVersion ?? 0,
              timestamp: nowTimestamp(),
            );
            // beginApply מעתיק DB של כמה GB ועשוי להימשך דקות. זו בדיקת הביטול
            // האחרונה; מכאן עד ה-rename אין await ולכן אין חלון race נוסף.
            _throwIfCancelled(isCancelled);
            _deleteDbWithSidecarsQuietly(dbPath);
            File(newDbPath).renameSync(dbPath);
            scope.markDbReplaced();
            _deleteQuietly('$newDbPath-wal');
            _deleteQuietly('$newDbPath-shm');
            recovery.finishSuccess(dbPath);
            // מסמנים את נקודת האל-חזור לפני ה-await של reopen. כך ה-BLoC חוסם
            // Cancel/Reset גם אם הפתיחה מחדש או ריענון ה-runtime נמשכים/נכשלים.
            try {
              onDbReplaced?.call();
            } catch (error, stackTrace) {
              // callback הוא התראה בלבד; אסור שכשל במאזין יגלגל לאחור DB תקין
              // אחרי שגיבוי ההתאוששות כבר נוקה.
              debugPrint(
                'Full DB replacement callback failed: $error\n$stackTrace',
              );
            }
          } catch (_) {
            // לפני beginApply אין לפעולה הזו artifacts משלה; rollback בשלב הזה
            // עלול לגעת בטעות בגיבוי ישן שאינו שייך לריצה הנוכחית.
            if (recoveryStarted) await recovery.rollback(dbPath);
            rethrow;
          }
        },
      );
    });
  }

  Future<PatchApplyResult> _applyStepInQueue({
    required PatchApplier applier,
    required Future<void> Function() initializeSqliteTempDirectory,
    required String dbPath,
    required String patchPath,
    required PatchEdge step,
    int? verifyTotalBytesHint,
    Map<String, int>? verifyTableBytesHint,
    void Function(String stage)? onStage,
    void Function(int done, int total)? onVerifyProgress,
    void Function(int rowsDone, int rowsTotal)? onApplyProgress,
  }) {
    return DatabaseLibraryProvider.operationQueue.enqueue(() async {
      await initializeSqliteTempDirectory();
      // WAL מאפשר לקוראים להמשיך לקרוא את ה-snapshot שלפני העדכון בזמן
      // שהאיזולייט כותב — בלי לסגור את חיבור ה-RO (שחסם פתיחת ספרים לדקות).
      // אם ההמרה נכשלת, נסוגים למסלול הישן: סגירת ה-RO למשך הכתיבה.
      final walFailure = await _trySetJournalMode(dbPath, 'WAL');
      final concurrentReads = walFailure == null;
      if (!concurrentReads) {
        _logJournalModeFailure('WAL', walFailure);
        await SqliteDataProvider.instance.closeForExternalWrite();
      }
      try {
        // ללא גיבוי מלא: ה-apply עטוף ב-transaction יחיד של SQLite, אז קריסה
        // באמצע מתגלגלת אחורה אוטומטית — ה-DB תמיד נשאר תקין (מקור או יעד).
        await recovery.beginApply(
          dbPath: dbPath,
          fromVersion: step.fromVersion,
          toVersion: step.toVersion,
          timestamp: nowTimestamp(),
          createBackup: false,
        );
        final booksTouched = await _applyPatchInIsolate(
          applier: applier,
          dbPath: dbPath,
          patchPath: patchPath,
          manifest: step.manifest,
          verifyTotalBytesHint: verifyTotalBytesHint,
          verifyTableBytesHint: verifyTableBytesHint,
          onStage: onStage,
          onVerifyProgress: onVerifyProgress,
          onApplyProgress: onApplyProgress,
        );
        DbReadWorker.clearBookCacheIfRunning();
        recovery.finishSuccess(dbPath);
        return booksTouched;
      } catch (_) {
        await recovery.rollback(dbPath);
        rethrow;
      } finally {
        try {
          if (concurrentReads) {
            // היציאה מ-WAL דורשת שאין חיבורים אחרים — סוגרים לרגע את ה-RO,
            // אחרת ההמרה נתקעת על מלוא ה-busy_timeout ונכשלת.
            try {
              // השער נשאר סגור גם בכישלון: שחרור הקוראים לפני המעבר ל-DELETE
              // היה פותח אותם מחדש ומכשיל את המעבר.
              await SqliteDataProvider.instance.closeForExternalWrite(
                releaseOnFailure: false,
              );
            } on DbReadWorkerNotReleased catch (error) {
              // העדכון כבר נשמר; worker תקוע רק מונע את החזרה ל-DELETE.
              _logJournalModeFailure('DELETE', error.message);
            }
            final revertFailure = await _trySetJournalMode(dbPath, 'DELETE');
            if (revertFailure != null) {
              _logJournalModeFailure('DELETE', revertFailure);
            }
          }
        } finally {
          await SqliteDataProvider.instance.reopenAfterExternalWrite();
        }
      }
    });
  }

  // ב-release אין debugPrint, ורק errors.txt יכול להסביר למה פתיחת ספרים
  // נחסמה בזמן העדכון (נסיגה לסגירת חיבור ה-RO).
  void _logJournalModeFailure(String mode, String reason) {
    try {
      ErrorLogFile.append(
        title: 'Library Update: journal_mode=$mode failed',
        error: reason,
      );
    } catch (_) {}
  }

  /// ממיר את מצב היומן של [dbPath]; מחזיר null בהצלחה, אחרת את סיבת הכשל.
  /// zdb נפתח ב-isolate: פתיחת כתיבה משחזרת את ה-overlay סינכרונית.
  static Future<String?> _trySetJournalMode(String dbPath, String mode) async {
    if (!isZdbPath(dbPath)) return _setJournalMode(dbPath, mode);
    return Isolate.run(() {
      ensureLibraryVfs();
      return _setJournalMode(dbPath, mode);
    });
  }

  /// ההמרה דורשת נעילה בלעדית קצרה — busy_timeout מכסה קריאות קצרות שבאמצע.
  static String? _setJournalMode(String dbPath, String mode) {
    try {
      final db = sqlite3.sqlite3.open(dbPath);
      try {
        db.execute('PRAGMA busy_timeout = 5000');
        if (mode == 'DELETE') {
          db.execute('PRAGMA wal_checkpoint(TRUNCATE)');
        }
        final result = db.select('PRAGMA journal_mode=$mode');
        final actual = result.isEmpty
            ? null
            : result.first.values.first?.toString().toLowerCase();
        return actual == mode.toLowerCase()
            ? null
            : 'journal_mode stayed ${actual ?? 'unknown'}';
      } finally {
        db.close();
      }
    } catch (e) {
      return e.toString();
    }
  }

  // מאזין לתת-שלבי ה-apply דרך ReceivePort ומעביר ל-onStage (רץ ב-main isolate).
  // ה-onStage עצמו אסור שייכנס ל-scope של ה-Isolate.run (ראה [_runApplyIsolate]).
  static Future<PatchApplyResult> _applyPatchInIsolate({
    required PatchApplier applier,
    required String dbPath,
    required String patchPath,
    required DeltaManifest manifest,
    int? verifyTotalBytesHint,
    Map<String, int>? verifyTableBytesHint,
    void Function(String stage)? onStage,
    void Function(int done, int total)? onVerifyProgress,
    void Function(int rowsDone, int rowsTotal)? onApplyProgress,
  }) async {
    final port = ReceivePort();
    final sub = port.listen((msg) {
      // String=שם תת-שלב (onStage); (int,int)=בתים באימות ה-hash;
      // ('apply',int,int)=שורות שהוחלו ב-upserts/deletes.
      if (msg is String) {
        onStage?.call(msg);
      } else if (msg is (int, int)) {
        onVerifyProgress?.call(msg.$1, msg.$2);
      } else if (msg is (String, int, int) && msg.$1 == _applyProgressTag) {
        onApplyProgress?.call(msg.$2, msg.$3);
      }
    });
    try {
      return await _runApplyIsolate(
        applier: applier,
        dbPath: dbPath,
        patchPath: patchPath,
        manifest: manifest,
        verifyTotalBytesHint: verifyTotalBytesHint,
        verifyTableBytesHint: verifyTableBytesHint,
        sendPort: port.sendPort,
      );
    } finally {
      await sub.cancel();
      port.close();
    }
  }

  // ה-Isolate.run מבודד כאן: closure לוכד את כל ה-scope של המתודה (גם פרמטרים
  // שאינם בשימוש), לכן המתודה מקבלת *רק* ערכים sendable. onStage/onProgress
  // נשארים ב-caller — אחרת הם גוררים את ה-bloc הלא-sendable ל-spawn.
  static Future<PatchApplyResult> _runApplyIsolate({
    required PatchApplier applier,
    required String dbPath,
    required String patchPath,
    required DeltaManifest manifest,
    required SendPort sendPort,
    int? verifyTotalBytesHint,
    Map<String, int>? verifyTableBytesHint,
  }) {
    return Isolate.run(
      () => applier.apply(
        dbPath: dbPath,
        patchPath: patchPath,
        manifest: manifest,
        verifyTotalBytesHint: verifyTotalBytesHint,
        verifyTableBytesHint: verifyTableBytesHint,
        // האימות החלקי הוא opt-in ב-updater: הריפוזיטורי משלים אותו במעבר
        // read-only על deferredTables אחרי ה-commit (ראו _verifyDeferredTables).
        enablePartialTableVerification: true,
        // verifyFromHash=false: verifyToHash אחרי ה-apply הוא הערובה האמיתית —
        // אם המקור שונה, ה-toHash ייכשל וה-transaction יתגלגל אחורה. הבדיקה
        // המקדימה רק כפילה קריאה של כל ה-DB (5.5GB) לחינם.
        verifyFromHash: false,
        // checkForeignKeys=false: התאמת ה-hash של הטבלאות שנגעו בהן ל-DB
        // הקנוני שוללת הפרות שה-patch יצר; הטבלאות האחרות נבדקות במעבר
        // deferred שאחרי ה-commit. כך נמנעת סריקת FK מלאה נוספת.
        checkForeignKeys: false,
        onStage: (stage) => sendPort.send(stage),
        onVerifyProgress: (done, total) => sendPort.send((done, total)),
        onApplyProgress: (rowsDone, rowsTotal) =>
            sendPort.send((_applyProgressTag, rowsDone, rowsTotal)),
      ),
    );
  }

  // כמו [_applyPatchInIsolate]: ה-callback נשאר ב-caller, ל-isolate נכנסים
  // ערכים sendable בלבד.
  static Future<List<String>> _verifyTablesInIsolateWithProgress({
    required PatchApplier applier,
    required String dbPath,
    required int schemaVersion,
    required Map<String, String> expected,
    required List<String> tables,
    Map<String, int>? tableBytesHint,
    void Function(int done, int total)? onVerifyProgress,
  }) async {
    final port = ReceivePort();
    final sub = port.listen((msg) {
      if (msg is (int, int)) onVerifyProgress?.call(msg.$1, msg.$2);
    });
    try {
      return await _runVerifyTablesIsolate(
        applier: applier,
        dbPath: dbPath,
        schemaVersion: schemaVersion,
        expected: expected,
        tables: tables,
        tableBytesHint: tableBytesHint,
        sendPort: port.sendPort,
      );
    } finally {
      await sub.cancel();
      port.close();
    }
  }

  static Future<List<String>> _runVerifyTablesIsolate({
    required PatchApplier applier,
    required String dbPath,
    required int schemaVersion,
    required Map<String, String> expected,
    required List<String> tables,
    required SendPort sendPort,
    Map<String, int>? tableBytesHint,
  }) {
    return Isolate.run(
      () => applier.verifyTableHashes(
        dbPath: dbPath,
        schemaVersion: schemaVersion,
        expected: expected,
        tables: tables,
        tableBytesHint: tableBytesHint,
        onProgress: (done, total) => sendPort.send((done, total)),
      ),
    );
  }

  /// מבדיל את הודעות התקדמות ה-apply מהודעות אימות ה-hash באותו SendPort.
  static const String _applyProgressTag = 'apply';

  // static מאותה סיבה כמו [_applyPatchInIsolate] — מונע לכידת `this`.
  static Future<void> _verifyFullDbInIsolate(
    String newDbPath,
    int? expectedVersion,
  ) {
    return Isolate.run(() => _verifyFullDb(newDbPath, expectedVersion));
  }

  void _deleteQuietly(String path) {
    try {
      final file = File(path);
      if (file.existsSync()) file.deleteSync();
    } catch (_) {}
  }

  static int? _readIntQuietly(File file) {
    try {
      if (!file.existsSync()) return null;
      final value = int.tryParse(file.readAsStringSync().trim());
      return (value != null && value > 0) ? value : null;
    } catch (_) {
      return null;
    }
  }

  static void _writeIntQuietly(File file, int value) {
    try {
      file.parent.createSync(recursive: true);
      file.writeAsStringSync('$value');
    } catch (_) {}
  }

  static Map<String, int>? _readTableBytesQuietly(File file) {
    try {
      if (!file.existsSync()) return null;
      final decoded = jsonDecode(file.readAsStringSync());
      if (decoded is! Map) return null;
      final result = <String, int>{};
      decoded.forEach((key, value) {
        if (key is String && value is int && value > 0) result[key] = value;
      });
      return result.isEmpty ? null : result;
    } catch (_) {
      return null;
    }
  }

  static void _writeTableBytesQuietly(File file, Map<String, int> value) {
    try {
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(jsonEncode(value));
    } catch (_) {}
  }
}
