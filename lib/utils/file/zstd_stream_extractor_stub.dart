/// מחלץ קובץ `.zst` אל הדיסק. אינו נתמך ללא dart:ffi.
Future<void> extractToFile(
  String archivePath,
  String outputPath, {
  void Function(double progress)? onProgress,
}) => throw UnsupportedError('חילוץ zst אינו נתמך בפלטפורמה זו');
