import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
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

typedef LibraryUpdateProgressCallback = void Function(
    LibraryUpdateProgress progress);

typedef FullDbExtractor = Future<void> Function(
    String archivePath, String outputPath);

/// ממשק שירות עדכון הספרייה — מאפשר ל-BLoC להיבדק מול מימוש מזויף.
abstract interface class LibraryUpdateService {
  Future<RecoveryResult> recoverIfNeeded();
  Future<LibraryUpdatePlan> checkForUpdate({required bool allowPrerelease});

  /// מחזיר את מזהי הספרים שתוכנם השתנה בעדכון — לרענון אינדקס החיפוש שלהם.
  Future<Set<int>> applyDeltaPlan(
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
  Future<Set<int>> applyDeltaPlan(
    LibraryUpdatePlan plan, {
    LibraryUpdateProgressCallback? onProgress,
    bool Function()? isCancelled,
  }) async {
    final dbPath = dbPathProvider();
    final cacheDir =
        Directory(p.join(await dataRootProvider(), 'library_update_cache'));

    // סך-הבתים של ה-hash מהריצה הקודמת — total מדויק למד ההתקדמות (גודל
    // הקובץ הוא הערכת-יתר של ~25%). בריצה הראשונה נופלים לגודל הקובץ.
    final hintFile = File(p.join(cacheDir.path, 'verify_total_bytes.txt'));
    var verifyTotalHint = _readIntQuietly(hintFile);
    var lastVerifyDone = 0;

    final booksTouched = <int>{};
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
        booksTouched.addAll(await _applyStepInQueue(
          dbPath: dbPath,
          patchPath: patchPath,
          step: step,
          verifyTotalBytesHint: verifyTotalHint,
          onStage: (stage) => onProgress?.call(LibraryUpdateProgress(
            phase: LibraryUpdatePhase.applying,
            stepIndex: i,
            totalSteps: steps.length,
            stage: stage,
          )),
          onVerifyProgress: (done, total) {
            lastVerifyDone = done;
            onProgress?.call(LibraryUpdateProgress(
              phase: LibraryUpdatePhase.applying,
              stepIndex: i,
              totalSteps: steps.length,
              stage: 'verifyToHash',
              applyProgress: total > 0 ? (done / total).clamp(0.0, 1.0) : null,
            ));
          },
        ));
        // הדיווח האחרון מ-compute הוא הסך המדויק — total לריצות הבאות.
        if (lastVerifyDone > 0) {
          verifyTotalHint = lastVerifyDone;
          _writeIntQuietly(hintFile, lastVerifyDone);
        }
      } finally {
        _deleteQuietly(patchPath); // מנקה גם בכשל apply, לא רק בהצלחה.
      }
    }

    onProgress?.call(
        const LibraryUpdateProgress(phase: LibraryUpdatePhase.refreshing));
    await refreshService.refreshAfterDbUpdate();

    onProgress
        ?.call(const LibraryUpdateProgress(phase: LibraryUpdatePhase.done));
    return booksTouched;
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

  Future<Set<int>> _applyStepInQueue({
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
      final concurrentReads = _trySetJournalMode(dbPath, 'WAL');
      if (!concurrentReads) {
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
          if (!_trySetJournalMode(dbPath, 'DELETE')) {
            debugPrint(
                '[LibraryUpdate] failed to revert journal_mode to DELETE');
          }
        }
        await SqliteDataProvider.instance.reopenAfterExternalWrite();
      }
    });
  }

  /// ממיר את מצב היומן של [dbPath] ומחזיר האם ההמרה הצליחה. ההמרה דורשת
  /// נעילה בלעדית קצרה — busy_timeout מכסה קריאות קצרות שבאמצע.
  bool _trySetJournalMode(String dbPath, String mode) {
    try {
      final db = sqlite3.sqlite3.open(dbPath);
      try {
        db.execute('PRAGMA busy_timeout = 5000');
        if (mode == 'DELETE') {
          db.execute('PRAGMA wal_checkpoint(TRUNCATE)');
        }
        final result = db.select('PRAGMA journal_mode=$mode');
        return result.isNotEmpty &&
            result.first.values.first?.toString().toLowerCase() ==
                mode.toLowerCase();
      } finally {
        db.close();
      }
    } catch (_) {
      return false;
    }
  }

  // מאזין לתת-שלבי ה-apply דרך ReceivePort ומעביר ל-onStage (רץ ב-main isolate).
  // ה-onStage עצמו אסור שייכנס ל-scope של ה-Isolate.run (ראה [_runApplyIsolate]).
  static Future<Set<int>> _applyPatchInIsolate({
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
  static Future<Set<int>> _runApplyIsolate({
    required String dbPath,
    required String patchPath,
    required DeltaManifest manifest,
    required SendPort sendPort,
    int? verifyTotalBytesHint,
  }) {
    return Isolate.run(() => const PatchApplier()
        .apply(
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
        )
        .booksTouched);
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
