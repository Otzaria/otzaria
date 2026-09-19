import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:otzaria/external_catalog/responsa/native/responsa_win32.dart';
import 'package:path/path.dart' as path;
import 'package:win32/win32.dart' show GetLogicalDrives;
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
    final file = File(path.join(installPath, 'Responsa.env'));
    if (!file.existsSync()) return null;
    try {
      for (final line in file.readAsLinesSync()) {
        final trimmed = line.trim();
        if (!trimmed.toLowerCase().startsWith('datalocation')) continue;
        final separator = trimmed.indexOf('=');
        if (separator < 0) continue;
        final value = trimmed.substring(separator + 1).trim();
        if (value.isNotEmpty) return value;
      }
    } catch (e) {
      debugPrint('ResponsaInstallation: cannot read Responsa.env: $e');
    }
    return null;
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
    final file = File(path.join(data, 'Responsa.ini'));
    if (!file.existsSync()) return const {};
    try {
      final values = <String, String>{};
      var inEnvironment = false;
      for (final line in file.readAsLinesSync()) {
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
    } catch (e) {
      debugPrint('ResponsaInstallation: cannot read Responsa.ini: $e');
      return const {};
    }
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
    // סדר העדיפות, מהחזק לחלש: קובץ הרצה קיים, ארכיון ספרים קיים,
    // מהדורה חדשה יותר.
    //
    // הארכיון אינו קישוט בסדר הזה: על המחשב הזה יושבת לצד ההתקנה גם
    // `ResponsaCD25H` — אתר נתונים משני של מופע מוסתר. בלי המבחן הזה
    // בחירה שרירותית בין השתיים תבנה קטלוג ממאגר אחד ותתייג אותו
    // בטביעת אצבע של אחר.
    result.sort((a, b) {
      final byExists = (a.exists ? 0 : 1).compareTo(b.exists ? 0 : 1);
      if (byExists != 0) return byExists;
      final byArchive = (a.archivePath == null ? 1 : 0).compareTo(
        b.archivePath == null ? 1 : 0,
      );
      if (byArchive != 0) return byArchive;
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

  /// שם קובץ ההרצה. תיקייה שמכילה אותו היא התקנה, איך שלא תיקרא.
  static const String executableName = 'RESPONSA.exe';

  /// תיקיות שמחפשים בהן בתוך כל כונן, מעבר לשורש עצמו.
  static const List<String> _searchSubdirectories = [
    'Program Files (x86)',
    'Program Files',
    'Bar-Ilan',
    'BarIlan',
  ];

  /// כמה רשומות לסרוק בתיקייה אחת. שורש כונן מכיל עשרות פריטים; התקרה
  /// מגינה מפני תיקייה חריגה שתעכב את הגילוי.
  static const int _maxEntriesPerDirectory = 400;

  /// גיבוי ל-Registry: סריקת **כל הכוננים** — קבועים, נשלפים ותקליטורים.
  ///
  /// שני מצבים שה-Registry אינו מכסה, ושניהם נפוצים:
  ///
  /// * התקנה שהועתקה ממחשב אחר ואינה רשומה.
  /// * **התקנה חלקית שרצה מהתקן נשלף** — קובץ ההרצה יושב על הכונן
  ///   הנשלף עצמו, מחוץ ל-`Program Files`, ואות הכונן משתנה ממחשב
  ///   למחשב. זיהוי לפי נתיב קבוע לא היה מוצא אותה כלל.
  ///
  /// הזיהוי אינו תלוי בשם התיקייה: תיקייה שיש בה [executableName] היא
  /// התקנה, גם אם שמה `שות בר אילן` וגם אם המהדורה עתידית.
  static List<ResponsaInstallation> _fromFileSystem() {
    final roots = <String>{
      for (final variable in const [
        'ProgramFiles(x86)',
        'ProgramFiles',
        'ProgramW6432',
      ])
        if (Platform.environment[variable] case final value?)
          if (value.isNotEmpty) value,
    };
    for (final drive in drives()) {
      roots.add(drive);
      for (final sub in _searchSubdirectories) {
        roots.add(path.join(drive, sub));
      }
    }

    final found = <ResponsaInstallation>[];
    final scanned = <String>{};

    /// סורק תיקייה אחת, ומחזיר את תתי-התיקיות שלה להמשך.
    List<Directory> scan(String root) {
      final directory = Directory(root);
      if (!scanned.add(root.toLowerCase())) return const [];
      if (!directory.existsSync()) return const [];
      final children = <Directory>[];
      try {
        var seen = 0;
        for (final entry in directory.listSync(followLinks: false)) {
          if (++seen > _maxEntriesPerDirectory) break;
          if (entry is! Directory) continue;
          final name = path.basename(entry.path);
          if (_skippedDirectories.contains(name.toLowerCase())) continue;
          children.add(entry);
          final looksRight = name.toLowerCase().startsWith('responsacd');
          if (!looksRight &&
              !File(path.join(entry.path, executableName)).existsSync()) {
            continue;
          }
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
        // כונן שאינו זמין, תיקייה ללא הרשאה — לא סיבה להפסיק את הסריקה.
      }
      return children;
    }

    for (final root in roots) {
      scan(root);
    }
    // רמה שנייה בשורש הכונן בלבד: התקנה שהועתקה יושבת לעתים קרובות
    // ב-`D:\תוכנות\בר אילן 25`, שאינה ב-Registry ואינה `Program Files`.
    // התיקיות הכבדות של המערכת מדולגות, והתקרה לכל תיקייה נשמרת.
    for (final drive in drives()) {
      for (final child in scan(drive)) {
        scan(child.path);
      }
    }
    return found;
  }

  /// תיקיות שאין בהן התקנה ושסריקתן יקרה.
  static const Set<String> _skippedDirectories = {
    'windows',
    'winnt',
    r'$recycle.bin',
    'system volume information',
    'users',
    'documents and settings',
    'programdata',
    'perflogs',
    'recovery',
    'msocache',
    'appdata',
    'node_modules',
    '.git',
  };

  /// אותיות הכוננים הקיימות במחשב, כנתיבי שורש (`E:\`).
  ///
  /// ציבורי כדי ש-[ResponsaInstallation.archivePath] יוכל לחפש את
  /// הארכיון על התקן נשלף, שאות הכונן שלו משתנה ממחשב למחשב.
  ///
  /// `GetLogicalDrives` הוא מפת ביטים בקריאה אחת, ולכן זול בהרבה
  /// מבדיקת 26 תיקיות — שכל אחת מהן על כונן מנותק עולה בהמתנה.
  static List<String> drives() {
    final mask = GetLogicalDrives().value;
    if (mask == 0) return const [];
    return [
      for (var index = 0; index < 26; index++)
        if ((mask & (1 << index)) != 0)
          '${String.fromCharCode(65 + index)}:${path.separator}',
    ];
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

  /// בוחר את ההתקנה שיש לעבוד מולה, יחד עם המופעים החיים שלה.
  ///
  /// סדר ההכרעה, וכל שלב בו נובע מכשל שנצפה:
  ///
  /// 1. **ההתקנה שנתיבה [preferredPath]** — זו שממנה נבנה הקטלוג.
  ///    הפניה שנבנתה ממאגר אחד אינה בהכרח מוליכה לאותו ספר במאגר אחר.
  /// 2. **ההתקנה הראשונה שיש לה מופע חי.** על מחשב עם שתי התקנות, אחת
  ///    מהן פתוחה, בחירה בשנייה מסתיימת ב"התוכנה אינה פעילה" בזמן
  ///    שהמשתמש רואה אותה פתוחה מולו.
  /// 3. ההתקנה המועדפת לפי דירוג הגילוי, גם בלי מופע חי — כדי שאפשר
  ///    יהיה להעלות אותה.
  ///
  /// `null` רק כשאין אף התקנה שימושית.
  static ({
    ResponsaInstallation installation,
    List<({int hwnd, int pid})> instances,
  })?
  selectInstallation({String? preferredPath}) {
    final installations = discover().where((i) => i.exists).toList();
    if (installations.isEmpty) return null;

    final wanted = preferredPath?.toLowerCase().replaceAll(
      RegExp(r'[\\/]+$'),
      '',
    );
    ResponsaInstallation? preferred;
    if (wanted != null && wanted.isNotEmpty) {
      for (final installation in installations) {
        final path = installation.installPath.toLowerCase().replaceAll(
          RegExp(r'[\\/]+$'),
          '',
        );
        if (path == wanted) {
          preferred = installation;
          break;
        }
      }
    }
    if (preferred != null) {
      return (
        installation: preferred,
        instances: instancesOf(preferred.installPath),
      );
    }

    for (final installation in installations) {
      final instances = instancesOf(installation.installPath);
      if (instances.isNotEmpty) {
        return (installation: installation, instances: instances);
      }
    }
    return (installation: installations.first, instances: const []);
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
    // בהתקנה חלקית הארכיון אינו יושב ליד קובץ ההרצה אלא באתר הנתונים
    // (או על ההתקן הנשלף). היעדרו אינו כשל — טביעת האצבע נשארת תקפה גם
    // בלעדיו, והיא מסתמכת אז על הנתיב, הגרסה ו-hash של קובץ ההרצה.
    int? size;
    int? mtime;
    if (installation.archivePath case final archive?) {
      final stat = File(archive).statSync();
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
