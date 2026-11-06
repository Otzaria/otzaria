import 'dart:io';

import 'package:otzaria/attached_libraries/models/attached_update_manifest.dart';
import 'package:otzaria/attached_libraries/repository/update/attached_update_artifact_builder.dart';
import 'package:otzaria/attached_libraries/repository/update/attached_update_fetcher.dart';
import 'package:otzaria/utils/file/zstd_patch_decoder.dart';
import 'package:otzaria/utils/file/zstd_stream_extractor.dart';

/// Stops once the output exceeds [maxOutputBytes] ([ZstdOutputLimitExceeded]):
/// a check afterwards would let a small patch fill the disk first.
typedef AttachedUpdatePatchDecoder =
    Future<void> Function(
      String patchPath,
      String basePath,
      String outputPath,
      int maxOutputBytes,
      ZstdCancelFlag? cancel,
    );

/// בונה את קובץ ה-.db מתיקון `zstd --patch-from` שהורד בחלקים: הקובץ המותקן
/// משמש prefix, והתוצאה נבדקת מול אותם גודל ו-sha256 של המסלול המלא.
class AttachedUpdateDeltaApplier {
  const AttachedUpdateDeltaApplier({this.decodePatch});

  final AttachedUpdatePatchDecoder? decodePatch;

  /// [combinedPath] הוא התיקון המשורשר, [basePath] המסד המותקן (אינו נכתב).
  /// בהצלחה [combinedPath] נמחק; בכשל הפלט נמחק ו-[combinedPath] נשאר.
  Future<void> apply(
    AttachedUpdateArtifact artifact,
    String combinedPath,
    String basePath,
    String outputPath, {
    AttachedUpdateCancelToken? cancel,
    void Function(int bytesWritten)? onProgress,
    bool retainInput = false,
  }) async {
    if (artifact.compression != AttachedUpdateCompression.zstdPatch) {
      throw const AttachedUpdateArtifactMismatch(
        'delta artifact must be zstd-patch',
      );
    }
    AttachedUpdateArtifactBuilder.checkCancelled(cancel);
    await AttachedUpdateArtifactBuilder.ensureDistinctPaths([
      combinedPath,
      basePath,
      outputPath,
    ]);
    await AttachedUpdateArtifactBuilder.produceVerified(
      artifact,
      combinedPath,
      outputPath,
      () async {
        if (!await File(basePath).exists()) {
          throw const AttachedUpdateArtifactMismatch(
            'the installed database to patch is missing',
          );
        }
        final flag = ZstdCancelFlag();
        final unsubscribe = cancel?.onCancel(flag.cancel);
        if (cancel?.isCancelled ?? false) flag.cancel();
        try {
          final legacy = decodePatch;
          if (legacy == null) {
            return await decodePatchVerifiedToFile(
              combinedPath,
              basePath,
              outputPath,
              maxOutputBytes: artifact.size,
              cancelAddress: flag.address,
              onProgress: onProgress,
            );
          }
          await legacy(combinedPath, basePath, outputPath, artifact.size, flag);
          return null;
        } on ZstdOutputLimitExceeded {
          throw AttachedUpdateArtifactMismatch(
            'patched output exceeds ${artifact.size}',
          );
        } on ZstdDecodeCancelled {
          throw const AttachedUpdateCancelled();
        } finally {
          unsubscribe?.call();
          flag.dispose();
        }
      },
      cancel: cancel,
      onProgress: onProgress,
      retainInput: retainInput,
    );
  }
}
