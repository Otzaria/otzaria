import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:otzaria/external_catalog/responsa/native/responsa_win32.dart';
import 'package:path/path.dart' as path;
import 'package:win32_registry/win32_registry.dart';

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

  String get executable => path.join(installPath, 'RESPONSA.exe');

  bool get exists => File(executable).existsSync();

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

/// גילוי ההתקנות של פרויקט השו"ת.
///
/// שני עקרונות:
///
/// * **מחזיר רשימה, לא התקנה יחידה.** אין מניעת single-instance, נתוני
///   המשתמש יכולים לשבת בתיקייה נפרדת, ויתכנו שתי מהדורות זו לצד זו.
/// * **מספר הגרסה נלקח מכל מקור שיש** — שם התיקייה, ה-`DisplayName`
///   ב-Registry, וכותרת החלון של מופע חי. אף אחד מהם אינו חובה.
class ResponsaInstallationDiscovery {
  ResponsaInstallationDiscovery._();

  static final RegExp _versionPattern = RegExp(
    r'ResponsaCD\s*(\d{1,3})',
    caseSensitive: false,
  );
  static final RegExp _hebrewVersionPattern = RegExp(r'גירסה\s*(\d{1,3})');
  static final RegExp _anyVersionPattern = RegExp(r'(\d{1,3})');

  static const List<String> _uninstallKeys = [
    r'SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall',
    r'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
  ];

  /// מספר הגרסה מתוך טקסט כלשהו — שם תיקייה, `DisplayName` או כותרת חלון.
  static int? versionFromText(String? text) {
    if (text == null || text.isEmpty) return null;
    for (final pattern in [_versionPattern, _hebrewVersionPattern]) {
      final match = pattern.firstMatch(text);
      if (match != null) return int.tryParse(match.group(1)!);
    }
    return null;
  }

  /// הגרסה מכותרת החלון של מופע חי (`פרוייקט השו"ת : גירסה 25`).
  ///
  /// זה המקור האמין ביותר: הוא מגיע מהתוכנה עצמה ולא מהמיקום שבו
  /// הותקנה, ולכן עובד גם בהתקנה שהועתקה או ששמה שונה.
  static int? versionFromWindowTitle(String title) {
    final byName = versionFromText(title);
    if (byName != null) return byName;
    final match = _anyVersionPattern.firstMatch(title);
    return match == null ? null : int.tryParse(match.group(1)!);
  }

  static List<ResponsaInstallation> discover() {
    final byPath = <String, ResponsaInstallation>{};
    for (final found in [
      ..._fromRegistry(),
      ..._fromFileSystem(),
      ..._fromRunningProcesses(),
    ]) {
      byPath.putIfAbsent(found.installPath.toLowerCase(), () => found);
    }
    final result = byPath.values.toList();
    // קודם כאלה שיש בהן קובץ הרצה, ואז לפי גרסה יורדת — המהדורה
    // החדשה ביותר היא ברירת מחדל סבירה כשיש כמה.
    result.sort((a, b) {
      final byExists = (a.exists ? 0 : 1).compareTo(b.exists ? 0 : 1);
      if (byExists != 0) return byExists;
      return (b.version ?? 0).compareTo(a.version ?? 0);
    });
    return result;
  }

  static List<ResponsaInstallation> _fromRegistry() {
    final found = <ResponsaInstallation>[];
    for (final keyPath in _uninstallKeys) {
      final RegistryKey base;
      try {
        base = LOCAL_MACHINE.open(keyPath);
      } catch (_) {
        continue;
      }
      try {
        for (final name in base.keys) {
          try {
            final display = base.getString('DisplayName', path: name) ?? '';
            final publisher = base.getString('Publisher', path: name) ?? '';
            if (!'$display$publisher'.toLowerCase().contains('responsa')) {
              continue;
            }
            var location = base.getString('InstallLocation', path: name) ?? '';
            location = location.replaceAll(RegExp(r'[\\/]+$'), '');
            if (location.isEmpty) continue;
            found.add(
              ResponsaInstallation(
                version:
                    versionFromText(path.basename(location)) ??
                    versionFromText(display),
                installPath: location,
                displayName: display.isEmpty ? name : display,
                source: 'registry',
              ),
            );
          } catch (_) {
            continue;
          }
        }
      } finally {
        base.close();
      }
    }
    return found;
  }

  /// גיבוי ל-Registry: סריקת `ResponsaCD*` תחת תיקיות התוכניות. התקנה
  /// שהועתקה ממחשב אחר אינה תמיד רשומה.
  static List<ResponsaInstallation> _fromFileSystem() {
    final roots = [
      Platform.environment['ProgramFiles(x86)'],
      Platform.environment['ProgramFiles'],
      Platform.environment['ProgramW6432'],
    ].whereType<String>();

    final found = <ResponsaInstallation>[];
    for (final root in roots) {
      final directory = Directory(root);
      if (!directory.existsSync()) continue;
      try {
        for (final entry in directory.listSync().whereType<Directory>()) {
          final name = path.basename(entry.path);
          if (!name.toLowerCase().startsWith('responsacd')) continue;
          found.add(
            ResponsaInstallation(
              version: versionFromText(name),
              installPath: entry.path,
              displayName: name,
              source: 'filesystem',
            ),
          );
        }
      } catch (_) {
        continue;
      }
    }
    return found;
  }

  /// המופעים הרצים ששייכים להתקנה נתונה, כזוגות `(hwnd, pid)`.
  ///
  /// ההשוואה היא לפי נתיב קובץ ההרצה. מופע ששייך להתקנה אחרת עלול
  /// להציג קטלוג אחר לגמרי.
  static List<({int hwnd, int pid})> instancesOf(String installPath) {
    final wanted = installPath.toLowerCase().replaceAll(RegExp(r'[\\/]+$'), '');
    return [
      for (final instance in ResponsaWin32.topWindowsByClass('ResponsaProject'))
        if (executableOf(instance.pid) case final executable?)
          if (path
                  .dirname(executable)
                  .toLowerCase()
                  .replaceAll(RegExp(r'[\\/]+$'), '') ==
              wanted)
            instance,
    ];
  }

  /// מופע שכבר רץ. מגלה גם התקנה שאינה רשומה ואינה תחת `Program Files`,
  /// ומוסר את הגרסה מכותרת החלון של התוכנה עצמה.
  static List<ResponsaInstallation> _fromRunningProcesses() {
    final found = <ResponsaInstallation>[];
    for (final instance in ResponsaWin32.topWindowsByClass('ResponsaProject')) {
      final title = ResponsaWin32.windowText(instance.hwnd);
      final executable = _executableOf(instance.pid);
      if (executable == null) continue;
      found.add(
        ResponsaInstallation(
          version: versionFromWindowTitle(title),
          installPath: path.dirname(executable),
          displayName: title.trim().isEmpty ? 'ResponsaProject' : title.trim(),
          source: 'runningProcess',
        ),
      );
    }
    return found;
  }

  /// נתיב קובץ ההרצה של מופע רץ.
  ///
  /// נדרש כדי לקשור מופע להתקנה: יכולים לרוץ כמה מופעים, ולכל אחד יכול
  /// להיות אתר נתונים אחר. קטלוג שנבנה ממופע אחד ותויג בטביעת אצבע של
  /// התקנה אחרת מתאר מאגר שאינו קיים.
  static String? executableOf(int pid) => _executableOf(pid);

  static String? _executableOf(int pid) => ResponsaWin32.processImagePath(pid);

  // ------------------------------------------------------- טביעת אצבע

  /// מעל הגודל הזה לא מחשבים SHA-256. `RESPONSA.exe` הוא ~3.9MB ולכן
  /// תמיד נכנס; המגבלה מגינה מפני שינוי מבנה עתידי.
  static const int _maxHashBytes = 64 * 1024 * 1024;

  static ResponsaFingerprint fingerprint(
    ResponsaInstallation installation, {
    bool withHash = true,
  }) {
    final archive = File(path.join(installation.installPath, 'DB', 'FILE00'));
    int? size;
    int? mtime;
    if (archive.existsSync()) {
      final stat = archive.statSync();
      size = stat.size;
      mtime = stat.modified.millisecondsSinceEpoch ~/ 1000;
    }
    return ResponsaFingerprint(
      version: installation.version,
      installPath: installation.installPath.replaceAll(RegExp(r'[\\/]+$'), ''),
      exeVersion: null,
      exeSha256: withHash ? _sha256(installation.executable) : null,
      file00Size: size,
      file00Mtime: mtime,
    );
  }

  static String? _sha256(String filePath) {
    try {
      final file = File(filePath);
      if (!file.existsSync() || file.lengthSync() > _maxHashBytes) return null;
      return sha256.convert(file.readAsBytesSync()).toString();
    } catch (e) {
      debugPrint('ResponsaInstallationDiscovery: hash failed: $e');
      return null;
    }
  }
}
