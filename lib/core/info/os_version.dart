import 'dart:async';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';

final _osDescription = OsDescriptionCache(
  platform: Platform.operatingSystem,
  rawVersion: Platform.operatingSystemVersion,
  readDetails: () async => (await DeviceInfoPlugin().deviceInfo).data,
);

/// מחמם פעם אחת אחרי חשיפת החלון; פתיחת טופס קוראת רק מהמטמון.
Future<void> warmUpOsVersion() => _osDescription.initialize();

/// גרסת מערכת ההפעלה לתצוגה ולדיווח.
///
/// ב-Windows 11 שם המוצר נשאר "Windows 10" לתאימות; Build 22000 ומעלה הוא
/// Windows 11. [raw] ו-[isWindows] נועדו לבדיקות.
String displayOsVersion({String? raw, bool? isWindows}) {
  if (raw == null && isWindows == null) return _osDescription.value;
  final version = raw ?? Platform.operatingSystemVersion;
  return _correctWindowsVersion(version, isWindows ?? Platform.isWindows);
}

String _correctWindowsVersion(String version, bool isWindows) {
  if (!isWindows) return version;
  final build = RegExp(r'Build (\d+)').firstMatch(version)?.group(1);
  if ((int.tryParse(build ?? '') ?? 0) < 22000) return version;
  return version.replaceFirst('Windows 10', 'Windows 11');
}

/// איסוף יחיד, גם בכשל; עד לסיומו זמינה מיד גרסת המערכת הבסיסית.
class OsDescriptionCache {
  OsDescriptionCache({
    required this.platform,
    required this.rawVersion,
    required this.readDetails,
    this.timeout = const Duration(seconds: 2),
  });

  final String platform;
  final String rawVersion;
  final Duration timeout;
  final Future<Map<String, dynamic>> Function() readDetails;
  String? _value;
  Future<void>? _initialization;

  String get value =>
      _value ?? _correctWindowsVersion(rawVersion, platform == 'windows');

  Future<void> initialize() => _initialization ??= _initialize();

  Future<void> _initialize() async {
    // Dart מספק ב-Windows מהדורה ו-build; שם המוצר מהתוסף עלול לאבד את תיקון Windows 11.
    if (platform == 'windows') return;
    try {
      final details = await readDetails().timeout(timeout);
      _value = describeOperatingSystem(platform, rawVersion, details);
    } catch (_) {
      // תוסף חסר, קובץ לא נגיש או timeout משאירים fallback בלי לנסות בכל פתיחת טופס.
    }
  }
}

/// בוחר פרטי מערכת ודגם, בלי שם מחשב, שם אישי של מכשיר או מזהים ייחודיים.
String describeOperatingSystem(
  String platform,
  String rawVersion,
  Map<String, dynamic> details,
) {
  String? text(Object? value) {
    if (value is! String && value is! num) return null;
    final result = value.toString().trim();
    return result.isEmpty ? null : result;
  }

  String join(Iterable<String?> parts) =>
      parts.whereType<String>().where((s) => s.isNotEmpty).join('; ');

  final description = switch (platform) {
    'linux' => join([
      text(details['prettyName']) ??
          [
            text(details['name']) ?? 'Linux',
            text(details['version']),
          ].whereType<String>().join(' '),
      rawVersion.isEmpty ? null : 'kernel $rawVersion',
    ]),
    'android' => () {
      final version = details['version'];
      final fields = version is Map ? version : const <String, Object?>{};
      return join([
        'Android ${text(fields['release']) ?? rawVersion}',
        if (text(fields['sdkInt']) case final String sdk) 'API $sdk',
        [
          text(details['manufacturer']),
          text(details['model']),
        ].whereType<String>().join(' '),
        if (text(details['display']) case final String build) 'build $build',
        if (text(fields['securityPatch']) case final String patch)
          'security patch $patch',
      ]);
    }(),
    'macos' => join([
      if (details['majorVersion'] is int && details['minorVersion'] is int)
        'macOS ${details['majorVersion']}.${details['minorVersion']}.'
            '${details['patchVersion'] is int ? details['patchVersion'] : 0}'
      else
        'macOS $rawVersion',
      if (text(details['osRelease']) case final String release)
        'Darwin $release',
    ]),
    'ios' => join([
      '${text(details['systemName']) ?? 'iOS'} '
          '${text(details['systemVersion']) ?? rawVersion}',
      if (details['utsname'] case final Map utsname) text(utsname['machine']),
      if (details['utsname'] case final Map utsname)
        if (text(utsname['release']) case final String release)
          'Darwin $release',
    ]),
    'windows' => _correctWindowsVersion(rawVersion, true),
    _ => rawVersion,
  };
  // חוזה הדיווח מגביל את השדה ל-200 תווים.
  return description.length <= 200
      ? description
      : description.substring(0, 200);
}
