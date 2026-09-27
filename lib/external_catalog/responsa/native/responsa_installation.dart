import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:otzaria/external_catalog/responsa/native/responsa_installation_discovery.dart';
import 'package:otzaria/external_catalog/responsa/native/responsa_instance.dart';
import 'package:path/path.dart' as path;

/// ההתקנה שיש לעבוד מולה, יחד עם כל מופעיה החיים — כולל חונים.
typedef ResponsaSelection = ({
  ResponsaInstallation installation,
  List<ResponsaInstance> instances,
});

/// התקנה אחת של פרויקט השו"ת.
class ResponsaInstallation {
  final int? version;
  final String installPath;
  final String displayName;

  /// `registry` / `filesystem` / `runningProcess` — מאיפה היא נמצאה.
  final String source;

  const ResponsaInstallation({
    required this.version,
    required this.installPath,
    required this.displayName,
    required this.source,
  });

  String get executable =>
      path.join(installPath, ResponsaInstallationDiscovery.executableName);

  bool get exists => File(executable).existsSync();

  /// לפי שרשרת הפתרון של התוכנה (`Sh_hdisk` + `db\`). בהתקנה חלקית הארכיון על
  /// התקן נשלף שאות הכונן שלו משתנה, ו-`null` (לא מחובר) הוא מצב חוקי.
  String? get archivePath {
    final settings = iniSettings;
    for (final candidate in [
      if (settings['sh_hdisk'] case final value?)
        path.join(value, 'db', 'FILE00'),
      path.join(installPath, 'DB', 'FILE00'),
      if (dataLocation case final data?) path.join(data, 'DB', 'FILE00'),
      if (settings['sh_cdrom'] case final value?)
        path.join(value, 'db', 'FILE00'),
      for (final drive in ResponsaInstallationDiscovery.drives())
        path.join(drive, 'db', 'FILE00'),
    ]) {
      if (File(candidate).existsSync()) return candidate;
    }
    return null;
  }

  /// תיקיית נתוני המשתמש מ-`Responsa.env`; `null` כשהקובץ חסר - מצב חוקי.
  String? get dataLocation {
    for (final line in _readLines(path.join(installPath, 'Responsa.env'))) {
      final trimmed = line.trim();
      if (!trimmed.toLowerCase().startsWith('datalocation')) continue;
      final separator = trimmed.indexOf('=');
      if (separator < 0) continue;
      final value = trimmed.substring(separator + 1).trim();
      if (value.isNotEmpty) return value;
    }
    return null;
  }

  /// `Responsa.ini` ב-CP1255, ו-`readAsLinesSync` היה זורק ומפיל את כל הקובץ.
  /// `latin1` אחרון כי אינו זורק; ערך מעוות ייפסל ממילא בבדיקת קיום.
  static List<String> _readLines(String filePath) {
    final file = File(filePath);
    if (!file.existsSync()) return const [];
    late final List<int> bytes;
    try {
      bytes = file.readAsBytesSync();
    } catch (e) {
      debugPrint('ResponsaInstallation: cannot read $filePath: $e');
      return const [];
    }
    for (final codec in <Encoding>[utf8, systemEncoding, latin1]) {
      try {
        return const LineSplitter().convert(codec.decode(bytes));
      } catch (_) {
        continue;
      }
    }
    return const [];
  }

  /// `[Environment]` של `Responsa.ini`, במפתחות קטנים. הקובץ יושב באתר
  /// הנתונים ולא ליד קובץ ההרצה; מפה ריקה כשהוא חסר.
  Map<String, String> get iniSettings {
    final data = dataLocation;
    if (data == null) return const {};
    final values = <String, String>{};
    var inEnvironment = false;
    for (final line in _readLines(path.join(data, 'Responsa.ini'))) {
      final trimmed = line.trim();
      if (trimmed.startsWith('[')) {
        inEnvironment = trimmed.toLowerCase() == '[environment]';
        continue;
      }
      if (!inEnvironment) continue;
      final separator = trimmed.indexOf('=');
      if (separator <= 0) continue;
      final value = trimmed.substring(separator + 1).trim();
      if (value.isEmpty) continue;
      values[trimmed.substring(0, separator).trim().toLowerCase()] = value;
    }
    return values;
  }

  /// תווית ההתקן הנשלף שהתוכנה מחפשת (`RESPONSAV25`), אם היא רשומה.
  String? get volumeLabel => iniSettings['vollabel'];

  Map<String, Object?> toJson() => {
    'version': version,
    'installPath': installPath,
    'displayName': displayName,
    'source': source,
    'exists': exists,
  };
}

/// טביעת אצבע של התקנה — מה שקושר קטלוג שנבנה להתקנה שממנה נבנה.
class ResponsaFingerprint {
  final int? version;
  final String installPath;
  final String? exeVersion;
  final String? exeSha256;
  final int? file00Size;
  final int? file00Mtime;

  const ResponsaFingerprint({
    required this.version,
    required this.installPath,
    this.exeVersion,
    this.exeSha256,
    this.file00Size,
    this.file00Mtime,
  });

  Map<String, String> toMeta() => {
    if (version case final value?) 'responsa_version': '$value',
    'install_path': installPath,
    'exe_version': ?exeVersion,
    'exe_sha256': ?exeSha256,
    if (file00Size case final value?) 'file00_size': '$value',
    if (file00Mtime case final value?) 'file00_mtime': '$value',
  };

  static ResponsaFingerprint? fromMeta(Map<String, String> meta) {
    final installPath = meta['install_path'];
    if (installPath == null || installPath.isEmpty) return null;
    return ResponsaFingerprint(
      version: int.tryParse(meta['responsa_version'] ?? ''),
      installPath: installPath,
      exeVersion: meta['exe_version'],
      exeSha256: meta['exe_sha256'],
      file00Size: int.tryParse(meta['file00_size'] ?? ''),
      file00Mtime: int.tryParse(meta['file00_mtime'] ?? ''),
    );
  }

  /// שדה שחסר באחד הצדדים אינו מכשיל, אחרת קטלוג ישן נפסל בגלל שדה חדש.
  bool matches(ResponsaFingerprint? other) {
    if (other == null) return false;
    if (_conflicts(version, other.version)) return false;
    if (_conflicts(exeVersion, other.exeVersion)) return false;
    if (_conflicts(exeSha256, other.exeSha256)) return false;
    if (_conflicts(file00Size, other.file00Size)) return false;
    if (_conflicts(file00Mtime, other.file00Mtime)) return false;
    final mine = installPath.toLowerCase().replaceAll(RegExp(r'[\\/]+$'), '');
    final theirs = other.installPath.toLowerCase().replaceAll(
      RegExp(r'[\\/]+$'),
      '',
    );
    return mine == theirs;
  }

  static bool _conflicts(Object? a, Object? b) =>
      a != null && b != null && a != b;
}
