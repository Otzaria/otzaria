import 'package:path/path.dart' as p;

/// סיומות שמערכת ההפעלה מריצה או מתקינה בלחיצה כפולה.
///
/// תוסף אינו מוציא קבצים כאלה מארגז החול שלו: קובץ הרצה שהמשתמש מפעיל עוקף
/// את כל ההרשאות, כולל רשימת ההיתר של הרשת.
const Set<String> pluginBlockedExecutableExtensions = {
  // Windows
  'exe', 'com', 'scr', 'pif', 'cpl', 'dll', 'msi', 'msp', 'mst', 'msix',
  'msixbundle', 'appx', 'appxbundle', 'appinstaller', 'application', 'bat',
  'cmd', 'ps1', 'psm1', 'vbs', 'vbe', 'js', 'jse', 'wsf', 'wsh', 'hta', 'lnk',
  'url', 'scf', 'reg', 'inf', 'msc',
  // חוצי-פלטפורמה
  'jar', 'py', 'pyw',
  // macOS / Linux
  'sh', 'bash', 'command', 'app', 'pkg', 'dmg', 'deb', 'rpm', 'appimage',
  'run', 'desktop',
  // Android
  'apk', 'xapk', 'apks',
};

/// האם [fileName] הוא קובץ הרצה, או חבילת יישום אם [isDirectory] מסומן.
bool isPluginBlockedExecutable(String fileName, {bool isDirectory = false}) {
  // Windows משמיט נקודות ורווחים בסוף השם: "a.exe." נשמר כ-a.exe.
  final name = p
      .basename(fileName.replaceAll('\\', '/'))
      .replaceAll(RegExp(r'[. ]+$'), '');
  final extension = p.extension(name).toLowerCase();
  return extension.length > 1 &&
      (!isDirectory || extension == '.app' || extension == '.pkg') &&
      pluginBlockedExecutableExtensions.contains(extension.substring(1));
}

/// זורקת `error.forbidden` כשתוסף מנסה לכתוב קובץ הרצה מחוץ לארגז החול שלו.
void rejectPluginExecutable(String fileName, {bool isDirectory = false}) {
  if (isPluginBlockedExecutable(fileName, isDirectory: isDirectory)) {
    throw Exception(
      'error.forbidden: תוספים אינם רשאים לשמור קבצי הרצה או התקנה '
      '(${p.basename(fileName.replaceAll('\\', '/'))})',
    );
  }
}
