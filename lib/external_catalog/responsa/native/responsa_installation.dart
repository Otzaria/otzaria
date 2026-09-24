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

  /// נתיב ארכיון הספרים (`db\FILE00`), אם הוא נמצא.
  ///
  /// סדר החיפוש נגזר משרשרת פתרון הנתונים של התוכנה עצמה, כפי שתועדה
  /// מתוך מחרוזות `RESPONSA.exe` (`docs/56` §22–§24):
  /// `Responsa.env → DataLocation → Responsa.ini → [Environment]`,
  /// ונתיב המאגר הוא **`Sh_hdisk` + `db\`**.
  ///
  /// בהתקנה **חלקית** הארכיון אינו על הדיסק כלל — הוא על ההתקן הנשלף,
  /// והתוכנה מאתרת אותו לפי **תווית הכונן** (`VolLabel`). לכן נבדקים גם
  /// `Sh_cdrom` שב-INI (הנתיב שהתוכנה השתמשה בו לאחרונה) וגם שורש כל
  /// כונן — אות הכונן משתנה ממחשב למחשב, והתווית היא שמזהה.
  ///
  /// `null` הוא מצב חוקי: בהתקנה חלקית שבה ההתקן אינו מחובר כרגע אין
  /// ארכיון, וזה אינו מונע שימוש בהתקנה.
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

  /// תיקיית נתוני המשתמש, כפי שהיא רשומה ב-`Responsa.env`.
  ///
  /// בהתקנה מלאה היא יושבת תחת `Public\Documents`; היא יכולה לשבת
  /// במקום אחר. `null` כשהקובץ חסר או אינו קריא — מצב חוקי.
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

  /// קורא קובץ תצורה של התוכנה, שאינו UTF-8.
  ///
  /// `Responsa.ini` נכתב ב-ANSI עברי (CP1255): `Sh_cdrom` מכיל את
  /// הנתיב שממנו הותקנה התוכנה, ובו עברית. `readAsLinesSync` בברירת
  /// המחדל זורק `FileSystemException` על הבתים האלה, ואיתו נופל הקובץ
  /// כולו — כולל המפתחות שהם ASCII טהור.
  ///
  /// הסדר: UTF-8 (מהדורה עתידית), קידוד המערכת (Windows עברי),
  /// ו-`latin1` שלעולם אינו זורק. ערך שיתקבל מעוות יפסל ממילא בבדיקת
  /// קיום הקובץ.
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

  /// המקטע `[Environment]` של `Responsa.ini`, במפתחות קטנים.
  ///
  /// זהו המקור שהתוכנה עצמה קוראת ממנו: `Sh_hdisk` (נתיב הדיסק),
  /// `Sh_data`, `Sh_HD` (מטמון), `Sh_cdrom` (ההתקן) ו-`VolLabel`
  /// (תווית ההתקן). הקובץ יושב באתר הנתונים, לא ליד קובץ ההרצה.
  ///
  /// מפה ריקה כשהקובץ חסר או אינו קריא — כל הקוראים כאן מטפלים בכך.
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

  /// האם קטלוג שנבנה מ-[other] עדיין תקף להתקנה הזו.
  ///
  /// שדה שחסר באחד הצדדים אינו מכשיל — אחרת קטלוג ישן היה נפסל רק בגלל
  /// שדה שנוסף מאוחר יותר.
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
