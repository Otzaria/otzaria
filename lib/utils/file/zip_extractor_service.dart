import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:otzaria/utils/file/archive_extractor.dart';
import 'package:otzaria/utils/file/zip_entry_io.dart';
import 'package:otzaria/utils/text/byte_size_text.dart';
import 'package:path/path.dart' as path;
import 'package:logging/logging.dart';

/// שירות לחילוץ קבצי ZIP
class ZipExtractorService {
  static final _log = Logger('ZipExtractorService');

  /// בודק אם בתיקייה יש קובץ ZIP יחיד ומחלץ אותו
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

        onProgress?.call(
          0.1,
          'מתחיל חילוץ (${formatMegabytesLtr(fileSize)})...',
        );

        // חילוץ בזרימה מהקובץ, בלי לטעון את הארכיון כולו לזיכרון.
        try {
          await extractArchiveFileToDisk(zipFile.path, targetDir);
          _log.info('החילוץ הושלם בהצלחה');
          onProgress?.call(0.95, 'משלים חילוץ...');
        } catch (e) {
          _log.severe('שגיאה בחילוץ בזרימה, מנסה שיטה חלופית', e);
          onProgress?.call(
            0.1,
            'קורא קובץ דחוס (${formatMegabytesLtr(fileSize)})...',
          );
          await extractManuallyInIsolate(zipFile.path, targetDir, onProgress);
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
      );
    } catch (e, stackTrace) {
      _log.severe('שגיאה בחילוץ קובץ ZIP', e, stackTrace);
      return ZipExtractionResult(
        success: false,
        errorMessage: 'שגיאה בחילוץ הקובץ: ${e.toString()}',
      );
    }
  }

  /// המסלול החלופי במלואו — קריאה, פענוח ופרישה — ב-isolate נפרד. פענוח
  /// ה-ZIP ופרישת הקבצים סינכרוניים, ועל isolate שיש בו UI הם מקפיאים אותו.
  @visibleForTesting
  static Future<void> extractManuallyInIsolate(
    String zipPath,
    String targetDir,
    Function(double progress, String message)? onProgress,
  ) async {
    final progressPort = ReceivePort();
    final sub = progressPort.listen((message) {
      if (message is List && message.length == 2) {
        onProgress?.call(message[0] as double, message[1] as String);
      }
    });
    try {
      await _runExtractIsolate(zipPath, targetDir, progressPort.sendPort);
    } finally {
      await sub.cancel();
      progressPort.close();
    }
  }

  // מבודד מ-[extractManuallyInIsolate]: הסגור לוכד את כל ה-scope, ושם
  // onProgress גורר את ה-State של הדיאלוג הלא-sendable ל-spawn.
  static Future<void> _runExtractIsolate(
    String zipPath,
    String targetDir,
    SendPort progressPort,
  ) => Isolate.run(
    () => _readDecodeAndExtract(zipPath, targetDir, progressPort),
  );

  static Future<void> _readDecodeAndExtract(
    String zipPath,
    String targetDir,
    SendPort progressPort,
  ) async {
    // The fallback must not retain the full ZIP in memory while processing
    // large library updates. Keep the input handle open for lazy entry reads.
    final input = openZipInput(zipPath);
    try {
      final archive = ZipDecoder().decodeStream(input);
      await _extractArchiveManually(
        archive,
        targetDir,
        (progress, message) => progressPort.send([progress, message]),
      );
    } finally {
      await input.close();
    }
  }

  /// חילוץ ידני של ארכיון (fallback)
  static Future<void> _extractArchiveManually(
    Archive archive,
    String directoryPath,
    Function(double progress, String message)? onProgress,
  ) async {
    onProgress?.call(0.2, 'מתכונן לחילוץ ${archive.length} קבצים...');

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

    onProgress?.call(0.22, 'מחלץ ${formatMegabytesLtr(totalBytes)}...');

    final root = path.canonicalize(directoryPath);
    await Directory(root).create(recursive: true);
    for (final entry in archive) {
      final target = path.canonicalize(path.join(root, entry.name));
      if (!path.isWithin(root, target)) {
        throw FormatException(
          'נתיב חולץ מקובץ ZIP באופן לא חוקי: ${entry.name}',
        );
      }

      if (entry.isFile) {
        // writeZipEntry decompresses into a bounded buffer and writes it
        // asynchronously. Splitting a fully decompressed byte array into
        // 1 MiB chunks still retains the entire array in memory.
        final written = await writeZipEntry(entry, target);
        if (written != entry.size) {
          await File(target).delete();
          throw ArchiveException(
            'ZIP entry ${entry.name} declared ${entry.size} bytes '
            'but extracted $written bytes',
          );
        }
        processedBytes += written;
      } else {
        await Directory(target).create(recursive: true);
      }

      extractedFiles++;
      if (totalFiles > 0) {
        final progress = 0.25 + (0.65 * extractedFiles / totalFiles);
        onProgress?.call(
          progress,
          'מחלץ קבצים... ($extractedFiles מתוך $totalFiles)\\n'
          '${formatMegabytesProgressHebrew(processedBytes, totalBytes)}',
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
  final String? errorMessage;

  ZipExtractionResult({
    required this.success,
    this.wasExtracted = false,
    this.extractedFileName,
    this.errorMessage,
  });

  /// האם הפעולה הצליחה והקובץ חולץ
  bool get successfullyExtracted => success && wasExtracted;
}
