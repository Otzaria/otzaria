import 'dart:convert';
import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:bloc/bloc.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/core/http_client_registry.dart';
import 'package:otzaria/data/constants/database_constants.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:otzaria/empty_library/bloc/empty_library_event.dart';
import 'package:otzaria/empty_library/bloc/empty_library_state.dart';
import 'package:otzaria/empty_library/services/android_storage_service.dart';
import 'package:otzaria/search/magic_dictionary_downloader.dart';
import 'package:otzaria/settings/settings_exports.dart';
import 'package:otzaria/utils/download_eta_estimator.dart';
import 'package:otzaria/utils/download_sidecar.dart';
import 'package:otzaria/utils/file/tar_zst_extractor.dart';
import 'package:otzaria/utils/file/zip_extractor_service.dart';
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
    this._defaultLibraryPathOverride,
    this.downloadConnectTimeout = _defaultDownloadConnectTimeout,
  }) : _httpClient = httpClient ?? http.Client(),
       _extractCompressedDatabase = extractCompressedDatabase ?? _extractZst,
       _extractTarArchive = extractTarArchive ?? _extractTarZst,
       super(
         const EmptyLibraryInitial(downloadDisabledReason: 'בודק מקום פנוי...'),
       ) {
    HttpClientRegistry.register(_httpClient.close);
    on<PickDirectoryRequested>(_onPickDirectoryRequested);
    on<DownloadLibraryRequested>(_onDownloadLibraryRequested);
    on<ImportExistingLibraryRequested>(_onImportExistingLibraryRequested);
    on<ImportLibraryFolderRequested>(_onImportLibraryFolderRequested);
    on<UpdateLibraryRequested>(_onUpdateLibraryRequested);
    on<DeleteZipAnswered>(_onDeleteZipAnswered);
    on<PickDbFileRequested>(_onPickDbFileRequested);
    on<CheckDiskSpaceRequested>(_onCheckDiskSpaceRequested);
    on<StorageLocationSelected>(_onStorageLocationSelected);
    // בדיקת מקום פנוי מתבצעת מיד — כפתור ההורדה מושבת עד להשלמתה
    add(CheckDiskSpaceRequested());
  }

  final http.Client _httpClient;
  final Duration downloadConnectTimeout;
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

  Future<void> _onPickDirectoryRequested(
    PickDirectoryRequested event,
    Emitter<EmptyLibraryState> emit,
  ) async {
    final result = await FilePicker.getDirectoryPath(
      dialogTitle: 'בחר את תיקיית הספרייה (התיקייה שמכילה את seforim.db)',
      lockParentWindow: true,
    );

    if (result == null) return;

    emit(EmptyLibraryLoading(selectedPath: result));
    await _handleDirectorySelection(result, emit);
  }

  /// מייבא ספרייה קיימת אל מיקום היעד: חילוץ ארכיון או העתקת תיקיית DB.
  Future<void> _onImportExistingLibraryRequested(
    ImportExistingLibraryRequested event,
    Emitter<EmptyLibraryState> emit,
  ) async {
    try {
      await _importExisting(
        event.sourcePath,
        event.targetPath,
        event.isArchive,
        emit,
      );
    } catch (e) {
      emit(
        _error(
          errorMessage: 'שגיאה בייבוא הספרייה: $e',
          selectedPath: event.sourcePath,
        ),
      );
    }
  }

  /// מייבא נכסי ספרייה מתיקייה שנבחרה: מזהה כל נכס (seforim.db, קטלוג, מילון,
  /// תלמוד) בגרסה דחוסה או רגילה, ומחלץ/מעתיק אותו אל היעד. אם [backupExistingPath]
  /// מסופק (עדכון במקום) — ה-DB הישן מגובה ומשוחזר בכישלון.
  Future<void> _onImportLibraryFolderRequested(
    ImportLibraryFolderRequested event,
    Emitter<EmptyLibraryState> emit,
  ) async {
    final backupPath = event.backupExistingPath;
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
    } catch (e) {
      if (backupDir != null) {
        await _restoreDatabaseFiles(backupDir, backupPath!);
      }
      emit(
        _error(
          errorMessage: 'שגיאה בייבוא הספרייה: $e',
          selectedPath: event.sourceFolder,
        ),
      );
    }
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
    final dbZst = File(
      path.join(source, DatabaseConstants.databaseArchiveFileName),
    );
    final dbPlain = File(path.join(source, DatabaseConstants.databaseFileName));
    final targetDb = File(
      path.join(target, DatabaseConstants.databaseFileName),
    );
    if (await dbZst.exists()) {
      await _extractCompressedDatabase(
        dbZst.path,
        path.join(target, DatabaseConstants.databaseFileName),
        _extractProgress(emit, source, 'מחלץ את ספריית הספרים...'),
      );
    } else if (await dbPlain.exists()) {
      await dbPlain.copy(path.join(target, DatabaseConstants.databaseFileName));
    } else if (!await targetDb.exists()) {
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

  /// ליבת הייבוא (זורקת בכשל). חילוץ ארכיון אל היעד, או העתקת תיקיית DB שלמה.
  Future<void> _importExisting(
    String sourcePath,
    String targetPath,
    bool isArchive,
    Emitter<EmptyLibraryState> emit,
  ) async {
    emit(EmptyLibraryLoading(selectedPath: sourcePath));
    await Directory(targetPath).create(recursive: true);
    if (isArchive) {
      final lower = sourcePath.toLowerCase();
      if (lower.endsWith('.zip')) {
        await _handleZipFile(sourcePath, emit, outputDir: targetPath);
      } else if (lower.endsWith('.zst')) {
        await _handleZstFile(sourcePath, emit, outputDir: targetPath);
      } else {
        emit(
          _error(
            errorMessage: 'סוג קובץ לא נתמך. בחר קובץ .zip או .zst',
            selectedPath: sourcePath,
          ),
        );
      }
      return;
    }
    // תיקייה עם DB קיים — מעתיקים את כל תכולתה אל היעד ואז מאמתים ושומרים.
    emit(
      EmptyLibraryExtracting(
        selectedPath: targetPath,
        progress: 0.0,
        message: 'מעתיק את קבצי הספרייה למיקום היעד...',
      ),
    );
    await copyDirectoryEntries(sourcePath, targetPath);
    await _handleDirectorySelection(targetPath, emit);
  }

  /// שמות קבצי ה-DB שמגובים/מועתקים בעדכון ספרייה (seforim.db והלוואי שלו).
  static const _dbFileSuffixes = ['', '-shm', '-wal', '-journal'];

  /// עדכון ספרייה קיימת עם גיבוי בטוח: ה-DB הישן מגובה לתיקייה זמנית, נמחק
  /// לצמיתות רק בהצלחה ומשוחזר בכישלון. הורדה מחדש, חילוץ ארכיון (ZIP/ZST),
  /// או העתקת seforim.db מתיקייה.
  Future<void> _onUpdateLibraryRequested(
    UpdateLibraryRequested event,
    Emitter<EmptyLibraryState> emit,
  ) async {
    final target = event.targetPath;
    String? backupDir;
    try {
      backupDir = await _backupDatabaseFiles(event.existingLibraryPath);
      if (event.isDownload) {
        await _downloadLibrary(target, emit);
      } else if (event.isArchive) {
        await Directory(target).create(recursive: true);
        final source = event.sourceFolder!;
        final lower = source.toLowerCase();
        if (lower.endsWith('.zip')) {
          await _handleZipFile(source, emit, outputDir: target);
        } else if (lower.endsWith('.zst')) {
          await _handleZstFile(source, emit, outputDir: target);
        } else {
          emit(
            _error(
              errorMessage: 'סוג קובץ לא נתמך. בחר קובץ .zip או .zst',
              selectedPath: source,
            ),
          );
        }
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
  }

  /// מעביר את seforim.db (ולוואיו) מ-[dir] לתיקיית גיבוי זמנית. מחזיר את נתיב
  /// תיקיית הגיבוי, או null אם אין seforim.db לגבות.
  Future<String?> _backupDatabaseFiles(String dir) async {
    final dbFile = File(path.join(dir, DatabaseConstants.databaseFileName));
    if (!await dbFile.exists()) return null;
    // סגירת חיבור ה-RO משחררת את נעילת seforim.db לפני ההזזה — ב-Windows
    // handle פתוח מונע rename/delete. החיבור ייפתח מחדש בקריאה הבאה.
    await SqliteDataProvider.instance.dispose();
    final backup = await Directory(
      path.join(
        Directory.systemTemp.path,
        'otzaria_db_backup_${DateTime.now().millisecondsSinceEpoch}',
      ),
    ).create(recursive: true);
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

  /// משחזר את קבצי ה-DB מתיקיית הגיבוי חזרה אל [dir] (דורס אם קיים).
  Future<void> _restoreDatabaseFiles(String backupDir, String dir) async {
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

  Future<void> _discardBackupDir(String backupDir) async {
    final d = Directory(backupDir);
    if (await d.exists()) await d.delete(recursive: true);
  }

  /// מעתיק את seforim.db (ולוואיו) מתיקיית המקור אל היעד (דורס אם קיים).
  Future<void> _copyDatabaseFiles(String sourceDir, String targetDir) async {
    final sourceDb = File(
      path.join(sourceDir, DatabaseConstants.databaseFileName),
    );
    if (!await sourceDb.exists()) {
      throw Exception(
        'לא נמצא ${DatabaseConstants.databaseFileName} בתיקייה שנבחרה',
      );
    }
    for (final suffix in _dbFileSuffixes) {
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

      // Android: בדוק אם sqlite3 native יכול לפתוח את הקובץ ישירות.
      // אחסון Scoped Storage (כגון /storage/emulated/0/...) נגיש ל-dart:io
      // בחלק מהמכשירים אבל לא לספריית sqlite3 native.
      if (Platform.isAndroid && !_isPathNativeAccessible(dbFilePath)) {
        final internalDbPath = await _getInternalDbPath();
        final dbStat = await dbFile.stat();
        final dbSize = dbStat.size;
        final appDir = await getApplicationDocumentsDirectory();
        final freeSpace = await _getFreeInternalSpace(appDir.path);

        // בדיקת מקום פנוי לפני ניסיון ההעתקה
        // (גם "העבר" לא יעזור — הוא מעתיק לפנימי לפני מחיקת החיצוני)
        if (freeSpace > 0 && dbSize > freeSpace) {
          final needed = (dbSize / 1024 / 1024).toStringAsFixed(1);
          final free = (freeSpace / 1024 / 1024).toStringAsFixed(1);
          emit(
            _error(
              errorMessage:
                  'אין מספיק מקום פנוי באחסון הפנימי.\n'
                  'נדרש: $needed MB, פנוי: $free MB.\n'
                  'יש לפנות מקום ידנית ולנסות שוב.',
              selectedPath: directoryPath,
            ),
          );
          return;
        }

        // נסה להעתיק ישירות — עובד אם לאפליקציה יש READ_EXTERNAL_STORAGE
        emit(EmptyLibraryLoading(selectedPath: directoryPath));
        try {
          final destFile = File(internalDbPath);
          await destFile.parent.create(recursive: true);
          await File(dbFilePath).openRead().pipe(destFile.openWrite());

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
  static Future<String> _getInternalDbPath() async {
    final appDir = await getApplicationDocumentsDirectory();
    return path.join(
      appDir.path,
      'otzaria',
      DatabaseConstants.databaseFileName,
    );
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
  Future<String?> _checkSpaceForDownload({int? downloadSize}) async {
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
    const int kExtractSize = 6979321856; // 6.5 GB

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
  ///
  /// משמש כאשר הנתיב הפיזי אינו נגיש ל-dart:io ב-Android Scoped Storage.
  /// FilePicker.pickFiles() מטפל ב-SAF ומחזיר נתיב נגיש (מ-cache אם נדרש).
  Future<void> _onPickDbFileRequested(
    PickDbFileRequested event,
    Emitter<EmptyLibraryState> emit,
  ) async {
    try {
      final result = await FilePicker.pickFiles(
        allowMultiple: false,
        type: FileType.any,
        dialogTitle: 'בחר את קובץ ${DatabaseConstants.databaseFileName}',
        lockParentWindow: true,
      );

      if (result == null || result.files.isEmpty) {
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

      final pickedFile = result.files.first;

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

  /// מחלץ קובץ `.zst` של ה-DB. [outputDir] קובע לאן נחלץ ה-DB: null → תיקיית
  /// המקור (חילוץ במקום, עם שאלת מחיקת הקובץ הדחוס); ערך מפורש → מיקום יעד
  /// (ייבוא), ואז שומרים ובוחרים ישירות ללא שאלת מחיקה.
  Future<void> _handleZstFile(
    String zstFilePath,
    Emitter<EmptyLibraryState> emit, {
    String? outputDir,
  }) async {
    try {
      // יעד מפורש (ייבוא) גובר; אחרת חילוץ אל מיקום ברירת המחדל של הספרייה.
      final targetDir =
          outputDir ??
          _defaultLibraryPathOverride ??
          await AppPaths.getDefaultLibraryPath();
      await Directory(targetDir).create(recursive: true);
      final outputPath = path.join(
        targetDir,
        DatabaseConstants.databaseFileName,
      );

      emit(
        EmptyLibraryExtracting(
          selectedPath: zstFilePath,
          progress: 0.0,
          message: 'מחלץ קובץ DB דחוס...',
        ),
      );

      await _extractCompressedDatabase(
        zstFilePath,
        outputPath,
        _extractProgress(emit, zstFilePath, 'מחלץ קובץ DB דחוס...'),
      );

      // אם הקובץ שנבחר הוא ה-DB הראשי, חפש את 2 הקבצים האחרים של חבילת FULL
      // (קטלוג ו-תלמוד בבלי) באותה תיקייה וחלץ גם אותם. זה חוסך למשתמש
      // הורדה מהרשת של ~3GB אחרי שהוא כבר הוריד אותם בחבילת ה-FULL.
      final basename = path.basename(zstFilePath).toLowerCase();
      if (basename == DatabaseConstants.databaseArchiveFileName.toLowerCase()) {
        await _extractBundleSiblings(
          path.dirname(zstFilePath),
          targetDir,
          emit,
        );
      }

      emit(
        EmptyLibraryExtracting(
          selectedPath: zstFilePath,
          progress: 1.0,
          message: 'החילוץ הושלם',
        ),
      );

      // ייבוא ליעד — שומרים ובוחרים ישירות ומשאירים את קובץ המקור של המשתמש.
      if (outputDir != null) {
        await _checkAndSaveExtractedDatabase(targetDir, emit);
        return;
      }

      emit(
        EmptyLibraryAskingDeleteZip(
          zipPath: zstFilePath,
          extractedPath: targetDir,
        ),
      );
    } catch (e) {
      emit(
        _error(
          errorMessage: 'שגיאה בחילוץ קובץ דחוס: $e',
          selectedPath: zstFilePath,
        ),
      );
    }
  }

  /// מחלץ קבצי FULL bundle נלווים (קטלוג חיצוני ו-תלמוד בבלי) אם הם
  /// נמצאים ליד הארכיון הראשי שנבחר. best-effort: כישלון בקובץ אחד
  /// לא עוצר את האחרים, כי ה-DB הראשי כבר נחלץ בהצלחה והאפליקציה תוכל
  /// לעבוד גם בלי הקבצים הנלווים (הם יורדו דרך הזרימה הרגילה בעת הצורך).
  /// [sourceDir] — התיקייה שבה מחפשים את הארכיונים הנלווים (ליד ה-DB הראשי).
  /// [outputDir] — התיקייה שאליה מחלצים אותם (זהה ל-[sourceDir] בחילוץ במקום).
  Future<void> _extractBundleSiblings(
    String sourceDir,
    String outputDir,
    Emitter<EmptyLibraryState> emit,
  ) async {
    final catalogArchive = File(
      path.join(sourceDir, DatabaseConstants.externalCatalogArchiveFileName),
    );
    if (await catalogArchive.exists()) {
      try {
        emit(
          EmptyLibraryExtracting(
            selectedPath: catalogArchive.path,
            progress: 0.0,
            message: 'מחלץ קטלוג אוצר החכמה...',
          ),
        );
        await _extractCompressedDatabase(
          catalogArchive.path,
          path.join(
            outputDir,
            DatabaseConstants.externalCatalogDatabaseFileName,
          ),
          _extractProgress(
            emit,
            catalogArchive.path,
            'מחלץ קטלוג אוצר החכמה...',
          ),
        );
      } catch (e) {
        debugPrint('Failed to extract bundled catalog archive: $e');
      }
    }

    final talmudArchive = File(
      path.join(sourceDir, DatabaseConstants.talmudBavliArchiveFileName),
    );
    if (await talmudArchive.exists()) {
      try {
        emit(
          EmptyLibraryExtracting(
            selectedPath: talmudArchive.path,
            progress: 0.0,
            message: 'מחלץ ספרי תלמוד בבלי...',
          ),
        );
        await _extractTarArchive(
          talmudArchive.path,
          outputDir,
          _extractProgress(emit, talmudArchive.path, 'מחלץ ספרי תלמוד בבלי...'),
        );
      } catch (e) {
        debugPrint('Failed to extract bundled Talmud Bavli archive: $e');
      }
    }
  }

  Future<void> _handleZipFile(
    String zipFilePath,
    Emitter<EmptyLibraryState> emit, {
    String? outputDir,
  }) async {
    // ייבוא ליעד — מחלצים את הקובץ שנבחר ישירות אל תיקיית היעד.
    if (outputDir != null) {
      try {
        emit(
          EmptyLibraryExtracting(
            selectedPath: zipFilePath,
            progress: 0.1,
            message: 'מחלץ קובץ דחוס...',
          ),
        );
        await extractFileToDisk(zipFilePath, outputDir);
        await _checkAndSaveExtractedDatabase(outputDir, emit);
      } catch (e) {
        emit(_error(errorMessage: 'שגיאה בחילוץ קובץ דחוס: $e'));
      }
      return;
    }
    try {
      emit(
        const EmptyLibraryExtracting(
          selectedPath: '',
          progress: 0.0,
          message: 'מתחיל חילוץ...',
        ),
      );

      final libraryPath =
          _defaultLibraryPathOverride ?? await AppPaths.getDefaultLibraryPath();
      await Directory(libraryPath).create(recursive: true);

      final extractionResult =
          await ZipExtractorService.checkAndExtractZipIfNeeded(
            path.dirname(zipFilePath),
            outputDirectoryPath: libraryPath,
            onProgress: (p, m) {
              emit(
                EmptyLibraryExtracting(
                  selectedPath: zipFilePath,
                  progress: p,
                  message: m,
                ),
              );
            },
            onAskDeleteZip: () async => false,
          );

      if (!extractionResult.success) {
        emit(
          _error(
            errorMessage: extractionResult.errorMessage ?? 'שגיאה בחילוץ',
            zipFiles: extractionResult.zipFiles,
          ),
        );
        return;
      }

      // אם החילוץ הצליח, נשאל את המשתמש אם למחוק את ה-ZIP
      if (extractionResult.successfullyExtracted) {
        emit(
          EmptyLibraryAskingDeleteZip(
            zipPath: zipFilePath,
            extractedPath: libraryPath,
          ),
        );
        return;
      }

      // אם לא היה חילוץ, נמשיך ישירות לבדיקת הקובץ
      await _checkAndSaveExtractedDatabase(path.dirname(zipFilePath), emit);
    } catch (e) {
      emit(_error(errorMessage: 'שגיאה: $e'));
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
                entity.path.toLowerCase().endsWith(
                  DatabaseConstants.databaseFileName,
                ),
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
        ),
        _DownloadAsset(
          url:
              'https://github.com/Otzaria/otzaria-library/releases/latest/download/talmud_bavli_latest.tar.zst',
          tempFileName: 'otzaria_talmud_bavli.tar.zst',
          downloadTitle: 'מוריד את התלמוד הבבלי',
          extractTitle: 'מחלץ את התלמוד הבבלי',
          isTar: true,
        ),
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

  Future<void> _onDeleteZipAnswered(
    DeleteZipAnswered event,
    Emitter<EmptyLibraryState> emit,
  ) async {
    try {
      if (event.shouldDelete) {
        final zipFile = File(event.zipPath);
        if (await zipFile.exists()) {
          await zipFile.delete();
        }
      }

      // המשך לבדיקת הקובץ המחולץ
      await _checkAndSaveExtractedDatabase(event.extractedPath, emit);
    } catch (e) {
      emit(_error(errorMessage: 'שגיאה: $e'));
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
      final mb = (cumulative / 1024 / 1024).toStringAsFixed(1);
      final totalMb = (grandTotal / 1024 / 1024).toStringAsFixed(1);
      final eta = estimator.update(
        downloadedBytes: cumulative,
        totalBytes: grandTotal,
        now: DateTime.now(),
      );
      final etaLine = eta != null ? '\n${formatRemainingTimeHebrew(eta)}' : '';
      final resumeMb = (resumeFromBytes / 1024 / 1024).toStringAsFixed(1);
      final resumeLine = resumeFromBytes > 0
          ? '\nממשיך הורדה מ-$resumeMb MB'
          : '';
      emit(
        EmptyLibraryDownloading(
          progress: (cumulative / grandTotal).clamp(0.0, 1.0),
          message:
              '${asset.downloadTitle}$resumeLine\n$mb MB מתוך $totalMb MB$etaLine',
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
    await downloader.downloadToFile(
      url: asset.resolvedUrl!,
      destPath: tempPath,
      expectedSize: asset.compressedSize > 0 ? asset.compressedSize : null,
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
          // SqliteDataProvider פותח את seforim.db ב-WAL בעלייה אם הקובץ קיים —
          // גם אם הוא חלקי/פגום משריד הורדה קודמת. הסגירה משחררת את ה-handle
          // לדריסה, ומחיקת shm/wal מונעת מ-SQLite לקרוא WAL ישן ולבלבל את
          // ה-DB החדש.
          await SqliteDataProvider.instance.dispose();
          for (final suffix in const ['', '-shm', '-wal', '-journal']) {
            final f = File('$outputPath$suffix');
            if (await f.exists()) {
              try {
                await f.delete();
              } catch (_) {
                // הסטרימינג יטפל בשארית — אם המחיקה כשלה גם כאן, השגיאה
                // האמיתית תעלה משם עם הודעה ברורה יותר.
              }
            }
          }
        }

        await _extractCompressedDatabase(tempPath, outputPath, report);
      }
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
      throw Exception('לא נמצא קובץ seforim.db.zst ברליס האחרון');
    }

    return asset;
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

    for (final asset in assets) {
      if (asset is! Map<String, dynamic>) {
        continue;
      }

      final name = asset['name']?.toString() ?? '';
      final downloadUrl = asset['browser_download_url']?.toString() ?? '';
      if (name == 'seforim.db.zst' && downloadUrl.isNotEmpty) {
        return DatabaseReleaseAsset(assetName: name, downloadUrl: downloadUrl);
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
  });

  final String assetName;
  final String downloadUrl;
}
