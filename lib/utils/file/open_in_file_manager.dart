import 'dart:io';

/// פותח נתיב במנהל הקבצים של מערכת ההפעלה. נתיב ריק — אין פעולה.
Future<void> openInFileManager(String path) async {
  if (path.isEmpty) return;
  if (Platform.isWindows) {
    await Process.run('explorer', [path]);
  } else if (Platform.isMacOS) {
    await Process.run('open', [path]);
  } else if (Platform.isLinux) {
    await Process.run('xdg-open', [path]);
  }
}
