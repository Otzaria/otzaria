import 'dart:io';
import 'dart:isolate';

import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/data/constants/database_constants.dart';
import 'package:otzaria/data/data_providers/database_library_provider.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:otzaria/utils/file/zstd_stream_extractor.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sqlite3;
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

  const LibraryUpdateProgress({
    required this.phase,
    this.stepIndex = 0,
    this.totalSteps = 0,
    this.bytesDownloaded,
    this.bytesTotal,
    this.stage,
  });
}

typedef LibraryUpdateProgressCallback = void Function(
    LibraryUpdateProgress progress);

typedef FullDbExtractor = Future<void> Function(
    String archivePath, String outputPath);

/// ממשק שירות עדכון הספרייה — מאפשר ל-BLoC להיבדק מול מימוש מזויף.
abstract interface class LibraryUpdateService {
  Future<RecoveryResult> recoverIfNeeded();
  Future<LibraryUpdatePlan> checkForUpdate({required bool allowPrerelease});
  Future<void> applyDeltaPlan(
    LibraryUpdatePlan plan, {
    LibraryUpdateProgressCallback? onProgress,
    bool Function()? isCancelled,
  });
  Future<void> applyFullDownload(
    LibraryUpdatePlan plan, {
    LibraryUpdateProgressCallback? onProgress,
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
  })  : dbPathProvider = dbPathProvider ?? DatabaseConstants.getDatabasePath,
        dataRootProvider = dataRootProvider ?? AppPaths.getDataRootPath,
        nowTimestamp = nowTimestamp ?? (() => DateTime.now().toIso8601String()),
        fullDbExtractor = fullDbExtractor ?? _defaultFullDbExtractor;

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
  Future<void> applyDeltaPlan(
    LibraryUpdatePlan plan, {
    LibraryUpdateProgressCallback? onProgress,
    bool Function()? isCancelled,
  }) async {
    final dbPath = dbPathProvider();
    final cacheDir =
        Directory(p.join(await dataRootProvider(), 'library_update_cache'));

    final steps = plan.deltaSteps;
    for (var i = 0; i < steps.length; i++) {
      final step = steps[i];
      final patchFile = step.manifest.patchFiles.first;
      final url = step.patchFileUrls[patchFile.file];
      if (url == null) {
        throw StateError('חסר URL להורדת ${patchFile.file}');
      }

      onProgress?.call(LibraryUpdateProgress(
        phase: LibraryUpdatePhase.downloading,
        stepIndex: i,
        totalSteps: steps.length,
      ));
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
        onProgress?.call(LibraryUpdateProgress(
          phase: LibraryUpdatePhase.applying,
          stepIndex: i,
          totalSteps: steps.length,
        ));
        await _applyStepInQueue(
          dbPath: dbPath,
          patchPath: patchPath,
          step: step,
          onStage: (stage) => onProgress?.call(LibraryUpdateProgress(
            phase: LibraryUpdatePhase.applying,
            stepIndex: i,
            totalSteps: steps.length,
            stage: stage,
          )),
        );
      } finally {
        _deleteQuietly(patchPath); // מנקה גם בכשל apply, לא רק בהצלחה.
      }
    }

    onProgress?.call(
        const LibraryUpdateProgress(phase: LibraryUpdatePhase.refreshing));
    await refreshService.refreshAfterDbUpdate();

    onProgress
        ?.call(const LibraryUpdateProgress(phase: LibraryUpdatePhase.done));
  }

  /// מבצע הורדה מלאה: מוריד את `seforim.db.zst`, מחלץ בזרימה ליד ה-DB,
  /// מאמת (quick_check + גרסה), ומחליף אטומית את ה-DB הישן.
  ///
  /// נקרא רק אחרי אישור מפורש של המשתמש (ההורדה גדולה — ~1.1GB).
  @override
  Future<void> applyFullDownload(
    LibraryUpdatePlan plan, {
    LibraryUpdateProgressCallback? onProgress,
    bool Function()? isCancelled,
  }) async {
    final asset = plan.fullDbAsset;
    if (asset == null) {
      throw StateError('אין DB מלא בתוכנית');
    }
    final dbPath = dbPathProvider();
    final cacheDir =
        Directory(p.join(await dataRootProvider(), 'library_update_cache'));
    if (!cacheDir.existsSync()) cacheDir.createSync(recursive: true);
    final archivePath = p.join(cacheDir.path, 'seforim.db.zst');
    // מחולץ ליד ה-DB (אותו filesystem) כדי שה-rename יהיה אטומי.
    final newDbPath = '$dbPath.new';

    try {
      onProgress?.call(
          const LibraryUpdateProgress(phase: LibraryUpdatePhase.downloading));
      await downloader.downloadToFile(
        url: asset.downloadUrl,
        destPath: archivePath,
        expectedSize: asset.size > 0 ? asset.size : null,
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
          const LibraryUpdateProgress(phase: LibraryUpdatePhase.applying));
      _deleteQuietly(newDbPath);
      await fullDbExtractor(archivePath, newDbPath);
      _deleteQuietly(archivePath);
      _throwIfCancelled(isCancelled);

      onProgress?.call(
          const LibraryUpdateProgress(phase: LibraryUpdatePhase.verifying));
      // האימות הכבד (quick_check על ~5.5GB) רץ ב-isolate כדי לא לחסום UI.
      await _verifyFullDbInIsolate(newDbPath, plan.targetVersion);
      _throwIfCancelled(isCancelled);

      // מכאן ואילך אין ביטול — ה-DB מוחלף אטומית.
      await _replaceDbInQueue(dbPath: dbPath, newDbPath: newDbPath, plan: plan);

      onProgress?.call(
          const LibraryUpdateProgress(phase: LibraryUpdatePhase.refreshing));
      await refreshService.refreshAfterDbUpdate();

      onProgress
          ?.call(const LibraryUpdateProgress(phase: LibraryUpdatePhase.done));
    } catch (_) {
      _deleteQuietly(archivePath);
      _deleteQuietly(newDbPath);
      rethrow;
    }
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
  }) {
    return DatabaseLibraryProvider.operationQueue.enqueue(() async {
      await SqliteDataProvider.instance.closeForExternalWrite();
      try {
        await recovery.beginApply(
          dbPath: dbPath,
          fromVersion: plan.localVersion,
          toVersion: plan.targetVersion ?? 0,
          timestamp: nowTimestamp(),
        );
        _deleteQuietly('$dbPath-wal');
        _deleteQuietly('$dbPath-shm');
        _deleteQuietly(dbPath);
        File(newDbPath).renameSync(dbPath);
        recovery.finishSuccess(dbPath);
      } catch (_) {
        await recovery.rollback(dbPath);
        rethrow;
      } finally {
        await SqliteDataProvider.instance.reopenAfterExternalWrite();
      }
    });
  }

  Future<void> _applyStepInQueue({
    required String dbPath,
    required String patchPath,
    required PatchEdge step,
    void Function(String stage)? onStage,
  }) {
    return DatabaseLibraryProvider.operationQueue.enqueue(() async {
      await SqliteDataProvider.instance.closeForExternalWrite();
      try {
        // ללא גיבוי מלא: ה-apply עטוף ב-transaction יחיד של SQLite, אז קריסה
        // באמצע מתגלגלת אחורה אוטומטית — ה-DB תמיד נשאר תקין (מקור או יעד).
        await recovery.beginApply(
          dbPath: dbPath,
          fromVersion: step.fromVersion,
          toVersion: step.toVersion,
          timestamp: nowTimestamp(),
        );
        await _applyPatchInIsolate(
          dbPath: dbPath,
          patchPath: patchPath,
          manifest: step.manifest,
          onStage: onStage,
        );
        recovery.finishSuccess(dbPath);
      } catch (_) {
        await recovery.rollback(dbPath);
        rethrow;
      } finally {
        await SqliteDataProvider.instance.reopenAfterExternalWrite();
      }
    });
  }

  // מאזין לתת-שלבי ה-apply דרך ReceivePort ומעביר ל-onStage (רץ ב-main isolate).
  // ה-onStage עצמו אסור שייכנס ל-scope של ה-Isolate.run (ראה [_runApplyIsolate]).
  static Future<void> _applyPatchInIsolate({
    required String dbPath,
    required String patchPath,
    required DeltaManifest manifest,
    void Function(String stage)? onStage,
  }) async {
    final port = ReceivePort();
    final sub = port.listen((msg) {
      if (msg is String) onStage?.call(msg);
    });
    try {
      await _runApplyIsolate(
        dbPath: dbPath,
        patchPath: patchPath,
        manifest: manifest,
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
  static Future<void> _runApplyIsolate({
    required String dbPath,
    required String patchPath,
    required DeltaManifest manifest,
    required SendPort sendPort,
  }) {
    return Isolate.run(() => const PatchApplier().apply(
          dbPath: dbPath,
          patchPath: patchPath,
          manifest: manifest,
          // verifyFromHash=false: verifyToHash אחרי ה-apply הוא הערובה האמיתית —
          // אם המקור שונה, ה-toHash ייכשל וה-transaction יתגלגל אחורה. הבדיקה
          // המקדימה רק כפילה קריאה של כל ה-DB (5.5GB) לחינם.
          verifyFromHash: false,
          // checkForeignKeys=false: verifyToHash מאמת את כל 28 הטבלאות (וכל ה-FK
          // שביניהן) מול ה-DB התקין, אז התאמת hash כבר שוללת הפרות FK — חוסך ~60ש.
          checkForeignKeys: false,
          onStage: (stage) => sendPort.send(stage),
        ));
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
}
