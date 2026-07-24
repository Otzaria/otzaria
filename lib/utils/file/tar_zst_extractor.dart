import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:otzaria/utils/file/zstd_stream_extractor.dart';

/// מחלץ ארכיון tar.zst לתיקיית היעד בזרימה נמוכת-זיכרון: חילוץ ה-zst לקובץ
/// tar זמני, ואז `extractFileToDisk` שקורא בזרימה מהקובץ.
Future<void> extractTarZstToDir(
  String archivePath,
  String outputDir, {
  void Function(double progress)? onProgress,
}) async {
  final tarPath = '$archivePath.tar';
  try {
    await ZstdStreamExtractor.extractToFile(
      archivePath,
      tarPath,
      onProgress: onProgress,
    );
    await extractFileToDisk(tarPath, outputDir);
  } finally {
    // גם חילוץ zst שנכשל באמצע משאיר tar חלקי — מנקים תמיד.
    await File(tarPath).delete().catchError((_) => File(tarPath));
  }
}
