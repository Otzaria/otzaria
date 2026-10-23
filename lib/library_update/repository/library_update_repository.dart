import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/core/directory_writability.dart';
import 'package:otzaria/core/error_log_file.dart';
import 'package:otzaria/data/constants/database_constants.dart';
import 'package:otzaria/data/data_providers/database_library_provider.dart';
import 'package:otzaria/data/data_providers/db_read_worker.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:otzaria/utils/file/disk_free_space.dart';
import 'package:otzaria/utils/file/download_space.dart';
import 'package:otzaria/utils/file/zstd_stream_extractor.dart';
import 'package:path/path.dart' as p;
import 'package:otzaria/data/sqlite/sqlite3_api.dart' as sqlite3;
import 'package:otzaria/empty_library/services/library_space_estimate.dart'
    show isSameVolume;
import 'package:seforim_library_updater/seforim_library_updater.dart';

import '../services/library_access_gate.dart';
import '../services/library_runtime_refresh_service.dart';
import '../services/streaming_patch_downloader.dart';
import '../services/update_sqlite_setup.dart';

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

/// הרשאות הספרייה אינן מאפשרות את העדכון.
class LibraryUpdateReadOnlyException implements Exception {
  final String dir;
  const LibraryUpdateReadOnlyException(this.dir);

  @override
  String toString() =>
      'אין לתוכנה הרשאת כתיבה לתיקיית הספרייה, ולכן אי אפשר לעדכן אותה.'
      '\n\nהתיקייה: $dir\n\nהעבר את הספרייה למיקום שניתן לכתוב אליו, '
      'או בטל את סימון "קריאה בלבד" של התיקייה ושל קובצי הספרייה.';
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

  /// האם נשמר קובץ חלקי שהורדה חוזרת של [plan] תמשיך ממנו.
  Future<bool> hasResumableDownload(LibraryUpdatePlan plan);
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

  /// משעה את הספרייה בכל החלונות לפני החלפת קובץ המסד.
  final LibraryAccessGate accessGate;

  /// ניתנים להזרקה לצורך בדיקות.
  final String Function() dbPathProvider;
  final Future<String> Function() dataRootProvider;
  final String Function() nowTimestamp;
  final Future<DiskSpaceInfo> Function(String dirPath) diskSpaceProvider;
  final Future<PatchApplier> Function() applierProvider;
  final Future<void> Function() sqliteTempDirectoryInitializer;
  final bool isAndroid;

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
    bool? isAndroid,
  }) : isAndroid = isAndroid ?? Platform.isAndroid,
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

  static Future<void> _defaultFullDbExtractor(
    String archivePath,
    String outputPath,
  ) {
    return ZstdStreamExtractor.extractToFile(archivePath, outputPath);
  }

  /// פתיחת המסד חוסמת עשרות ms ויותר, וב-Windows ה-UI isolate הוא ה-platform thread.
  /// static: ה-closure של Isolate.run לוכד את כל ה-scope, ו-this אינו sendable.
  static Future<LocalDbVersion> _readLocalVersion(
    LocalDbVersionReader reader,
    String dbPath,
  ) => Isolate.run(() => reader.read(dbPath));

  /// בודק אם יש עדכון זמין ומחזיר את התוכנית.
  @override
  Future<LibraryUpdatePlan> checkForUpdate({
    required bool allowPrerelease,
  }) async {
    final dbPath = dbPathProvider();
    // ממסד פגום אין גרסה אמינה; בלי גרסה המתכנן בוחר הורדה מלאה.
    final local = DbReadWorker.corruptDatabaseDetected.value
        ? const LocalDbVersion(
            dbVersion: 0,
            schemaVersion: null,
            hasVersionMeta: false,
          )
        : await _readLocalVersion(versionReader, dbPath);
    final result = await discovery.discover(allowPrerelease: allowPrerelease);
    return planner.plan(
      localDbSizeBytes: _fileSizeOrNull(dbPath),
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
    final dbPath = dbPathProvider();
    await _ensureDbDirectoryWritable(dbPath);
    if (_hasWindowsReadOnlyAttribute(dbPath)) {
      throw LibraryUpdateReadOnlyException(p.dirname(dbPath));
    }
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
        void report(
          LibraryUpdatePhase phase, {
          String? stage,
          int? bytesDownloaded,
          int? bytesTotal,
          double? applyProgress,
        }) => onProgress?.call(
          LibraryUpdateProgress(
            phase: phase,
            stepIndex: i,
            totalSteps: steps.length,
            bytesDownloaded: bytesDownloaded,
            bytesTotal: bytesTotal,
            stage: stage,
            applyProgress: applyProgress,
          ),
        );
        void reportVerify(int done, int total) => report(
          LibraryUpdatePhase.verifying,
          applyProgress: _fraction(done, total),
        );

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
                    onVerifyProgress: reportVerify,
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

        report(LibraryUpdatePhase.downloading);
        final patchPath =
            reusablePatchPath ??
            await downloader.downloadAndExtract(
              patchFile: patchFile,
              downloadUrl: url,
              destDir: cacheDir,
              isCancelled: isCancelled,
              onProgress: (downloaded, total) => report(
                LibraryUpdatePhase.downloading,
                bytesDownloaded: downloaded,
                bytesTotal: total,
              ),
              // אימות patch פרוס של כמה GB נמשך עשרות שניות — בלי מד הוא נראה קפוא.
              onVerifyProgress: reportVerify,
            );

        try {
          // ביטול בדיוק אחרי החילוץ ולפני ההחלה — עוצרים לפני שנוגעים ב-DB.
          _throwIfCancelled(isCancelled);
          report(LibraryUpdatePhase.applying);
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
              report(LibraryUpdatePhase.applying, stage: stage);
            },
            onApplyProgress: (rowsDone, rowsTotal) => report(
              LibraryUpdatePhase.applying,
              stage: currentStage,
              applyProgress: _fraction(rowsDone, rowsTotal),
            ),
            onVerifyProgress: (done, total) {
              lastVerifyDone = done;
              report(
                LibraryUpdatePhase.applying,
                stage: 'verifyToHash',
                applyProgress: _fraction(done, total),
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
            applyProgress: _fraction(done, total),
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

  /// בדיקה מקדימה חלקית: ACL של קובץ המסד מתגלה רק בעת ההחלה או ההחלפה.
  Future<void> _ensureDbDirectoryWritable(String dbPath) async {
    final dir = p.dirname(dbPath);
    if (!await isDirectoryWritable(dir)) {
      throw LibraryUpdateReadOnlyException(dir);
    }
  }

  // ב-Windows ביט הכתיבה משקף את מאפיין "קריאה בלבד" שחוסם דלתא.
  // החלפה מלאה מזיזה את הקובץ לגיבוי ב-rename, שמותר גם כשהמאפיין מוגדר.
  static bool _hasWindowsReadOnlyAttribute(String path) {
    if (!Platform.isWindows) return false;
    final stat = FileStat.statSync(path);
    return stat.type == FileSystemEntityType.file && stat.mode & 0x80 == 0;
  }

  static bool _isPermissionError(FileSystemException error) =>
      (Platform.isWindows ? const {5, 19} : const {1, 13, 30}).contains(
        error.osError?.errorCode,
      );

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

    final sameVolume = isSameVolume(
      cacheDir.path,
      cacheInfo,
      dbDir,
      dbInfo,
      isAndroid: isAndroid,
    );
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
    await _ensureDbDirectoryWritable(dbPath);
    final cacheDir = Directory(
      p.join(await dataRootProvider(), 'library_update_cache'),
    );
    if (!cacheDir.existsSync()) cacheDir.createSync(recursive: true);
    _deleteStalePatchFiles(cacheDir, const []);
    final archivePath = p.join(cacheDir.path, 'seforim.db.zst');
    final sidecarPath = PatchDownloader.resumeSidecarPath(archivePath);
    // מחולץ ליד ה-DB (אותו filesystem) כדי שה-rename יהיה אטומי.
    final newDbPath = '$dbPath.new';
    final resumeToken = _fullDbResumeToken(asset);
    await ensureDiskSpaceForFullDownload(
      archivePath: archivePath,
      archiveNeeded: await additionalDownloadBytes(
        destPath: archivePath,
        identity: resumeToken,
        size: asset.size,
        split: asset.split,
      ),
      dbDir: p.dirname(dbPath),
    );

    try {
      onProgress?.call(
        const LibraryUpdateProgress(phase: LibraryUpdatePhase.downloading),
      );
      await downloader.downloadReleaseAssetToFile(
        asset: asset,
        destPath: archivePath,
        // קושר את הקובץ החלקי ל-release — מונע resume על ארכיון מגרסה אחרת.
        resumeToken: resumeToken,
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

  static String _fullDbResumeToken(ReleaseAsset asset) =>
      '${asset.downloadUrl}|${asset.size}|${asset.id ?? ''}|${asset.updatedAt ?? ''}';

  @override
  Future<bool> hasResumableDownload(LibraryUpdatePlan plan) async {
    final cacheDir = p.join(await dataRootProvider(), 'library_update_cache');
    final asset = plan.fullDbAsset;
    if (plan.kind == LibraryUpdatePlanKind.fullDownload && asset != null) {
      return hasReusableDownload(
        destPath: p.join(cacheDir, 'seforim.db.zst'),
        identity: _fullDbResumeToken(asset),
        size: asset.size,
        split: asset.split,
      );
    }
    for (final step in plan.deltaSteps) {
      final patchFile = step.manifest.patchFiles.first;
      final partial = File(p.join(cacheDir, patchFile.file));
      if (_resumablePatchBytes(partial, patchFile) > 0) return true;
    }
    return false;
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
  @visibleForTesting
  Future<void> ensureDiskSpaceForFullDownload({
    required String archivePath,
    required int archiveNeeded,
    required String dbDir,
  }) async {
    final archiveInfo = await diskSpaceProvider(p.dirname(archivePath));
    final extractInfo = await diskSpaceProvider(dbDir);
    String gb(int bytes) => (bytes / (1 << 30)).toStringAsFixed(1);

    final sameVolume = isSameVolume(
      p.dirname(archivePath),
      archiveInfo,
      dbDir,
      extractInfo,
      isAndroid: isAndroid,
    );
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
            // מכאן עד ה-rename אין await, ולכן ביטול נבדק מיד אחרי יצירת הגיבוי.
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
          } catch (error) {
            // לפני beginApply אין לפעולה הזו artifacts משלה; rollback בשלב הזה
            // עלול לגעת בטעות בגיבוי ישן שאינו שייך לריצה הנוכחית.
            if (recoveryStarted) await recovery.rollback(dbPath);
            if (error is FileSystemException && _isPermissionError(error)) {
              throw LibraryUpdateReadOnlyException(p.dirname(dbPath));
            }
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
      } catch (error) {
        await recovery.rollback(dbPath);
        if (error is sqlite3.SqliteException && error.resultCode == 8) {
          throw LibraryUpdateReadOnlyException(p.dirname(dbPath));
        }
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
            final revertFailure = await _trySetJournalMode(
              dbPath,
              'DELETE',
            );
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
  /// רץ ב-isolate: פתיחת הכתיבה וה-busy_timeout לא יחסמו את ה-UI.
  static Future<String?> _trySetJournalMode(String dbPath, String mode) =>
      Isolate.run(() => _setJournalMode(dbPath, mode));

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

  static double? _fraction(int done, int total) =>
      total > 0 ? (done / total).clamp(0.0, 1.0) : null;

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
