/// מחלץ קבצי `.zst` בזרימה (streaming) דרך [ZstdStreamDecoder] — נתחים
/// קטנים ישירות לדיסק, כך שצריכת ה-RAM נשארת בכמה מאות KB גם לקבצי ג'יגות.
library;

import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:otzaria/utils/file/tar_stream_extractor.dart';
import 'package:otzaria/utils/file/zstd_library.dart';
import 'package:otzaria/utils/file/zstd_stream_decoder.dart';
import 'package:otzaria/utils/file/zstd_stream_extractor.dart';

const _readChunkSize = 256 * 1024;

/// מחלץ את [archivePath] (קובץ `.zst`) אל [outputPath]. רץ ב-isolate נפרד
/// כדי לא לחסום את ה-UI. [onProgress] מקבל ערך 0.0–1.0.
Future<void> extractToFile(
  String archivePath,
  String outputPath, {
  void Function(double progress)? onProgress,
  int? maxOutputBytes,
}) {
  return _runWithProgress(
    onProgress,
    (port) => Isolate.run(
      () => _decompressWithLib(
        archivePath,
        outputPath,
        openZstandardLib(),
        port,
        maxOutputBytes,
      ),
    ),
  );
}

/// פורס tar.zst אל [outputDir] ב-isolate נפרד, בלי קובץ tar ביניים.
Future<void> extractTarToDir(
  String archivePath,
  String outputDir, {
  void Function(double progress)? onProgress,
}) {
  return _runWithProgress(
    onProgress,
    (port) => Isolate.run(
      () => _extractTarWithLib(
        archivePath,
        outputDir,
        openZstandardLib(),
        port,
      ),
    ),
  );
}

/// מאזין לעדכוני התקדמות מ-isolate ומעביר אותם הלאה.
///
/// [runInIsolate] נקראת מקומית (לא נשלחת ל-isolate); היא עצמה אחראית להפעיל
/// את [Isolate.run]. ה-isolate שולח `double` (0.0–1.0) דרך ה-[SendPort].
Future<void> _runWithProgress(
  void Function(double progress)? onProgress,
  Future<void> Function(SendPort progressPort) runInIsolate,
) async {
  final progressPort = ReceivePort();
  final sub = progressPort.listen((message) {
    if (message is double) onProgress?.call(message);
  });
  try {
    await runInIsolate(progressPort.sendPort);
  } finally {
    await sub.cancel();
    progressPort.close();
  }
}

/// נקודת כניסה לבדיקות בלבד: מריצה את החילוץ סינכרונית עם [lib] מוזרק,
/// כדי לאמת את לוגיקת ה-FFI גם בלי ה-framework של Flutter (למשל מול
/// libzstd סטנדרטי במערכת).
void decompressSyncForTest(
  String archivePath,
  String outputPath,
  DynamicLibrary lib, {
  int? maxOutputBytes,
}) => _decompressWithLib(archivePath, outputPath, lib, null, maxOutputBytes);

/// נקודת כניסה לבדיקות בלבד, כמו [decompressSyncForTest] עבור tar.zst.
void extractTarSyncForTest(
  String archivePath,
  String outputDir,
  DynamicLibrary lib,
) => _extractTarWithLib(archivePath, outputDir, lib, null);

/// בכשל מוחק את קובץ הפלט החלקי, אחרת קובץ חתוך נשאר ומפיל את פתיחת ה-DB
/// בעלייה הבאה.
void _decompressWithLib(
  String archivePath,
  String outputPath,
  DynamicLibrary dylib,
  SendPort? progressPort,
  int? maxOutputBytes,
) {
  final outFile = File(outputPath);
  try {
    if (outFile.existsSync()) outFile.deleteSync();
    final outputRaf = outFile.openSync(mode: FileMode.writeOnly);
    try {
      var totalWritten = 0;
      _decodeFile(archivePath, dylib, progressPort, (output) {
        totalWritten += output.length;
        if (maxOutputBytes != null && totalWritten > maxOutputBytes) {
          throw ZstdOutputLimitExceeded(maxOutputBytes);
        }
        outputRaf.writeFromSync(output);
      });
      // flush מפורש כדי לתפוס דיסק מלא (ENOSPC) שנבלע ב-page cache.
      outputRaf.flushSync();
    } finally {
      outputRaf.closeSync();
    }
  } catch (_) {
    try {
      if (outFile.existsSync()) outFile.deleteSync();
    } catch (_) {}
    rethrow;
  }
}

/// פריסה חלקית שנשארת אחרי כשל היא באחריות הקורא, כמו בכל חילוץ לתיקייה.
void _extractTarWithLib(
  String archivePath,
  String outputDir,
  DynamicLibrary dylib,
  SendPort? progressPort,
) {
  final tar = TarStreamExtractor(outputDir, rootFolder: null);
  try {
    _decodeFile(archivePath, dylib, progressPort, tar.add);
    tar.close();
  } finally {
    tar.abort();
  }
}

/// קורא את [archivePath] בנתחים ומעביר את הפלט הפרוס ל-[onOutput]; זורק
/// אם הקובץ נגמר באמצע frame.
void _decodeFile(
  String archivePath,
  DynamicLibrary dylib,
  SendPort? progressPort,
  void Function(Uint8List output) onOutput,
) {
  final decoder = ZstdStreamDecoder(dylib);
  RandomAccessFile? inputRaf;
  try {
    inputRaf = File(archivePath).openSync();
    final totalBytes = inputRaf.lengthSync();
    final buffer = Uint8List(_readChunkSize);
    var totalRead = 0;
    var lastReported = 0.0;
    while (true) {
      final bytesRead = inputRaf.readIntoSync(buffer);
      if (bytesRead == 0) break;
      totalRead += bytesRead;
      decoder.add(Uint8List.sublistView(buffer, 0, bytesRead), onOutput);
      if (progressPort != null && totalBytes > 0) {
        final progress = totalRead / totalBytes;
        if (progress - lastReported >= 0.01) {
          lastReported = progress;
          progressPort.send(progress);
        }
      }
    }
    decoder.close();
  } finally {
    decoder.dispose();
    inputRaf?.closeSync();
  }
}
