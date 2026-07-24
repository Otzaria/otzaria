import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path/path.dart' as p;

/// היכן ליצור את קיצור הדרך.
enum ShortcutLocation {
  /// שולחן העבודה — נתמך בכל פלטפורמות הדסקטופ.
  desktop,

  /// תפריט ההתחל — Windows בלבד.
  startMenu,
}

/// שירות יצירת קיצורי דרך (deep-link) עבור גשר התוספים — `shortcut.create`.
///
/// יוצר קובץ קיצור תלוי-פלטפורמה שלחיצה עליו מפעילה קישור `otzaria://`:
/// Windows `.url`, macOS `.webloc`, Linux `.desktop`. כל הפעולה מתבצעת בצד
/// אוצריא (Flutter) — ה-WebView של התוסף נטען מ-origin `file://` ואינו יכול
/// לכתוב לדיסק.
///
/// **אבטחה:** הקורא ([PluginBridgeAdapter]) בונה את ה-deep-link בעצמו (תמיד
/// `otzaria://open/plugin/<id>`) ומאמת אישור משתמש. השירות לעולם אינו דורס
/// קובץ קיים — הוא מוצא שם פנוי, וכך גם אינו כותב דרך symlink קיים. הוא אינו
/// יוצר את תיקיית היעד; אם אין שולחן עבודה אמיתי, מוחזר `error.unsupported`.
class PluginShortcutService {
  const PluginShortcutService();

  /// יוצר קיצור דרך ל-[deepLink] עם השם [label] במיקום [location].
  ///
  /// מחזיר את הנתיב המלא של הקובץ שנוצר (שם ייחודי — לא דורס קיים). זורק
  /// [Exception] אם הפלטפורמה אינה דסקטופ, אם [location] אינו נתמך בפלטפורמה
  /// (`startMenu` ב-Windows בלבד), אם תיקיית היעד אינה קיימת, או אם שם הקובץ
  /// ריק לאחר ניקוי.
  Future<String> createShortcut({
    required String deepLink,
    required String label,
    ShortcutLocation location = ShortcutLocation.desktop,
  }) async {
    final safeLabel = sanitizeFileName(label);
    if (safeLabel.isEmpty) {
      throw Exception(
        'error.invalid_params: label produces an empty file name',
      );
    }

    final String dir;
    final String extension;
    final String content;
    var makeExecutable = false;

    if (Platform.isWindows) {
      dir = location == ShortcutLocation.startMenu
          ? await _windowsStartMenuDir()
          : await _windowsDesktopDir();
      extension = '.url';
      content = buildWindowsUrl(deepLink);
    } else if (Platform.isMacOS) {
      _rejectStartMenu(location);
      dir = _homeDesktopDir();
      extension = '.webloc';
      content = buildWebloc(deepLink);
    } else if (Platform.isLinux) {
      _rejectStartMenu(location);
      dir = await _linuxDesktopDir();
      extension = '.desktop';
      content = buildLinuxDesktop(deepLink, safeLabel);
      makeExecutable = true;
    } else {
      throw Exception(
        'error.unsupported: shortcuts are available on desktop only',
      );
    }

    // לא יוצרים את התיקייה — קיצור שמור רק במיקום שכבר קיים אצל המשתמש.
    if (!Directory(dir).existsSync()) {
      throw Exception('error.unsupported: target folder not found');
    }

    return writeUniqueShortcut(
      dirPath: dir,
      baseName: safeLabel,
      extension: extension,
      content: content,
      makeExecutable: makeExecutable,
    );
  }

  /// כותב את הקיצור לשם **פנוי** בתוך [dirPath] — לעולם אינו דורס קובץ קיים
  /// (כולל symlink): אם השם תפוס מוסיף " (N)" עד שנמצא שם פנוי. הבדיקה משתמשת
  /// ב-`followLinks: false` כך ש-symlink קיים נחשב תפוס ולא נכתב דרכו. מחזיר
  /// את הנתיב שנכתב בפועל.
  @visibleForTesting
  Future<String> writeUniqueShortcut({
    required String dirPath,
    required String baseName,
    required String extension,
    required String content,
    bool makeExecutable = false,
  }) async {
    var candidate = '$baseName$extension';
    var n = 2;
    while (FileSystemEntity.typeSync(
          p.join(dirPath, candidate),
          followLinks: false,
        ) !=
        FileSystemEntityType.notFound) {
      candidate = '$baseName ($n)$extension';
      n++;
    }
    final file = File(p.join(dirPath, candidate));
    await file.writeAsString(content);
    if (makeExecutable && Platform.isLinux) {
      // קובץ launcher בלינוקס חייב הרשאת הרצה כדי שסביבת שולחן העבודה תפעיל אותו.
      await Process.run('chmod', ['0755', file.path]);
    }
    return file.path;
  }

  void _rejectStartMenu(ShortcutLocation location) {
    if (location == ShortcutLocation.startMenu) {
      throw Exception(
        'error.unsupported: startMenu is available on Windows only',
      );
    }
  }

  // ── זיהוי תיקיית היעד (מכבד הפניות Known-Folder / XDG) ──

  Future<String> _windowsDesktopDir() async =>
      await _windowsShellFolder('Desktop') ??
      _envJoin('USERPROFILE', ['Desktop']);

  Future<String> _windowsStartMenuDir() async =>
      await _windowsShellFolder('Programs') ??
      _envJoin('APPDATA', ['Microsoft', 'Windows', 'Start Menu', 'Programs']);

  /// קורא נתיב תיקיית-מערכת מה-registry (מכבד הפניית OneDrive / Known Folder).
  /// מחזיר `null` אם הקריאה נכשלה — אז נופלים חזרה למשתנה הסביבה.
  Future<String?> _windowsShellFolder(String name) async {
    try {
      final result = await Process.run('reg', [
        'query',
        r'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Shell Folders',
        '/v',
        name,
      ]);
      if (result.exitCode != 0) return null;
      final match = RegExp(
        '$name'
        r'\s+REG_\w+\s+(.+)',
      ).firstMatch(result.stdout.toString());
      final raw = match?.group(1)?.trim();
      if (raw == null || raw.isEmpty) return null;
      return _expandWindowsEnv(raw);
    } catch (_) {
      return null;
    }
  }

  String _expandWindowsEnv(String path) =>
      path.replaceAllMapped(RegExp(r'%([^%]+)%'), (m) {
        return Platform.environment[m.group(1)!] ?? m.group(0)!;
      });

  /// תיקיית שולחן העבודה בלינוקס — מכבד `XDG_DESKTOP_DIR` דרך `xdg-user-dir`,
  /// ונופל חזרה ל-`$HOME/Desktop` אם הכלי אינו זמין.
  Future<String> _linuxDesktopDir() async {
    try {
      final result = await Process.run('xdg-user-dir', ['DESKTOP']);
      if (result.exitCode == 0) {
        final path = result.stdout.toString().trim();
        if (path.isNotEmpty) return path;
      }
    } catch (_) {
      // xdg-user-dir אינו מותקן — fallback למטה.
    }
    return _homeDesktopDir();
  }

  String _homeDesktopDir() => _envJoin('HOME', ['Desktop']);

  String _envJoin(String varName, List<String> parts) {
    final base = Platform.environment[varName];
    if (base == null || base.isEmpty) {
      throw Exception('error.internal: $varName not set');
    }
    return p.join(base, p.joinAll(parts));
  }

  /// תוכן קובץ `.url` של Windows (פורמט InternetShortcut, שורות CRLF).
  static String buildWindowsUrl(String deepLink) =>
      '[InternetShortcut]\r\nURL=$deepLink\r\n';

  /// תוכן קובץ `.webloc` של macOS (property list בפורמט XML).
  static String buildWebloc(String deepLink) =>
      '<?xml version="1.0" encoding="UTF-8"?>\n'
      '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" '
      '"http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n'
      '<plist version="1.0">\n'
      '<dict>\n'
      '\t<key>URL</key>\n'
      '\t<string>${_xmlEscape(deepLink)}</string>\n'
      '</dict>\n'
      '</plist>\n';

  /// תוכן קובץ `.desktop` של Linux. מפעיל את הקישור דרך `xdg-open`, שמנתב
  /// אותו ל-handler הרשום של סכמת `otzaria://`.
  static String buildLinuxDesktop(String deepLink, String label) =>
      '[Desktop Entry]\n'
      'Type=Application\n'
      'Name=$label\n'
      'Exec=xdg-open "$deepLink"\n'
      'Terminal=false\n';

  /// מנקה שם קובץ: מסיר תווים אסורים ב-Windows/Unix ותווי בקרה (כולל שורות
  /// חדשות), ומקצץ רווחים בקצוות.
  static String sanitizeFileName(String name) =>
      name.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), ' ').trim();

  static String _xmlEscape(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');
}
