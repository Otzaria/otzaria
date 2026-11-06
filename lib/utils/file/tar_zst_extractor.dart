import 'package:otzaria/utils/file/zstd_stream_extractor.dart';
import 'package:seforim_library_updater/seforim_library_updater.dart'
    show kDefaultMaxExtractedBytes;

/// מחלץ ארכיון tar.zst לתיקיית היעד בזרימה אחת (zstd → tar), בלי קובץ tar
/// זמני, כדי שהחילוץ לא ידרוש מקום כפול בדיסק.
Future<void> extractTarZstToDir(
  String archivePath,
  String outputDir, {
  void Function(double progress)? onProgress,
  int maxOutputBytes = kDefaultMaxExtractedBytes,
  bool Function()? isCancelled,
}) => ZstdStreamExtractor.extractTarToDir(
  archivePath,
  outputDir,
  onProgress: onProgress,
  maxOutputBytes: maxOutputBytes,
  isCancelled: isCancelled,
);
