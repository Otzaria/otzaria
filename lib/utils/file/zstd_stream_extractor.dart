import 'zstd_stream_extractor_stub.dart'
    if (dart.library.io) 'zstd_stream_extractor_io.dart'
    as impl;
import 'package:seforim_library_updater/seforim_library_updater.dart';

/// חילוץ zstd בחוצצים קבועים; חלון הפענוח הנייטיבי מוגבל בנפרד לפי הפלטפורמה.
class ZstdStreamExtractor {
  const ZstdStreamExtractor();

  /// מחלץ את [archivePath] אל [outputPath] ב-isolate נפרד; [onProgress] מקבל 0.0–1.0.
  /// חריגה מ-[maxOutputBytes] עוצרת מיד ב-[ZstdOutputLimitExceeded] ומוחקת את הפלט.
  static Future<void> extractToFile(
    String archivePath,
    String outputPath, {
    void Function(double progress)? onProgress,
    int? maxOutputBytes = kDefaultMaxExtractedBytes,
    bool Function()? isCancelled,
  }) => impl.extractToFile(
    archivePath,
    outputPath,
    onProgress: onProgress,
    maxOutputBytes: maxOutputBytes,
    isCancelled: isCancelled,
  );

  /// חילוץ חסום בגודל עם SHA-256 המחושב בזמן הכתיבה, ללא קריאה חוזרת של הפלט.
  static Future<FileExtractionResult> extractVerifiedToFile(
    String archivePath,
    String outputPath, {
    required int maxOutputBytes,
    bool Function()? isCancelled,
    void Function(int bytesWritten)? onProgress,
  }) => impl.extractVerifiedToFile(
    archivePath,
    outputPath,
    maxOutputBytes: maxOutputBytes,
    isCancelled: isCancelled,
    onProgress: onProgress,
  );

  /// פורס את ה-tar.zst [archivePath] אל [outputDir] ב-isolate נפרד, בלי קובץ
  /// tar ביניים. נתיב שבורח מהיעד נדחה; [onProgress] מקבל 0.0–1.0.
  static Future<void> extractTarToDir(
    String archivePath,
    String outputDir, {
    void Function(double progress)? onProgress,
    int? maxOutputBytes = kDefaultMaxExtractedBytes,
    bool Function()? isCancelled,
  }) => impl.extractTarToDir(
    archivePath,
    outputDir,
    onProgress: onProgress,
    maxOutputBytes: maxOutputBytes,
    isCancelled: isCancelled,
  );
}

/// הפלט הפרוס חרג מהתקרה שנקבעה — הארכיון אינו מה שהוצהר עליו.
class ZstdOutputLimitExceeded implements Exception {
  final int maxOutputBytes;
  const ZstdOutputLimitExceeded(this.maxOutputBytes);

  @override
  String toString() =>
      'ZstdOutputLimitExceeded: more than $maxOutputBytes bytes';
}
