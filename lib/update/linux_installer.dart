import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'shell_quote.dart';

/// התקנת עדכון ב-Linux דרך מנהל החבילות של המערכת.
///
/// ההתקנה דורשת הרשאות root, ולכן הסקריפט רץ בטרמינל עם `pkexec` שמציג
/// למשתמש בקשת סיסמה (אין דרך לגיטימית לעקוף אותה). בסיום ההתקנה
/// הסקריפט מפעיל את אוצריא מחדש לפי אותה סמנטיקה כמו Windows ו-macOS:
/// עדכון יזום — כן; עדכון בעת סגירת התוכנה — לא.

/// פקודת ההתקנה למנהל חבילות נתון. הנתיב מצוטט לבטיחות.
@visibleForTesting
String buildLinuxInstallCommand({
  required String packageManager,
  required String packagePath,
}) {
  final quoted = shellQuote(packagePath);
  return switch (packageManager) {
    'apt' => 'apt install -y $quoted',
    'dnf' => 'dnf install -y $quoted',
    'yum' => 'yum install -y $quoted',
    'zypper' => 'zypper --non-interactive install $quoted',
    _ => throw ArgumentError('Unsupported package manager: $packageManager'),
  };
}

/// בונה את תוכן סקריפט העדכון: ממתין ליציאת אוצריא, מתקין את החבילה עם
/// pkexec (בקשת סיסמה), מנקה את קובץ החבילה, ומפעיל מחדש את
/// [relaunchExecutable] אם ניתן (nohup — כדי שסגירת הטרמינל לא תסגור את
/// התוכנה).
@visibleForTesting
String buildLinuxUpdateScript({
  required String installCommand,
  required String packagePath,
  required int appPid,
  String? relaunchExecutable,
}) {
  final pkg = shellQuote(packagePath);
  final relaunch = relaunchExecutable == null
      ? ''
      : 'nohup ${shellQuote(relaunchExecutable)} >/dev/null 2>&1 &\n';
  return '''
#!/bin/bash
# סקריפט עדכון אוצריא — נוצר אוטומטית על ידי מנגנון העדכון ונמחק בסיומו.
set -e

echo "ממתין לסגירת אוצריא..."
while kill -0 $appPid 2>/dev/null; do sleep 0.2; done

echo "מתקין את אוצריא..."
pkexec $installCommand
echo "ההתקנה הושלמה בהצלחה!"
rm -f $pkg
${relaunch}rm -f "\$0" || true
''';
}

Future<bool> _commandExists(String command) async {
  final result = await Process.run('which', [command]);
  return result.exitCode == 0;
}

Future<String?> _firstAvailableCommand(List<String> commands) async {
  for (final command in commands) {
    if (await _commandExists(command)) return command;
  }
  return null;
}

/// מתקין את קובץ החבילה שהורד (deb/rpm) ומפעיל מחדש לפי [relaunchApp].
/// זורק חריגה אם לא נמצא מנהל חבילות נתמך — הקורא נופל לפתיחת הקובץ
/// במתקין הגרפי של המערכת.
Future<void> installLinuxUpdate({
  required File packageFile,
  required bool relaunchApp,
}) async {
  final isDeb = packageFile.path.toLowerCase().endsWith('.deb');
  final packageManager = await _firstAvailableCommand(
    isDeb ? const ['apt'] : const ['dnf', 'zypper', 'yum'],
  );
  if (packageManager == null) {
    throw Exception('No supported package manager found');
  }

  final scriptFile = File(
    p.join(p.dirname(packageFile.path), 'otzaria-update.sh'),
  );
  await scriptFile.writeAsString(
    buildLinuxUpdateScript(
      installCommand: buildLinuxInstallCommand(
        packageManager: packageManager,
        packagePath: packageFile.absolute.path,
      ),
      packagePath: packageFile.absolute.path,
      appPid: pid,
      relaunchExecutable: relaunchApp ? Platform.resolvedExecutable : null,
    ),
  );
  await Process.run('chmod', ['+x', scriptFile.path]);

  // הרצה בטרמינל כדי שהמשתמש יראה את בקשת הסיסמה ואת ההתקדמות.
  const terminals = [
    'x-terminal-emulator',
    'gnome-terminal',
    'konsole',
    'xterm',
  ];
  for (final terminal in terminals) {
    if (await _commandExists(terminal)) {
      await Process.start(terminal, [
        '-e',
        scriptFile.path,
      ], mode: ProcessStartMode.detached);
      return;
    }
  }

  // ללא טרמינל: סוכן ה-polkit הגרפי עדיין יציג את בקשת הסיסמה.
  await Process.start('bash', [
    scriptFile.path,
  ], mode: ProcessStartMode.detached);
}
