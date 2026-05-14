import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'package:archive/archive.dart';
import 'package:bloc/bloc.dart';
import 'package:ffi/ffi.dart';
import 'package:zstandard_native/zstandard_native_bindings.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/data/constants/database_constants.dart';
import 'package:otzaria/empty_library/bloc/empty_library_event.dart';
import 'package:otzaria/empty_library/bloc/empty_library_state.dart';
import 'package:otzaria/settings/settings_exports.dart';
import 'package:otzaria/utils/file/zip_extractor_service.dart';
import 'package:path/path.dart' as path;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:zstandard/zstandard.dart';

class EmptyLibraryBloc extends Bloc<EmptyLibraryEvent, EmptyLibraryState> {
  EmptyLibraryBloc({
    http.Client? httpClient,
    Future<void> Function(String archivePath, String outputPath)?
        extractCompressedDatabase,
    Future<void> Function(String archivePath, String outputDir)?
        extractTarArchive,
    String? defaultLibraryPathOverride,
  })  : _httpClient = httpClient ?? http.Client(),
        _extractCompressedDatabase =
            extractCompressedDatabase ?? _extractZstWithSystemProcess,
        _extractTarArchive = extractTarArchive ?? _extractTarZst,
        _defaultLibraryPathOverride = defaultLibraryPathOverride,
        super(const EmptyLibraryInitial(
            downloadDisabledReason: 'בודק מקום פנוי...')) {
    on<PickDirectoryRequested>(_onPickDirectoryRequested);
    on<PickArchiveFileRequested>(_onPickArchiveFileRequested);
    on<DownloadLibraryRequested>(_onDownloadLibraryRequested);
    on<DeleteZipAnswered>(_onDeleteZipAnswered);
    on<PickDbFileRequested>(_onPickDbFileRequested);
    on<CheckDiskSpaceRequested>(_onCheckDiskSpaceRequested);
    // בדיקת מקום פנוי מתבצעת מיד — כפתור ההורדה מושבת עד להשלמתה
    add(CheckDiskSpaceRequested());
  }

  final http.Client _httpClient;
  final Future<void> Function(String archivePath, String outputPath)
      _extractCompressedDatabase;
  final Future<void> Function(String archivePath, String outputDir)
      _extractTarArchive;
  // סיבת השבתת כפתור ההורדה — נשמרת כ-instance field כדי להישמר בין state transitions
  String? _downloadDisabledReason = 'בודק מקום פנוי...';
  final String? _defaultLibraryPathOverride;

  Future<void> _onPickDirectoryRequested(
      PickDirectoryRequested event, Emitter<EmptyLibraryState> emit) async {
    final result = await FilePicker.getDirectoryPath(
      dialogTitle: 'בחר את תיקיית הספרייה (התיקייה שמכילה את seforim.db)',
    );

    if (result == null) return;

    emit(EmptyLibraryLoading(selectedPath: result));
    await _handleDirectorySelection(result, emit);
  }

  Future<void> _onPickArchiveFileRequested(
      PickArchiveFileRequested event, Emitter<EmptyLibraryState> emit) async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['zip', 'zst'],
      dialogTitle: 'בחר קובץ דחוס (ZIP או ZST)',
    );

    if (result == null || result.files.isEmpty) return;

    final selectedFile = result.files.first.path;
    if (selectedFile == null) return;

    emit(EmptyLibraryLoading(selectedPath: selectedFile));

    if (selectedFile.toLowerCase().endsWith('.zip')) {
      await _handleZipFile(selectedFile, emit);
    } else if (selectedFile.toLowerCase().endsWith('.zst')) {
      await _handleZstFile(selectedFile, emit);
    } else {
      emit(_error(
        errorMessage: 'סוג קובץ לא נתמך. בחר קובץ .zip או .zst',
        selectedPath: selectedFile,
      ));
    }
  }

  Future<void> _handleDirectorySelection(
      String directoryPath, Emitter<EmptyLibraryState> emit) async {
    try {
      final directory = Directory(directoryPath);
      if (!await directory.exists()) {
        emit(_error(
          errorMessage: 'התיקייה לא קיימת: $directoryPath',
          selectedPath: directoryPath,
        ));
        return;
      }

      // מחפש את המסד בתיקייה שנבחרה (ללא חיפוש עמוק)
      final dbFilePath =
          path.join(directoryPath, DatabaseConstants.databaseFileName);
      final dbFile = File(dbFilePath);

      if (!await dbFile.exists()) {
        emit(_error(
          errorMessage:
              'לא נמצא מסד הנתונים ${DatabaseConstants.databaseFileName} בתיקייה שנבחרה.',
          selectedPath: directoryPath,
        ));
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
          emit(_error(
            errorMessage:
                'אין מספיק מקום פנוי באחסון הפנימי.\n'
                'נדרש: $needed MB, פנוי: $free MB.\n'
                'יש לפנות מקום ידנית ולנסות שוב.',
            selectedPath: directoryPath,
          ));
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
              SettingsRepository.keyLibraryPath, directoryPath);
          await Settings.setValue(SettingsRepository.keyLibraryFolderName, '');
          await Settings.setValue(
              SettingsRepository.keyDbEffectivePath, internalDbPath);
          emit(EmptyLibraryDirectorySelected(selectedPath: directoryPath));
          return;
        } on PathAccessException {
          // dart:io לא יכול לגשת לקובץ — צריך FilePicker (SAF)
          // ממשיכים למטה להצגת הדיאלוג
        } catch (copyError) {
          // שגיאת I/O שאינה הרשאה (למשל ENOSPC, שגיאת קריאה)
          // מנקים קובץ יעד חלקי אם נוצר
          try { await File(internalDbPath).delete(); } catch (_) {}
          final isNoSpace = copyError.toString().contains('No space') ||
              copyError.toString().contains('ENOSPC');
          emit(_error(
            errorMessage: isNoSpace
                ? 'אין מספיק מקום פנוי. יש לפנות מקום ולנסות שוב.'
                : 'שגיאה בהעתקת קובץ הספרייה: $copyError',
            selectedPath: directoryPath,
          ));
          return;
        }
        // נגענו כאן רק אם PathAccessException — הדרך היחידה קדימה היא picker שני
        emit(EmptyLibraryAskingDbCopy(
          externalDbPath: dbFilePath,
          libraryPath: directoryPath,
          internalDbPath: internalDbPath,
          dbSizeBytes: dbSize,
          freeSpaceBytes: freeSpace,
        ));
        return;
      }

      await Settings.setValue(SettingsRepository.keyLibraryPath, directoryPath);
      await Settings.setValue(SettingsRepository.keyLibraryFolderName, '');
      // נקה override קודם אם קיים
      await Settings.setValue(SettingsRepository.keyDbEffectivePath, '');

      emit(EmptyLibraryDirectorySelected(selectedPath: directoryPath));
    } catch (e) {
      emit(_error(
        errorMessage: 'שגיאה בבדיקת התיקייה: $e',
        selectedPath: directoryPath,
      ));
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
        appDir.path, 'otzaria', DatabaseConstants.databaseFileName);
  }

  /// מחזיר מידע df עבור נתיב נתון: filesystem ומקום פנוי בבייטים.
  /// מחזיר freeBytes = -1 אם לא ניתן לקבוע.
  static Future<_DfInfo> _getDfInfo(String dirPath) async {
    if (!Platform.isAndroid) return const _DfInfo(filesystem: null, freeBytes: -1);
    try {
      final result =
          await Process.run('df', ['-B1', dirPath], runInShell: false);
      if (result.exitCode != 0) return const _DfInfo(filesystem: null, freeBytes: -1);
      final lines = result.stdout.toString().trim().split('\n');
      if (lines.length < 2) return const _DfInfo(filesystem: null, freeBytes: -1);
      // שורת הנתונים של df: Filesystem 1B-blocks Used Available Use% Mount
      final parts = lines.last.trim().split(RegExp(r'\s+'));
      if (parts.length < 4) return const _DfInfo(filesystem: null, freeBytes: -1);
      return _DfInfo(
        filesystem: parts[0],
        freeBytes: int.tryParse(parts[3]) ?? -1,
      );
    } catch (_) {
      return const _DfInfo(filesystem: null, freeBytes: -1);
    }
  }

  /// עוטף את _getDfInfo להחזרת מקום פנוי בלבד (לשימוש קיים).
  static Future<int> _getFreeInternalSpace(String dirPath) async =>
      (await _getDfInfo(dirPath)).freeBytes;

  /// בודק אם יש מספיק מקום פנוי להורדה ולחילוץ הספרייה.
  /// מחזיר הודעת שגיאה אם אין מספיק מקום, או null אם הכל תקין.
  /// מטפל גם בתרחיש שבו temp ותיקיית הספרייה חולקים אותו volume.
  Future<String?> _checkSpaceForDownload() async {
    if (!Platform.isAndroid) return null;
    const int kDownloadSize = 1610612736; // 1.5 GB
    const int kExtractSize = 6979321856; // 6.5 GB

    final tempPath = Directory.systemTemp.path;
    final libraryPath =
        _defaultLibraryPathOverride ?? await AppPaths.getDefaultLibraryPath();
    final checkPath = _findExistingAncestor(libraryPath);

    final tempInfo = await _getDfInfo(tempPath);
    final extractInfo = await _getDfInfo(checkPath);

    final sameVolume = tempInfo.filesystem != null &&
        extractInfo.filesystem != null &&
        tempInfo.filesystem == extractInfo.filesystem;

    if (sameVolume) {
      // שני הנתיבים על אותו volume: צריך מקום לשניהם יחד (1.5 + 6.5 = 8 GB)
      final free = tempInfo.freeBytes;
      if (free > 0 && free < kDownloadSize + kExtractSize) {
        final freeGb = (free / 1024 / 1024 / 1024).toStringAsFixed(1);
        return 'אין מספיק מקום פנוי להורדה ולחילוץ הספרייה.\n'
            'נדרש: לפחות 8 GB, פנוי: $freeGb GB.\n'
            'יש לפנות מקום ולנסות שוב.';
      }
    } else {
      // volumes נפרדים: בדיקה לכל אחד בנפרד
      if (tempInfo.freeBytes > 0 && tempInfo.freeBytes < kDownloadSize) {
        final freeGb =
            (tempInfo.freeBytes / 1024 / 1024 / 1024).toStringAsFixed(1);
        return 'אין מספיק מקום פנוי להורדת הקובץ הדחוס.\n'
            'נדרש: לפחות 1.5 GB, פנוי: $freeGb GB.\n'
            'יש לפנות מקום ולנסות שוב.';
      }
      if (extractInfo.freeBytes > 0 && extractInfo.freeBytes < kExtractSize) {
        final freeGb =
            (extractInfo.freeBytes / 1024 / 1024 / 1024).toStringAsFixed(1);
        return 'אין מספיק מקום פנוי לחילוץ הספרייה.\n'
            'נדרש: לפחות 6.5 GB, פנוי: $freeGb GB.\n'
            'יש לפנות מקום ולנסות שוב.';
      }
    }
    return null;
  }

  Future<void> _onCheckDiskSpaceRequested(
      CheckDiskSpaceRequested event, Emitter<EmptyLibraryState> emit) async {
    _downloadDisabledReason = await _checkSpaceForDownload();
    emit(EmptyLibraryInitial(downloadDisabledReason: _downloadDisabledReason));
  }

  /// מייצר EmptyLibraryError תמיד עם downloadDisabledReason הנוכחי.
  EmptyLibraryError _error({
    String? errorMessage,
    String? selectedPath,
    List<String>? zipFiles,
  }) =>
      EmptyLibraryError(
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
      PickDbFileRequested event, Emitter<EmptyLibraryState> emit) async {
    try {
      final result = await FilePicker.pickFiles(
        allowMultiple: false,
        type: FileType.any,
        dialogTitle: 'בחר את קובץ ${DatabaseConstants.databaseFileName}',
      );

      if (result == null || result.files.isEmpty) {
        // המשתמש ביטל — חזרה לדיאלוג ההעתקה
        final internalDbPath = await _getInternalDbPath();
        emit(EmptyLibraryAskingDbCopy(
          externalDbPath: '',
          libraryPath: event.libraryPath,
          internalDbPath: internalDbPath,
          dbSizeBytes: 0,
          freeSpaceBytes: -1,
        ));
        return;
      }

      final pickedFile = result.files.first;

      // וודא שנבחר הקובץ הנכון — אם לא, חזור לדיאלוג עם הסבר
      if (pickedFile.name != DatabaseConstants.databaseFileName) {
        final internalDbPath = await _getInternalDbPath();
        emit(EmptyLibraryAskingDbCopy(
          externalDbPath: event.externalDbPath,
          libraryPath: event.libraryPath,
          internalDbPath: internalDbPath,
          dbSizeBytes: 0,
          freeSpaceBytes: -1,
          errorMessage:
              'יש לבחור את הקובץ ${DatabaseConstants.databaseFileName}. '
              'נבחר: "${pickedFile.name}" — נסה שוב.',
        ));
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
          SettingsRepository.keyLibraryPath, event.libraryPath);
      await Settings.setValue(SettingsRepository.keyLibraryFolderName, '');
      await Settings.setValue(
          SettingsRepository.keyDbEffectivePath, event.internalDbPath);

      emit(EmptyLibraryDirectorySelected(selectedPath: event.libraryPath));
    } catch (e) {
      // זיהוי שגיאת חוסר מקום (ENOSPC / No space left)
      final isNoSpace = e.toString().contains('No space') ||
          e.toString().contains('ENOSPC') ||
          e.toString().contains('28');
      final msg = isNoSpace
          ? 'אין מספיק מקום פנוי. בחר "העבר" (מחיקת מקור) כדי לפנות מקום, '
              'או פנה מקום ידנית ונסה שוב.'
          : 'שגיאה בהעתקת קובץ הספרייה: $e';
      emit(_error(
        errorMessage: msg,
        selectedPath: event.libraryPath,
      ));
    }
  }

  Future<void> _handleZstFile(
      String zstFilePath, Emitter<EmptyLibraryState> emit) async {
    try {
      final outputPath = path.join(
        path.dirname(zstFilePath),
        DatabaseConstants.databaseFileName,
      );

      emit(EmptyLibraryExtracting(
        selectedPath: zstFilePath,
        progress: 0.0,
        message: 'מחלץ קובץ DB דחוס...',
      ));

      await _extractCompressedDatabase(zstFilePath, outputPath);

      emit(EmptyLibraryExtracting(
        selectedPath: zstFilePath,
        progress: 1.0,
        message: 'החילוץ הושלם',
      ));

      emit(EmptyLibraryAskingDeleteZip(
        zipPath: zstFilePath,
        extractedPath: path.dirname(zstFilePath),
      ));
    } catch (e) {
      emit(_error(
        errorMessage: 'שגיאה בחילוץ קובץ דחוס: $e',
        selectedPath: zstFilePath,
      ));
    }
  }

  Future<void> _handleZipFile(
      String zipFilePath, Emitter<EmptyLibraryState> emit) async {
    try {
      emit(const EmptyLibraryExtracting(
        selectedPath: '',
        progress: 0.0,
        message: 'מתחיל חילוץ...',
      ));

      final extractionResult =
          await ZipExtractorService.checkAndExtractZipIfNeeded(
        path.dirname(zipFilePath),
        onProgress: (p, m) {
          emit(EmptyLibraryExtracting(
            selectedPath: zipFilePath,
            progress: p,
            message: m,
          ));
        },
        onAskDeleteZip: () async => false,
      );

      if (!extractionResult.success) {
        emit(_error(
          errorMessage: extractionResult.errorMessage ?? 'שגיאה בחילוץ',
          zipFiles: extractionResult.zipFiles,
        ));
        return;
      }

      // אם החילוץ הצליח, נשאל את המשתמש אם למחוק את ה-ZIP
      if (extractionResult.successfullyExtracted) {
        emit(EmptyLibraryAskingDeleteZip(
          zipPath: zipFilePath,
          extractedPath: path.dirname(zipFilePath),
        ));
        return;
      }

      // אם לא היה חילוץ, נמשיך ישירות לבדיקת הקובץ
      await _checkAndSaveExtractedDatabase(path.dirname(zipFilePath), emit);
    } catch (e) {
      emit(_error(
        errorMessage: 'שגיאה: $e',
      ));
    }
  }

  Future<void> _checkAndSaveExtractedDatabase(
      String extractedDirectory, Emitter<EmptyLibraryState> emit) async {
    try {
      // חיפוש קובץ seforim.db בתיקייה המחולצת
      final directory = Directory(extractedDirectory);
      final dbFiles = await directory
          .list(recursive: true)
          .where((entity) =>
              entity is File &&
              entity.path
                  .toLowerCase()
                  .endsWith(DatabaseConstants.databaseFileName))
          .cast<File>()
          .toList();

      if (dbFiles.isEmpty) {
        emit(_error(
          errorMessage:
              'לא נמצא קובץ ${DatabaseConstants.databaseFileName} בקובץ הדחוס',
          selectedPath: extractedDirectory,
        ));
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
      emit(_error(
        errorMessage: 'שגיאה: $e',
      ));
    }
  }

  Future<void> _onDownloadLibraryRequested(
      DownloadLibraryRequested event, Emitter<EmptyLibraryState> emit) async {
    try {
      // בדיקת מקום פנוי (safety net — מכסה מצב שהדיסק התמלא אחרי טעינת המסך)
      final spaceError = await _checkSpaceForDownload();
      if (spaceError != null) {
        _downloadDisabledReason = spaceError;
        emit(_error(errorMessage: spaceError));
        return;
      }

      final libraryPath =
          _defaultLibraryPathOverride ?? await AppPaths.getDefaultLibraryPath();
      final latestAsset = await _fetchLatestDatabaseAsset();

      // קובץ temp קבוע — נשמר בין ניסיונות לצורך resume
      final tempArchivePath = path.join(
        Directory.systemTemp.path,
        'otzaria_${latestAsset.assetName}',
      );
      final tempArchive = File(tempArchivePath);

      // בדיקת כמה כבר הורדנו (resume)
      var alreadyDownloaded =
          await tempArchive.exists() ? await tempArchive.length() : 0;

      emit(EmptyLibraryDownloading(
        progress: 0.0,
        message: alreadyDownloaded > 0
            ? 'ממשיך הורדה מ-${(alreadyDownloaded / 1024 / 1024).toStringAsFixed(1)} MB...'
            : 'מתחבר לשרת...',
      ));

      // פותרים redirect ידנית כדי לשמור על Range header
      // (package:http מאבד headers בעת redirect)
      final resolvedUrl = await _resolveRedirect(latestAsset.downloadUrl);

      final request = http.Request('GET', Uri.parse(resolvedUrl));
      if (alreadyDownloaded > 0) {
        request.headers['Range'] = 'bytes=$alreadyDownloaded-';
      }
      final response = await _httpClient.send(request);

      // 200 = הורדה מלאה מחדש, 206 = המשך (partial content)
      if (response.statusCode == 200) {
        // השרת לא תומך ב-Range — מתחילים מחדש
        alreadyDownloaded = 0;
        await tempArchive.delete().catchError((_) => tempArchive);
      } else if (response.statusCode != 206) {
        emit(EmptyLibraryError(
          errorMessage: 'שגיאה בהורדה: ${response.statusCode}',
        ));
        return;
      }

      // וידוא שה-resume אכן עבד לפי Content-Range header
      // אם השרת החזיר 206 אבל מ-0, נתאים את alreadyDownloaded
      if (response.statusCode == 206) {
        final contentRange = response.headers['content-range'];
        if (contentRange != null) {
          // פורמט: "bytes START-END/TOTAL"
          final match = RegExp(r'bytes (\d+)-').firstMatch(contentRange);
          if (match != null) {
            final serverStart = int.tryParse(match.group(1)!) ?? 0;
            if (serverStart == 0 && alreadyDownloaded > 0) {
              // השרת התחיל מ-0 למרות הבקשה — מחיקת הקובץ החלקי
              alreadyDownloaded = 0;
              await tempArchive.delete().catchError((_) => tempArchive);
            }
          }
        }
      }

      final contentLength = response.contentLength ?? 0;
      final totalLength =
          contentLength > 0 ? contentLength + alreadyDownloaded : 0;
      var downloadedBytes = alreadyDownloaded;

      final sink = tempArchive.openWrite(
        mode: alreadyDownloaded > 0 ? FileMode.append : FileMode.write,
      );

      try {
        await for (var chunk in response.stream) {
          sink.add(chunk);
          downloadedBytes += chunk.length;

          if (totalLength > 0) {
            final progress = downloadedBytes / totalLength;
            final mb = (downloadedBytes / 1024 / 1024).toStringAsFixed(1);
            final totalMb = (totalLength / 1024 / 1024).toStringAsFixed(1);
            emit(EmptyLibraryDownloading(
              progress: progress,
              message: 'מוריד... $mb MB מתוך $totalMb MB',
            ));
          }
        }
      } finally {
        await sink.close();
      }

      // יצירת תיקיית הספרייה אם לא קיימת
      final libraryDir = Directory(libraryPath);
      if (!await libraryDir.exists()) {
        await libraryDir.create(recursive: true);
      }

      final outputPath = path.join(
        libraryPath,
        DatabaseConstants.databaseFileName,
      );

      emit(EmptyLibraryExtracting(
        selectedPath: tempArchivePath,
        progress: 0.0,
        message: 'מחלץ קובץ DB דחוס...',
      ));

      await _extractCompressedDatabase(tempArchivePath, outputPath);

      // מחיקת קובץ ה-temp לאחר חילוץ מוצלח
      await tempArchive.delete().catchError((_) => tempArchive);

      emit(EmptyLibraryExtracting(
        selectedPath: tempArchivePath,
        progress: 1.0,
        message: 'החילוץ הושלם',
      ));

      await Settings.setValue(SettingsRepository.keyLibraryPath, libraryPath);
      await Settings.setValue(SettingsRepository.keyLibraryFolderName, '');
      // ניקוי override Android — ה-DB החדש נמצא ישירות בספרייה
      await Settings.setValue(SettingsRepository.keyDbEffectivePath, '');

      // הורדת תלמוד בבלי
      await _downloadAndExtractAsset(
        url: 'https://github.com/Otzaria/otzaria-library/releases/latest/download/talmud_bavli_latest.tar.zst',
        tempFileName: 'otzaria_talmud_bavli.tar.zst',
        statusMessage: 'מוריד תלמוד בבלי...',
        outputDir: libraryPath,
        isTar: true,
        emit: emit,
      );

      // הורדת קטלוגים
      await _downloadAndExtractAsset(
        url: 'https://github.com/Otzaria/otzar-HB_catalog/releases/latest/download/otzar-HB_catalog.db.zst',
        tempFileName: 'otzaria_otzar-HB_catalog.db.zst',
        statusMessage: 'מוריד קטלוגים...',
        outputDir: libraryPath,
        outputFileName: DatabaseConstants.externalCatalogDatabaseFileName,
        isTar: false,
        emit: emit,
      );

      emit(EmptyLibraryDirectorySelected(selectedPath: libraryPath));
    } catch (e) {
      // קובץ ה-temp נשמר בכוונה — ישמש ל-resume בניסיון הבא
      emit(EmptyLibraryError(
        errorMessage: 'שגיאה בהורדה: $e\nניתן ללחוץ שוב כדי להמשיך מהנקודה שנעצרה.',
      ));
    }
  }

  Future<void> _onDeleteZipAnswered(
      DeleteZipAnswered event, Emitter<EmptyLibraryState> emit) async {
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
      emit(_error(
        errorMessage: 'שגיאה: $e',
      ));
    }
  }

  /// עוזר כללי: מוריד קובץ (עם resume), מחלץ אותו ומוחק את ה-temp.
  /// [isTar] = true → מחלץ tar.zst לתיקייה [outputDir]
  /// [isTar] = false → מחלץ .zst לקובץ [outputDir]/[outputFileName]
  Future<void> _downloadAndExtractAsset({
    required String url,
    required String tempFileName,
    required String statusMessage,
    required String outputDir,
    required bool isTar,
    required Emitter<EmptyLibraryState> emit,
    String? outputFileName,
  }) async {
    final tempPath = path.join(Directory.systemTemp.path, tempFileName);
    final tempFile = File(tempPath);

    var alreadyDownloaded =
        await tempFile.exists() ? await tempFile.length() : 0;

    emit(EmptyLibraryDownloading(
      progress: alreadyDownloaded > 0 ? 0.0 : 0.0,
      message: alreadyDownloaded > 0
          ? '$statusMessage (ממשיך מ-${(alreadyDownloaded / 1024 / 1024).toStringAsFixed(1)} MB)'
          : statusMessage,
    ));

    final resolvedUrl = await _resolveRedirect(url);
    final request = http.Request('GET', Uri.parse(resolvedUrl));
    if (alreadyDownloaded > 0) {
      request.headers['Range'] = 'bytes=$alreadyDownloaded-';
    }
    final response = await _httpClient.send(request);

    if (response.statusCode == 200) {
      alreadyDownloaded = 0;
      await tempFile.delete().catchError((_) => tempFile);
    } else if (response.statusCode == 206) {
      final contentRange = response.headers['content-range'];
      if (contentRange != null) {
        final match = RegExp(r'bytes (\d+)-').firstMatch(contentRange);
        if (match != null) {
          final serverStart = int.tryParse(match.group(1)!) ?? 0;
          if (serverStart == 0 && alreadyDownloaded > 0) {
            // השרת התחיל מ-0 למרות הבקשה — מחיקת הקובץ החלקי
            alreadyDownloaded = 0;
            await tempFile.delete().catchError((_) => tempFile);
          } else {
            // וידוא שה-offset תואם למה שהשרת אישר
            alreadyDownloaded = serverStart;
          }
        }
      }
    } else {
      // שגיאת HTTP — זורקים כדי שהמשתמש יידע
      throw Exception('שגיאה בהורדת $statusMessage: ${response.statusCode}');
    }

    final contentLength = response.contentLength ?? 0;
    final totalLength =
        contentLength > 0 ? contentLength + alreadyDownloaded : 0;
    var downloadedBytes = alreadyDownloaded;

    final sink = tempFile.openWrite(
      mode: alreadyDownloaded > 0 ? FileMode.append : FileMode.write,
    );
    try {
      await for (final chunk in response.stream) {
        sink.add(chunk);
        downloadedBytes += chunk.length;
        if (totalLength > 0) {
          final mb = (downloadedBytes / 1024 / 1024).toStringAsFixed(1);
          final totalMb = (totalLength / 1024 / 1024).toStringAsFixed(1);
          emit(EmptyLibraryDownloading(
            progress: downloadedBytes / totalLength,
            message: '$statusMessage $mb MB / $totalMb MB',
          ));
        }
      }
    } finally {
      await sink.close();
    }

    emit(EmptyLibraryExtracting(
      selectedPath: tempPath,
      progress: 0.0,
      message: 'מחלץ...',
    ));

    if (isTar) {
      await _extractTarArchive(tempPath, outputDir);
    } else {
      final outPath = path.join(outputDir, outputFileName!);
      await _extractCompressedDatabase(tempPath, outPath);
    }

    await tempFile.delete().catchError((_) => tempFile);
  }

  /// מחלץ קובץ tar.zst לתיקיית היעד.
  /// רץ ב-isolate נפרד כדי למנוע חסימת UI וכדי שהזיכרון ישוחרר בסיום.
  static Future<void> _extractTarZst(
      String archivePath, String outputDir) async {
    await compute(_extractTarZstIsolate, [archivePath, outputDir]);
  }

  static Future<void> _extractTarZstIsolate(List<String> args) async {
    final archivePath = args[0];
    final outputDir = args[1];

    final compressedBytes = await File(archivePath).readAsBytes();
    final tarBytes = await Zstandard().decompress(compressedBytes);
    if (tarBytes == null) {
      throw Exception('חילוץ ZST נכשל: $archivePath');
    }

    final archive = TarDecoder().decodeBytes(tarBytes);
    for (final file in archive.files) {
      final filePath = path.join(outputDir, file.name);
      if (file.isFile) {
        final outFile = File(filePath);
        await outFile.parent.create(recursive: true);
        await outFile.writeAsBytes(file.content as List<int>);
      } else {
        await Directory(filePath).create(recursive: true);
      }
    }
  }

  /// עוקב אחרי redirects ידנית כדי לקבל את ה-URL הסופי.
  /// נדרש כי package:http מאבד את ה-Range header בעת redirect.
  Future<String> _resolveRedirect(String url) async {
    var current = Uri.parse(url);
    for (var i = 0; i < 5; i++) {
      final request = http.Request('HEAD', current)
        ..followRedirects = false;
      final response = await _httpClient.send(request);
      if (response.statusCode >= 300 && response.statusCode < 400) {
        final location = response.headers['location'];
        if (location == null) break;
        // תמיכה ב-Location יחסי
        current = current.resolve(location);
      } else {
        break;
      }
    }
    return current.toString();
  }

  Future<DatabaseReleaseAsset> _fetchLatestDatabaseAsset() async {
    final response = await _httpClient.get(
      Uri.parse(
        'https://api.github.com/repos/Otzaria/SeforimLibrary/releases/latest',
      ),
      headers: const {
        'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
      },
    );

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
      Map<String, dynamic> releaseJson) {
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
        return DatabaseReleaseAsset(
          assetName: name,
          downloadUrl: downloadUrl,
        );
      }
    }

    return null;
  }

  static Future<void> _extractZstWithSystemProcess(
    String archivePath,
    String outputPath,
  ) async {
    if (Platform.isAndroid) {
      // ב-Android טוענים את כל הקובץ לזיכרון RAM (1.5 GB דחוס + 6.5 GB פרוס)
      // גורם לקריסה על מכשירים עם 4-6 GB RAM.
      // במקום זאת, משתמשים ב-ZSTD streaming API שמעבד בנתחים של ~128 KB.
      await Isolate.run(
          () => _decompressZstStreaming(archivePath, outputPath));
      return;
    }
    final compressedBytes = await File(archivePath).readAsBytes();
    final decompressed = await Zstandard().decompress(compressedBytes);
    if (decompressed == null) {
      throw Exception('חילוץ קובץ ZST נכשל: $archivePath');
    }
    final outputFile = File(outputPath);
    if (await outputFile.exists()) {
      await outputFile.delete();
    }
    await outputFile.writeAsBytes(decompressed, flush: true);
  }

  /// חילוץ ZST streaming דרך ZSTD FFI — רץ ב-isolate נפרד.
  /// מעבד את הקובץ בנתחים של ~128 KB ישירות לדיסק.
  /// שימוש ב-RAM: כמה מאות KB בלבד (במקום ~8 GB).
  static void _decompressZstStreaming(
      String archivePath, String outputPath) {
    final dylib = DynamicLibrary.open('libzstandard_android.so');
    final bindings = ZstandardNativeBindings(dylib);

    final inBufSize = bindings.ZSTD_DStreamInSize();
    final outBufSize = bindings.ZSTD_DStreamOutSize();

    final dStream = bindings.ZSTD_createDStream();
    if (dStream == nullptr) throw Exception('ZSTD_createDStream נכשל');

    try {
      final initRet = bindings.ZSTD_initDStream(dStream);
      if (bindings.ZSTD_isError(initRet) != 0) {
        throw Exception('ZSTD_initDStream נכשל: $initRet');
      }

      final inNative = malloc.allocate<Uint8>(inBufSize);
      final outNative = malloc.allocate<Uint8>(outBufSize);
      final inBuf = malloc<ZSTD_inBuffer_s>();
      final outBuf = malloc<ZSTD_outBuffer_s>();

      try {
        final inputRaf = File(archivePath).openSync();
        final outFile = File(outputPath);
        if (outFile.existsSync()) outFile.deleteSync();
        final outputRaf = outFile.openSync(mode: FileMode.writeOnly);

        try {
          final inView = inNative.asTypedList(inBufSize);

          // 0 = frame הושלם, >0 = עדיין נתונים בממתנה, <0 = שגיאה
          int lastRet = 0;

          while (true) {
            final bytesRead = inputRaf.readIntoSync(inView);
            if (bytesRead == 0) break;

            inBuf.ref.src = inNative.cast();
            inBuf.ref.size = bytesRead;
            inBuf.ref.pos = 0;

            while (inBuf.ref.pos < inBuf.ref.size) {
              outBuf.ref.dst = outNative.cast();
              outBuf.ref.size = outBufSize;
              outBuf.ref.pos = 0;

              lastRet =
                  bindings.ZSTD_decompressStream(dStream, outBuf, inBuf);

              if (bindings.ZSTD_isError(lastRet) != 0) {
                throw Exception('שגיאת ZSTD בחילוץ (קוד: $lastRet)');
              }

              if (outBuf.ref.pos > 0) {
                outputRaf
                    .writeFromSync(outNative.asTypedList(outBuf.ref.pos));
              }
            }
          }

          // לפי תיעוד ZSTD: ערך חזרה > 0 אחרי EOF = frame לא הושלם (קובץ קטוע/פגום)
          if (lastRet != 0) {
            throw Exception(
              'קובץ ה-ZST קטוע או פגום: ה-frame לא הושלם (נותרו $lastRet bytes לפענוח)',
            );
          }

          outputRaf.flushSync();
        } finally {
          inputRaf.closeSync();
          outputRaf.closeSync();
        }
      } finally {
        malloc.free(inNative);
        malloc.free(outNative);
        malloc.free(inBuf);
        malloc.free(outBuf);
      }
    } finally {
      bindings.ZSTD_freeDStream(dStream);
    }
  }
}

/// תוצאת קריאת df עבור נתיב נתון.
class _DfInfo {
  const _DfInfo({required this.filesystem, required this.freeBytes});
  final String? filesystem;
  final int freeBytes;
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
