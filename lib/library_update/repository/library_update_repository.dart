import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/core/error_log_file.dart';
import 'package:otzaria/data/constants/database_constants.dart';
import 'package:otzaria/data/data_providers/database_library_provider.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:otzaria/utils/file/disk_free_space.dart';
import 'package:otzaria/utils/file/zstd_stream_extractor.dart';
import 'package:path/path.dart' as p;
import 'package:otzaria/data/sqlite/sqlite3_api.dart' as sqlite3;
import 'package:seforim_library_updater/seforim_library_updater.dart';

import '../services/library_runtime_refresh_service.dart';

/// שלבי תהליך העדכון — לתצוגת הודעות למשתמש.
enum LibraryUpdatePhase {
  checking,
  downloading,
  verifying,
  applying,
  refreshing,
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

  /// יחס התקדמות (0..1) בתוך שלב אימות ה-hash הארוך; null בשאר שלבי ה-apply.
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

/// אין מספיק מקום פנוי בדיסק להורדה המלאה — נבדק לפני תחילת ההורדה.
class LibraryUpdateDiskSpaceException implements Exception {
  final String message;
  const LibraryUpdateDiskSpaceException(this.message);

  @override
  String toString() => message;
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
class LibraryUpdateRepository implements LibraryUpdateService {
  final LibraryUpdateDiscovery discovery;
  final LibraryUpdatePlanner planner;
  final LocalDbVersionReader versionReader;
  final PatchDownloader downloader;
  final LibraryDbRecoveryService recovery;
  final LibraryRuntimeRefreshService refreshService;
  final FullDbExtractor fullDbExtractor;

  /// ניתנים להזרקה לצורך בדיקות.
  final String Function() dbPathProvider;
  final Future<String> Function() dataRootProvider;
  final String Function() nowTimestamp;
  final Future<DiskSpaceInfo> Function(String dirPath) diskSpaceProvider;

  LibraryUpdateRepository({
    required this.discovery,
    this.planner = const LibraryUpdatePlanner(),
    this.versionReader = const LocalDbVersionReader(),
    required this.downloader,
    this.recovery = const LibraryDbRecoveryService(),
    this.refreshService = const LibraryRuntimeRefreshService(),
    FullDbExtractor? fullDbExtractor,
    String Function()? dbPathProvider,
    Future<String> Function()? dataRootProvider,
    String Function()? nowTimestamp,
    Future<DiskSpaceInfo> Function(String dirPath)? diskSpaceProvider,
  }) : dbPathProvider = dbPathProvider ?? DatabaseConstants.getDatabasePath,
       dataRootProvider = dataRootProvider ?? AppPaths.getDataRootPath,
       nowTimestamp = nowTimestamp ?? (() => DateTime.now().toIso8601String()),
       fullDbExtractor = fullDbExtractor ?? _defaultFullDbExtractor,
       diskSpaceProvider = diskSpaceProvider ?? getDiskSpaceInfo;

  static Future<void> _defaultFullDbExtractor(
    String archivePath,
    String outputPath,
  ) {
    return ZstdStreamExtractor.extractToFile(archivePath, outputPath);
  }

  /// נקרא בעליית האפליקציה, לפני פתיחת ה-DB, כדי לשחזר עדכון שנקטע.
  @override
  Future<RecoveryResult> recoverIfNeeded() =>
      recovery.recoverIfNeeded(dbPathProvider());

  /// בודק אם יש עדכון זמין ומחזיר את התוכנית.
  @override
  Future<LibraryUpdatePlan> checkForUpdate({
    required bool allowPrerelease,
  }) async {
    final local = versionReader.read(dbPathProvider());
    final result = await discovery.discover(allowPrerelease: allowPrerelease);
    return planner.plan(
      localVersion: local.dbVersion,
      localSchemaVersion: local.schemaVersion,
      hasLocalVersionMeta: local.hasVersionMeta,
      latestVersion: result.latestVersion,
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
    final dbPath = dbPathProvider();
    final cacheDir = Directory(
      p.join(await dataRootProvider(), 'library_update_cache'),
    );

    // סך-הבתים של ה-hash מהריצה הקודמת — total מדויק למד ההתקדמות (גודל
    // הקובץ הוא הערכת-יתר של ~25%). בריצה הראשונה נופלים לגודל הקובץ.
    final hintFile = File(p.join(cacheDir.path, 'verify_total_bytes.txt'));
    var verifyTotalHint = _readIntQuietly(hintFile);
    var lastVerifyDone = 0;

    var result = const LibraryDeltaApplyResult();
    final steps = plan.deltaSteps;
    try {
      for (var i = 0; i < steps.length; i++) {
        final step = steps[i];
        final patchFile = step.manifest.patchFiles.first;
        final url = step.patchFileUrls[patchFile.file];
        if (url == null) {
          throw StateError('חסר URL להורדת ${patchFile.file}');
        }

        onProgress?.call(
          LibraryUpdateProgress(
            phase: LibraryUpdatePhase.downloading,
            stepIndex: i,
            totalSteps: steps.length,
          ),
        );
        final patchPath = await downloader.downloadAndExtract(
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
          final stepResult = await _applyStepInQueue(
            dbPath: dbPath,
            patchPath: patchPath,
            step: step,
            verifyTotalBytesHint: verifyTotalHint,
            onStage: (stage) => onProgress?.call(
              LibraryUpdateProgress(
                phase: LibraryUpdatePhase.applying,
                stepIndex: i,
                totalSteps: steps.length,
                stage: stage,
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
          // הדיווח האחרון מ-compute הוא הסך המדויק — total לריצות הבאות.
          if (lastVerifyDone > 0) {
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

    onProgress?.call(
      const LibraryUpdateProgress(phase: LibraryUpdatePhase.done),
    );
    return result;
  }

  /// מבצע הורדה מלאה: מוריד את `seforim.db.zst`, מחלץ בזרימה ליד ה-DB,
  /// מאמת (quick_check + גרסה), ומחליף אטומית את ה-DB הישן.
  ///
  /// נקרא רק אחרי אישור מפורש של המשתמש (ההורדה גדולה — ~1.1GB).
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
    final dbPath = dbPathProvider();
    final cacheDir = Directory(
      p.join(await dataRootProvider(), 'library_update_cache'),
    );
    if (!cacheDir.existsSync()) cacheDir.createSync(recursive: true);
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
    if (expectedVersion != null) {
      final local = const LocalDbVersionReader().read(newDbPath);
      if (local.dbVersion != expectedVersion) {
        throw StateError(
          'גרסת ה-DB שהורד (${local.dbVersion}) אינה הגרסה הצפויה '
          '($expectedVersion)',
        );
      }
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
      await SqliteDataProvider.instance.closeForExternalWrite();
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
      } finally {
        await SqliteDataProvider.instance.reopenAfterExternalWrite();
      }
    });
  }

  Future<PatchApplyResult> _applyStepInQueue({
    required String dbPath,
    required String patchPath,
    required PatchEdge step,
    int? verifyTotalBytesHint,
    void Function(String stage)? onStage,
    void Function(int done, int total)? onVerifyProgress,
  }) {
    return DatabaseLibraryProvider.operationQueue.enqueue(() async {
      // WAL מאפשר לקוראים להמשיך לקרוא את ה-snapshot שלפני העדכון בזמן
      // שהאיזולייט כותב — בלי לסגור את חיבור ה-RO (שחסם פתיחת ספרים לדקות).
      // אם ההמרה נכשלת, נסוגים למסלול הישן: סגירת ה-RO למשך הכתיבה.
      final walFailure = _trySetJournalMode(dbPath, 'WAL');
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
          dbPath: dbPath,
          patchPath: patchPath,
          manifest: step.manifest,
          verifyTotalBytesHint: verifyTotalBytesHint,
          onStage: onStage,
          onVerifyProgress: onVerifyProgress,
        );
        recovery.finishSuccess(dbPath);
        return booksTouched;
      } catch (_) {
        await recovery.rollback(dbPath);
        rethrow;
      } finally {
        if (concurrentReads) {
          // היציאה מ-WAL דורשת שאין חיבורים אחרים — סוגרים לרגע את ה-RO,
          // אחרת ההמרה נתקעת על מלוא ה-busy_timeout ונכשלת.
          await SqliteDataProvider.instance.closeForExternalWrite();
          final revertFailure = _trySetJournalMode(dbPath, 'DELETE');
          if (revertFailure != null) {
            _logJournalModeFailure('DELETE', revertFailure);
          }
        }
        await SqliteDataProvider.instance.reopenAfterExternalWrite();
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
  /// ההמרה דורשת נעילה בלעדית קצרה — busy_timeout מכסה קריאות קצרות שבאמצע.
  String? _trySetJournalMode(String dbPath, String mode) {
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
    required String dbPath,
    required String patchPath,
    required DeltaManifest manifest,
    int? verifyTotalBytesHint,
    void Function(String stage)? onStage,
    void Function(int done, int total)? onVerifyProgress,
  }) async {
    final port = ReceivePort();
    final sub = port.listen((msg) {
      // String=שם תת-שלב (onStage); record=(bytesHashed, total) של האימות.
      if (msg is String) {
        onStage?.call(msg);
      } else if (msg is (int, int)) {
        onVerifyProgress?.call(msg.$1, msg.$2);
      }
    });
    try {
      return await _runApplyIsolate(
        dbPath: dbPath,
        patchPath: patchPath,
        manifest: manifest,
        verifyTotalBytesHint: verifyTotalBytesHint,
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
    required String dbPath,
    required String patchPath,
    required DeltaManifest manifest,
    required SendPort sendPort,
    int? verifyTotalBytesHint,
  }) {
    return Isolate.run(
      () => const PatchApplier().apply(
        dbPath: dbPath,
        patchPath: patchPath,
        manifest: manifest,
        verifyTotalBytesHint: verifyTotalBytesHint,
        // verifyFromHash=false: verifyToHash אחרי ה-apply הוא הערובה האמיתית —
        // אם המקור שונה, ה-toHash ייכשל וה-transaction יתגלגל אחורה. הבדיקה
        // המקדימה רק כפילה קריאה של כל ה-DB (5.5GB) לחינם.
        verifyFromHash: false,
        // checkForeignKeys=false: verifyToHash מאמת את כל 28 הטבלאות (וכל ה-FK
        // שביניהן) מול ה-DB התקין, אז התאמת hash כבר שוללת הפרות FK — חוסך ~60ש.
        checkForeignKeys: false,
        onStage: (stage) => sendPort.send(stage),
        onVerifyProgress: (done, total) => sendPort.send((done, total)),
      ),
    );
  }

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
}
