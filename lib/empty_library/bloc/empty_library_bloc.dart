import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'package:archive/archive.dart';
import 'package:bloc/bloc.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/data/constants/database_constants.dart';
import 'package:otzaria/empty_library/bloc/empty_library_event.dart';
import 'package:otzaria/empty_library/bloc/empty_library_state.dart';
import 'package:otzaria/settings/settings_exports.dart';
import 'package:otzaria/utils/zip_extractor_service.dart';
import 'package:path/path.dart' as path;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:zstandard/zstandard.dart';

class EmptyLibraryBloc extends Bloc<EmptyLibraryEvent, EmptyLibraryState> {
  EmptyLibraryBloc({
    http.Client? httpClient,
    Future<void> Function(String archivePath, String outputPath)?
        extractCompressedDatabase,
    Future<void> Function(String archivePath, String outputDirectory)?
        extractCompressedTarArchive,
    String? defaultLibraryPathOverride,
  })  : _httpClient = httpClient ?? http.Client(),
        _extractCompressedDatabase =
            extractCompressedDatabase ?? _extractZstWithSystemProcess,
        _extractCompressedTarArchive =
            extractCompressedTarArchive ?? _extractTarZstWithArchive,
        _defaultLibraryPathOverride = defaultLibraryPathOverride,
        super(EmptyLibraryInitial()) {
    on<PickDirectoryRequested>(_onPickDirectoryRequested);
    on<PickArchiveFileRequested>(_onPickArchiveFileRequested);
    on<DownloadLibraryRequested>(_onDownloadLibraryRequested);
    on<DeleteZipAnswered>(_onDeleteZipAnswered);
    on<PickDbFileRequested>(_onPickDbFileRequested);
  }

  final http.Client _httpClient;
  final Future<void> Function(String archivePath, String outputPath)
      _extractCompressedDatabase;
  final Future<void> Function(String archivePath, String outputDirectory)
      _extractCompressedTarArchive;
  final String? _defaultLibraryPathOverride;

  Future<void> _onPickDirectoryRequested(
      PickDirectoryRequested event, Emitter<EmptyLibraryState> emit) async {
    final result = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'בחר את תיקיית הספרייה (התיקייה שמכילה את seforim.db)',
    );

    if (result == null) return;

    emit(EmptyLibraryLoading(selectedPath: result));
    await _handleDirectorySelection(result, emit);
  }

  Future<void> _onPickArchiveFileRequested(
      PickArchiveFileRequested event, Emitter<EmptyLibraryState> emit) async {
    final result = await FilePicker.platform.pickFiles(
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
      emit(EmptyLibraryError(
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
        emit(EmptyLibraryError(
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
        emit(EmptyLibraryError(
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
          emit(EmptyLibraryError(
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
          emit(EmptyLibraryError(
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
      emit(EmptyLibraryError(
        errorMessage: 'שגיאה בבדיקת התיקייה: $e',
        selectedPath: directoryPath,
      ));
    }
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

  /// מחזיר הערכה של המקום הפנוי באחסון הפנימי (בייטים) ב-Android.
  /// משתמש בפקודת `df -B1` שנהיגה בכל מכשירי Android.
  /// מחזיר -1 אם לא ניתן לקבוע (לא Android, שגיאה, וכו').
  static Future<int> _getFreeInternalSpace(String dirPath) async {
    if (!Platform.isAndroid) return -1;
    try {
      final result =
          await Process.run('df', ['-B1', dirPath], runInShell: false);
      if (result.exitCode != 0) return -1;
      final lines =
          result.stdout.toString().trim().split('\n');
      if (lines.length < 2) return -1;
      // שורת הנתונים של df: Filesystem 1B-blocks Used Available Use% Mount
      final parts = lines.last.trim().split(RegExp(r'\s+'));
      if (parts.length < 4) return -1;
      return int.tryParse(parts[3]) ?? -1;
    } catch (_) {
      return -1;
    }
  }

  /// בוחר את קובץ seforim.db ישירות דרך FilePicker (SAF-aware).
  ///
  /// משמש כאשר הנתיב הפיזי אינו נגיש ל-dart:io ב-Android Scoped Storage.
  /// FilePicker.pickFiles() מטפל ב-SAF ומחזיר נתיב נגיש (מ-cache אם נדרש).
  Future<void> _onPickDbFileRequested(
      PickDbFileRequested event, Emitter<EmptyLibraryState> emit) async {
    try {
      final result = await FilePicker.platform.pickFiles(
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
      emit(EmptyLibraryError(
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
      emit(EmptyLibraryError(
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
        emit(EmptyLibraryError(
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
      emit(EmptyLibraryError(
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
        emit(EmptyLibraryError(
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
      emit(EmptyLibraryError(
        errorMessage: 'שגיאה: $e',
      ));
    }
  }

  Future<void> _onDownloadLibraryRequested(
      DownloadLibraryRequested event, Emitter<EmptyLibraryState> emit) async {
    File? tempDbArchive;
    File? tempTalmudArchive;
    try {
      // קבלת נתיב ברירת מחדל של הספרייה ויצירתו אם לא קיים
      final libraryPath =
          _defaultLibraryPathOverride ?? await AppPaths.getDefaultLibraryPath();
      final libraryDir = Directory(libraryPath);
      if (!await libraryDir.exists()) {
        await libraryDir.create(recursive: true);
      }

      final assets = await _fetchLatestLibraryAssets();

      // === שלב 1: מסד הנתונים ===
      final tempDbArchivePath = path.join(
        Directory.systemTemp.path,
        'otzaria_${assets.dbAssetName}',
      );
      tempDbArchive = File(tempDbArchivePath);

      emit(const EmptyLibraryDownloading(
        progress: 0.0,
        message: 'מתחבר לשרת להורדת מסד נתונים...',
      ));

      await _downloadFile(
        url: assets.dbDownloadUrl,
        outputFile: tempDbArchive,
        onProgress: (progress, downloadedMb, totalMb) {
          emit(EmptyLibraryDownloading(
            progress: progress,
            message: 'מוריד מסד נתונים... $downloadedMb MB מתוך $totalMb MB',
          ));
        },
      );

      // === שלב 2: תלמוד בבלי ===
      final tempTalmudArchivePath = path.join(
        Directory.systemTemp.path,
        'otzaria_${assets.talmudAssetName}',
      );
      tempTalmudArchive = File(tempTalmudArchivePath);

      emit(const EmptyLibraryDownloading(
        progress: 0.0,
        message: 'מתחבר לשרת להורדת תלמוד בבלי...',
      ));

      await _downloadFile(
        url: assets.talmudDownloadUrl,
        outputFile: tempTalmudArchive,
        onProgress: (progress, downloadedMb, totalMb) {
          emit(EmptyLibraryDownloading(
            progress: progress,
            message: 'מוריד תלמוד בבלי... $downloadedMb MB מתוך $totalMb MB',
          ));
        },
      );

      // === שלב 3: חילוץ מסד הנתונים ===
      final outputPath = path.join(
        libraryPath,
        DatabaseConstants.databaseFileName,
      );

      emit(EmptyLibraryExtracting(
        selectedPath: tempDbArchivePath,
        progress: 0.0,
        message: 'מחלץ מסד נתונים...',
      ));

      await _extractCompressedDatabase(tempDbArchivePath, outputPath);

      // מחיקת קובץ ה-temp של מסד הנתונים מיד לאחר חילוץ מוצלח
      await tempDbArchive.delete();
      tempDbArchive = null;

      // === שלב 4: חילוץ תלמוד בבלי ===
      final talmudOutputPath = libraryPath;

      emit(EmptyLibraryExtracting(
        selectedPath: tempTalmudArchivePath,
        progress: 0.0,
        message: 'מחלץ תלמוד בבלי...',
      ));

      await _extractCompressedTarArchive(tempTalmudArchivePath, talmudOutputPath);

      // מחיקת קובץ ה-temp של תלמוד בבלי
      await tempTalmudArchive.delete();
      tempTalmudArchive = null;

      emit(EmptyLibraryExtracting(
        selectedPath: libraryPath,
        progress: 1.0,
        message: 'ההתקנה הושלמה',
      ));

      await Settings.setValue(SettingsRepository.keyLibraryPath, libraryPath);
      await Settings.setValue(SettingsRepository.keyLibraryFolderName, '');
      // ניקוי override Android — ה-DB החדש נמצא ישירות בספרייה
      await Settings.setValue(SettingsRepository.keyDbEffectivePath, '');

      emit(EmptyLibraryDirectorySelected(selectedPath: libraryPath));
    } catch (e) {
      emit(EmptyLibraryError(
        errorMessage: 'שגיאה בהורדה: $e',
      ));
    } finally {
      // מחיקת קובצי temp תמיד, גם במקרה שגיאה
      if (tempDbArchive != null && await tempDbArchive.exists()) {
        await tempDbArchive.delete();
      }
      if (tempTalmudArchive != null && await tempTalmudArchive.exists()) {
        await tempTalmudArchive.delete();
      }
    }
  }

  Future<void> _downloadFile({
    required String url,
    required File outputFile,
    required void Function(double progress, String downloadedMb, String totalMb) onProgress,
  }) async {
    final request = http.Request('GET', Uri.parse(url));
    final response = await _httpClient.send(request);

    if (response.statusCode != 200) {
      throw Exception('שגיאה בהורדה: ${response.statusCode}');
    }

    final contentLength = response.contentLength ?? 0;
    var downloadedBytes = 0;
    final sink = outputFile.openWrite();

    try {
      await for (var chunk in response.stream) {
        sink.add(chunk);
        downloadedBytes += chunk.length;

        if (contentLength > 0) {
          final progress = downloadedBytes / contentLength;
          final mb = (downloadedBytes / 1024 / 1024).toStringAsFixed(1);
          final totalMb = (contentLength / 1024 / 1024).toStringAsFixed(1);
          onProgress(progress, mb, totalMb);
        }
      }
    } finally {
      await sink.close();
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
      emit(EmptyLibraryError(
        errorMessage: 'שגיאה: $e',
      ));
    }
  }

  Future<LibraryReleaseAssets> _fetchLatestLibraryAssets() async {
    // 1. קבלת נתוני מסד הנתונים מ-SeforimLibrary
    final dbResponse = await _httpClient.get(
      Uri.parse(
        'https://api.github.com/repos/Otzaria/SeforimLibrary/releases/latest',
      ),
      headers: const {
        'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
      },
    );

    if (dbResponse.statusCode != 200) {
      throw Exception('שגיאה בקבלת הרליס האחרון של מסד הנתונים: ${dbResponse.statusCode}');
    }

    final dbDecoded = jsonDecode(utf8.decode(dbResponse.bodyBytes));
    if (dbDecoded is! Map<String, dynamic>) {
      throw Exception('מבנה תשובת GitHub עבור מסד הנתונים אינו תקין');
    }

    // 2. קבלת נתוני התלמוד בבלי מ-otzaria-library
    final talmudResponse = await _httpClient.get(
      Uri.parse(
        'https://api.github.com/repos/Otzaria/otzaria-library/releases/latest',
      ),
      headers: const {
        'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
      },
    );

    if (talmudResponse.statusCode != 200) {
      throw Exception('שגיאה בקבלת הרליס האחרון של תלמוד בבלי: ${talmudResponse.statusCode}');
    }

    final talmudDecoded = jsonDecode(utf8.decode(talmudResponse.bodyBytes));
    if (talmudDecoded is! Map<String, dynamic>) {
      throw Exception('מבנה תשובת GitHub עבור תלמוד בבלי אינו תקין');
    }

    final assets = parseLatestLibraryAssets(dbDecoded, talmudDecoded);
    if (assets == null) {
      throw Exception('לא נמצאו קבצי הספרייה הנדרשים (seforim.db.zst או talmud_bavli_latest.tar.zst) ברליס האחרון');
    }

    return assets;
  }

  @visibleForTesting

  /// מחלץ מתוך JSON של רליס את קובצי הספרייה והתלמוד בבלי.
  static LibraryReleaseAssets? parseLatestLibraryAssets(
      Map<String, dynamic> dbReleaseJson,
      Map<String, dynamic> talmudReleaseJson) {
    final dbAssets = dbReleaseJson['assets'];
    final talmudAssets = talmudReleaseJson['assets'];
    if (dbAssets is! List || talmudAssets is! List) {
      return null;
    }

    String dbAssetName = '';
    String dbDownloadUrl = '';
    String talmudAssetName = '';
    String talmudDownloadUrl = '';

    for (final asset in dbAssets) {
      if (asset is! Map<String, dynamic>) {
        continue;
      }

      final name = asset['name']?.toString() ?? '';
      final downloadUrl = asset['browser_download_url']?.toString() ?? '';
      if (name == 'seforim.db.zst' && downloadUrl.isNotEmpty) {
        dbAssetName = name;
        dbDownloadUrl = downloadUrl;
        break;
      }
    }

    for (final asset in talmudAssets) {
      if (asset is! Map<String, dynamic>) {
        continue;
      }

      final name = asset['name']?.toString() ?? '';
      final downloadUrl = asset['browser_download_url']?.toString() ?? '';
      if (name == 'talmud_bavli_latest.tar.zst' && downloadUrl.isNotEmpty) {
        talmudAssetName = name;
        talmudDownloadUrl = downloadUrl;
        break;
      }
    }

    if (dbDownloadUrl.isNotEmpty && talmudDownloadUrl.isNotEmpty) {
      return LibraryReleaseAssets(
        dbAssetName: dbAssetName,
        dbDownloadUrl: dbDownloadUrl,
        talmudAssetName: talmudAssetName,
        talmudDownloadUrl: talmudDownloadUrl,
      );
    }

    return null;
  }

  static Future<void> _extractZstWithSystemProcess(
    String archivePath,
    String outputPath,
  ) async {
    await Isolate.run(() async {
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
    });
  }

  static Future<void> _extractTarZstWithArchive(
    String archivePath,
    String outputDirectory,
  ) async {
    await Isolate.run(() async {
      final compressedBytes = await File(archivePath).readAsBytes();
      final decompressed = await Zstandard().decompress(compressedBytes);
      if (decompressed == null) {
        throw Exception('חילוץ קובץ ZST נכשל: $archivePath');
      }
      
      final archive = TarDecoder().decodeBytes(decompressed);
      for (final file in archive) {
        final filename = file.name;
        if (file.isFile) {
          final data = file.content as List<int>;
          final outputFile = File(path.join(outputDirectory, filename));
          await outputFile.parent.create(recursive: true);
          await outputFile.writeAsBytes(data, flush: true);
        } else {
          final dir = Directory(path.join(outputDirectory, filename));
          await dir.create(recursive: true);
        }
      }
    });
  }
}

/// מייצג assets של הספרייה מתוך GitHub Release.
class LibraryReleaseAssets {
  const LibraryReleaseAssets({
    required this.dbAssetName,
    required this.dbDownloadUrl,
    required this.talmudAssetName,
    required this.talmudDownloadUrl,
  });

  final String dbAssetName;
  final String dbDownloadUrl;
  final String talmudAssetName;
  final String talmudDownloadUrl;
}
