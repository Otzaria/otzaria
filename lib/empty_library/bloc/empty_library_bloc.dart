import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'package:bloc/bloc.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:file_picker/file_picker.dart';
import 'package:otzaria/utils/text/byte_size_text.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/core/http_client_registry.dart';
import 'package:otzaria/data/constants/database_constants.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:otzaria/empty_library/bloc/empty_library_event.dart';
import 'package:otzaria/empty_library/bloc/empty_library_state.dart';
import 'package:otzaria/empty_library/services/android_storage_service.dart';
import 'package:otzaria/empty_library/services/library_package/library_package.dart';
import 'package:otzaria/empty_library/services/library_package/library_package_extractor.dart';
import 'package:otzaria/empty_library/services/library_package/library_package_importer.dart';
import 'package:otzaria/empty_library/services/library_package/library_source.dart';
import 'package:otzaria/empty_library/services/library_space_estimate.dart';
import 'package:otzaria/library_update/services/library_access_gate.dart';
import 'package:otzaria/library_update/services/companion_assets_service.dart';
import 'package:otzaria/search/magic_dictionary_downloader.dart';
import 'package:otzaria/settings/settings_exports.dart';
import 'package:otzaria/utils/download_eta_estimator.dart';
import 'package:otzaria/utils/download_sidecar.dart';
import 'package:otzaria/utils/file/disk_free_space.dart';
import 'package:otzaria/utils/file/download_space.dart';
import 'package:otzaria/utils/file/tar_zst_extractor.dart';
import 'package:otzaria/utils/file/zstd_patch_decoder.dart';
import 'package:otzaria/utils/file/zstd_stream_extractor.dart';
import 'package:path/path.dart' as path;
import 'package:http/http.dart' as http;
import 'package:seforim_library_updater/seforim_library_updater.dart';

class EmptyLibraryBloc extends Bloc<EmptyLibraryEvent, EmptyLibraryState> {
  static const Duration _defaultDownloadConnectTimeout = Duration(seconds: 20);
  static const Duration _downloadStallTimeout = Duration(seconds: 60);

  EmptyLibraryBloc({
    http.Client? httpClient,
    Future<void> Function(
      String archivePath,
      String outputPath,
      void Function(double progress)? onProgress,
    )?
    extractCompressedDatabase,
    Future<void> Function(
      String archivePath,
      String outputDir,
      void Function(double progress)? onProgress,
    )?
    extractTarArchive,
    this._defaultLibraryPathOverride,
    this.downloadConnectTimeout = _defaultDownloadConnectTimeout,
    this.downloadSpaceChecker,
    LibraryAccessGate? accessGate,
    LibraryPackageImporter? packageImporter,
  }) : _httpClient = httpClient ?? http.Client(),
       _accessGate = accessGate ?? LibraryAccessGate.instance,
       _packageImporter = packageImporter ?? LibraryPackageImporter(),
       _extractCompressedDatabase = extractCompressedDatabase ?? _extractZst,
       _extractTarArchive = extractTarArchive ?? _extractTarZst,
       super(
         const EmptyLibraryInitial(downloadDisabledReason: 'בודק מקום פנוי...'),
       ) {
    HttpClientRegistry.register(_httpClient.close);
    on<UseLibraryInPlaceRequested>(_onUseLibraryInPlaceRequested);
    on<DownloadLibraryRequested>(_onDownloadLibraryRequested);
    on<ImportLibraryFolderRequested>(_onImportLibraryFolderRequested);
    on<ImportLibraryPackageRequested>(_onImportLibraryPackageRequested);
    on<CancelLibraryImportRequested>(
      (_, _) => _activeImportCancel?.cancel(),
    );
    on<UpdateLibraryRequested>(_onUpdateLibraryRequested);
    on<CheckDiskSpaceRequested>(_onCheckDiskSpaceRequested);
    on<StorageLocationSelected>(_onStorageLocationSelected);
    // בדיקת מקום פנוי מתבצעת מיד — כפתור ההורדה מושבת עד להשלמתה
    add(CheckDiskSpaceRequested());
  }

  final http.Client _httpClient;
  final Duration downloadConnectTimeout;
  final Future<String?> Function(int? downloadSize)? downloadSpaceChecker;

  /// חלון משני מחזיק את המסד פתוח, והזזתו לגיבוי נכשלת ב-Windows.
  final LibraryAccessGate _accessGate;
  final LibraryPackageImporter _packageImporter;

  /// דגל הביטול של פריסת חבילה שרצה כעת.
  ZstdCancelFlag? _activeImportCancel;
  final Future<void> Function(
    String archivePath,
    String outputPath,
    void Function(double progress)? onProgress,
  )
  _extractCompressedDatabase;
  final Future<void> Function(
    String archivePath,
    String outputDir,
    void Function(double progress)? onProgress,
  )
  _extractTarArchive;

  // סיבת השבתת כפתור ההורדה — נשמרת כ-instance field כדי להישמר בין state transitions
  String? _downloadDisabledReason = 'בודק מקום פנוי...';
  final String? _defaultLibraryPathOverride;

  /// מצביע על ספרייה קיימת בלי להעתיק דבר — מאמת שיש seforim.db בתיקייה
  /// ושומר אותה כנתיב הספרייה.
  Future<void> _onUseLibraryInPlaceRequested(
    UseLibraryInPlaceRequested event,
    Emitter<EmptyLibraryState> emit,
  ) async {
    emit(EmptyLibraryLoading(selectedPath: event.folderPath));
    await _handleDirectorySelection(event.folderPath, emit);
  }

  /// מייבא את נכסי הספרייה הגולמיים שזוהו בתיקייה (ראה [scanRawLibraryAssets]).
  Future<void> _onImportLibraryFolderRequested(
    ImportLibraryFolderRequested event,
    Emitter<EmptyLibraryState> emit,
  ) => _replaceLibrarySafely(
    emit,
    backupPath: event.backupExistingPath,
    body: () => _importRawAssets(event.assets, event.targetPath, emit),
    onError: (e) => _error(
      errorMessage: packageImportErrorMessage(e, assistantFiles: false),
      selectedPath: event.targetPath,
    ),
  );

  /// מריץ ייבוא שמחליף את הספרייה. עם [backupPath] (עדכון במקום) המסד מושעה
  /// בכל החלונות, ה-DB הישן מגובה, ומשוחזר אם [body] לא הסתיים בבחירת ספרייה.
  Future<void> _replaceLibrarySafely(
    Emitter<EmptyLibraryState> emit, {
    required String? backupPath,
    required Future<void> Function() body,
    required EmptyLibraryState Function(Object error) onError,
    Future<void> Function()? afterReplacement,
  }) async {
    String? backupDir;
    var writeSessionStarted = false;
    LibrarySuspension? suspension;
    try {
      if (backupPath != null) {
        suspension = await _accessGate.suspendAll();
        await SqliteDataProvider.instance.closeForExternalWrite();
        writeSessionStarted = true;
        await _accessGate.verifyReleased(_dbPathIn(backupPath));
        backupDir = await _backupDatabaseFiles(backupPath);
      }
      await body();
      if (backupDir != null) {
        if (state is EmptyLibraryDirectorySelected) {
          await _cleanupCommittedImport(
            'גיבוי המסד',
            () => _discardBackupDir(backupDir!),
          );
        } else {
          await _restoreDatabaseFiles(backupDir, backupPath!);
        }
      }
    } catch (e) {
      if (backupDir != null) {
        await _restoreDatabaseFiles(backupDir, backupPath!);
      }
      emit(onError(e));
    } finally {
      if (writeSessionStarted) {
        await SqliteDataProvider.instance.reopenAfterExternalWrite(
          reopenDatabase: false,
        );
      }
      await afterReplacement?.call();
      await clearFilePickerCache();
      if (suspension != null) {
        await _accessGate.resumeAll(
          suspension,
          dbReplaced: state is EmptyLibraryDirectorySelected,
        );
      }
    }
  }

  /// מייבא את קובצי הספרייה (ואופציונלית האינדקס) שמסייע ההורדה הכין.
  Future<void> _onImportLibraryPackageRequested(
    ImportLibraryPackageRequested event,
    Emitter<EmptyLibraryState> emit,
  ) async {
    var indexReleased = false;
    await _replaceLibrarySafely(
      emit,
      backupPath: event.backupExistingPath,
      body: () => _importLibraryPackage(
        event.packages,
        event.targetPath,
        emit,
        onIndexReleased: () => indexReleased = true,
      ),
      afterReplacement: () async {
        // פתיחה מחדש חייבת לראות גם את המסד שהוחזר בכשל, לפני חידוש החלונות.
        if (indexReleased) {
          await _packageImporter.reopenIndex().catchError(
            (Object e) => debugPrint('[EmptyLibrary] פתיחת האינדקס נכשלה: $e'),
          );
        }
      },
      onError: (e) => _error(
        // באנדרואיד החבילה מגיעה בדרך כלל מכרכי ה-ZIP שהורדו, לא מהמסייע.
        errorMessage: packageImportErrorMessage(
          e,
          assistantFiles: !Platform.isAndroid,
        ),
        selectedPath: event.packages.folder.displayName,
      ),
    );
  }

  /// פריסה ל-staging (ניתנת לביטול), בדיקת ה-DB, החלפת האינדקס והעברת
  /// הספרים ליעד. כשל לפני ההעברה אינו נוגע ביעד.
  Future<void> _importLibraryPackage(
    LibraryPackageSet packages,
    String target,
    Emitter<EmptyLibraryState> emit, {
    required VoidCallback onIndexReleased,
  }) async {
    void report(String message, double progress, {bool cancellable = true}) =>
        emit(
          EmptyLibraryExtracting(
            selectedPath: target,
            progress: progress,
            message: message,
            cancellable: cancellable,
          ),
        );

    report('בודק מקום פנוי...', 0, cancellable: false);
    final indexTarget = packages.index == null
        ? null
        : await LibraryPackageImporter.indexTargetFor(target);
    await _packageImporter.checkSpace(packages, target, indexTarget);

    final cancel = ZstdCancelFlag();
    _activeImportCancel = cancel;
    final StagedLibraryPackage staged;
    try {
      staged = await _packageImporter.stage(
        packages: packages,
        booksTarget: target,
        indexTarget: indexTarget,
        cancel: cancel,
        onProgress: (kind, done, total) => report(
          '${kind == LibraryPackageKind.searchIndex ? 'מאמת ופורס את אינדקס החיפוש' : 'מאמת ופורס את הספרייה'}\n'
          '${formatMegabytesProgressHebrew(done, total)}',
          total > 0 ? (done / total).clamp(0.0, 1.0) : 0,
        ),
      );
    } finally {
      _activeImportCancel = null;
      cancel.dispose();
    }

    final hasIndex = indexTarget != null && staged.indexDir != null;
    final previousSettings = {
      for (final key in [
        SettingsRepository.keyIndexPath,
        SettingsRepository.keyLibraryPath,
        SettingsRepository.keyLibraryFolderName,
        SettingsRepository.keyDbEffectivePath,
      ])
        key: Settings.getValue<String>(key),
    };
    Future<void> rollback() async {
      if (hasIndex) await _packageImporter.rollbackIndex(indexTarget);
      for (final entry in previousSettings.entries) {
        if (Settings.getValue<String>(entry.key) != entry.value) {
          await Settings.setValue<String?>(entry.key, entry.value);
        }
      }
    }

    try {
      report('מעביר את הספרייה למקומה...', 1, cancellable: false);
      final stagedDb = _dbPathIn(staged.booksDir);
      if (!await File(stagedDb).exists()) {
        throw FormatException(
          'בספרייה שהורדה חסר ${DatabaseConstants.databaseFileName}',
        );
      }
      await _checkDbSchemaOffThread(stagedDb);
      final imported = {
        ...await _presentComponents(staged.booksDir),
        if (hasIndex) LibraryComponent.searchIndex,
      };
      if (hasIndex) {
        onIndexReleased();
        await _packageImporter.installIndex(staged, indexTarget);
      }
      try {
        await promoteStagedImport(staged.booksDir, target);
        if (hasIndex) {
          await Settings.setValue<String>(
            SettingsRepository.keyIndexPath,
            indexTarget,
          );
        }
        await _handleDirectorySelection(target, emit, imported: imported);
      } catch (_) {
        await rollback();
        rethrow;
      }
      if (state is EmptyLibraryDirectorySelected) {
        if (hasIndex) {
          await _cleanupCommittedImport(
            'גיבוי האינדקס',
            () => _packageImporter.commitIndex(indexTarget),
          );
        }
      } else {
        await rollback();
      }
    } finally {
      if (state is EmptyLibraryDirectorySelected) {
        await _cleanupCommittedImport(
          'תיקיית הפריסה הזמנית',
          () => _packageImporter.discard(staged),
        );
      } else {
        await _packageImporter.discard(staged);
      }
    }
  }

  // אחרי אישור הספרייה ניקוי אינו יכול להחזיר עסקה שגיבוייה כבר נמחקו.
  static Future<void> _cleanupCommittedImport(
    String name,
    Future<void> Function() cleanup,
  ) async {
    try {
      await cleanup();
    } catch (e) {
      debugPrint('[EmptyLibrary] ניקוי $name נכשל: $e');
    }
  }

  static Future<void> _checkDbSchemaOffThread(String dbPath) =>
      Isolate.run(() => requireReadableDbSchema(dbPath));

  /// הודעה למשתמש על כשל בייבוא; [assistantFiles] — הקבצים הוכנו במסייע ההורדה.
  @visibleForTesting
  static String packageImportErrorMessage(
    Object error, {
    bool assistantFiles = true,
  }) {
    final prepareAgain = assistantFiles
        ? 'יש להכין את התיקייה מחדש במסייע ההורדה.'
        : 'יש לוודא שכל הקבצים הועתקו במלואם לתיקייה ולנסות שוב.';
    return switch (error) {
      LibraryImportCancelled() => 'הייבוא בוטל. הספרייה לא שונתה.',
      InsufficientSpaceException() => '$error',
      PathAccessException(:final path) =>
        'אין לתוכנה הרשאת קריאה לקובץ $path. '
            'יש לבחור את התיקייה שוב, או להעתיק את הקבצים לתיקייה אחרת.',
      FileSystemException(osError: OSError(errorCode: 28 || 112)) =>
        'אין מספיק מקום פנוי לפריסת הספרייה. יש לפנות מקום ולנסות שוב.',
      FormatException(:final message) =>
        'ייבוא הספרייה נכשל: $message\n$prepareAgain',
      PlatformException(:final message) =>
        'קריאת הקבצים מהתיקייה שנבחרה נכשלה: $message',
      _ => 'שגיאה בייבוא הספרייה: $error',
    };
  }

  /// פריסת הנכסים ל-staging (ניתנת לביטול), בדיקת ה-DB והעברה ליעד —
  /// seforim.db אחרון. כשל לפני ההעברה אינו נוגע ביעד.
  Future<void> _importRawAssets(
    RawLibraryScan raw,
    String target,
    Emitter<EmptyLibraryState> emit,
  ) async {
    void report(String message, double progress, {bool cancellable = true}) =>
        emit(
          EmptyLibraryExtracting(
            selectedPath: target,
            progress: progress,
            message: message,
            cancellable: cancellable,
          ),
        );

    report('בודק מקום פנוי...', 0, cancellable: false);
    final importsDb = raw.assets.containsKey(LibraryComponent.libraryDb);
    // ייבוא נלווים בלבד מותר רק אל ספרייה שכבר יש בה מסד.
    if (!importsDb && !await File(_dbPathIn(target)).exists()) {
      throw FormatException(
        'לא נמצא ${DatabaseConstants.databaseFileName} '
        '(או הגרסה הדחוסה שלו) בתיקייה שנבחרה',
      );
    }
    await _packageImporter.checkRawSpace(raw, target);

    final cancel = ZstdCancelFlag();
    _activeImportCancel = cancel;
    String? staging;
    try {
      staging = await _packageImporter.stageRaw(
        raw: raw,
        booksTarget: target,
        cancel: cancel,
        onProgress: (component, done, total) => report(
          '${_extractTitle(component)}\n'
          '${formatMegabytesProgressHebrew(done, total)}',
          total > 0 ? (done / total).clamp(0.0, 1.0) : 0,
        ),
      );
      if (importsDb) await _checkDbSchemaOffThread(_dbPathIn(staging));
      if (Pointer<Uint8>.fromAddress(cancel.address).value != 0) {
        throw const LibraryImportCancelled();
      }
      report('מעביר את הספרייה למקומה...', 1, cancellable: false);
      await promoteStagedImport(staging, target);
    } finally {
      _activeImportCancel = null;
      cancel.dispose();
      if (staging != null) await _packageImporter.discardRaw(staging);
    }
    await _handleDirectorySelection(
      target,
      emit,
      imported: raw.assets.keys.toSet(),
    );
  }

  static String _extractTitle(LibraryComponent component) =>
      switch (component) {
        LibraryComponent.libraryDb => 'מחלץ את ספריית הספרים',
        LibraryComponent.talmudBavli => 'מחלץ את ספרי התלמוד הבבלי',
        LibraryComponent.catalog => 'מחלץ את קטלוג אוצר החכמה',
        LibraryComponent.lexicon => 'מעתיק את המילון לחיפוש המקורב',
        LibraryComponent.searchIndex => 'פורס את אינדקס החיפוש',
      };

  /// רכיבי הספרייה הקיימים בתיקיית הספרים [booksDir] (בלי האינדקס).
  static Future<Set<LibraryComponent>> _presentComponents(
    String booksDir,
  ) async => {
    if (await File(_dbPathIn(booksDir)).exists()) LibraryComponent.libraryDb,
    if (await Directory(
      path.join(booksDir, DatabaseConstants.talmudBavliFolderName),
    ).exists())
      LibraryComponent.talmudBavli,
    if (await File(
      path.join(booksDir, DatabaseConstants.externalCatalogDatabaseFileName),
    ).exists())
      LibraryComponent.catalog,
    if (await File(
      path.join(booksDir, DatabaseConstants.lexicalDatabaseFileName),
    ).exists())
      LibraryComponent.lexicon,
  };

  /// שמות קבצי ה-DB שמגובים/מועתקים בעדכון ספרייה (seforim.db והלוואי שלו).
  static const _dbFileSuffixes = ['', '-shm', '-wal', '-journal'];

  /// עדכון ספרייה קיימת עם גיבוי בטוח: ה-DB הישן מגובה לתיקייה זמנית, נמחק
  /// לצמיתות רק בהצלחה ומשוחזר בכישלון, וביניהם הספרייה מורדת מחדש.
  Future<void> _onUpdateLibraryRequested(
    UpdateLibraryRequested event,
    Emitter<EmptyLibraryState> emit,
  ) async {
    final target = event.targetPath;
    String? backupDir;
    var writeSessionStarted = false;
    LibrarySuspension? suspension;
    try {
      suspension = await _accessGate.suspendAll();
      await SqliteDataProvider.instance.closeForExternalWrite();
      writeSessionStarted = true;
      await _accessGate.verifyReleased(_dbPathIn(event.existingLibraryPath));
      backupDir = await _backupDatabaseFiles(event.existingLibraryPath);
      await _downloadLibrary(target, emit);
      // הצלחה = state סופי DirectorySelected; אחרת (כשל שקט) משחזרים.
      if (state is EmptyLibraryDirectorySelected) {
        if (backupDir != null) await _discardBackupDir(backupDir);
      } else if (backupDir != null) {
        await _restoreDatabaseFiles(backupDir, event.existingLibraryPath);
      }
    } catch (e) {
      if (backupDir != null) {
        await _restoreDatabaseFiles(backupDir, event.existingLibraryPath);
      }
      emit(_error(errorMessage: 'שגיאה בעדכון הספרייה: $e'));
    } finally {
      if (writeSessionStarted) {
        await SqliteDataProvider.instance.reopenAfterExternalWrite(
          reopenDatabase: false,
        );
      }
      if (suspension != null) {
        await _accessGate.resumeAll(
          suspension,
          dbReplaced: state is EmptyLibraryDirectorySelected,
        );
      }
    }
  }

  static String _dbPathIn(String dir) =>
      path.join(dir, DatabaseConstants.databaseFileName);

  /// שם הקובץ הזמני שאליו נכתב ה-DB לפני ההעברה לשם הסופי.
  static String _dbTempPathFor(String finalPath) => '$finalPath.new';

  /// מוחק את [dbPath] ואת לוואיו (shm/wal/journal), בשקט.
  static Future<void> _deleteDbFamily(String dbPath) async {
    for (final suffix in _dbFileSuffixes) {
      final f = File('$dbPath$suffix');
      if (await f.exists()) {
        try {
          await f.delete();
        } catch (_) {}
      }
    }
  }

  /// כותב את ה-DB דרך שם זמני באותה תיקייה ומעביר אותו לשם הסופי רק בסיום
  /// מוצלח. הריגת התהליך באמצע משאירה שארית `.new` ולא DB חלקי בשם האמיתי —
  /// שאחרת נראה תקין ומאבד את הגיבוי היחיד.
  static Future<void> _writeDbAtomically(
    String finalPath,
    Future<void> Function(String tempPath) write,
  ) async {
    final tempPath = _dbTempPathFor(finalPath);
    await _deleteDbFamily(tempPath);
    try {
      await write(tempPath);
      await Isolate.run(() => requireReadableDbSchema(tempPath));
      await _deleteDbFamily(finalPath);
      await File(tempPath).rename(finalPath);
    } catch (_) {
      await _deleteDbFamily(tempPath);
      rethrow;
    }
  }

  /// מסד בסכמה חדשה מזו שהגרסה קוראת היה מחליף את הספרייה ונכשל בכל ספר.
  @visibleForTesting
  static void requireReadableDbSchema(String dbPath) {
    final schema = const LocalDbVersionReader().read(dbPath).schemaVersion;
    const readable = DatabaseConstants.readableDbSchemaVersion;
    if (schema != null && schema > readable) {
      throw UnsupportedDbSchemaException(schema, readable);
    }
  }

  static String? _tempRootOverride;

  /// בסיס התיקיות הזמניות של הגיבוי. הגיבוי הוא שם קבוע אחד, ולכן ריצת טסטים
  /// שנהרגה הייתה דולפת לריצה הבאה — כל טסט מזריק תיקייה משלו.
  @visibleForTesting
  static set tempRootOverride(String? value) => _tempRootOverride = value;

  static String get _tempRoot => _tempRootOverride ?? Directory.systemTemp.path;

  /// תיקיית הביניים שאליה נפרס ייבוא: אחות ליעד, ולכן על אותו התקן —
  /// תנאי ל-rename אטומי בהעברה ממנה.
  @visibleForTesting
  static String stagingDirFor(String target) => '$target.import';

  /// מוחק קובץ/תיקייה/קישור בנתיב, בשקט.
  static Future<void> _deleteEntity(String entityPath) async {
    for (final entity in [
      Directory(entityPath),
      File(entityPath),
      Link(entityPath),
    ]) {
      try {
        if (await entity.exists()) {
          await entity.delete(recursive: true);
          return;
        }
      } catch (_) {}
    }
  }

  /// מעביר את תוכן [from] אל [to] ב-rename (תיקיות אחיות ⇒ אותו התקן), דורס
  /// פריטים מתנגשים; תיקייה שכבר קיימת ביעד ממוזגת רקורסיבית ולא נמחקת.
  static Future<void> _renameEntriesOver(
    String from,
    String to, {
    Set<String> skip = const {},
  }) async {
    await Directory(to).create(recursive: true);
    await for (final entity in Directory(from).list(followLinks: false)) {
      final name = path.basename(entity.path);
      if (skip.contains(name)) continue;
      final dest = path.join(to, name);
      if (entity is Directory && await Directory(dest).exists()) {
        await _renameEntriesOver(entity.path, dest);
        await entity.delete(recursive: true);
        continue;
      }
      await _deleteEntity(dest);
      await entity.rename(dest);
    }
  }

  /// מעביר ייבוא שחולץ ל-[staging] אל [target]. seforim.db עובר אחרון, ולכן
  /// הופעתו ביעד משמעה שהייבוא הושלם.
  @visibleForTesting
  static Future<void> promoteStagedImport(
    String staging,
    String target,
  ) async {
    final dbName = DatabaseConstants.databaseFileName;
    final family = {for (final s in _dbFileSuffixes) '$dbName$s'};
    final lexicalName = DatabaseConstants.lexicalDatabaseFileName;
    final installsDictionary = await File(
      path.join(staging, lexicalName),
    ).exists();
    await _renameEntriesOver(staging, target, skip: family);
    if (installsDictionary) {
      await MagicDictionaryDownloader.writeFileDigestMarker(
        path.join(target, lexicalName),
      );
    }
    final stagedDb = File(path.join(staging, dbName));
    if (!await stagedDb.exists()) return;
    await _deleteDbFamily(path.join(target, dbName));
    for (final suffix in _dbFileSuffixes.where((s) => s.isNotEmpty)) {
      final sidecar = File(path.join(staging, '$dbName$suffix'));
      if (await sidecar.exists()) {
        await sidecar.rename(path.join(target, '$dbName$suffix'));
      }
    }
    await stagedDb.rename(path.join(target, dbName));
  }

  /// תיקיית הגיבוי הזמני של ה-DB בזמן עדכון. שם קבוע: ריצה שנהרגה באמצע
  /// משאירה גיבוי יתום (כל ה-DB), ושם ייחודי לכל ריצה היה מצבר עותק על עותק.
  static String get dbBackupDirPath =>
      path.join(_tempRoot, 'otzaria_db_backup');

  /// מטפל בגיבויים יתומים מריצות שנהרגו (השם הקבוע וגם שמות ישנים עם
  /// timestamp): אם בספרייה [dir] אין seforim.db — מחזיר אותו מהגיבוי שבו
  /// הקובץ החדש ביותר; כל שאר הגיבויים נמחקים. נקרא בעלייה ולפני כל גיבוי חדש.
  static Future<void> recoverOrphanedDbBackup(String dir) async {
    final dbName = DatabaseConstants.databaseFileName;
    // כתיבה שנהרגה באמצע משאירה `.new` בגודל ה-DB המלא; אין ממנו המשך,
    // וכך גם תיקיית הביניים של ייבוא שנקטע.
    await _deleteDbFamily(_dbTempPathFor(path.join(dir, dbName)));
    await _deleteEntity(stagingDirFor(dir));
    // list ולא listSync: הפונקציה רצה בעלייה לפני הפריים הראשון, וסריקה
    // סינכרונית של כל תיקיית ה-temp (אלפי פריטים) חוסמת את ה-isolate הראשי.
    final backups = await Directory(_tempRoot)
        .list()
        .where((e) => e is Directory)
        .cast<Directory>()
        .where((d) => path.basename(d.path).startsWith('otzaria_db_backup'))
        .toList();
    if (backups.isEmpty) return;
    Directory? newest;
    if (!await File(path.join(dir, dbName)).exists()) {
      DateTime? newestTime;
      for (final backup in backups) {
        final db = File(path.join(backup.path, dbName));
        if (!await db.exists()) continue;
        final modified = await db.lastModified();
        if (newestTime == null || modified.isAfter(newestTime)) {
          newest = backup;
          newestTime = modified;
        }
      }
    }
    // ההחזרה קודמת למחיקה: אם היא נכשלת (הספרייה על כונן שהוסר) הגיבויים
    // נשארים על הדיסק במקום להימחק בלי שה-DB חזר.
    if (newest != null) await _restoreDatabaseFiles(newest.path, dir);
    for (final backup in backups) {
      if (backup.path == newest?.path) continue;
      // ב-Linux /tmp משותף לכל המשתמשים: גיבוי של משתמש אחר אינו שלנו למחוק,
      // ובלי הדילוג הזה כשל ההרשאה היה מפיל כל עדכון ספרייה.
      try {
        await _discardBackupDir(backup.path);
      } on FileSystemException catch (e) {
        debugPrint(
          '[EmptyLibrary] דילוג על גיבוי שאינו נגיש: ${backup.path} ($e)',
        );
      }
    }
  }

  /// מעביר את seforim.db (ולוואיו) מ-[dir] לתיקיית גיבוי זמנית. מחזיר את נתיב
  /// תיקיית הגיבוי, או null אם אין seforim.db לגבות.
  Future<String?> _backupDatabaseFiles(String dir) async {
    await recoverOrphanedDbBackup(dir);
    final dbFile = File(path.join(dir, DatabaseConstants.databaseFileName));
    if (!await dbFile.exists()) return null;
    final backup = await Directory(dbBackupDirPath).create(recursive: true);
    // גיבוי אטומי: אם הזזת קובץ נכשלת באמצע (seforim.db כבר הוזז אך לוואי לא),
    // מחזירים את מה שכבר הוזז ואז זורקים — אחרת הספרייה נשארת בלי DB ראשי.
    try {
      for (final suffix in _dbFileSuffixes) {
        final f = File('${dbFile.path}$suffix');
        if (await f.exists()) {
          await _moveFile(
            f,
            path.join(
              backup.path,
              '${DatabaseConstants.databaseFileName}$suffix',
            ),
          );
        }
      }
    } catch (_) {
      await _restoreDatabaseFiles(backup.path, dir);
      rethrow;
    }
    return backup.path;
  }

  /// מעביר קובץ אל [destPath]. rename נכשל בין volumes שונים (temp מול הספרייה)
  /// עם Cross-device link — במקרה כזה נופלים להעתקה ומחיקה.
  static Future<void> _moveFile(File file, String destPath) async {
    try {
      await file.rename(destPath);
    } on FileSystemException {
      await file.copy(destPath);
      await file.delete();
    }
  }

  /// עותקים שהבורר יצר במטמון בגרסאות קודמות הכפילו את נפח הספרייה על
  /// המכשיר (issue #1360); נמחקים בסוף כל ייבוא, גם בכשל.
  static Future<void> clearFilePickerCache() async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    try {
      await FilePicker.clearTemporaryFiles();
    } catch (_) {}
  }

  /// משחזר את קבצי ה-DB מתיקיית הגיבוי חזרה אל [dir] (דורס אם קיים).
  static Future<void> _restoreDatabaseFiles(
    String backupDir,
    String dir,
  ) async {
    for (final suffix in _dbFileSuffixes) {
      final name = '${DatabaseConstants.databaseFileName}$suffix';
      final backupFile = File(path.join(backupDir, name));
      if (await backupFile.exists()) {
        final dest = File(path.join(dir, name));
        if (await dest.exists()) await dest.delete();
        await _moveFile(backupFile, dest.path);
      }
    }
    await _discardBackupDir(backupDir);
  }

  static Future<void> _discardBackupDir(String backupDir) async {
    final d = Directory(backupDir);
    if (await d.exists()) await d.delete(recursive: true);
  }

  /// [imported] — הרכיבים שהייבוא התקין; אז המצב הסופי נושא דוח רכיבים.
  Future<void> _handleDirectorySelection(
    String directoryPath,
    Emitter<EmptyLibraryState> emit, {
    Set<LibraryComponent>? imported,
  }) async {
    try {
      final directory = Directory(directoryPath);
      if (!await directory.exists()) {
        emit(
          _error(
            errorMessage: 'התיקייה לא קיימת: $directoryPath',
            selectedPath: directoryPath,
          ),
        );
        return;
      }

      // מחפש את המסד בתיקייה שנבחרה (ללא חיפוש עמוק)
      final dbFilePath = path.join(
        directoryPath,
        DatabaseConstants.databaseFileName,
      );
      final dbFile = File(dbFilePath);

      if (!await dbFile.exists()) {
        emit(
          _error(
            errorMessage:
                'לא נמצא מסד הנתונים ${DatabaseConstants.databaseFileName} בתיקייה שנבחרה.',
            selectedPath: directoryPath,
          ),
        );
        return;
      }

      await Settings.setValue(SettingsRepository.keyLibraryPath, directoryPath);
      await Settings.setValue(SettingsRepository.keyLibraryFolderName, '');
      // נקה override קודם אם קיים
      await Settings.setValue(SettingsRepository.keyDbEffectivePath, '');

      final present = imported == null
          ? null
          : await _presentComponents(directoryPath);
      emit(
        EmptyLibraryDirectorySelected(
          selectedPath: directoryPath,
          importReport: imported == null
              ? null
              : LibraryImportReport(
                  imported: imported,
                  // האינדקס נבנה בתוכנה כשאינו בחבילה, ולכן אינו רכיב חסר.
                  missing: {
                    for (final component in LibraryComponent.values)
                      if (component != LibraryComponent.searchIndex &&
                          !imported.contains(component) &&
                          !present!.contains(component))
                        component,
                  },
                ),
        ),
      );
    } catch (e) {
      emit(
        _error(
          errorMessage: 'שגיאה בבדיקת התיקייה: $e',
          selectedPath: directoryPath,
        ),
      );
    }
  }

  /// בודק שיש מקום להורדה ולחילוץ, לפי הגדלים האמיתיים של [assets] כשהם
  /// ידועים ולפי [measuredLibraryDownload] לפני כן.
  ///
  /// [downloadSize] הוא השטח הנוסף להורדה ולחיבור, בניכוי קבצים למחזור.
  /// מחזיר הודעת שגיאה, או null כשהכול תקין.
  Future<String?> _checkSpaceForDownload({
    int? downloadSize,
    List<_DownloadAsset>? assets,
    String? libraryPath,
  }) async {
    final checker = downloadSpaceChecker;
    if (checker != null) return checker(downloadSize);
    if (!Platform.isAndroid) return null;

    // הספרייה שמורה על כרטיס SD שאינו זמין כרגע — הורדה חדשה תיצור ספרייה
    // כפולה באחסון הפנימי, לכן חוסמים ומסבירים.
    final sdRoot = Settings.getValue<String>(
      SettingsRepository.keyAndroidLibraryRoot,
    );
    if (sdRoot != null &&
        sdRoot.isNotEmpty &&
        !await Directory(sdRoot).exists()) {
      return 'הספרייה שלך שמורה על כרטיס SD שאינו זמין כעת.\n'
          'יש להכניס את הכרטיס ולהפעיל מחדש את האפליקציה.';
    }

    final sizes = <ArchiveSize>[];
    int? largestFile;
    // בלי Content-Length משתמשים בגדלים שנמדדו במקום לספור את הנכס כאפס.
    if (assets == null || assets.any((asset) => asset.compressedSize <= 0)) {
      sizes.addAll(measuredLibraryDownload);
    } else {
      for (final asset in assets) {
        final compressed = asset.compressedSize;
        final contentSize = asset.isCompressed
            ? await _probeArchiveContentSize(asset)
            : compressed;
        final extracted = extractedSizeOf(
          compressed,
          archiveContentSize: contentSize,
          fallbackRatio: _fallbackExpansion(asset),
        );
        sizes.add((compressed: compressed, extracted: extracted));
        if (!asset.isTar && contentSize == extracted) {
          largestFile = math.max(largestFile ?? 0, extracted);
        }
      }
    }
    final downloadNeed =
        downloadSize ?? sizes.fold<int>(0, (sum, s) => sum + s.compressed);

    final target =
        libraryPath ??
        _defaultLibraryPathOverride ??
        await AppPaths.getDefaultLibraryPath();

    if (exceedsFat32FileLimit(largestFile) &&
        !await AndroidStorageService.volumeSupportsLargeFiles(target)) {
      return 'כרטיס ה-SD מפורמט ב-FAT32, שאינו תומך בקבצים מעל 4GB — '
          'וקובץ הספרייה (${formatMegabytesLtr(largestFile!, fractionDigits: 0)}) '
          'גדול מכך.\n'
          'יש לבחור באחסון הפנימי, או לפרמט את הכרטיס ל-exFAT.';
    }

    final tempPath = Directory.systemTemp.path;
    final temp = await getDiskSpaceInfo(tempPath);
    final library = await getDiskSpaceInfo(target);
    final tempVolume = comparableVolumeId(
      tempPath,
      temp.volumeId,
      isAndroid: true,
    );
    final sameVolume =
        tempVolume != null &&
        tempVolume ==
            comparableVolumeId(target, library.volumeId, isAndroid: true);
    // על אותו כונן הארכיונים נמחקים אחד-אחד בזמן החילוץ, ולכן רק השיא נספר.
    return insufficientSpaceMessage([
      if (sameVolume)
        VolumeSpaceNeed(
          label: 'הורדה וחילוץ הספרייה',
          volumeId: library.volumeId,
          requiredBytes: withSafetyMargin(
            downloadNeed + peakExtractionGrowth(sizes),
          ),
          freeBytes: library.freeBytes,
        )
      else ...[
        VolumeSpaceNeed(
          label: 'קבצי ההורדה הזמניים',
          volumeId: null,
          requiredBytes: withSafetyMargin(downloadNeed),
          freeBytes: temp.freeBytes,
        ),
        VolumeSpaceNeed(
          label: 'תיקיית הספרייה',
          volumeId: null,
          requiredBytes: withSafetyMargin(
            sizes.fold<int>(0, (sum, s) => sum + s.extracted),
          ),
          freeBytes: library.freeBytes,
        ),
      ],
    ]);
  }

  static double _fallbackExpansion(_DownloadAsset asset) {
    if (asset.isTar) return ExpansionFallback.pdfArchive;
    if (asset.outputFileName ==
        DatabaseConstants.externalCatalogDatabaseFileName) {
      return ExpansionFallback.catalog;
    }
    return ExpansionFallback.database;
  }

  /// גודל מלא מוכח רק לארכיון קטן שאינו מפוצל; הגדולים נשארים אומדן.
  Future<int?> _probeArchiveContentSize(_DownloadAsset asset) async {
    if (asset.split != null ||
        asset.compressedSize <= 0 ||
        asset.compressedSize > zstdSizeProbeMaxBytes) {
      return null;
    }
    final url = asset.resolvedUrl;
    if (url == null) return null;
    try {
      final request = http.Request('GET', Uri.parse(url))
        ..headers['Range'] = 'bytes=0-${asset.compressedSize - 1}';
      final response = await _httpClient
          .send(request)
          .timeout(downloadConnectTimeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        await response.stream.listen((_) {}).cancel();
        return null;
      }
      return await readZstdArchiveContentSize(
        response.stream,
        compressedSize: asset.compressedSize,
      ).timeout(downloadConnectTimeout);
    } catch (_) {
      return null;
    }
  }

  Future<void> _onCheckDiskSpaceRequested(
    CheckDiskSpaceRequested event,
    Emitter<EmptyLibraryState> emit,
  ) async {
    _downloadDisabledReason = await _checkSpaceForDownload();
    emit(EmptyLibraryInitial(downloadDisabledReason: _downloadDisabledReason));
  }

  /// שומר את מיקום האחסון שנבחר ומריץ מחדש את בדיקת המקום הפנוי עבור היעד
  /// החדש (הורדה וחילוץ ינותבו לשם דרך getDefaultLibraryPath).
  Future<void> _onStorageLocationSelected(
    StorageLocationSelected event,
    Emitter<EmptyLibraryState> emit,
  ) async {
    await AppPaths.setAndroidLibraryRoot(event.libraryRoot);
    _downloadDisabledReason = await _checkSpaceForDownload();
    emit(EmptyLibraryInitial(downloadDisabledReason: _downloadDisabledReason));
  }

  /// מייצר EmptyLibraryError תמיד עם downloadDisabledReason הנוכחי.
  EmptyLibraryError _error({String? errorMessage, String? selectedPath}) =>
      EmptyLibraryError(
        errorMessage: errorMessage,
        selectedPath: selectedPath,
        downloadDisabledReason: _downloadDisabledReason,
      );

  Future<void> _onDownloadLibraryRequested(
    DownloadLibraryRequested event,
    Emitter<EmptyLibraryState> emit,
  ) async {
    try {
      final libraryPath =
          event.targetPath ??
          _defaultLibraryPathOverride ??
          await AppPaths.getDefaultLibraryPath();
      await _downloadLibrary(libraryPath, emit);
    } catch (e) {
      // קבצי ה-temp נשמרים בכוונה — ישמשו ל-resume בניסיון הבא
      emit(
        EmptyLibraryError(
          errorMessage:
              'שגיאה בהורדה: $e\nניתן ללחוץ שוב כדי להמשיך מהנקודה שנעצרה.',
        ),
      );
    }
  }

  /// מוריד ומחלץ את חבילת הספרייה המלאה אל [libraryPath]. זורק בכשל אמיתי;
  /// כשל מקום פנוי פולט שגיאה ומחזיר בלי DirectorySelected (לבדיקת המצב אצל הקורא).
  Future<void> _downloadLibrary(
    String libraryPath,
    Emitter<EmptyLibraryState> emit,
  ) async {
    {
      final latestAsset = await _fetchLatestDatabaseAsset();

      // ה-release האחרון של otzaria-library לא תמיד מכיל את התלמוד (יש בו גם
      // releases של fordb) — מאתרים דרך ה-API, עם fallback לכתובת ה-latest.
      TalmudRelease? talmudRelease;
      var talmudAssetMissing = false;
      try {
        talmudRelease = await CompanionAssetsService.findLatestTalmudRelease(
          _httpClient,
        );
      } on TalmudAssetNotFoundException catch (e) {
        // הנכס אינו קיים באף release — גם כתובת ה-latest לא תכיל אותו; מדלגים,
        // ובדיקת העדכון תתקין את התלמוד כשיפורסם מחדש.
        debugPrint('$e');
        talmudAssetMissing = true;
      } catch (e) {
        debugPrint('איתור release של התלמוד נכשל: $e');
      }

      // ה-API מוסר את הנכס המועדף ואת ה-digest שלו; בכשל — כתובת ה-latest.
      MagicDictionaryRelease? lexicalRelease;
      try {
        lexicalRelease = await MagicDictionaryDownloader(
          client: _httpClient,
        ).fetchLatestRelease();
      } catch (e) {
        debugPrint('איתור release של המילון נכשל: $e');
      }

      // שלושת הקבצים מורדים יחד ואז מחולצים יחד. פס ההתקדמות בשני השלבים
      // מתייחס לסכום שלושתם; רק כותרת המשנה משתנה לפי הקובץ הנוכחי.
      final assets = <_DownloadAsset>[
        _DownloadAsset(
          url: latestAsset.downloadUrl,
          tempFileName: 'otzaria_${latestAsset.assetName}',
          downloadTitle: 'מוריד את ספריית אוצריא',
          extractTitle: 'מחלץ את ספריית אוצריא',
          isTar: false,
          outputFileName: DatabaseConstants.databaseFileName,
          isMainDb: true,
          split: latestAsset.split,
        ),
        _DownloadAsset(
          url:
              talmudRelease?.assetUrl ??
              'https://github.com/Otzaria/otzaria-library/releases/latest/download/talmud_bavli_latest.tar.zst',
          tempFileName: 'otzaria_talmud_bavli.tar.zst',
          downloadTitle: 'מוריד את התלמוד הבבלי',
          extractTitle: 'מחלץ את התלמוד הבבלי',
          isTar: true,
          sha256: talmudRelease?.sha256,
        )..skipped = talmudAssetMissing,
        _DownloadAsset(
          url:
              'https://github.com/Otzaria/otzar-HB_catalog/releases/latest/download/otzar-HB_catalog.db.zst',
          tempFileName: 'otzaria_otzar-HB_catalog.db.zst',
          downloadTitle: 'מוריד את הקטלוגים',
          extractTitle: 'מחלץ את הקטלוגים',
          isTar: false,
          outputFileName: DatabaseConstants.externalCatalogDatabaseFileName,
        ),
        // מילון החיפוש המקורב — אינו דחוס ו-best-effort: כשל אינו חוסם כניסה
        // לספרייה (החיפוש המקורב יפעל ללא הרחבה מורפולוגית).
        _DownloadAsset(
          url:
              lexicalRelease?.downloadUrl.toString() ??
              'https://github.com/Otzaria/SeforimMagicIndexer/releases/latest/download/${DatabaseConstants.lexicalReleaseAssetFileNames.first}',
          tempFileName: 'otzaria_lexical.db',
          downloadTitle: 'מוריד מילון לחיפוש המקורב',
          extractTitle: 'מתקין מילון לחיפוש המקורב',
          isTar: false,
          outputFileName: DatabaseConstants.lexicalDatabaseFileName,
          isCompressed: false,
          optional: true,
          sha256: lexicalRelease?.sha256,
        ),
      ];

      emit(
        const EmptyLibraryDownloading(progress: 0.0, message: 'מתחבר לשרת...'),
      );

      // פתרון redirect-ים מראש (package:http מאבד את ה-Range בעת redirect) +
      // קריאת גודל כל קובץ דחוס, לחישוב פס התקדמות וזמן משוער מאוחדים.
      for (final asset in assets) {
        if (asset.skipped) continue;
        final split = asset.split;
        if (split != null) {
          // גודל וזהות של נכס מפוצל באים מהמניפסט; לכל חלק כתובת משלו.
          asset.compressedSize = split.size;
          asset.identity = 'split|${split.sha256}';
          continue;
        }
        try {
          final resolved = await _resolveRedirectWithSize(asset.url);
          asset.resolvedUrl = resolved.url;
          asset.compressedSize = resolved.size;
          asset.identity = resolved.identity;
          asset.releaseTag = resolved.releaseTag;
        } catch (e) {
          if (!asset.optional) rethrow;
          debugPrint('פתרון כתובת ${asset.tempFileName} (אופציונלי) נכשל: $e');
          asset.skipped = true;
        }
      }
      final grandTotal = assets.fold<int>(
        0,
        (sum, a) => sum + a.compressedSize,
      );

      // כולל שטח חיבור לחלקים, בניכוי ההורדות שניתן להמשיך מהן.
      var downloadNeeded = 0;
      for (final asset in assets.where((asset) => !asset.skipped)) {
        downloadNeeded += await additionalDownloadBytes(
          destPath: path.join(Directory.systemTemp.path, asset.tempFileName),
          identity: asset.identity!,
          size: asset.compressedSize,
          split: asset.split,
        );
      }
      final spaceError = await _checkSpaceForDownload(
        downloadSize: grandTotal > 0 ? downloadNeeded : null,
        assets: assets.where((asset) => !asset.skipped).toList(),
        libraryPath: libraryPath,
      );
      if (spaceError != null) {
        _downloadDisabledReason = spaceError;
        emit(_error(errorMessage: spaceError));
        return;
      }

      // יצירת תיקיית הספרייה אם לא קיימת
      final libraryDir = Directory(libraryPath);
      if (!await libraryDir.exists()) {
        await libraryDir.create(recursive: true);
      }

      // שלב 1 — הורדת כל הקבצים יחד (פס וזמן משוער מאוחדים)
      final etaEstimator = DownloadEtaEstimator();
      var downloadedBase = 0;
      for (final asset in assets) {
        if (!asset.skipped) {
          try {
            await _downloadAsset(
              asset: asset,
              cumulativeBase: downloadedBase,
              grandTotal: grandTotal,
              estimator: etaEstimator,
              emit: emit,
            );
          } catch (e) {
            if (!asset.optional) rethrow;
            debugPrint('הורדת ${asset.tempFileName} (אופציונלי) נכשלה: $e');
            asset.skipped = true;
          }
        }
        downloadedBase += asset.compressedSize;
        // נכס אופציונלי שדולג/נכשל לא פלט את המשקל שלו — משלימים את הפס כדי
        // שלא ייתקע מתחת ל-100% לפני המעבר לחילוץ (best-effort: שקוף למשתמש).
        if (asset.skipped && grandTotal > 0) {
          emit(
            EmptyLibraryDownloading(
              progress: (downloadedBase / grandTotal).clamp(0.0, 1.0),
              message: asset.downloadTitle,
            ),
          );
        }
      }

      // שלב 2 — חילוץ כל הקבצים יחד (פס מאוחד, משוקלל לפי הגודל הדחוס)
      var extractBase = 0;
      for (final asset in assets) {
        if (!asset.skipped) {
          try {
            await _extractAsset(
              asset: asset,
              weightBase: extractBase,
              totalWeight: grandTotal,
              outputDir: libraryPath,
              emit: emit,
            );
          } catch (e) {
            if (!asset.optional) rethrow;
            debugPrint('חילוץ ${asset.tempFileName} (אופציונלי) נכשל: $e');
            asset.skipped = true;
          }
        }
        extractBase += asset.compressedSize;
      }

      emit(
        const EmptyLibraryExtracting(
          selectedPath: '',
          progress: 1.0,
          message: 'החילוץ הושלם',
        ),
      );

      await Settings.setValue(SettingsRepository.keyLibraryPath, libraryPath);
      await Settings.setValue(SettingsRepository.keyLibraryFolderName, '');
      // ניקוי override Android — ה-DB החדש נמצא ישירות בספרייה
      await Settings.setValue(SettingsRepository.keyDbEffectivePath, '');

      emit(EmptyLibraryDirectorySelected(selectedPath: libraryPath));
    }
  }

  /// מוריד קובץ דחוס יחיד (עם resume) ומדווח התקדמות מאוחדת על פני כל
  /// הקבצים: [cumulativeBase] = סכום הגדלים הדחוסים של הקבצים שכבר הורדו
  /// במלואם, [grandTotal] = סך הגדלים הדחוסים של כל הקבצים.
  Future<void> _downloadAsset({
    required _DownloadAsset asset,
    required int cumulativeBase,
    required int grandTotal,
    required DownloadEtaEstimator estimator,
    required Emitter<EmptyLibraryState> emit,
  }) async {
    final tempPath = path.join(Directory.systemTemp.path, asset.tempFileName);
    final tempFile = File(tempPath);
    final identity =
        asset.identity ?? '${asset.resolvedUrl}|${asset.compressedSize}';

    // הבייטים שהיו כבר על הדיסק כשההורדה חודשה (0 = הורדה חדשה). נקבע סופית
    // אחרי טיפול בקוד התגובה, ומשמש להצגת חיווי "ממשיך הורדה".
    var resumeFromBytes = await _reusableDownloadOffset(
      tempFile,
      identity,
      asset.compressedSize,
    );

    // מדווח התקדמות מאוחדת לפי הבייטים שהורדו עד כה בקובץ הנוכחי.
    void emitProgress(int downloadedBytes) {
      if (grandTotal <= 0) {
        emit(
          EmptyLibraryDownloading(progress: 0.0, message: asset.downloadTitle),
        );
        return;
      }
      final cumulative = cumulativeBase + downloadedBytes;
      final eta = estimator.update(
        downloadedBytes: cumulative,
        totalBytes: grandTotal,
        now: DateTime.now(),
      );
      final etaLine = eta != null ? '\n${formatRemainingTimeHebrew(eta)}' : '';
      final resumeLine = resumeFromBytes > 0
          ? '\nממשיך הורדה מ-${formatMegabytesLtr(resumeFromBytes)}'
          : '';
      emit(
        EmptyLibraryDownloading(
          progress: (cumulative / grandTotal).clamp(0.0, 1.0),
          message:
              '${asset.downloadTitle}$resumeLine\n'
              '${formatMegabytesProgressHebrew(cumulative, grandTotal)}$etaLine',
        ),
      );
    }

    // מנקה sidecar מהפורמט המקומי הישן. מכאן ואילך PatchDownloader מנהל
    // Range/If-Range, אימות 206/416, גודל, timeout וסגירת משאבים במקום אחד.
    await deleteDownloadSidecar(tempPath);
    final downloader = PatchDownloader(
      decompress: (_) async => null,
      httpClient: _httpClient,
      connectTimeout: downloadConnectTimeout,
      stallTimeout: _downloadStallTimeout,
    );
    final split = asset.split;
    if (split != null) {
      await downloader.downloadSplitToFile(
        split: split,
        destPath: tempPath,
        resumeToken: identity,
        onProgress: (downloaded, _) => emitProgress(downloaded),
      );
      return;
    }
    await downloader.downloadToFile(
      url: asset.resolvedUrl!,
      destPath: tempPath,
      expectedSize: asset.compressedSize > 0 ? asset.compressedSize : null,
      expectedSha256: asset.sha256,
      resumeToken: identity,
      onProgress: (downloaded, _) => emitProgress(downloaded),
    );
  }

  Future<int> _reusableDownloadOffset(
    File file,
    String identity,
    int expectedSize,
  ) async {
    return reusableDownloadBytes(file.path, identity, expectedSize);
  }

  Future<void> _deleteDownloadState(String tempPath) async {
    // אם מחיקת הארכיון נכשלה, שומרים את ה-sidecar: בלעדיו הניסיון הבא עלול
    // למחוק הורדה שלמה/חלקית תקינה או לחדש אותה ללא ולידטור.
    if (await File(tempPath).exists()) return;
    await deleteDownloadSidecar(tempPath); // פורמט .meta הישן
    final resume = File(PatchDownloader.resumeSidecarPath(tempPath));
    await resume.delete().catchError((_) => resume);
  }

  /// מחלץ קובץ דחוס יחיד ומדווח התקדמות מאוחדת, משוקללת לפי הגודל הדחוס
  /// ([weightBase] = סכום הגדלים של הקבצים שכבר חולצו, [totalWeight] = סך
  /// הכול). החילוץ מדווח לפי בייטים דחוסים שנקראו, ולכן שקלול לפי הגודל
  /// הדחוס נותן פס התקדמות לינארי ומדויק על פני שלושת הקבצים.
  Future<void> _extractAsset({
    required _DownloadAsset asset,
    required int weightBase,
    required int totalWeight,
    required String outputDir,
    required Emitter<EmptyLibraryState> emit,
  }) async {
    final tempPath = path.join(Directory.systemTemp.path, asset.tempFileName);

    void report(double assetProgress) {
      final combined = totalWeight > 0
          ? ((weightBase + asset.compressedSize * assetProgress) / totalWeight)
                .clamp(0.0, 1.0)
          : assetProgress;
      emit(
        EmptyLibraryExtracting(
          selectedPath: tempPath,
          progress: combined,
          message: asset.extractTitle,
        ),
      );
    }

    report(0.0);

    try {
      if (asset.isTar) {
        await _extractTarArchive(tempPath, outputDir, report);
        // עדיף digest: תגי otzaria-library מתחלפים כמעט יומית גם כשהתוכן זהה.
        await _writeTalmudVersionMarker(
          outputDir,
          asset.sha256 ?? asset.releaseTag,
        );
      } else if (!asset.isCompressed) {
        // קובץ לא דחוס (lexical.db) — מועתק מ-temp ליעד ללא חילוץ.
        final outputPath = path.join(outputDir, asset.outputFileName!);
        await File(tempPath).copy(outputPath);
        // בלי סימון גרסה, בדיקת העדכון הבאה תוריד את המילון מחדש בכל הפעלה.
        final version = asset.sha256 ?? asset.releaseTag;
        if (asset.outputFileName == DatabaseConstants.lexicalDatabaseFileName) {
          if (version != null) {
            await MagicDictionaryDownloader.writeVersionMarker(
              outputPath,
              version,
            );
          } else {
            await MagicDictionaryDownloader.writeFileDigestMarker(outputPath);
          }
        }
        report(1.0);
      } else {
        final outputPath = path.join(outputDir, asset.outputFileName!);

        if (asset.isMainDb) {
          // הסגירה משחררת את ה-handle של seforim.db לפני מחיקתו והחלפתו;
          // מחיקת shm/wal (בתוך ההעברה האטומית) מונעת מ-SQLite לקרוא WAL ישן.
          await SqliteDataProvider.instance.dispose();
          await _writeDbAtomically(
            outputPath,
            (dbTempPath) =>
                _extractCompressedDatabase(tempPath, dbTempPath, report),
          );
        } else {
          await _extractCompressedDatabase(tempPath, outputPath, report);
        }
      }
    } on FileSystemException {
      // כשל כתיבה ביעד (הרשאה, מקום) אינו ארכיון פגום — שומרים לניסיון חוזר.
      rethrow;
    } catch (_) {
      // חילוץ שנכשל על קובץ שלם (פגום/franken) משאיר temp שיגרום לדילוג על
      // ההורדה בניסיון הבא ולולאה אינסופית — מוחקים כדי לכפות הורדה מחדש.
      await File(tempPath).delete().catchError((_) => File(tempPath));
      await _deleteDownloadState(tempPath);
      rethrow;
    }

    // מחיקת קובץ ה-temp לאחר חילוץ מוצלח.
    await File(tempPath).delete().catchError((_) => File(tempPath));
    await _deleteDownloadState(tempPath);
  }

  /// כותב את זיהוי הגרסה (digest או תג) לתיקיית התלמוד שחולצה. בלי הסימון,
  /// בדיקת העדכון הבאה מחתימה את הזיהוי העדכני גם על התקנה ישנה — והעדכון ידולג.
  /// כשל כתיבה מכשיל את החילוץ בכוונה — הצלחה שקטה בלי סימון מחזירה את הבאג.
  static Future<void> _writeTalmudVersionMarker(
    String outputDir,
    String? versionStamp,
  ) async {
    if (versionStamp == null) return;
    final talmudDir = path.join(
      outputDir,
      DatabaseConstants.talmudBavliFolderName,
    );
    // אין ליצור את התיקייה: תיקייה עם סימון בלבד תיראה כהתקנה קיימת ומעודכנת.
    if (!await Directory(talmudDir).exists()) return;
    await File(
      DatabaseConstants.talmudBavliVersionFilePath(talmudDir),
    ).writeAsString(versionStamp);
  }

  /// חילוץ `.zst` יחיד (ל-DB) דרך השירות המשותף. עוטף כדי להתאים לחתימת
  /// ה-positional של [_extractCompressedDatabase].
  static Future<void> _extractZst(
    String archivePath,
    String outputPath,
    void Function(double progress)? onProgress,
  ) => ZstdStreamExtractor.extractToFile(
    archivePath,
    outputPath,
    onProgress: onProgress,
  );

  static Future<void> _extractTarZst(
    String archivePath,
    String outputDir,
    void Function(double progress)? onProgress,
  ) => extractTarZstToDir(archivePath, outputDir, onProgress: onProgress);

  /// עוקב אחרי redirects ידנית ומחזיר את ה-URL הסופי, גודל הקובץ
  /// (Content-Length) ו-[identity] המקשר שריד temp לגרסה המרוחקת. נדרש כי
  /// package:http מאבד את ה-Range header בעת redirect; הגודל משמש לפס התקדמות
  /// וזמן משוער מאוחדים. [identity] = `<etag>|<size>` (fallback: last-modified,
  /// ואז ה-URL הסופי). מחזיר size=0 אם השרת לא סיפק Content-Length, ואת תג
  /// ה-release אם הופיע באחד מנתיבי ה-redirect.
  Future<({String url, int size, String identity, String? releaseTag})>
  _resolveRedirectWithSize(String url) async {
    var current = Uri.parse(url);
    String? releaseTag;
    const maxRedirects = 5;
    for (var i = 0; i <= maxRedirects; i++) {
      releaseTag = releaseTagFromUrl(current.path) ?? releaseTag;
      final request = http.Request('HEAD', current)..followRedirects = false;
      final response = await _httpClient
          .send(request)
          .timeout(downloadConnectTimeout);
      if (response.statusCode >= 300 && response.statusCode < 400) {
        final location = response.headers['location'];
        try {
          await response.stream.listen((_) {}).cancel();
        } catch (_) {}
        if (location == null || location.isEmpty) {
          throw Exception('redirect ללא Location: $current');
        }
        // תמיכה ב-Location יחסי
        current = current.resolve(location);
        continue;
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        try {
          await response.stream.listen((_) {}).cancel();
        } catch (_) {}
        throw Exception('HEAD נכשל (${response.statusCode}): $current');
      }
      final size = response.contentLength ?? 0;
      final tag =
          response.headers['etag'] ??
          response.headers['last-modified'] ??
          current.toString();
      try {
        await response.stream.listen((_) {}).cancel();
      } catch (_) {}
      return (
        url: current.toString(),
        size: size,
        identity: '$tag|$size',
        releaseTag: releaseTag,
      );
    }
    throw Exception('יותר מדי redirects: $url');
  }

  /// מחלץ את תג ה-release מתוך נתיב הורדה של GitHub — שרשרת ה-redirect של
  /// `releases/latest/download` עוברת דרך `releases/download/<tag>/<file>`.
  @visibleForTesting
  static String? releaseTagFromUrl(String urlPath) {
    return RegExp(r'/releases/download/([^/]+)/').firstMatch(urlPath)?.group(1);
  }

  Future<DatabaseReleaseAsset> _fetchLatestDatabaseAsset() async {
    final response = await _httpClient
        .get(
          Uri.parse(
            'https://api.github.com/repos/Otzaria/SeforimLibrary/releases/latest',
          ),
          headers: const {
            'Accept': 'application/vnd.github+json',
            'X-GitHub-Api-Version': '2022-11-28',
          },
        )
        .timeout(downloadConnectTimeout);

    if (response.statusCode != 200) {
      throw Exception('שגיאה בקבלת הרליס האחרון: ${response.statusCode}');
    }

    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map<String, dynamic>) {
      throw Exception('מבנה תשובת GitHub אינו תקין');
    }

    final asset = parseLatestDatabaseAsset(decoded);
    if (asset == null) {
      throw Exception(
        'לא נמצאה ספרייה שאפשר להוריד. נסו לעדכן את התוכנה לגרסה האחרונה ולנסות שוב',
      );
    }
    if (!asset.isSplitManifest) return asset;

    final release = LibraryRelease.fromJson(decoded);
    final resolved =
        await GithubLibraryReleaseClient(
          httpClient: _httpClient,
          timeout: downloadConnectTimeout,
        ).resolveSplitAsset(
          release,
          release.assetByName('${asset.assetName}$kSplitManifestSuffix')!,
        );
    return DatabaseReleaseAsset(
      assetName: asset.assetName,
      downloadUrl: asset.downloadUrl,
      split: resolved.split,
    );
  }

  @visibleForTesting
  /// מחלץ מתוך JSON של רליס את קובץ ה-DB הדחוס של הספרייה.
  static DatabaseReleaseAsset? parseLatestDatabaseAsset(
    Map<String, dynamic> releaseJson,
  ) {
    final assets = releaseJson['assets'];
    if (assets is! List) {
      return null;
    }

    final urlsByName = <String, String>{};
    for (final asset in assets) {
      if (asset is! Map<String, dynamic>) {
        continue;
      }

      final name = asset['name']?.toString() ?? '';
      final downloadUrl = asset['browser_download_url']?.toString() ?? '';
      if (downloadUrl.isNotEmpty) urlsByName[name] = downloadUrl;
    }

    // הסכמה הגבוהה ביותר שהגרסה הזו קוראת; ארכיון בסכמה חדשה יותר מדולג.
    // DB מעל מגבלת GitHub מתפרסם כחלקים ומניפסט; קובץ יחיד גובר באותה סכמה.
    for (final name in DatabaseConstants.supportedDatabaseArchiveFileNames) {
      final downloadUrl = urlsByName[name];
      if (downloadUrl != null) {
        return DatabaseReleaseAsset(assetName: name, downloadUrl: downloadUrl);
      }
      final manifestUrl = urlsByName['$name$kSplitManifestSuffix'];
      if (manifestUrl != null) {
        return DatabaseReleaseAsset(
          assetName: name,
          downloadUrl: manifestUrl,
          isSplitManifest: true,
        );
      }
    }

    return null;
  }

  @override
  Future<void> close() {
    HttpClientRegistry.unregister(_httpClient.close);
    _httpClient.close();
    return super.close();
  }
}

/// מתאר קובץ דחוס יחיד בחבילת ההורדה הראשונית (ספרייה / תלמוד / קטלוגים).
/// שלושת הקבצים מורדים יחד ואז מחולצים יחד, עם פס התקדמות מאוחד.
class _DownloadAsset {
  _DownloadAsset({
    required this.url,
    required this.tempFileName,
    required this.downloadTitle,
    required this.extractTitle,
    required this.isTar,
    this.outputFileName,
    this.isMainDb = false,
    this.isCompressed = true,
    this.optional = false,
    this.sha256,
    this.split,
  });

  /// כתובת ההורדה (לפני פתרון redirect).
  final String url;

  /// שם קובץ ה-temp הקבוע (נשמר בין ניסיונות לצורך resume).
  final String tempFileName;

  /// כותרת המשנה המוצגת בזמן ההורדה.
  final String downloadTitle;

  /// כותרת המשנה המוצגת בזמן החילוץ.
  final String extractTitle;

  /// `true` → tar.zst שמחולץ לתיקיית היעד. `false` → .zst לקובץ יחיד.
  final bool isTar;

  /// שם קובץ היעד לחילוץ (נדרש כש-[isTar] = false).
  final String? outputFileName;

  /// האם זהו seforim.db הראשי — דורש סגירת SqliteDataProvider ומחיקת
  /// קבצי WAL/SHM ישנים לפני החילוץ.
  final bool isMainDb;

  /// `false` → הקובץ אינו דחוס (lexical.db); בשלב החילוץ הוא רק מועתק ליעד.
  final bool isCompressed;

  /// `true` → best-effort: כשל בהורדה/חילוץ אינו מפיל את כל התהליך.
  final bool optional;

  /// sha256 של הנכס מה-API — לאימות ההורדה ולסימון גרסת התלמוד והמילון.
  final String? sha256;

  /// החלקים כשהנכס מפוצל; אז הם מורדים ומחוברים אל קובץ ה-temp.
  final SplitAsset? split;

  /// ה-URL הסופי לאחר פתרון redirect (נקבע בזמן ריצה).
  String? resolvedUrl;

  /// גודל הקובץ הדחוס בבייטים (נקבע בזמן ריצה מ-Content-Length).
  int compressedSize = 0;

  /// מזהה גרסת הקובץ המרוחק (`<etag>|<size>`), לקישור שריד ה-temp לגרסה.
  String? identity;

  /// תג ה-release שחולץ משרשרת ה-redirect — לכתיבת סימון גרסת המילון.
  String? releaseTag;

  /// סומן לדילוג לאחר כשל best-effort (resolve/download) — מונע ניסיון חילוץ.
  bool skipped = false;
}

/// מייצג asset של DB דחוס מתוך GitHub Release.
class DatabaseReleaseAsset {
  const DatabaseReleaseAsset({
    required this.assetName,
    required this.downloadUrl,
    this.isSplitManifest = false,
    this.split,
  });

  final String assetName;

  /// כתובת הקובץ, או כתובת מניפסט הפיצול כשה-DB מפוצל.
  final String downloadUrl;

  /// [downloadUrl] היא מניפסט פיצול שעוד לא פוענח ל-[split].
  final bool isSplitManifest;

  /// החלקים, כשה-DB מתפרסם בחלקים מתחת למגבלת GitHub.
  final SplitAsset? split;
}

/// ה-DB שנבחר חדש מהסכמה שהגרסה הזו קוראת.
class UnsupportedDbSchemaException implements Exception {
  final int schemaVersion;
  final int readableSchemaVersion;

  const UnsupportedDbSchemaException(
    this.schemaVersion,
    this.readableSchemaVersion,
  );

  @override
  String toString() =>
      'ספריית הספרים בסכמה $schemaVersion, חדשה מזו שהגרסה הזו קוראת '
      '($readableSchemaVersion) — נדרש עדכון של התוכנה';
}
