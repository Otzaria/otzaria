import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as path;
import 'package:logging/logging.dart';

/// שירות לחילוץ קבצי ZIP
class ZipExtractorService {
  static final _log = Logger('ZipExtractorService');

  /// בודק אם בתיקייה יש קובץ ZIP יחיד ומחלץ אותו
  /// מחזיר את נתיב התיקייה שנוצרה או null אם לא היה צורך בחילוץ
  /// [outputDirectoryPath] - תיקיית היעד לחילוץ (ברירת מחדל: תיקיית ה-ZIP)
  /// [onProgress] - callback להתקדמות (0.0 - 1.0)
  /// [onAskDeleteZip] - callback לשאול את המשתמש אם למחוק את ה-ZIP (מחזיר `Future<bool>`)
  static Future<ZipExtractionResult> checkAndExtractZipIfNeeded(
    String directoryPath, {
    String? outputDirectoryPath,
    Function(double progress, String message)? onProgress,
    Future<bool> Function()? onAskDeleteZip,
  }) async {
    try {
      final directory = Directory(directoryPath);
      if (!directory.existsSync()) {
        return ZipExtractionResult(
          success: false,
          errorMessage: 'התיקייה לא קיימת',
        );
      }

      // מציאת כל קבצי ה-ZIP בתיקייה
      final zipFiles = <File>[];
      await for (final entity in directory.list()) {
        if (entity is File && entity.path.toLowerCase().endsWith('.zip')) {
          zipFiles.add(entity);
        }
      }

      // אם אין קבצי ZIP, אין צורך בחילוץ
      if (zipFiles.isEmpty) {
        return ZipExtractionResult(
          success: true,
          wasExtracted: false,
        );
      }

      // אם יש יותר מקובץ ZIP אחד, נשאל את המשתמש
      if (zipFiles.length > 1) {
        return ZipExtractionResult(
          success: false,
          errorMessage:
              'נמצאו ${zipFiles.length} קבצים דחוסים. אנא השאר רק קובץ דחוס אחד בתיקייה.',
          multipleZipFiles: true,
          zipFiles: zipFiles.map((f) => path.basename(f.path)).toList(),
        );
      }

      final zipFile = zipFiles.first;
      final zipFileName = path.basename(zipFile.path);
      final targetDir = outputDirectoryPath ?? directoryPath;

      _log.info('נמצא קובץ דחוס: $zipFileName');
      _log.info('נתיב מלא: ${zipFile.path}');
      _log.info('תיקיית יעד: $targetDir');

      // חילוץ הקובץ באמצעות archive package
      try {
        // בדיקת גודל הקובץ
        final fileSize = await zipFile.length();
        final fileSizeMB = (fileSize / 1024 / 1024).toStringAsFixed(1);
        _log.info('גודל קובץ ZIP: $fileSize bytes ($fileSizeMB MB)');

        onProgress?.call(0.1, 'מתחיל חילוץ ($fileSizeMB MB)...');

        // שימוש ב-extractFileToDisk - פונקציה אופטימלית שמטפלת ב-streaming אוטומטית
        // זה מונע טעינת כל הקובץ לזיכרון ומתאים לקבצים גדולים
        _log.info('משתמש ב-extractFileToDisk לחילוץ אופטימלי');

        try {
          await extractFileToDisk(zipFile.path, targetDir);
          _log.info('החילוץ הושלם בהצלחה');
          onProgress?.call(0.95, 'משלים חילוץ...');
        } catch (e) {
          _log.severe('שגיאה בחילוץ עם extractFileToDisk, מנסה שיטה חלופית', e);
          // אם נכשל, ננסה את השיטה הישנה
          onProgress?.call(0.1, 'קורא קובץ דחוס ($fileSizeMB MB)...');
          final bytes = await zipFile.readAsBytes();
          _log.info('קובץ ZIP נקרא, גודל: ${bytes.length} bytes');

          onProgress?.call(0.15, 'מפענח ארכיון ($fileSizeMB MB)...');
          await Future.delayed(const Duration(milliseconds: 100));
          final archive = ZipDecoder().decodeBytes(bytes);
          _log.info('ארכיון פוענח, ${archive.length} קבצים');

          // חילוץ ידני
          await _extractArchiveManually(
            archive,
            targetDir,
            onProgress,
          );
        }

        onProgress?.call(0.95, 'משלים חילוץ...');
        _log.info('החילוץ הושלם בהצלחה');
      } catch (extractError, extractStackTrace) {
        _log.severe('שגיאה בפעולת החילוץ', extractError, extractStackTrace);
        return ZipExtractionResult(
          success: false,
          errorMessage: 'שגיאה בחילוץ הקובץ: ${extractError.toString()}',
        );
      }

      // מחיקת קובץ ה-ZIP המקורי
      try {
        onProgress?.call(0.98, 'משלים...');

        // שאלת המשתמש אם למחוק
        bool shouldDelete = true;
        if (onAskDeleteZip != null) {
          shouldDelete = await onAskDeleteZip();
        }

        if (shouldDelete) {
          await zipFile.delete();
          _log.info('קובץ ה-ZIP המקורי נמחק');
        } else {
          _log.info('המשתמש בחר לשמור את קובץ ה-ZIP');
        }
      } catch (deleteError) {
        _log.warning('לא ניתן למחוק את קובץ ה-ZIP המקורי: $deleteError');
        // לא נכשיל את כל הפעולה בגלל זה
      }

      onProgress?.call(1.0, 'החילוץ הושלם!');

      return ZipExtractionResult(
        success: true,
        wasExtracted: true,
        extractedFileName: zipFileName,
        extractionPath: targetDir,
      );
    } catch (e, stackTrace) {
      _log.severe('שגיאה בחילוץ קובץ ZIP', e, stackTrace);
      return ZipExtractionResult(
        success: false,
        errorMessage: 'שגיאה בחילוץ הקובץ: ${e.toString()}',
      );
    }
  }

  /// בודק אם קובץ הוא קובץ ZIP
  static bool isZipFile(String filePath) {
    final extension = path.extension(filePath).toLowerCase();
    return extension == '.zip';
  }

  /// חילוץ ידני של ארכיון (fallback)
  static Future<void> _extractArchiveManually(
    Archive archive,
    String directoryPath,
    Function(double progress, String message)? onProgress,
  ) async {
    onProgress?.call(0.2, 'מתכונן לחילוץ ${archive.length} קבצים...');
    await Future.delayed(const Duration(milliseconds: 100));

    final totalFiles = archive.length;
    var extractedFiles = 0;
    var totalBytes = 0;
    var processedBytes = 0;

    // חישוב סך כל הבתים
    for (final file in archive) {
      if (file.isFile) {
        totalBytes += file.size;
      }
    }

    final totalMB = (totalBytes / 1024 / 1024).toStringAsFixed(1);
    onProgress?.call(0.22, 'מחלץ $totalMB MB...');
    await Future.delayed(const Duration(milliseconds: 100));

    for (final file in archive) {
      final filename = file.name;

      if (file.isFile) {
        final data = file.content as List<int>;
        final outputFile = File(path.join(directoryPath, filename));

        // יצירת תיקיות אם צריך
        await outputFile.parent.create(recursive: true);

        // כתיבת הקובץ עם חיווי התקדמות
        final fileSize = data.length;
        if (fileSize > 1024 * 1024) {
          // קובץ גדול מ-1MB - נכתוב בחלקים
          final sink = outputFile.openWrite();
          const chunkSize = 1024 * 1024; // 1MB chunks
          var written = 0;

          while (written < fileSize) {
            final end = (written + chunkSize < fileSize)
                ? written + chunkSize
                : fileSize;
            sink.add(data.sublist(written, end));
            final chunkWritten = end - written;
            written = end;
            processedBytes += chunkWritten;

            // עדכון התקדמות
            final bytesProgress = totalBytes > 0
                ? processedBytes / totalBytes
                : 0.0;
            final filesProgress = totalFiles > 0
                ? extractedFiles / totalFiles
                : 0.0;
            final progress =
                0.25 + (0.65 * ((bytesProgress + filesProgress) / 2));
            final mb = (processedBytes / 1024 / 1024).toStringAsFixed(1);
            final totalMb = (totalBytes / 1024 / 1024).toStringAsFixed(1);
            onProgress?.call(
              progress,
              'מחלץ: ${path.basename(filename)}\n$mb MB מתוך $totalMb MB',
            );
          }

          await sink.close();
        } else {
          // קובץ קטן - נכתוב בבת אחת
          await outputFile.writeAsBytes(data);
          processedBytes += fileSize;
        }
      } else {
        // יצירת תיקייה
        final dir = Directory(path.join(directoryPath, filename));
        await dir.create(recursive: true);
      }

      extractedFiles++;
      if (totalFiles > 0) {
        final progress = 0.25 + (0.65 * extractedFiles / totalFiles);
        onProgress?.call(
          progress,
          'מחלץ קבצים... ($extractedFiles מתוך $totalFiles)',
        );
      }
    }
  }
}

/// תוצאת פעולת חילוץ
class ZipExtractionResult {
  final bool success;
  final bool wasExtracted;
  final String? extractedFileName;
  final String? extractionPath;
  final String? errorMessage;
  final bool multipleZipFiles;
  final List<String>? zipFiles;

  ZipExtractionResult({
    required this.success,
    this.wasExtracted = false,
    this.extractedFileName,
    this.extractionPath,
    this.errorMessage,
    this.multipleZipFiles = false,
    this.zipFiles,
  });

  /// האם הפעולה הצליחה והקובץ חולץ
  bool get successfullyExtracted => success && wasExtracted;

  /// האם הפעולה הצליחה אבל לא היה צורך בחילוץ
  bool get noExtractionNeeded => success && !wasExtracted;
}
