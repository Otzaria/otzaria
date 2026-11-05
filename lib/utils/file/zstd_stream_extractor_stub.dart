import 'package:seforim_library_updater/seforim_library_updater.dart';

/// מחלץ קובץ `.zst` אל הדיסק. אינו נתמך ללא dart:ffi.
Future<void> extractToFile(
  String archivePath,
  String outputPath, {
  void Function(double progress)? onProgress,
  int? maxOutputBytes,
  bool Function()? isCancelled,
}) => throw UnsupportedError('חילוץ zst אינו נתמך בפלטפורמה זו');

Future<FileExtractionResult> extractVerifiedToFile(
  String archivePath,
  String outputPath, {
  required int maxOutputBytes,
  bool Function()? isCancelled,
  void Function(int bytesWritten)? onProgress,
}) => throw UnsupportedError('חילוץ zst אינו נתמך בפלטפורמה זו');

/// פורס tar.zst לתיקייה. אינו נתמך ללא dart:ffi.
Future<void> extractTarToDir(
  String archivePath,
  String outputDir, {
  void Function(double progress)? onProgress,
  int? maxOutputBytes,
  bool Function()? isCancelled,
}) => throw UnsupportedError('חילוץ zst אינו נתמך בפלטפורמה זו');
