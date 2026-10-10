import 'dart:io';
import 'dart:isolate';

import 'package:otzaria/attached_libraries/models/attached_update_manifest.dart';
import 'package:otzaria/utils/file/native_sha256.dart';
import 'package:otzaria/utils/file/zstd_stream_extractor.dart';

/// הקובץ שנבנה אינו תואם לגודל או ל-sha256 שבמניפסט. הפלט נמחק.
class AttachedUpdateArtifactMismatch implements Exception {
  final String message;
  const AttachedUpdateArtifactMismatch(this.message);

  @override
  String toString() => 'AttachedUpdateArtifactMismatch: $message';
}

/// Stops once the output exceeds [maxOutputBytes] ([ZstdOutputLimitExceeded]):
/// a check afterwards would let a small archive fill the disk first.
typedef AttachedUpdateDecompressor =
    Future<void> Function(
      String archivePath,
      String outputPath,
      int maxOutputBytes,
    );

/// בונה את קובץ ה-.db מהחלקים המשורשרים (פלט [AttachedUpdateFetcher.downloadParts]):
/// פריסת zstd בזרם — אותו מסלול FFI של עדכון הספרייה הרשמי, בלי טעינה ל-RAM —
/// ואז בדיקת גודל ו-sha256 של התוצאה ב-isolate.
class AttachedUpdateArtifactBuilder {
  const AttachedUpdateArtifactBuilder({
    this.decompress = _zstdStream,
  });

  final AttachedUpdateDecompressor decompress;

  static Future<void> _zstdStream(String archive, String output, int max) =>
      ZstdStreamExtractor.extractToFile(archive, output, maxOutputBytes: max);

  /// [combinedPath] נמחק בהצלחה; בכשל הפלט נמחק ו-[combinedPath] נשאר
  /// (ההורדה אינה חוזרת על עצמה בניסיון הבא).
  Future<void> build(
    AttachedUpdateArtifact artifact,
    String combinedPath,
    String outputPath,
  ) async {
    await _deleteIfExists(outputPath);
    try {
      switch (artifact.compression) {
        case AttachedUpdateCompression.zstd:
          try {
            await decompress(combinedPath, outputPath, artifact.size);
          } on ZstdOutputLimitExceeded {
            throw AttachedUpdateArtifactMismatch(
              'decompressed output exceeds ${artifact.size}',
            );
          }
        case AttachedUpdateCompression.none:
          // החלקים כבר אומתו; אי-התאמה כאן היא מניפסט סותר ולא תקלת הורדה.
          await File(combinedPath).rename(outputPath);
        case AttachedUpdateCompression.zstdPatch:
          throw const AttachedUpdateArtifactMismatch(
            'a zstd-patch artifact needs AttachedUpdateDeltaApplier',
          );
      }
      final size = await File(outputPath).length();
      if (size != artifact.size) {
        throw AttachedUpdateArtifactMismatch(
          'size $size, expected ${artifact.size}',
        );
      }
      final digest = await Isolate.run(() => sha256OfFile(outputPath));
      if (digest != artifact.sha256) {
        throw const AttachedUpdateArtifactMismatch('sha256 differs');
      }
    } catch (_) {
      await _deleteIfExists(outputPath);
      rethrow;
    }
    await _deleteIfExists(combinedPath);
  }

  static Future<String> sha256OfFile(String path) => sha256OfFileFast(path);

  static Future<void> _deleteIfExists(String path) async {
    final file = File(path);
    if (await file.exists()) await file.delete();
  }
}
