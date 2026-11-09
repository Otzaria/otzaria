import 'dart:io';

import 'package:seforim_library_updater/seforim_library_updater.dart';

/// בייטים שהמוריד יכול למחזר לפי זהות הנכס ו-validator של הקובץ החלקי.
Future<int> reusableDownloadBytes(
  String filePath,
  String identity,
  int expectedSize,
) async {
  try {
    final file = File(filePath);
    if (!await file.exists()) return 0;
    final sidecar = File(PatchDownloader.resumeSidecarPath(filePath));
    if (!await sidecar.exists()) return 0;
    final lines = (await sidecar.readAsString()).split('\n');
    if (lines.first != identity) return 0;
    final length = await file.length();
    if (expectedSize > 0 && length == expectedSize) return length;
    if (length <= 0 || (expectedSize > 0 && length > expectedSize)) return 0;
    final etag = lines.length > 1 ? lines[1].trim() : '';
    return etag.isNotEmpty && !etag.startsWith('W/') ? length : 0;
  } catch (_) {
    return 0;
  }
}

/// תוספת השטח להורדה ולחיבור, בניכוי בייטים שניתנים להמשך לפי חוזה המוריד.
Future<int> additionalDownloadBytes({
  required String destPath,
  required String identity,
  required int size,
  SplitAsset? split,
}) async {
  if (split == null) {
    if (size <= 0) return 0;
    return size - await reusableDownloadBytes(destPath, identity, size);
  }
  final joined = await reusableDownloadBytes(
    destPath,
    '$identity|joined:${split.sha256}',
    split.size,
  );
  if (joined == split.size) return 0;
  // Verified parts stay available for retry until the joined archive commits.
  var needed = split.size * 2;
  for (var i = 0; i < split.parts.length; i++) {
    final part = split.parts[i];
    needed -= await reusableDownloadBytes(
      PatchDownloader.splitPartPath(destPath, i),
      '$identity|${part.name}|${part.sha256}',
      part.size,
    );
  }
  return needed;
}

/// האם נשמר קובץ חלקי של הנכס שהמוריד ימשיך ממנו (ראו [additionalDownloadBytes]).
Future<bool> hasReusableDownload({
  required String destPath,
  required String identity,
  required int size,
  SplitAsset? split,
}) async {
  if (split == null) {
    return await reusableDownloadBytes(destPath, identity, size) > 0;
  }
  final joinedIdentity = '$identity|joined:${split.sha256}';
  if (await reusableDownloadBytes(destPath, joinedIdentity, split.size) > 0) {
    return true;
  }
  for (var i = 0; i < split.parts.length; i++) {
    final part = split.parts[i];
    final partBytes = await reusableDownloadBytes(
      PatchDownloader.splitPartPath(destPath, i),
      '$identity|${part.name}|${part.sha256}',
      part.size,
    );
    if (partBytes > 0) return true;
  }
  return false;
}
