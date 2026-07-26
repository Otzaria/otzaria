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

  /// מחלץ את [archivePath] (קובץ `.zst`) אל [outputPath]. רץ ב-isolate נפרד
  /// כדי לא לחסום את ה-UI. [onProgress] מקבל ערך 0.0–1.0.
  static Future<void> extractToFile(
    String archivePath,
    String outputPath, {
    void Function(double progress)? onProgress,
  }) => impl.extractToFile(archivePath, outputPath, onProgress: onProgress);
}
