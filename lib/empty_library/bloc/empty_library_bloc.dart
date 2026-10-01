import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'package:bloc/bloc.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:file_picker/file_picker.dart';
import 'package:otzaria/utils/text/byte_size_text.dart';
import 'package:otzaria/utils/file/file_picker_dialog_options.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/core/http_client_registry.dart';
import 'package:otzaria/core/messages/library_messages.dart';
import 'package:otzaria/data/constants/database_constants.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:otzaria/data/sqlite/library_vfs.dart';
import 'package:otzaria/empty_library/bloc/empty_library_event.dart';
import 'package:otzaria/empty_library/bloc/empty_library_state.dart';
import 'package:otzaria/empty_library/services/android_storage_service.dart';
import 'package:otzaria/library_update/services/companion_assets_service.dart';
import 'package:otzaria/library_update/services/library_access_gate.dart';
import 'package:otzaria/library_update/services/library_zdb_install.dart';
import 'package:otzaria/search/magic_dictionary_downloader.dart';
import 'package:otzaria/settings/settings_exports.dart';
import 'package:otzaria/utils/download_eta_estimator.dart';
import 'package:otzaria/utils/download_sidecar.dart';
import 'package:otzaria/utils/file/archive_extractor.dart';
import 'package:otzaria/utils/file/tar_zst_extractor.dart';
import 'package:otzaria/utils/move_directory.dart';
import 'package:otzaria/utils/file/zstd_stream_extractor.dart';
import 'package:path/path.dart' as path;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
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
    Future<void> Function(String archivePath, String outputDir)?
    extractZipArchive,
    this._defaultLibraryPathOverride,
    this.downloadConnectTimeout = _defaultDownloadConnectTimeout,
    LibraryAccessGate? accessGate,
  }) : _httpClient = httpClient ?? http.Client(),
       _accessGate = accessGate ?? _defaultAccessGate(),
       _extractCompressedDatabase = extractCompressedDatabase ?? _extractZst,
       _extractTarArchive = extractTarArchive ?? _extractTarZst,
       _extractZipArchive = extractZipArchive ?? extractArchiveFileToDisk,
       super(
         const EmptyLibraryInitial(downloadDisabledReason: 'בודק מקום פנוי...'),
       ) {
    HttpClientRegistry.register(_httpClient.close);
    on<PickDirectoryRequested>(_onPickDirectoryRequested);
    on<UseLibraryInPlaceRequested>(_onUseLibraryInPlaceRequested);
    on<DownloadLibraryRequested>(_onDownloadLibraryRequested);
    on<ImportLibraryFolderRequested>(_onImportLibraryFolderRequested);
    on<ImportLibraryArchiveRequested>(_onImportLibraryArchiveRequested);
    on<UpdateLibraryRequested>(_onUpdateLibraryRequested);
    on<PickDbFileRequested>(_onPickDbFileRequested);
    on<CheckDiskSpaceRequested>(_onCheckDiskSpaceRequested);
    on<StorageLocationSelected>(_onStorageLocationSelected);
    // בדיקת מקום פנוי מתבצעת מיד — כפתור ההורדה מושבת עד להשלמתה
    add(CheckDiskSpaceRequested());
  }

  final http.Client _httpClient;
  final Duration downloadConnectTimeout;

  /// סוגר את הספרייה בכל החלונות לפני שמחליפים את קובץ המסד.
  final LibraryAccessGate _accessGate;

  // המסך הזה מחליף ספרייה; ה-UI פותח אותה מחדש אחרי DirectorySelected.
  static LibraryAccessGate _defaultAccessGate() => LibraryAccessGate(
    selfAccess: LibraryAccessRoutine(
      suspend: () => SqliteDataProvider.instance.closeForExternalWrite(),
      resume: (_) => SqliteDataProvider.instance.reopenAfterExternalWrite(
        reopenDatabase: false,
      ),
    ),
  );

  /// מריץ [body] כשהספרייה ב-[libraryDir] סגורה בכל החלונות; בלי ספרייה
  /// קיימת — מיד. כשל ההשעיה עצמה מוצג כשגיאה ([body] מטפל בשלו).
  Future<void> _withLibraryReleased(
    String? libraryDir,
    Emitter<EmptyLibraryState> emit,
    Future<void> Function() body,
  ) async {
    if (libraryDir == null) return body();
    try {
      await _accessGate.runExclusive(
        dbPath: DatabaseConstants.resolveLibraryDbPath(libraryDir),
        body: (scope) async {
          // שאר החלונות טוענים את הספרייה מחדש גם אם הפעולה שוחזרה.
          scope.markDbReplaced();
          await body();
        },
      );
    } on LibrarySuspendFailed catch (e) {
      emit(_error(errorMessage: e.message));
    } on LibraryStillOpenException catch (e) {
      emit(_error(errorMessage: 'הספרייה עדיין פתוחה: $e'));
    }
  }

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
  final Future<void> Function(String archivePath, String outputDir)
  _extractZipArchive;

  /// בונה callback שמ-emit-ת התקדמות חילוץ למסך.
  /// הקריאות מגיעות מתוך ה-isolet בזמן ה-await על פעולת החילוץ — עדיין
  /// בתוך מטפל האירוע — ולכן ה-emit חוקי.
  void Function(double) _extractProgress(
    Emitter<EmptyLibraryState> emit,
    String selectedPath,
    String message,
  ) =>
      (progress) => emit(
        EmptyLibraryExtracting(
          selectedPath: selectedPath,
          progress: progress,
          message: message,
        ),
      );
  // סיבת השבתת כפתור ההורדה — נשמרת כ-instance field כדי להישמר בין state transitions
  String? _downloadDisabledReason = 'בודק מקום פנוי...';
  final String? _defaultLibraryPathOverride;

  // [בדיקת אנדרואיד] לא נגיש מ-UI כרגע (PickDirectoryRequested לא משוגר). מפעיל
  // את זרימת בחירת התיקייה + SAF — לאמת על מכשיר לפני חיבור מחדש או מחיקה.
  Future<void> _onPickDirectoryRequested(
    PickDirectoryRequested event,
    Emitter<EmptyLibraryState> emit,
  ) async {
    final result = await FilePicker.getDirectoryPath(
      dialogTitle: 'בחר את תיקיית הספרייה (התיקייה שמכילה את seforim.db)',
      windowsOptions: kModalWindowsOptions,
      linuxOptions: kModalLinuxOptions,
    );

    if (result == null) return;

    emit(EmptyLibraryLoading(selectedPath: result));
    await _handleDirectorySelection(result, emit);
  }

  /// מצביע על ספרייה קיימת בלי להעתיק דבר — מאמת שיש seforim.db בתיקייה
  /// ושומר אותה כנתיב הספרייה.
  Future<void> _onUseLibraryInPlaceRequested(
    UseLibraryInPlaceRequested event,
    Emitter<EmptyLibraryState> emit,
  ) async {
    emit(EmptyLibraryLoading(selectedPath: event.folderPath));
    await _handleDirectorySelection(event.folderPath, emit);
  }

  /// מייבא נכסי ספרייה מתיקייה שנבחרה: מזהה כל נכס (seforim.db, קטלוג, מילון,
  /// תלמוד) בגרסה דחוסה או רגילה, ומחלץ/מעתיק אותו אל היעד. אם [backupExistingPath]
  /// מסופק (עדכון במקום) — ה-DB הישן מגובה ומשוחזר בכישלון.
  Future<void> _onImportLibraryFolderRequested(
    ImportLibraryFolderRequested event,
    Emitter<EmptyLibraryState> emit,
  ) async {
    final backupPath = event.backupExistingPath;
    await _withLibraryReleased(backupPath, emit, () async {
      String? backupDir;
      try {
        if (backupPath != null) {
          backupDir = await _backupDatabaseFiles(backupPath);
        }
        await _importLibraryFolder(event.sourceFolder, event.targetPath, emit);
        if (backupDir != null) {
          if (state is EmptyLibraryDirectorySelected) {
            await _discardBackupDir(backupDir);
          } else {
            await _restoreDatabaseFiles(backupDir, backupPath!);
          }
        }
        if (state is EmptyLibraryDirectorySelected) {
          await clearFilePickerCache();
        }
      } catch (e) {
        if (backupDir != null) {
          await _restoreDatabaseFiles(backupDir, backupPath!);
        }
        // Scoped Storage באנדרואיד: התיקייה נראית אך אינה ניתנת לקריאה (#1219).
        final message = e is PathAccessException
            ? 'אין לתוכנה הרשאת קריאה לקובץ המקור ${e.path}. '
                  'באנדרואיד יש לבחור את קובץ ${DatabaseConstants.databaseFileName} '
                  'דרך "בחר קובץ ספרייה".'
            : 'שגיאה בייבוא הספרייה: $e';
        emit(_error(errorMessage: message, selectedPath: event.sourceFolder));
      }
    });
  }

  /// מייבא את הספרייה מארכיון ZIP או ZST, ומשחזר את ה-DB הישן אם הפעולה
  /// אינה מסתיימת בבחירת ספרייה תקינה.
  Future<void> _onImportLibraryArchiveRequested(
    ImportLibraryArchiveRequested event,
    Emitter<EmptyLibraryState> emit,
  ) async {
    final backupPath = event.backupExistingPath;
    await _withLibraryReleased(backupPath, emit, () async {
      String? backupDir;
      try {
        if (backupPath != null) {
          backupDir = await _backupDatabaseFiles(backupPath);
        }
        final awaitingDatabase = await _importLibraryArchive(
          event.archivePath,
          event.targetPath,
          emit,
        );
        if (backupDir != null) {
          if (state is EmptyLibraryDirectorySelected) {
            await _discardBackupDir(backupDir);
          } else {
            await _restoreDatabaseFiles(backupDir, backupPath!);
          }
        }
        // ההחלטה אחרי החזרת הגיבוי: ארכיון נלווים לספרייה קיימת מסתיים בה.
        if (awaitingDatabase) {
          if (await DatabaseConstants.libraryDbExistsIn(event.targetPath)) {
            await _saveImportedLibrary(event.targetPath, emit);
          } else {
            _awaitDatabaseImport(event.targetPath, emit);
          }
        }
        if (state is EmptyLibraryDirectorySelected) {
          await clearFilePickerCache();
        }
      } catch (e) {
        if (backupDir != null) {
          await _restoreDatabaseFiles(backupDir, backupPath!);
        }
        emit(
          _error(
            errorMessage: 'שגיאה בייבוא הארכיון: $e',
            selectedPath: event.archivePath,
          ),
        );
      }
    });
  }

  /// מחזיר true כשהארכיון הכיל רק קבצים נלווים ובליעד אין DB; אז ה-state
  /// הסופי נקבע אצל הקורא, אחרי החזרת גיבוי אם יש.
  Future<bool> _importLibraryArchive(
    String archivePath,
    String target,
    Emitter<EmptyLibraryState> emit,
  ) async {
    final lowerPath = archivePath.toLowerCase();
    if (!lowerPath.endsWith('.zip') &&
        !lowerPath.endsWith('.zst') &&
        !isZdbPath(lowerPath)) {
      throw ArgumentError('יש לבחור קובץ ZIP, ZST או ZDB');
    }
    await Directory(target).create(recursive: true);
    emit(
      EmptyLibraryExtracting(
        selectedPath: archivePath,
        progress: 0.0,
        message: 'מחלץ את קובץ הספרייה...',
      ),
    );
    if (lowerPath.endsWith('.zip')) {
      final staging = stagingDirFor(target);
      await _deleteEntity(staging);
      try {
        await _extractZipArchive(archivePath, staging);
        // לפני ההעברה: מבנה ישן עם DB בתיקייה פנימית היה מותקן רק בחלקו.
        if (await hasNestedLibraryDatabase(staging)) {
          throw const _ArchiveLayoutException(
            LibraryMessages.archiveNestedDatabaseUnsupported,
          );
        }
        await promoteStagedImport(staging, target);
      } finally {
        await _deleteEntity(staging);
      }
      emit(
        EmptyLibraryExtracting(
          selectedPath: archivePath,
          progress: 1.0,
          message: 'הייבוא הושלם',
        ),
      );
      if (!await DatabaseConstants.libraryDbExistsIn(target)) return true;
      await _saveImportedLibrary(target, emit);
      return false;
    } else if (isZdbPath(lowerPath)) {
      // קובץ ספרייה בודד (חבילת FULL באנדרואיד): אימות והתקנה, בלי חילוץ.
      await _importZdbFile(
        File(archivePath),
        target,
        onProgress: _extractProgress(
          emit,
          archivePath,
          'מעתיק ומאמת את קובץ הספרייה...',
        ),
      );
    } else {
      await _writeDbAtomically(
        path.join(target, DatabaseConstants.databaseFileName),
        (tempPath) => _extractCompressedDatabase(
          archivePath,
          tempPath,
          _extractProgress(emit, archivePath, 'מחלץ את קובץ הספרייה...'),
        ),
      );
    }
    emit(
      EmptyLibraryExtracting(
        selectedPath: archivePath,
        progress: 1.0,
        message: 'הייבוא הושלם',
      ),
    );
    await _checkAndSaveExtractedDatabase(target, emit);
    return false;
  }

  /// ארכיון בלי DB (חבילת FULL של אנדרואיד): הקבצים הנלווים נשמרים ביעד, אבל
  /// keyLibraryPath לא משתנה עד שקובץ ה-DB יובא. אחרת סגירת הדיאלוג או
  /// הפעלה מחדש היו משאירות את התוכנה מצביעה על תיקייה בלי DB.
  void _awaitDatabaseImport(String target, Emitter<EmptyLibraryState> emit) {
    emit(
      EmptyLibraryAwaitingDatabase(
        selectedPath: target,
        message: LibraryMessages.archiveImportedAwaitingDatabase,
      ),
    );
  }

  /// [target] מכיל מסד פעיל: שומר אותו כנתיב הספרייה.
  Future<void> _saveImportedLibrary(
    String target,
    Emitter<EmptyLibraryState> emit,
  ) async {
    await Settings.setValue(SettingsRepository.keyLibraryPath, target);
    await Settings.setValue(SettingsRepository.keyLibraryFolderName, '');
    await Settings.setValue(SettingsRepository.keyDbEffectivePath, '');
    emit(EmptyLibraryDirectorySelected(selectedPath: target));
  }

  /// האם בארכיון שחולץ ל-[staging] יש קובץ ספרייה שיש לייבא בנפרד: `seforim.db`
  /// או `seforim.zdb` בתיקייה פנימית, כל `*.zdb` אחר, או ארכיון DB ראשי
  /// (`*.db.zst`). קבצים נלווים מוכרים, כמו קטלוג אוצר החכמה, אינם נחשבים.
  @visibleForTesting
  static Future<bool> hasNestedLibraryDatabase(String staging) async {
    final rootNames = {
      DatabaseConstants.databaseFileName,
      DatabaseConstants.zdbDatabaseFileName,
    };
    final sideAssets = {
      DatabaseConstants.externalCatalogArchiveFileName.toLowerCase(),
    };
    await for (final entity in Directory(
      staging,
    ).list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final name = path.basename(entity.path).toLowerCase();
      if (sideAssets.contains(name)) continue;
      final atRoot = path.equals(path.dirname(entity.path), staging);
      if (rootNames.contains(name)) {
        if (!atRoot) return true;
        continue;
      }
      if (isZdbPath(name) || name.endsWith('.db.zst')) return true;
    }
    return false;
  }

  /// ליבת ייבוא התיקייה (זורקת בכשל). לכל נכס — מעדיפים גרסה דחוסה (חילוץ),
  /// ואם אין נופלים לגרסה הרגילה (העתקה). seforim.db חובה; השאר אופציונליים.
  Future<void> _importLibraryFolder(
    String source,
    String target,
    Emitter<EmptyLibraryState> emit,
  ) async {
    emit(
      EmptyLibraryExtracting(
        selectedPath: target,
        progress: 0.0,
        message: 'מייבא את קבצי הספרייה...',
      ),
    );
    await Directory(target).create(recursive: true);

    // seforim.db — דחוס או רגיל. נדרש אלא אם כבר קיים ביעד (ייבוא נלווים בלבד
    // אל ספרייה קיימת).
    // zdb קודם ל-zst, כמו ברזולבר וב-_copyDatabaseFiles: גרסת zst נקראת רק
    // אחרי פריסה מלאה, ו-zdb בתיקייה הוא בדרך כלל הספרייה החיה.
    Future<File?> firstExisting(Iterable<String> names) async {
      for (final name in names) {
        final candidate = File(path.join(source, name));
        if (await candidate.exists()) return candidate;
      }
      return null;
    }

    final archives = DatabaseConstants.supportedDatabaseArchiveFileNames;
    final zdbFiles = [
      for (final name in [
        ...archives.where(isZdbPath),
        DatabaseConstants.zdbDatabaseFileName,
      ])
        if (await File(path.join(source, name)).exists())
          File(path.join(source, name)),
    ];
    final dbZdb = zdbFiles.length < 2
        ? zdbFiles.firstOrNull
        : await _newestZdb(zdbFiles);
    final dbZst = dbZdb == null
        ? await firstExisting(archives.where((name) => !isZdbPath(name)))
        : null;
    final dbPlain = File(path.join(source, DatabaseConstants.databaseFileName));
    if (dbZdb != null) {
      await _importZdbFile(
        dbZdb,
        target,
        onProgress: _extractProgress(
          emit,
          source,
          'מעתיק ומאמת את ספריית הספרים...',
        ),
      );
    } else if (dbZst != null) {
      await _writeDbAtomically(
        path.join(target, DatabaseConstants.databaseFileName),
        (tempPath) => _extractCompressedDatabase(
          dbZst.path,
          tempPath,
          _extractProgress(emit, source, 'מחלץ את ספריית הספרים...'),
        ),
      );
    } else if (await dbPlain.exists()) {
      // File.copy אינו מדווח התקדמות — על קובץ של כמה GB המסך נשאר על 0% עד
      // הסוף (issue #1334). עותק שהבורר יצר במטמון מועבר, לא מועתק שוב (#1360).
      final fromPickerCache = await isFilePickerCacheFile(dbPlain);
      await _writeDbAtomically(
        path.join(target, DatabaseConstants.databaseFileName),
        (tempPath) {
          final onProgress = _extractProgress(
            emit,
            source,
            'מעתיק את ספריית הספרים...',
          );
          return fromPickerCache
              ? moveFileWithProgress(dbPlain, tempPath, onProgress: onProgress)
              : copyFileWithProgress(dbPlain, tempPath, onProgress: onProgress);
        },
      );
    } else if (!await DatabaseConstants.libraryDbExistsIn(target)) {
      emit(
        _error(
          errorMessage:
              'לא נמצא ${DatabaseConstants.databaseFileName} (או הגרסה הדחוסה) בתיקייה שנבחרה',
          selectedPath: source,
        ),
      );
      return;
    }

    // קטלוג אוצר החכמה — אופציונלי (דחוס או רגיל)
    final catZst = File(
      path.join(source, DatabaseConstants.externalCatalogArchiveFileName),
    );
    final catPlain = File(
      path.join(source, DatabaseConstants.externalCatalogDatabaseFileName),
    );
    if (await catZst.exists()) {
      await _extractCompressedDatabase(
        catZst.path,
        path.join(target, DatabaseConstants.externalCatalogDatabaseFileName),
        _extractProgress(emit, source, 'מחלץ קטלוג אוצר החכמה...'),
      );
    } else if (await catPlain.exists()) {
      await catPlain.copy(
        path.join(target, DatabaseConstants.externalCatalogDatabaseFileName),
      );
    }

    // מילון החיפוש המקורב — אינו דחוס, אופציונלי
    final lexical = File(
      path.join(source, DatabaseConstants.lexicalDatabaseFileName),
    );
    if (await lexical.exists()) {
      await lexical.copy(
        path.join(target, DatabaseConstants.lexicalDatabaseFileName),
      );
    }

    // תלמוד בבלי — ארכיון tar.zst או תיקייה מחולצת, אופציונלי
    final talmudArchive = File(
      path.join(source, DatabaseConstants.talmudBavliArchiveFileName),
    );
    final talmudDir = Directory(
      path.join(source, DatabaseConstants.talmudBavliFolderName),
    );
    if (await talmudArchive.exists()) {
      await _extractTarArchive(
        talmudArchive.path,
        target,
        _extractProgress(emit, source, 'מחלץ ספרי תלמוד בבלי...'),
      );
    } else if (await talmudDir.exists()) {
      await copyDirectoryEntries(
        talmudDir.path,
        path.join(target, DatabaseConstants.talmudBavliFolderName),
      );
    }

    emit(
      EmptyLibraryExtracting(
        selectedPath: target,
        progress: 1.0,
        message: 'הייבוא הושלם',
      ),
    );
    await _checkAndSaveExtractedDatabase(target, emit);
  }

  /// שמות קבצי ה-DB שמגובים/מועתקים בעדכון ספרייה (seforim.db והלוואי שלו).
  static const _dbFileSuffixes = ['', '-shm', '-wal', '-journal'];

  /// עדכון ספרייה קיימת עם גיבוי בטוח: ה-DB הישן מגובה לתיקייה זמנית, נמחק
  /// לצמיתות רק בהצלחה ומשוחזר בכישלון. הורדה מחדש או העתקת seforim.db מתיקייה.
  Future<void> _onUpdateLibraryRequested(
    UpdateLibraryRequested event,
    Emitter<EmptyLibraryState> emit,
  ) async {
    final target = event.targetPath;
    await _withLibraryReleased(event.existingLibraryPath, emit, () async {
      String? backupDir;
      try {
        backupDir = await _backupDatabaseFiles(event.existingLibraryPath);
        if (event.isDownload) {
          await _downloadLibrary(target, emit);
        } else {
          emit(
            EmptyLibraryExtracting(
              selectedPath: target,
              progress: 0.0,
              message: 'מעתיק את קובץ הספרייה החדש...',
            ),
          );
          await Directory(target).create(recursive: true);
          await _copyDatabaseFiles(event.sourceFolder!, target);
          await _handleDirectorySelection(target, emit);
        }
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
      }
    });
  }

  /// שם הקובץ הזמני שאליו נכתב ה-DB לפני ההעברה לשם הסופי.
  static String _dbTempPathFor(String finalPath) => '$finalPath.new';

  /// מעתיק קובץ מסד (וה-overlay של zdb) אל [destPath] דרך שם זמני. לוואים
  /// ישנים ביעד נמחקים לפני ההחלפה: overlay של בסיס קודם היה פוסל את החדש.
  @visibleForTesting
  static Future<void> copyLibraryDbFile(
    String sourcePath,
    String destPath,
  ) async {
    final temp = '$destPath.copying';
    final overlay = File('$sourcePath-zovl');
    final hasOverlay = await overlay.exists();
    await File(destPath).parent.create(recursive: true);
    try {
      await File(sourcePath).openRead().pipe(File(temp).openWrite());
      if (hasOverlay) {
        await overlay.openRead().pipe(File('$temp-zovl').openWrite());
      }
      // -zlck נשאר: הוא מנעול ההחלפה של zvfs, לא חלק מהתוכן.
      for (final suffix in ['-zovl', '-journal', '-wal', '-shm']) {
        await _deleteEntity('$destPath$suffix');
      }
      await File(temp).rename(destPath);
      if (hasOverlay) await File('$temp-zovl').rename('$destPath-zovl');
    } finally {
      await _deleteEntity(temp);
      await _deleteEntity('$temp-zovl');
    }
  }

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

  /// ארכיון שהורד ו-seforim.zdb שקיבל דלתאות מאז: ה-db_version הגבוה מנצח,
  /// ובתיקו seforim.zdb (האחרון ברשימה). הקריאה משחזרת overlay — ב-isolate.
  static Future<File> _newestZdb(List<File> files) async {
    final paths = [for (final file in files) file.path];
    final versions = await Isolate.run(() {
      ensureLibraryVfs();
      return [
        for (final path in paths)
          () {
            try {
              return const LocalDbVersionReader().read(path).dbVersion;
            } catch (_) {
              return -1;
            }
          }(),
      ];
    });
    var best = 0;
    for (var i = 1; i < files.length; i++) {
      if (versions[i] >= versions[best]) best = i;
    }
    return files[best];
  }

  /// מאמת את ה-zdb שב-[candidatePath] (באותה תיקייה כמו [targetDir]) ומתקין
  /// אותו כ-seforim.zdb. seforim.db ישן ב-[targetDir] נמחק אחרי ההתקנה.
  static Future<void> _installZdbCandidate(
    String candidatePath,
    String targetDir, {
    FullDbManifest? manifest,
    void Function(double progress)? onProgress,
  }) async {
    await deleteZdbCandidateSidecars(candidatePath);
    await verifyZdbCandidate(candidatePath, manifest: manifest);
    await verifyLibraryZdbFrames(
      candidatePath,
      onProgress: (done, total) =>
          onProgress?.call(total > 0 ? (done / total).clamp(0.0, 1.0) : 0),
    );
    await SqliteDataProvider.instance.dispose();
    await installLibraryZdb(
      LibraryZdbFiles.zdbPathIn(targetDir),
      candidatePath,
      verify: false,
    );
    try {
      await deleteLegacyLibraryDb(targetDir);
    } on FileSystemException catch (e) {
      // הרזולבר כבר בוחר ב-zdb; ניקוי העלייה ינסה שוב.
      debugPrint('[EmptyLibrary] מחיקת seforim.db הישן נכשלה: $e');
    }
  }

  /// מייבא קובץ zdb: מעתיק אותו ליד היעד (בשביל ה-rename של ההתקנה), מאחד
  /// overlay שלצידו, מאמת ומתקין. מניפסט שלצידו נבדק כשאין overlay.
  static Future<void> _importZdbFile(
    File source,
    String target, {
    void Function(double progress)? onProgress,
  }) async {
    // ניקוי העלייה לא ימחק את seforim.zdb.import באמצע הייבוא.
    await runZdbImport(() async {
      final candidate = LibraryZdbFiles.importTempFor(
        LibraryZdbFiles.zdbPathIn(target),
      );
      final sourceOverlay = File('${source.path}-zovl');
      final hasOverlay = await sourceOverlay.exists();
      FullDbManifest? manifest;
      final manifestFile = File(fullDbManifestNameFor(source.path));
      if (!hasOverlay && await manifestFile.exists()) {
        final decoded = jsonDecode(await manifestFile.readAsString());
        if (decoded is! Map<String, dynamic>) {
          throw const FormatException('מניפסט הספרייה אינו תקין');
        }
        manifest = FullDbManifest.fromJson(decoded);
        checkZdbManifestSupported(manifest);
      }
      await _deleteZdbCandidate(candidate);
      try {
        void copied(double p) => onProgress?.call(p / 2);
        if (await isFilePickerCacheFile(source)) {
          await moveFileWithProgress(source, candidate, onProgress: copied);
        } else {
          await copyFileWithProgress(source, candidate, onProgress: copied);
        }
        if (hasOverlay) {
          await sourceOverlay.copy('$candidate-zovl');
          // installZdb מסרב למועמד עם overlay; הדחיסה מאחדת אותם לבסיס אחד.
          await compactLibraryZdb(candidate);
        }
        await _installZdbCandidate(
          candidate,
          target,
          manifest: manifest,
          onProgress: (p) => onProgress?.call(0.5 + p / 2),
        );
      } finally {
        await _deleteZdbCandidate(candidate);
      }
    });
  }

  static Future<void> _deleteZdbCandidate(String candidate) async {
    await _deleteEntity(candidate);
    await deleteZdbCandidateSidecars(candidate);
  }

  /// seforim.zdb ולוואיו, בלי `-zlck` (ראו README של otzaria_zvfs).
  static const _zdbFileSuffixes = ['', '-zovl', '-journal', '-wal', '-shm'];

  /// seforim.db רגיל שנכתב לתיקייה עם seforim.zdb היה מוסתר על ידו ברזולבר.
  static Future<void> _deleteZdbFamily(String dir) async {
    final zdb = LibraryZdbFiles.zdbPathIn(dir);
    for (final suffix in _zdbFileSuffixes.reversed) {
      await _deleteEntity('$zdb$suffix');
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
      await _deleteDbFamily(finalPath);
      await File(tempPath).rename(finalPath);
    } catch (_) {
      await _deleteDbFamily(tempPath);
      rethrow;
    }
    if (path.basename(finalPath) == DatabaseConstants.databaseFileName) {
      await _deleteZdbFamily(path.dirname(finalPath));
    }
  }

  static String? _tempRootOverride;

  /// בסיס התיקיות הזמניות של הגיבוי. הגיבוי הוא שם קבוע אחד, ולכן ריצת טסטים
  /// שנהרגה הייתה דולפת לריצה הבאה — כל טסט מזריק תיקייה משלו.
  @visibleForTesting
  static set tempRootOverride(String? value) => _tempRootOverride = value;

  static String get _tempRoot => _tempRootOverride ?? Directory.systemTemp.path;

  /// תיקיית הביניים שאליה מחולץ ארכיון ZIP: אחות ליעד, ולכן על אותו התקן —
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
    final zdbName = DatabaseConstants.zdbDatabaseFileName;
    final family = {
      for (final s in _dbFileSuffixes) '$dbName$s',
      for (final s in [..._zdbFileSuffixes, '-zlck']) '$zdbName$s',
    };
    await _renameEntriesOver(staging, target, skip: family);
    // rename על בסיס zdb היה משאיר לידו overlay של הבסיס הקודם.
    final stagedZdb = File(path.join(staging, zdbName));
    if (await stagedZdb.exists()) {
      if (await File('${stagedZdb.path}-zovl').exists()) {
        await compactLibraryZdb(stagedZdb.path);
      }
      await _installZdbCandidate(stagedZdb.path, target);
      return;
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
    await _deleteZdbFamily(target);
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
    // וכך גם תיקיית הביניים של ייבוא ZIP שנקטע.
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
    if (!await DatabaseConstants.libraryDbExistsIn(dir)) {
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
  /// מעתיק קובץ בזרימה ומדווח התקדמות (0..1) כל [reportEvery] בייטים.
  /// [File.copy] אינו מדווח כלום, ולכן קבצים גדולים הראו 0% עד הסוף.
  @visibleForTesting
  static Future<void> copyFileWithProgress(
    File source,
    String destPath, {
    void Function(double progress)? onProgress,
    int reportEvery = 4 << 20,
  }) async {
    final total = await source.length();
    final sink = File(destPath).openWrite();
    var done = 0;
    var sinceReport = 0;
    onProgress?.call(0);
    try {
      await for (final chunk in source.openRead()) {
        sink.add(chunk);
        done += chunk.length;
        sinceReport += chunk.length;
        if (sinceReport >= reportEvery && total > 0) {
          sinceReport = 0;
          onProgress?.call(done / total);
        }
      }
      await sink.flush();
    } finally {
      await sink.close();
    }
    onProgress?.call(1);
  }

  static Future<void> _moveFile(File file, String destPath) async {
    try {
      await file.rename(destPath);
    } on FileSystemException {
      await file.copy(destPath);
      await file.delete();
    }
  }

  static String? _filePickerCacheDirOverride;

  /// תיקיית המטמון שבה file_picker שומר עותקים (`<cache>/file_picker`).
  /// בבדיקות אין path_provider — מזריקים תיקייה.
  @visibleForTesting
  static set filePickerCacheDirOverride(String? value) =>
      _filePickerCacheDirOverride = value;

  /// האם [file] הוא עותק זמני שיצר file_picker במטמון האפליקציה. באנדרואיד
  /// הבורר מעתיק לשם כל קובץ נבחר, והעותק מיותר אחרי הייבוא (issue #1360).
  @visibleForTesting
  static Future<bool> isFilePickerCacheFile(File file) async {
    var cacheDir = _filePickerCacheDirOverride;
    if (cacheDir == null) {
      try {
        cacheDir = (await getTemporaryDirectory()).path;
      } catch (_) {
        return false;
      }
    }
    final pickerDir = path.join(cacheDir, 'file_picker');
    return path.isWithin(pickerDir, file.absolute.path);
  }

  /// מעביר עותק זמני אל [destPath]: rename מיידי על אותו התקן, ובנפילה
  /// (Cross-device) העתקה עם התקדמות ומחיקת המקור.
  @visibleForTesting
  static Future<void> moveFileWithProgress(
    File source,
    String destPath, {
    void Function(double progress)? onProgress,
  }) async {
    onProgress?.call(0);
    try {
      await source.rename(destPath);
    } on FileSystemException {
      await copyFileWithProgress(source, destPath, onProgress: onProgress);
      await source.delete();
    }
    onProgress?.call(1);
  }

  /// אחרי ייבוא מוצלח העותקים שיצר הבורר במטמון מיותרים — באנדרואיד הם
  /// הכפילו את נפח הספרייה על המכשיר, גם מניסיונות קודמים (issue #1360).
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

  /// מעתיק את seforim.db (ולוואיו) מתיקיית המקור אל היעד (דורס אם קיים).
  Future<void> _copyDatabaseFiles(String sourceDir, String targetDir) async {
    final sourceActive = DatabaseConstants.resolveLibraryDbPath(sourceDir);
    if (isZdbPath(sourceActive)) {
      await _importZdbFile(File(sourceActive), targetDir);
      return;
    }
    final sourceDb = File(
      path.join(sourceDir, DatabaseConstants.databaseFileName),
    );
    if (!await sourceDb.exists()) {
      throw Exception(
        'לא נמצא ${DatabaseConstants.databaseFileName} בתיקייה שנבחרה',
      );
    }
    // ה-DB הראשי נכתב אטומית תחילה (ההעברה מוחקת גם לוואים ישנים), והלוואים
    // מועתקים אחריו.
    await _writeDbAtomically(
      path.join(targetDir, DatabaseConstants.databaseFileName),
      (tempPath) => sourceDb.copy(tempPath),
    );
    for (final suffix in _dbFileSuffixes.where((s) => s.isNotEmpty)) {
      final name = '${DatabaseConstants.databaseFileName}$suffix';
      final src = File(path.join(sourceDir, name));
      if (await src.exists()) {
        final dest = File(path.join(targetDir, name));
        if (await dest.exists()) await dest.delete();
        await src.copy(dest.path);
      }
    }
  }

  Future<void> _handleDirectorySelection(
    String directoryPath,
    Emitter<EmptyLibraryState> emit,
  ) async {
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
      final dbFilePath = DatabaseConstants.resolveLibraryDbPath(directoryPath);
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

      // [בדיקת אנדרואיד] זרימת SAF: העתקת seforim.db מאחסון לא-נגיש ל-native
      // אל אחסון פנימי. לא נגישה מ-UI כרגע — לאמת על מכשיר לפני שינוי.
      if (Platform.isAndroid && !_isPathNativeAccessible(dbFilePath)) {
        final internalDbPath = await _getInternalDbPath(
          path.basename(dbFilePath),
        );
        final dbStat = await dbFile.stat();
        final dbSize = dbStat.size;
        final appDir = await getApplicationDocumentsDirectory();
        final freeSpace = await _getFreeInternalSpace(appDir.path);

        // בדיקת מקום פנוי לפני ניסיון ההעתקה
        // (גם "העבר" לא יעזור — הוא מעתיק לפנימי לפני מחיקת החיצוני)
        if (freeSpace > 0 && dbSize > freeSpace) {
          final needed = formatMegabytesLtr(dbSize);
          final free = formatMegabytesLtr(freeSpace);
          emit(
            _error(
              errorMessage:
                  'אין מספיק מקום פנוי באחסון הפנימי.\n'
                  'נדרש: $needed, פנוי: $free.\n'
                  'יש לפנות מקום ידנית ולנסות שוב.',
              selectedPath: directoryPath,
            ),
          );
          return;
        }

        // נסה להעתיק ישירות — עובד אם לאפליקציה יש READ_EXTERNAL_STORAGE
        emit(EmptyLibraryLoading(selectedPath: directoryPath));
        try {
          await copyLibraryDbFile(dbFilePath, internalDbPath);

          // העתקה הצליחה — שמור הגדרות והמשך
          await Settings.setValue(
            SettingsRepository.keyLibraryPath,
            directoryPath,
          );
          await Settings.setValue(SettingsRepository.keyLibraryFolderName, '');
          await Settings.setValue(
            SettingsRepository.keyDbEffectivePath,
            internalDbPath,
          );
          emit(EmptyLibraryDirectorySelected(selectedPath: directoryPath));
          return;
        } on PathAccessException {
          // dart:io לא יכול לגשת לקובץ — צריך FilePicker (SAF)
          // ממשיכים למטה להצגת הדיאלוג
        } catch (copyError) {
          // שגיאת I/O שאינה הרשאה (למשל ENOSPC, שגיאת קריאה)
          // מנקים קובץ יעד חלקי אם נוצר
          try {
            await File(internalDbPath).delete();
          } catch (_) {}
          final isNoSpace =
              copyError.toString().contains('No space') ||
              copyError.toString().contains('ENOSPC');
          emit(
            _error(
              errorMessage: isNoSpace
                  ? 'אין מספיק מקום פנוי. יש לפנות מקום ולנסות שוב.'
                  : 'שגיאה בהעתקת קובץ הספרייה: $copyError',
              selectedPath: directoryPath,
            ),
          );
          return;
        }
        // נגענו כאן רק אם PathAccessException — הדרך היחידה קדימה היא picker שני
        emit(
          EmptyLibraryAskingDbCopy(
            externalDbPath: dbFilePath,
            libraryPath: directoryPath,
            internalDbPath: internalDbPath,
            dbSizeBytes: dbSize,
            freeSpaceBytes: freeSpace,
          ),
        );
        return;
      }

      await Settings.setValue(SettingsRepository.keyLibraryPath, directoryPath);
      await Settings.setValue(SettingsRepository.keyLibraryFolderName, '');
      // נקה override קודם אם קיים
      await Settings.setValue(SettingsRepository.keyDbEffectivePath, '');

      emit(EmptyLibraryDirectorySelected(selectedPath: directoryPath));
    } catch (e) {
      emit(
        _error(
          errorMessage: 'שגיאה בבדיקת התיקייה: $e',
          selectedPath: directoryPath,
        ),
      );
    }
  }

  /// מחזיר את הנתיב הראשון בעץ ההורים שקיים בפועל, לצורך בדיקת df.
  static String _findExistingAncestor(String dirPath) {
    var dir = Directory(dirPath);
    while (!dir.existsSync() && dir.parent.path != dir.path) {
      dir = dir.parent;
    }
    return dir.path;
  }

  /// בודק אם נתיב נגיש לספריית sqlite3 native ב-Android.
  ///
  /// ב-Android Scoped Storage, רק אחסון פנימי (/data/) ואחסון חיצוני
  /// ייעודי לאפליקציה (Android/data/PACKAGE_NAME/) נגיש לגישה native.
  /// נתיבים כגון /storage/emulated/0/Download/ אינם נגישים.
  static bool _isPathNativeAccessible(String filePath) {
    if (!Platform.isAndroid) return true;
    // אחסון פנימי
    if (filePath.startsWith('/data/')) return true;
    // אחסון חיצוני ייעודי לאפליקציה
    if (filePath.contains('/Android/data/')) return true;
    // אחסון חיצוני ייעודי אחר
    if (filePath.contains('/Android/obb/')) return true;
    return false;
  }

  /// מחזיר את הנתיב הפנימי שאליו יועתק seforim.db ב-Android.
  static Future<String> _getInternalDbPath([
    String fileName = DatabaseConstants.databaseFileName,
  ]) async {
    final appDir = await getApplicationDocumentsDirectory();
    return path.join(appDir.path, 'otzaria', fileName);
  }

  /// מחזיר מידע df עבור נתיב נתון: filesystem ומקום פנוי בבייטים.
  /// מחזיר freeBytes = -1 אם לא ניתן לקבוע.
  static Future<_DfInfo> _getDfInfo(String dirPath) async {
    if (!Platform.isAndroid) {
      return const _DfInfo(filesystem: null, freeBytes: -1);
    }
    try {
      // -k (בלוקים של 1024B) נתמך גם ב-toybox של אנדרואיד וגם ב-coreutils.
      // הדגל -B1 של GNU אינו קיים ב-toybox ומחזיר exit!=0, מה שהשבית בעבר
      // את כל בדיקת המקום הפנוי באנדרואיד (freeBytes נשאר -1 תמיד).
      final result = await Process.run('df', [
        '-k',
        dirPath,
      ], runInShell: false);
      if (result.exitCode != 0) {
        return const _DfInfo(filesystem: null, freeBytes: -1);
      }
      final lines = result.stdout.toString().trim().split('\n');
      if (lines.length < 2) {
        return const _DfInfo(filesystem: null, freeBytes: -1);
      }
      // שורת הנתונים של df -k: Filesystem 1K-blocks Used Available Use% Mount
      final parts = lines.last.trim().split(RegExp(r'\s+'));
      if (parts.length < 4) {
        return const _DfInfo(filesystem: null, freeBytes: -1);
      }
      final availableKb = int.tryParse(parts[3]);
      return _DfInfo(
        filesystem: parts[0],
        freeBytes: availableKb == null ? -1 : availableKb * 1024,
      );
    } catch (_) {
      return const _DfInfo(filesystem: null, freeBytes: -1);
    }
  }

  /// עוטף את _getDfInfo להחזרת מקום פנוי בלבד (לשימוש קיים).
  static Future<int> _getFreeInternalSpace(String dirPath) async =>
      (await _getDfInfo(dirPath)).freeBytes;

  /// בודק אם יש מספיק מקום פנוי להורדה ולחילוץ הספרייה.
  ///
  /// [downloadSize] - גודל הקבצים הדחוסים בבייטים. כשידוע (אחרי קריאת
  /// ה-Content-Length של שלושת הקבצים) מועבר הסכום **האמיתי**; אחרת משמש
  /// אומדן (1.5GB) לבדיקת הסף הראשונית שמשביתה את כפתור ההורדה.
  ///
  /// מחזיר הודעת שגיאה אם אין מספיק מקום, או null אם הכל תקין.
  /// מטפל גם בתרחיש שבו temp ותיקיית הספרייה חולקים אותו volume.
  Future<String?> _checkSpaceForDownload({
    int? downloadSize,
    bool mainDbIsZdb = false,
  }) async {
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

    // אומדן fallback לסכום הדחוס של שלושת הקבצים, בשימוש רק כש-downloadSize
    // לא ידוע (בדיקת הסף הראשונית, או כש-HEAD לא החזיר Content-Length).
    // נכון להיום הסכום האמיתי ~1.45GB (seforim ~1.01GB + תלמוד ~0.44GB +
    // קטלוג ~0.005GB). אם ה-DB יגדל בעתיד מעבר ל-1.5GB, יש להגדיל את
    // הקבוע בהתאם — אחרת בדיקת הסף הראשונית עלולה לעבור בטעות במכשירים עם
    // מעט מקום (הבדיקה האמיתית מול grandTotal עדיין תתפוס זאת בהמשך).
    final int kDownloadSize = downloadSize ?? 1610612736; // אומדן 1.5 GB
    // zdb אינו מחולץ: הוא והנלווים תופסים ביעד בערך את גודל ההורדה.
    final int kExtractSize = mainDbIsZdb ? kDownloadSize : 6979321856;

    final tempPath = Directory.systemTemp.path;
    final libraryPath =
        _defaultLibraryPathOverride ?? await AppPaths.getDefaultLibraryPath();
    final checkPath = _findExistingAncestor(libraryPath);

    if (!await AndroidStorageService.volumeSupportsLargeFiles(libraryPath)) {
      return 'כרטיס ה-SD מפורמט ב-FAT32, שאינו תומך בקבצים מעל 4GB — '
          'וקובץ הספרייה גדול מכך.\n'
          'יש לבחור באחסון הפנימי, או לפרמט את הכרטיס ל-exFAT.';
    }

    final tempInfo = await _getDfInfo(tempPath);
    final extractInfo = await _getDfInfo(checkPath);

    String gb(int bytes) => (bytes / 1024 / 1024 / 1024).toStringAsFixed(1);

    final sameVolume =
        tempInfo.filesystem != null &&
        extractInfo.filesystem != null &&
        tempInfo.filesystem == extractInfo.filesystem;

    if (sameVolume) {
      // שני הנתיבים על אותו volume: צריך מקום לשניהם יחד.
      final free = tempInfo.freeBytes;
      if (free > 0 && free < kDownloadSize + kExtractSize) {
        return 'אין מספיק מקום פנוי להורדה ולחילוץ הספרייה.\n'
            'נדרש: לפחות ${gb(kDownloadSize + kExtractSize)} GB, פנוי: ${gb(free)} GB.\n'
            'יש לפנות מקום ולנסות שוב.';
      }
    } else {
      // volumes נפרדים: בדיקה לכל אחד בנפרד
      if (tempInfo.freeBytes > 0 && tempInfo.freeBytes < kDownloadSize) {
        return 'אין מספיק מקום פנוי להורדת הקבצים הדחוסים.\n'
            'נדרש: לפחות ${gb(kDownloadSize)} GB, פנוי: ${gb(tempInfo.freeBytes)} GB.\n'
            'יש לפנות מקום ולנסות שוב.';
      }
      if (extractInfo.freeBytes > 0 && extractInfo.freeBytes < kExtractSize) {
        return 'אין מספיק מקום פנוי לחילוץ הספרייה.\n'
            'נדרש: לפחות ${gb(kExtractSize)} GB, פנוי: ${gb(extractInfo.freeBytes)} GB.\n'
            'יש לפנות מקום ולנסות שוב.';
      }
    }
    return null;
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
  EmptyLibraryError _error({
    String? errorMessage,
    String? selectedPath,
    List<String>? zipFiles,
  }) => EmptyLibraryError(
    errorMessage: errorMessage,
    selectedPath: selectedPath,
    zipFiles: zipFiles,
    downloadDisabledReason: _downloadDisabledReason,
  );

  /// בוחר את קובץ seforim.db ישירות דרך FilePicker (SAF-aware).
  /// משמש כאשר הנתיב הפיזי אינו נגיש ל-dart:io ב-Android Scoped Storage.
  // [בדיקת אנדרואיד] המשך זרימת ה-SAF (אחרי EmptyLibraryAskingDbCopy). מגיע רק
  // מ-system_settings_tab, וזרימה זו אינה ניתנת-להתנעה כרגע — לאמת על מכשיר.
  Future<void> _onPickDbFileRequested(
    PickDbFileRequested event,
    Emitter<EmptyLibraryState> emit,
  ) async {
    try {
      final pickedFile = await FilePicker.pickFile(
        type: FileType.any,
        dialogTitle: 'בחר את קובץ ${DatabaseConstants.databaseFileName}',
        windowsOptions: kModalWindowsOptions,
        linuxOptions: kModalLinuxOptions,
      );

      if (pickedFile == null) {
        // המשתמש ביטל — חזרה לדיאלוג ההעתקה
        final internalDbPath = await _getInternalDbPath();
        emit(
          EmptyLibraryAskingDbCopy(
            externalDbPath: '',
            libraryPath: event.libraryPath,
            internalDbPath: internalDbPath,
            dbSizeBytes: 0,
            freeSpaceBytes: -1,
          ),
        );
        return;
      }

      // וודא שנבחר הקובץ הנכון — אם לא, חזור לדיאלוג עם הסבר
      if (pickedFile.name != DatabaseConstants.databaseFileName) {
        final internalDbPath = await _getInternalDbPath();
        emit(
          EmptyLibraryAskingDbCopy(
            externalDbPath: event.externalDbPath,
            libraryPath: event.libraryPath,
            internalDbPath: internalDbPath,
            dbSizeBytes: 0,
            freeSpaceBytes: -1,
            errorMessage:
                'יש לבחור את הקובץ ${DatabaseConstants.databaseFileName}. '
                'נבחר: "${pickedFile.name}" — נסה שוב.',
          ),
        );
        return;
      }

      emit(EmptyLibraryLoading(selectedPath: event.libraryPath));

      final sourcePath = pickedFile.path;
      final destFile = File(event.internalDbPath);
      await destFile.parent.create(recursive: true);

      if (sourcePath == null) {
        throw Exception('FilePicker לא החזיר נתיב נגיש לקובץ שנבחר');
      }

      // העתק תוך שימוש ב-streams (FilePicker מספק נתיב נגיש מ-cache SAF)
      await File(sourcePath).openRead().pipe(destFile.openWrite());

      // אם בחר להעביר — מחק את קובץ המקור החיצוני האמיתי
      if (event.shouldMove && event.externalDbPath.isNotEmpty) {
        try {
          await File(event.externalDbPath).delete();
        } catch (_) {
          // dart:io עשוי להיכשל על Scoped Storage — לא קריטי, ה-DB כבר הועתק
        }
      }

      await Settings.setValue(
        SettingsRepository.keyLibraryPath,
        event.libraryPath,
      );
      await Settings.setValue(SettingsRepository.keyLibraryFolderName, '');
      await Settings.setValue(
        SettingsRepository.keyDbEffectivePath,
        event.internalDbPath,
      );

      emit(EmptyLibraryDirectorySelected(selectedPath: event.libraryPath));
    } catch (e) {
      // זיהוי שגיאת חוסר מקום (ENOSPC / No space left)
      final isNoSpace =
          (e is FileSystemException && e.osError?.errorCode == 28) ||
          e.toString().contains('No space') ||
          e.toString().contains('ENOSPC');
      final msg = isNoSpace
          ? 'אין מספיק מקום פנוי. בחר "העבר" (מחיקת מקור) כדי לפנות מקום, '
                'או פנה מקום ידנית ונסה שוב.'
          : 'שגיאה בהעתקת קובץ הספרייה: $e';
      emit(_error(errorMessage: msg, selectedPath: event.libraryPath));
    }
  }

  Future<void> _checkAndSaveExtractedDatabase(
    String extractedDirectory,
    Emitter<EmptyLibraryState> emit,
  ) async {
    try {
      // חיפוש קובץ seforim.db בתיקייה המחולצת
      final directory = Directory(extractedDirectory);
      final dbFiles = await directory
          .list(recursive: true)
          .where(
            (entity) =>
                entity is File &&
                (entity.path.toLowerCase().endsWith(
                      DatabaseConstants.databaseFileName,
                    ) ||
                    entity.path.toLowerCase().endsWith(
                      DatabaseConstants.zdbDatabaseFileName,
                    )),
          )
          .cast<File>()
          .toList();

      if (dbFiles.isEmpty) {
        emit(
          _error(
            errorMessage:
                'לא נמצא קובץ ${DatabaseConstants.databaseFileName} בקובץ הדחוס',
            selectedPath: extractedDirectory,
          ),
        );
        return;
      }

      final dbPath = dbFiles.first.path;
      final rootPath = path.dirname(dbPath);

      await Settings.setValue(SettingsRepository.keyLibraryPath, rootPath);
      await Settings.setValue(SettingsRepository.keyLibraryFolderName, '');
      // ניקוי override Android — ה-DB החדש נמצא ישירות בספרייה
      await Settings.setValue(SettingsRepository.keyDbEffectivePath, '');

      emit(EmptyLibraryDirectorySelected(selectedPath: rootPath));
    } catch (e) {
      emit(_error(errorMessage: 'שגיאה: $e'));
    }
  }

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
      final zdbManifest = latestAsset.isZdb
          ? await _fetchZdbManifest(latestAsset)
          : null;

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

      // שלושת הקבצים מורדים יחד ואז מחולצים יחד. פס ההתקדמות בשני השלבים
      // מתייחס לסכום שלושתם; רק כותרת המשנה משתנה לפי הקובץ הנוכחי.
      final assets = <_DownloadAsset>[
        if (zdbManifest != null)
          // ליד היעד: ההתקנה היא rename, שנכשל בין כוננים.
          _DownloadAsset(
            url: latestAsset.downloadUrl,
            tempFileName: path.basename(
              LibraryZdbFiles.downloadPathFor(
                DatabaseConstants.zdbDatabaseFileName,
              ),
            ),
            downloadDir: libraryPath,
            downloadTitle: 'מוריד את ספריית אוצריא',
            extractTitle: 'מאמת ומתקין את ספריית אוצריא',
            isTar: false,
            outputFileName: DatabaseConstants.zdbDatabaseFileName,
            isMainDb: true,
            sha256: zdbManifest.sha256,
            zdbManifest: zdbManifest,
          )
        else
          _DownloadAsset(
            url: latestAsset.downloadUrl,
            tempFileName: 'otzaria_${latestAsset.assetName}',
            downloadTitle: 'מוריד את ספריית אוצריא',
            extractTitle: 'מחלץ את ספריית אוצריא',
            isTar: false,
            outputFileName: DatabaseConstants.databaseFileName,
            isMainDb: true,
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
              'https://github.com/Otzaria/SeforimMagicIndexer/releases/latest/download/lexical.db',
          tempFileName: 'otzaria_lexical.db',
          downloadTitle: 'מוריד מילון לחיפוש המקורב',
          extractTitle: 'מתקין מילון לחיפוש המקורב',
          isTar: false,
          outputFileName: 'lexical.db',
          isCompressed: false,
          optional: true,
        ),
      ];

      emit(
        const EmptyLibraryDownloading(progress: 0.0, message: 'מתחבר לשרת...'),
      );

      // פתרון redirect-ים מראש (package:http מאבד את ה-Range בעת redirect) +
      // קריאת גודל כל קובץ דחוס, לחישוב פס התקדמות וזמן משוער מאוחדים.
      for (final asset in assets) {
        if (asset.skipped) continue;
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

      // בדיקת מקום פנוי מול הסכום הדחוס האמיתי של שלושת הקבצים (במקום
      // אומדן קבוע). גם safety net למצב שהדיסק התמלא אחרי טעינת המסך.
      final spaceError = await _checkSpaceForDownload(
        downloadSize: grandTotal > 0 ? grandTotal : null,
        mainDbIsZdb: zdbManifest != null,
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
    final tempPath = asset.localPath;
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
    if (asset.zdbManifest != null) await deleteZdbCandidateSidecars(tempPath);
    final downloader = PatchDownloader(
      decompress: (_) async => null,
      httpClient: _httpClient,
      connectTimeout: downloadConnectTimeout,
      stallTimeout: _downloadStallTimeout,
    );
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
    try {
      if (!await file.exists()) return 0;
      final sidecar = File(PatchDownloader.resumeSidecarPath(file.path));
      if (!await sidecar.exists()) return 0;
      final lines = (await sidecar.readAsString()).split('\n');
      if (lines.first != identity) return 0;
      final length = await file.length();
      if (expectedSize > 0 && length >= expectedSize) return length;
      final etag = lines.length > 1 ? lines[1].trim() : '';
      return etag.isNotEmpty && !etag.startsWith('W/') ? length : 0;
    } catch (_) {
      return 0;
    }
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
    final tempPath = asset.localPath;

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
      final zdbManifest = asset.zdbManifest;
      if (zdbManifest != null) {
        await _installZdbCandidate(
          tempPath,
          outputDir,
          manifest: zdbManifest,
          onProgress: report,
        );
      } else if (asset.isTar) {
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
        final releaseTag = asset.releaseTag;
        if (asset.outputFileName == DatabaseConstants.lexicalDatabaseFileName &&
            releaseTag != null) {
          await MagicDictionaryDownloader.writeVersionMarker(
            outputPath,
            releaseTag,
          );
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
    } catch (e) {
      // busy: הקובץ שלם ומאומת, וההתקנה תצליח כשהספרייה תשתחרר.
      if (e is LibraryZdbException && e.isBusy) rethrow;
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
      throw Exception('לא נמצא ברליס האחרון קובץ ספרייה שגרסה זו יודעת לקרוא');
    }

    return asset;
  }

  /// המניפסט של ה-zdb שב-release, נבדק לפני הורדת ~2GB.
  Future<FullDbManifest> _fetchZdbManifest(DatabaseReleaseAsset asset) async {
    final response = await _httpClient
        .get(Uri.parse(asset.manifestUrl!))
        .timeout(downloadConnectTimeout);
    if (response.statusCode != 200) {
      throw Exception('שגיאה בקבלת מניפסט הספרייה: ${response.statusCode}');
    }
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('מניפסט הספרייה אינו תקין');
    }
    final manifest = FullDbManifest.fromJson(decoded);
    if (manifest.file != asset.assetName) {
      throw FormatException('המניפסט שייך ל-${manifest.file}');
    }
    checkZdbManifestSupported(manifest);
    return manifest;
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
    for (final name in DatabaseConstants.supportedDatabaseArchiveFileNames) {
      final downloadUrl = urlsByName[name];
      if (downloadUrl == null) continue;
      if (!isZdbPath(name)) {
        return DatabaseReleaseAsset(assetName: name, downloadUrl: downloadUrl);
      }
      // zdb בלי מניפסט אינו ניתן לאימות, ולכן אינו מוצע.
      final manifestUrl = urlsByName[fullDbManifestNameFor(name)];
      if (manifestUrl != null) {
        return DatabaseReleaseAsset(
          assetName: name,
          downloadUrl: downloadUrl,
          manifestUrl: manifestUrl,
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

/// ארכיון במבנה שאינו נתמך; ההודעה מוצגת למשתמש כמות שהיא.
class _ArchiveLayoutException implements Exception {
  const _ArchiveLayoutException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// תוצאת קריאת df עבור נתיב נתון.
class _DfInfo {
  const _DfInfo({required this.filesystem, required this.freeBytes});
  final String? filesystem;
  final int freeBytes;
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
    this.downloadDir,
    this.zdbManifest,
  });

  /// תיקיית ההורדה; null — תיקיית ה-temp של המערכת.
  final String? downloadDir;

  /// מניפסט ה-DB כשהוא zdb: מאומת ומותקן במקום לחלץ אותו.
  final FullDbManifest? zdbManifest;

  String get localPath =>
      path.join(downloadDir ?? Directory.systemTemp.path, tempFileName);

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

  /// sha256 של הנכס מה-API — לאימות ההורדה ולסימון גרסת התלמוד.
  final String? sha256;

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
    this.manifestUrl,
  });

  final String assetName;
  final String downloadUrl;

  /// מניפסט ה-zdb (`<name>.manifest.json`). חובה ל-zdb; null לארכיון zst.
  final String? manifestUrl;

  bool get isZdb => isZdbPath(assetName);
}
