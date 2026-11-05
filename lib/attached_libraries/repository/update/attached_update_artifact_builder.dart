import 'dart:io';

import 'package:otzaria/attached_libraries/models/attached_update_manifest.dart';
import 'package:otzaria/attached_libraries/repository/update/attached_update_fetcher.dart';
import 'package:otzaria/utils/file/native_sha256.dart';
import 'package:otzaria/utils/file/zstd_stream_extractor.dart';
import 'package:path/path.dart' as p;
import 'package:seforim_library_updater/seforim_library_updater.dart';

/// The produced artifact differs from its signed size or digest.
class AttachedUpdateArtifactMismatch implements Exception {
  final String message;
  const AttachedUpdateArtifactMismatch(this.message);
  @override
  String toString() => 'AttachedUpdateArtifactMismatch: $message';
}

/// Compatibility injection. Implementations must enforce the cap while writing.
/// Production uses [FileExtractor] to hash the same bytes as it writes.
typedef AttachedUpdateDecompressor =
    Future<void> Function(
      String archivePath,
      String outputPath,
      int maxOutputBytes,
    );

class AttachedUpdateArtifactBuilder {
  const AttachedUpdateArtifactBuilder({
    this.decompress,
    this.extractor = ZstdStreamExtractor.extractVerifiedToFile,
  });

  final AttachedUpdateDecompressor? decompress;
  final FileExtractor extractor;

  /// Retains the source on failure; removes it on verified success unless the
  /// outer worker still needs to drain progress/cancellation events.
  Future<void> build(
    AttachedUpdateArtifact artifact,
    String combinedPath,
    String outputPath, {
    AttachedUpdateCancelToken? cancel,
    void Function(int bytesWritten)? onProgress,
    bool retainInput = false,
  }) => produceVerified(
    artifact,
    combinedPath,
    outputPath,
    () async {
      switch (artifact.compression) {
        case AttachedUpdateCompression.zstd:
          try {
            final legacy = decompress;
            if (legacy != null) {
              await legacy(combinedPath, outputPath, artifact.size);
              return null;
            }
            return await extractor(
              combinedPath,
              outputPath,
              maxOutputBytes: artifact.size,
              isCancelled: () => cancel?.isCancelled ?? false,
              onProgress: onProgress,
            );
          } on ZstdOutputLimitExceeded {
            throw AttachedUpdateArtifactMismatch(
              'decompressed output exceeds ${artifact.size}',
            );
          } on PatchDownloadCancelled {
            throw const AttachedUpdateCancelled();
          }
        case AttachedUpdateCompression.none:
          return _copyAndHash(
            combinedPath,
            outputPath,
            artifact.size,
            cancel,
            onProgress,
          );
        case AttachedUpdateCompression.zstdPatch:
          throw const AttachedUpdateArtifactMismatch(
            'a zstd-patch artifact needs AttachedUpdateDeltaApplier',
          );
      }
    },
    cancel: cancel,
    onProgress: onProgress,
    retainInput: retainInput,
  );

  static Future<void> produceVerified(
    AttachedUpdateArtifact artifact,
    String combinedPath,
    String outputPath,
    Future<FileExtractionResult?> Function() produce, {
    AttachedUpdateCancelToken? cancel,
    void Function(int bytesWritten)? onProgress,
    bool retainInput = false,
  }) async {
    checkCancelled(cancel);
    await ensureDistinctPaths([combinedPath, outputPath]);
    checkCancelled(cancel);
    await _deleteIfExists(outputPath);
    try {
      final result = await produce();
      checkCancelled(cancel);
      final size = await File(outputPath).length();
      if (size != artifact.size ||
          (result != null && result.bytesWritten != size)) {
        throw AttachedUpdateArtifactMismatch(
          'size $size, expected ${artifact.size}',
        );
      }
      final digest =
          result?.sha256 ??
          await _hashOutput(outputPath, artifact.size, cancel, onProgress);
      if (digest.toLowerCase() != artifact.sha256.toLowerCase()) {
        throw const AttachedUpdateArtifactMismatch('sha256 differs');
      }
      checkCancelled(cancel);
    } catch (_) {
      try {
        await _deleteIfExists(outputPath);
      } on FileSystemException {
        /* preserve the cause */
      }
      rethrow;
    }
    if (!retainInput) await _deleteIfExists(combinedPath);
  }

  static void checkCancelled(AttachedUpdateCancelToken? cancel) {
    if (cancel?.isCancelled ?? false) throw const AttachedUpdateCancelled();
  }

  /// Called before locks or cleanup too, so a source cannot alias any writable
  /// staging path (including an existing symlink or hard link).
  static Future<void> ensureDistinctPaths(List<String> paths) async {
    for (var i = 0; i < paths.length; i++) {
      for (var j = i + 1; j < paths.length; j++) {
        var same = p.equals(
          p.normalize(p.absolute(paths[i])),
          p.normalize(p.absolute(paths[j])),
        );
        if (!same &&
            await File(paths[i]).exists() &&
            await File(paths[j]).exists()) {
          final a = await File(paths[i]).resolveSymbolicLinks();
          final b = await File(paths[j]).resolveSymbolicLinks();
          same = p.equals(a, b) || await FileSystemEntity.identical(a, b);
        }
        if (same) {
          throw ArgumentError(
            'Update sources and staging files must be distinct',
          );
        }
      }
    }
  }

  static Future<FileExtractionResult> _copyAndHash(
    String source,
    String target,
    int limit,
    AttachedUpdateCancelToken? cancel,
    void Function(int)? progress,
  ) async {
    final hash = Sha256Stream();
    RandomAccessFile? output;
    try {
      output = await File(target).open(mode: FileMode.write);
      var written = 0;
      await for (final chunk in File(source).openRead()) {
        checkCancelled(cancel);
        if (chunk.length > limit - written) {
          throw AttachedUpdateArtifactMismatch('output exceeds $limit');
        }
        await output.writeFrom(chunk);
        hash.add(chunk);
        written += chunk.length;
        progress?.call(written);
        checkCancelled(cancel);
      }
      await output.flush();
      checkCancelled(cancel);
      return FileExtractionResult(bytesWritten: written, sha256: hash.close());
    } finally {
      try {
        await output?.close();
      } finally {
        hash.dispose();
      }
    }
  }

  static Future<String> _hashOutput(
    String path,
    int limit,
    AttachedUpdateCancelToken? cancel,
    void Function(int)? progress,
  ) async {
    final hash = Sha256Stream();
    try {
      var read = 0;
      await for (final chunk in File(path).openRead()) {
        checkCancelled(cancel);
        if (chunk.length > limit - read) {
          throw AttachedUpdateArtifactMismatch('output exceeds $limit');
        }
        hash.add(chunk);
        read += chunk.length;
        progress?.call(read);
        checkCancelled(cancel);
      }
      if (read != limit) {
        throw const AttachedUpdateArtifactMismatch(
          'output changed while hashing',
        );
      }
      return hash.close();
    } finally {
      hash.dispose();
    }
  }

  static Future<String> sha256OfFile(String path) => sha256OfFileFast(path);

  static Future<void> _deleteIfExists(String path) async {
    final file = File(path);
    if (await file.exists()) await file.delete();
  }
}
