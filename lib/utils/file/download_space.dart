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

/// תפוסה נוספת בשיא החיבור, ומה שנשאר ממנו לקראת החילוץ.
typedef DownloadSpace = ({int peak, int retained});

/// תוספת השטח, בניכוי בייטים שניתנים להמשך לפי חוזה המוריד.
Future<DownloadSpace> additionalDownloadSpace({
  required String destPath,
  required String identity,
  required int size,
  SplitAsset? split,
}) async {
  if (split == null) {
    final remaining = size <= 0
        ? 0
        : size - await reusableDownloadBytes(destPath, identity, size);
    return (peak: remaining, retained: remaining);
  }
  final joined = await reusableDownloadBytes(
    destPath,
    '$identity|joined:${split.sha256}',
    split.size,
  );
  if (joined == split.size) return (peak: 0, retained: 0);
  var reusableParts = 0;
  for (var i = 0; i < split.parts.length; i++) {
    final part = split.parts[i];
    reusableParts += await reusableDownloadBytes(
      PatchDownloader.splitPartPath(destPath, i),
      '$identity|${part.name}|${part.sha256}',
      part.size,
    );
  }
  // החלקים נשארים עד שהארכיון המחובר נשמר, ונמחקים לפני החילוץ.
  return (
    peak: split.size * 2 - reusableParts,
    retained: split.size - reusableParts,
  );
}

/// האם נשמר קובץ חלקי של הנכס שהמוריד ימשיך ממנו (ראו [additionalDownloadSpace]).
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
