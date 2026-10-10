import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// גרסת השחרור הקנונית, ללא מספר ה-hotfix שקופל לגרסת החנות ב-iOS.
String canonicalAppVersion(PackageInfo info) {
  final version = info.version.trim();
  final code = int.tryParse(info.buildNumber.trim());
  if (defaultTargetPlatform != TargetPlatform.iOS || code == null || code < 0) {
    return version;
  }
  final major = code ~/ 1000000;
  final minor = code ~/ 10000 % 100;
  final maintenance = code % 10000;
  if (version != '$major.$minor.$maintenance') return version;
  return '$major.$minor.${maintenance ~/ 100}';
}

/// גרסת האפליקציה בפורמט תג השחרור: `0.9.97.2` כשיש hotfix, אחרת `0.9.97`.
/// ה-hotfix הוא `buildNumber % 100`, רק כש-buildNumber הוא קוד הגרסה של אותה גרסה.
String appReleaseVersion(PackageInfo info) {
  final version = canonicalAppVersion(info);
  final parts = version.split('.').map(int.tryParse).toList();
  final code = int.tryParse(info.buildNumber.trim());
  if (parts.length != 3 || parts.contains(null) || code == null) {
    return version;
  }
  final base = parts[0]! * 10000 + parts[1]! * 100 + parts[2]!;
  final hotfix = code ~/ 100 == base ? code % 100 : 0;
  return hotfix > 0 ? '$version.$hotfix' : version;
}
