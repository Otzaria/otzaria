import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:path/path.dart' as p;

class PluginProtocolRegistrationService {
  static const String scheme = 'otzaria';
  static const String pluginFileExtension = '.otzplugin';
  static const String pluginFileProgId = 'OtzariaPluginFile';
  static const String pluginMimeType = 'application/x-otzaria-plugin';
  static const Duration _windowsRegistrationTimeout = Duration(seconds: 5);

  Future<void> ensureRegistered() async {
    // במצב נייד אין לרשום שיוכים מערכתיים: הרישום מצביע על נתיב EXE
    // שעלול להיעלם (דיסק-און-קי), ומשאיר שאריות ברגיסטרי/desktop של כל
    // מחשב מארח. התקנת תוספים עדיין זמינה דרך הממשק הפנימי.
    if (AppPaths.isPortable) {
      return;
    }

    if (Platform.isWindows) {
      await _ensureWindowsRegistration();
      return;
    }

    if (Platform.isLinux) {
      await _ensureLinuxRegistration();
    }
  }

  Future<void> _ensureWindowsRegistration() async {
    final exePath = Platform.resolvedExecutable;
    final regExecutable = resolveWindowsRegistryExecutable(
      Platform.environment,
    );
    final commands = buildWindowsRegistrationCommands(exePath);

    for (final arguments in commands) {
      final result =
          await Process.run(
            regExecutable,
            arguments,
          ).timeout(
            _windowsRegistrationTimeout,
            onTimeout: () => ProcessResult(
              0,
              -1,
              '',
              'Timed out after ${_windowsRegistrationTimeout.inSeconds} seconds',
            ),
          );
      if (result.exitCode != 0) {
        throw Exception(
          'רישום פרוטוקול התוספים נכשל: ${result.stderr}'.trim(),
        );
      }
    }
  }

  Future<void> _ensureLinuxRegistration() async {
    final home = Platform.environment['HOME'] ?? '';
    if (home.isEmpty) {
      throw Exception('לא ניתן לאתר את תיקיית הבית לרישום פרוטוקול בלינוקס');
    }

    final applicationsDir = Directory(
      p.join(home, '.local', 'share', 'applications'),
    );
    await applicationsDir.create(recursive: true);

    final mimePackagesDir = Directory(
      p.join(home, '.local', 'share', 'mime', 'packages'),
    );
    await mimePackagesDir.create(recursive: true);

    final desktopFile = File(p.join(applicationsDir.path, 'otzaria.desktop'));
    final executable = Platform.resolvedExecutable;
    final iconPath = p.join(
      p.dirname(executable),
      'data',
      'flutter_assets',
      'assets',
      'icon',
      'iconnew.png',
    );
    final desktopEntry = buildLinuxDesktopEntry(
      executable: executable,
      scheme: scheme,
      pluginMimeType: pluginMimeType,
      iconPath: File(iconPath).existsSync() ? iconPath : null,
    );

    await desktopFile.writeAsString(desktopEntry, flush: true);

    // שם האייקון שיוטמע ב-XML של ה-MIME וייעתק לתיקיית האייקונים.
    // freedesktop ממיר את שם ה-MIME (`application/x-otzaria-plugin`) ל-
    // `application-x-otzaria-plugin` כשהוא מחפש אייקון.
    const mimeIconName = 'application-x-otzaria-plugin';

    final mimeFile = File(p.join(mimePackagesDir.path, 'otzaria-plugin.xml'));
    await mimeFile.writeAsString(
      buildLinuxMimeXml(
        mimeType: pluginMimeType,
        extension: pluginFileExtension,
        iconName: mimeIconName,
      ),
      flush: true,
    );

    // ===== רישום קריטי — חייב להצליח =====
    await _runLinuxCommandIfAvailable('update-mime-database', [
      p.join(home, '.local', 'share', 'mime'),
    ]);
    await _runLinuxCommandIfAvailable('update-desktop-database', [
      applicationsDir.path,
    ]);
    await _runLinuxCommandIfAvailable('xdg-mime', [
      'default',
      p.basename(desktopFile.path),
      'x-scheme-handler/$scheme',
    ]);
    await _runLinuxCommandIfAvailable('xdg-mime', [
      'default',
      p.basename(desktopFile.path),
      pluginMimeType,
    ]);

    // ===== אייקון — תוספת קוסמטית =====
    // נריץ אחרי הרישום הקריטי וניתן ל-failures להיבלע, כדי שכשל
    // ב-gtk-update-icon-cache (למשל בלי index.theme) לא יבטל את השיוך עצמו.
    try {
      await _installLinuxMimeIcon(home, mimeIconName, executable);
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint(
          'התקנת אייקון MIME בלינוקס נכשלה (לא קריטי): $error\n$stackTrace',
        );
      }
    }
  }

  /// מעתיק את `otzplugin_file_icon.png` (256×256) ל-
  /// `~/.local/share/icons/hicolor/256x256/mimetypes/<mimeIconName>.png` ומרענן
  /// את מטמון האייקונים. אם קובץ המקור לא קיים — נדלג בשקט (התקנה
  /// פיתוחית/לא רגילה), והמערכת תציג אייקון גנרי.
  Future<void> _installLinuxMimeIcon(
    String home,
    String mimeIconName,
    String executable,
  ) async {
    final sourceIcon = File(
      p.join(
        p.dirname(executable),
        'data',
        'flutter_assets',
        'assets',
        'icon',
        'otzplugin_file_icon.png',
      ),
    );
    if (!await sourceIcon.exists()) {
      return;
    }

    final iconsRoot = p.join(home, '.local', 'share', 'icons', 'hicolor');
    final mimetypesDir = Directory(p.join(iconsRoot, '256x256', 'mimetypes'));
    await mimetypesDir.create(recursive: true);

    final destination = File(p.join(mimetypesDir.path, '$mimeIconName.png'));
    await sourceIcon.copy(destination.path);

    // gtk-update-icon-cache דורש ‎index.theme‎ בתיקיית התמה כדי להצליח.
    // ב-‎~/.local/share/icons/hicolor‎ הקובץ הזה בדרך כלל לא קיים (התמה
    // המערכתית יושבת ב-‎/usr/share/icons/hicolor‎), אז נריץ רק אם הוא קיים.
    // ה-MIME database עצמו יודע על האייקון דרך ‎mime-info‎ XML, וסביבות
    // עבודה רובן יסרקו מחדש את התיקייה בלי הקריאה הזו.
    final themeIndex = File(p.join(iconsRoot, 'index.theme'));
    if (await themeIndex.exists()) {
      await _runLinuxCommandIfAvailable('gtk-update-icon-cache', [
        '-f',
        '-t',
        iconsRoot,
      ]);
    }
  }

  Future<void> _runLinuxCommandIfAvailable(
    String executable,
    List<String> arguments,
  ) async {
    final lookup = await Process.run('which', [executable], runInShell: true);
    if (lookup.exitCode != 0) {
      return;
    }

    final result = await Process.run(executable, arguments, runInShell: true);
    if (result.exitCode != 0) {
      throw Exception(
        'רישום פרוטוקול בלינוקס נכשל עבור $executable: ${result.stderr}'.trim(),
      );
    }
  }

  @visibleForTesting
  static String buildLinuxDesktopEntry({
    required String executable,
    required String scheme,
    String? pluginMimeType,
    String? iconPath,
  }) {
    final mimeTypes = <String>[
      'x-scheme-handler/$scheme',
      if (pluginMimeType != null && pluginMimeType.trim().isNotEmpty)
        pluginMimeType,
    ];

    final lines = <String>[
      '[Desktop Entry]',
      'Version=1.0',
      'Type=Application',
      'Name=אוצריא',
      'Exec="$executable" %u',
      'Terminal=false',
      'MimeType=${mimeTypes.join(';')};',
      'Categories=Education;Utility;',
      'StartupNotify=true',
      if (iconPath != null && iconPath.trim().isNotEmpty) 'Icon=$iconPath',
    ];

    return '${lines.join('\n')}\n';
  }

  @visibleForTesting
  static String buildLinuxMimeXml({
    required String mimeType,
    required String extension,
    String? iconName,
  }) {
    final pattern = extension.startsWith('.') ? '*$extension' : '*.$extension';
    final iconLine = (iconName != null && iconName.trim().isNotEmpty)
        ? '    <icon name="$iconName"/>\n'
        : '';
    return '''<?xml version="1.0" encoding="UTF-8"?>
<mime-info xmlns="http://www.freedesktop.org/standards/shared-mime-info">
  <mime-type type="$mimeType">
    <comment>Otzaria plugin package</comment>
    <comment xml:lang="he">חבילת תוסף אוצריא</comment>
$iconLine    <glob pattern="$pattern"/>
  </mime-type>
</mime-info>
''';
  }

  @visibleForTesting
  static String resolveWindowsRegistryExecutable(
    Map<String, String> environment,
  ) {
    final windowsDirectory =
        environment['WINDIR'] ?? environment['SystemRoot'] ?? r'C:\Windows';
    return p.windows.join(windowsDirectory, 'System32', 'reg.exe');
  }

  @visibleForTesting
  static List<List<String>> buildWindowsRegistrationCommands(String exePath) {
    final command = '"$exePath" "%1"';
    final protocolRoot = r'HKCU\Software\Classes\otzaria';
    final progIdRoot = r'HKCU\Software\Classes\' + pluginFileProgId;
    final extensionRoot = r'HKCU\Software\Classes\' + pluginFileExtension;

    return <List<String>>[
      // ===== otzaria:// protocol =====
      ['add', protocolRoot, '/ve', '/d', 'URL:Otzaria Protocol', '/f'],
      ['add', protocolRoot, '/v', 'URL Protocol', '/d', '', '/f'],
      ['add', '$protocolRoot\\DefaultIcon', '/ve', '/d', exePath, '/f'],
      [
        'add',
        '$protocolRoot\\shell\\open\\command',
        '/ve',
        '/d',
        command,
        '/f',
      ],

      // ===== .otzplugin file association =====
      ['add', progIdRoot, '/ve', '/d', 'תוסף אוצריא', '/f'],
      // התקנת תוסף היא פעולה חד-פעמית; הדגל FTA_NoRecentDocs (0x00100000)
      // מונע מהמעטפת להוסיף את הקובץ ל"מסמכים אחרונים" / Jump List.
      [
        'add',
        progIdRoot,
        '/v',
        'EditFlags',
        '/t',
        'REG_DWORD',
        '/d',
        '0x00100000',
        '/f',
      ],
      // האייקון הייעודי לתוסף משובץ ב-EXE כמשאב שני
      // (IDI_OTZPLUGIN_FILE_ICON ב-Runner.rc); index ‎1 מצביע עליו.
      ['add', '$progIdRoot\\DefaultIcon', '/ve', '/d', '$exePath,1', '/f'],
      [
        'add',
        '$progIdRoot\\shell\\open\\command',
        '/ve',
        '/d',
        command,
        '/f',
      ],
      ['add', extensionRoot, '/ve', '/d', pluginFileProgId, '/f'],
      [
        'add',
        extensionRoot,
        '/v',
        'Content Type',
        '/d',
        pluginMimeType,
        '/f',
      ],
    ];
  }
}
