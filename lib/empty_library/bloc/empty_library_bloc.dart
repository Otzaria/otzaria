import 'dart:convert';
import 'dart:io';
import 'package:bloc/bloc.dart';
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

class EmptyLibraryBloc extends Bloc<EmptyLibraryEvent, EmptyLibraryState> {
  EmptyLibraryBloc({
    http.Client? httpClient,
    Future<void> Function(String archivePath, String outputPath)?
        extractCompressedDatabase,
    String? installationDirectoryPath,
  })  : _httpClient = httpClient ?? http.Client(),
        _extractCompressedDatabase =
            extractCompressedDatabase ?? _extractZstWithSystemProcess,
        _installationDirectoryPath = installationDirectoryPath,
        super(EmptyLibraryInitial()) {
    on<PickDirectoryRequested>(_onPickDirectoryRequested);
    on<PickArchiveFileRequested>(_onPickArchiveFileRequested);
    on<DownloadLibraryRequested>(_onDownloadLibraryRequested);
    on<DeleteZipAnswered>(_onDeleteZipAnswered);
  }

  final http.Client _httpClient;
  final Future<void> Function(String archivePath, String outputPath)
      _extractCompressedDatabase;
  final String? _installationDirectoryPath;

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

      await Settings.setValue(SettingsRepository.keyLibraryPath, directoryPath);
      await Settings.setValue(SettingsRepository.keyLibraryFolderName,
          path.basename(directoryPath));

      emit(EmptyLibraryDirectorySelected(selectedPath: directoryPath));
    } catch (e) {
      emit(EmptyLibraryError(
        errorMessage: 'שגיאה בבדיקת התיקייה: $e',
        selectedPath: directoryPath,
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
      await Settings.setValue(
          SettingsRepository.keyLibraryFolderName, path.basename(rootPath));

      emit(EmptyLibraryDirectorySelected(selectedPath: rootPath));
    } catch (e) {
      emit(EmptyLibraryError(
        errorMessage: 'שגיאה: $e',
      ));
    }
  }

  Future<void> _onDownloadLibraryRequested(
      DownloadLibraryRequested event, Emitter<EmptyLibraryState> emit) async {
    try {
      final latestAsset = await _fetchLatestDatabaseAsset();

      // קבלת תיקיית ההתקנה
      final installDir = _installationDirectoryPath ??
          path.dirname(Platform.resolvedExecutable);
      final otzariaDir = Directory(
        path.join(installDir, DatabaseConstants.otzariaFolderName),
      );

      // יצירת תיקיית אוצריא אם לא קיימת
      if (!await otzariaDir.exists()) {
        await otzariaDir.create(recursive: true);
      }

      final archivePath = path.join(otzariaDir.path, latestAsset.assetName);

      // הורדת הקובץ
      emit(const EmptyLibraryDownloading(
        progress: 0.0,
        message: 'מתחבר לשרת...',
      ));

      final request = http.Request('GET', Uri.parse(latestAsset.downloadUrl));
      final response = await _httpClient.send(request);

      if (response.statusCode != 200) {
        emit(EmptyLibraryError(
          errorMessage: 'שגיאה בהורדה: ${response.statusCode}',
        ));
        return;
      }

      final contentLength = response.contentLength ?? 0;
      var downloadedBytes = 0;
      final file = File(archivePath);
      final sink = file.openWrite();

      try {
        await for (var chunk in response.stream) {
          sink.add(chunk);
          downloadedBytes += chunk.length;

          if (contentLength > 0) {
            final progress = downloadedBytes / contentLength;
            final mb = (downloadedBytes / 1024 / 1024).toStringAsFixed(1);
            final totalMb = (contentLength / 1024 / 1024).toStringAsFixed(1);
            emit(EmptyLibraryDownloading(
              progress: progress,
              message: 'מוריד... $mb MB מתוך $totalMb MB',
            ));
          }
        }
      } finally {
        await sink.close();
      }

      await _handleZstFile(archivePath, emit);
    } catch (e) {
      emit(EmptyLibraryError(
        errorMessage: 'שגיאה בהורדה: $e',
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
      emit(EmptyLibraryError(
        errorMessage: 'שגיאה: $e',
      ));
    }
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
    final outputFile = File(outputPath);
    if (await outputFile.exists()) {
      await outputFile.delete();
    }

    final result = await Process.run(
      'zstd',
      ['-d', '-f', '-T0', '--long=31', archivePath, '-o', outputPath],
    );

    if (result.exitCode != 0) {
      final stderr = (result.stderr as String?)?.trim();
      final stdout = (result.stdout as String?)?.trim();
      throw Exception(stderr?.isNotEmpty == true ? stderr : stdout);
    }
  }
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
