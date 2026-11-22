import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import 'package:otzaria/attached_libraries/models/attached_update_manifest.dart';
import 'package:otzaria/attached_libraries/repository/update/attached_update_artifact_builder.dart';

/// תקרת החלון של zstd (2^31): prefix גדול מזה אינו ניתן להצגה לפענוח.
const int kMaxDeltaBaseBytes = 2 * 1024 * 1024 * 1024;

/// מה יורד בפועל: [delta] לא null ⇒ [artifact] הוא תיקון שיוחל על המסד המותקן.
class AttachedUpdatePlan {
  const AttachedUpdatePlan(this.artifact, {this.delta});

  final AttachedUpdateArtifact artifact;
  final AttachedUpdateDelta? delta;

  bool get isDelta => delta != null;
}

/// בוחר בין הקובץ המלא לתיקון דלתא. דלתא יחידה נבחרת בלי קריאת הבסיס;
/// בכמה מועמדות בודק SHA-256 כדי לבחור בסיס תואם. כל ספק מחזיר את הקובץ המלא.
class AttachedUpdateArtifactPlanner {
  const AttachedUpdateArtifactPlanner({
    this.pointerSize,
    this.maxBaseBytes = kMaxDeltaBaseBytes,
    @visibleForTesting this.hashFile = _hashInstalled,
  });

  /// דריסה לבדיקות של רוחב המצביע (8 = 64 סיביות).
  final int? pointerSize;

  /// גודל הקובץ המותקן שעדיין אפשר להשתמש בו כ-prefix.
  final int maxBaseBytes;

  @visibleForTesting
  final Future<String> Function(String path) hashFile;

  static Future<String> _hashInstalled(String path) => Isolate.run(
    () => AttachedUpdateArtifactBuilder.sha256OfFile(path),
  );

  // בדיקה והתקנה קוראות את אותו בסיס; שינוי בגודל או בזמן מבטל את המטמון.
  static final _hashCache =
      <String, ({int size, DateTime modified, String digest})>{};

  @visibleForTesting
  static void clearCacheForTesting() => _hashCache.clear();

  Future<AttachedUpdatePlan> plan(
    AttachedUpdateManifest manifest, {
    required String installedPath,
    required int installedDbVersion,
  }) async {
    final full = AttachedUpdatePlan(manifest.full);
    try {
      if ((pointerSize ?? sizeOf<Pointer>()) != 8) return full;
      final candidates =
          manifest.deltas
              .where(
                (d) =>
                    d.fromDbVersion == installedDbVersion &&
                    d.artifact.compression ==
                        AttachedUpdateCompression.zstdPatch &&
                    d.artifact.compressedSize < manifest.full.compressedSize,
              )
              .toList()
            ..sort(
              (a, b) => a.artifact.compressedSize.compareTo(
                b.artifact.compressedSize,
              ),
            );
      if (candidates.isEmpty) return full;
      final stat = await FileStat.stat(installedPath);
      if (stat.type != FileSystemEntityType.file ||
          stat.size <= 0 ||
          stat.size > maxBaseBytes) {
        return full;
      }
      if (candidates.length > 1) {
        final installedSha256 = await _installedDigest(installedPath, stat);
        candidates.removeWhere((d) => d.fromSha256 != installedSha256);
        if (candidates.isEmpty) return full;
      }
      final delta = candidates.first;
      return AttachedUpdatePlan(delta.artifact, delta: delta);
    } catch (e) {
      debugPrint('[AttachedUpdates] delta planning failed: $e');
      return full;
    }
  }

  Future<String> _installedDigest(String path, FileStat stat) async {
    final cached = _hashCache[path];
    if (cached != null &&
        cached.size == stat.size &&
        cached.modified == stat.modified) {
      return cached.digest;
    }
    final digest = await hashFile(path);
    _hashCache[path] = (
      size: stat.size,
      modified: stat.modified,
      digest: digest,
    );
    return digest;
  }
}
