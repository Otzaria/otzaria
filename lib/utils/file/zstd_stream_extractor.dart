import 'zstd_stream_extractor_stub.dart'
    if (dart.library.io) 'zstd_stream_extractor_io.dart'
    as impl;

/// מחלץ קבצי `.zst` בזרימה (streaming) דרך ZSTD FFI — מעבד נתחים של ~128KB
/// ישירות לדיסק, כך שצריכת ה-RAM נשארת בכמה מאות KB גם לקבצים בגודל ג'יגות.
///
/// טעינת הקובץ כולו ל-RAM (`Zstandard().decompress`) קרסה על מכשירים עם
/// 8GB RAM (DB של ~6.5GB פרוס). שיטה זו אינה חורגת מכמה מאות KB.
class ZstdStreamExtractor {
  const ZstdStreamExtractor();

  /// מחלץ את [archivePath] אל [outputPath] ב-isolate נפרד; [onProgress] מקבל 0.0–1.0.
  /// חריגה מ-[maxOutputBytes] עוצרת מיד ב-[ZstdOutputLimitExceeded] ומוחקת את הפלט.
  static Future<void> extractToFile(
    String archivePath,
    String outputPath, {
    void Function(double progress)? onProgress,
    int? maxOutputBytes,
  }) => impl.extractToFile(
    archivePath,
    outputPath,
    onProgress: onProgress,
    maxOutputBytes: maxOutputBytes,
  );

  /// פורס את ה-tar.zst [archivePath] אל [outputDir] ב-isolate נפרד, בלי קובץ
  /// tar ביניים. נתיב שבורח מהיעד נדחה; [onProgress] מקבל 0.0–1.0.
  static Future<void> extractTarToDir(
    String archivePath,
    String outputDir, {
    void Function(double progress)? onProgress,
  }) => impl.extractTarToDir(archivePath, outputDir, onProgress: onProgress);
}

/// הפלט הפרוס חרג מהתקרה שנקבעה — הארכיון אינו מה שהוצהר עליו.
class ZstdOutputLimitExceeded implements Exception {
  final int maxOutputBytes;
  const ZstdOutputLimitExceeded(this.maxOutputBytes);

  @override
  String toString() =>
      'ZstdOutputLimitExceeded: more than $maxOutputBytes bytes';
}
