import 'dart:convert';

/// מזהה את קובץ המנוע שה-host אימת לפני ההפעלה, בלי להפוך זאת למדידת heap.
Map<String, Object?>? parsePerfEngineIdentity(
  String source, {
  required String buildMode,
  required String platform,
}) {
  if (source.isEmpty) return null;
  final value = jsonDecode(source);
  if (value is! Map<String, dynamic>) {
    throw const FormatException('Engine identity must be a JSON object.');
  }
  const fields = {
    'schemaVersion',
    'platform',
    'architecture',
    'buildMode',
    'engineRevision',
    'bundleSha256',
    'verification',
    'expectedSha256',
  };
  if (value.keys.any((key) => !fields.contains(key)) ||
      value['schemaVersion'] is! int ||
      value['schemaVersion'] != 1 ||
      platform != 'windows' ||
      value['platform'] != platform ||
      value['architecture'] != 'x64' ||
      !const ['debug', 'profile', 'release'].contains(buildMode) ||
      value['buildMode'] != buildMode) {
    throw const FormatException('Engine identity does not match this build.');
  }
  bool digest(Object? candidate, int length) =>
      candidate is String &&
      RegExp('^[a-f0-9]{$length}\$').hasMatch(candidate);
  if (!digest(value['engineRevision'], 40) ||
      !digest(value['bundleSha256'], 64)) {
    throw const FormatException('Engine identity hashes are malformed.');
  }
  switch (value['verification']) {
    case 'bundle-sha256':
      if (value.containsKey('expectedSha256')) {
        throw const FormatException('Unverified engine cannot claim a patch hash.');
      }
    case 'patched-action-sha256':
      if (buildMode != 'release' ||
          !digest(value['expectedSha256'], 64) ||
          value['expectedSha256'] != value['bundleSha256']) {
        throw const FormatException('Patched engine identity does not match.');
      }
    default:
      throw const FormatException('Unknown engine verification method.');
  }
  return Map<String, Object?>.unmodifiable(value);
}
