import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'shell_quote.dart';

/// התקנת עדכון ב-macOS על ידי החלפת ה-bundle המותקן.
///
/// אי אפשר להחליף bundle בזמן שהאפליקציה רצה, ותהליך-בן ימות עם סגירתה.
/// לכן נכתב סקריפט `.command` שמשוגר דרך `open` — LaunchServices מריץ אותו
/// ב-Terminal כתהליך עצמאי ששורד את סגירת האפליקציה, ממתין ליציאתה, מחליף
/// את ה-bundle ומפעיל מחדש. בדומה לזרימת ההתקנה ב-Linux שפותחת טרמינל.

/// מחזירה את נתיב ה-bundle המותקן (`.../אוצריא.app`) שניתן להחליפו, או
/// `null` כשהאפליקציה רצה ממיקום שאינו מתאים לעדכון עצמי:
/// - App Translocation (הרצה ראשונה מקובץ עם quarantine) — הנתיב אקראי
///   וקריאה-בלבד, וההחלפה לא תגיע להתקנה האמיתית.
/// - הרצה ישירות מתוך DMG (תחת ‎/Volumes‎) — כרך קריאה-בלבד.
///
/// [executablePath] ניתן להזרקה בטסטים; ברירת המחדל היא
/// [Platform.resolvedExecutable] (למשל
/// `/Applications/אוצריא.app/Contents/MacOS/אוצריא`).
String? findInstalledMacAppBundlePath({String? executablePath}) {
  final exe = executablePath ?? Platform.resolvedExecutable;
  // המבנה הקבוע של bundle:‏ <app>.app/Contents/MacOS/<binary>
  final bundle = p.dirname(p.dirname(p.dirname(exe)));
  if (!bundle.endsWith('.app')) return null;
  if (bundle.contains('/AppTranslocation/')) return null;
  if (bundle.startsWith('/Volumes/')) return null;
  return bundle;
}

/// בונה את תוכן סקריפט העדכון: ממתין ליציאת אוצריא, מחלץ את ה-zip עם
/// `ditto` (משמר symlinks והרשאות, בניגוד לחילוץ ב-Dart), מחליף את
/// ה-bundle המותקן עם שחזור אוטומטי במקרה כשל, ומפעיל מחדש לפי
/// [relaunchApp] (עדכון יזום — כן; עדכון בעת סגירת התוכנה — לא).
@visibleForTesting
String buildMacUpdateScript({
  required String zipPath,
  required String appBundlePath,
  required int appPid,
  required bool relaunchApp,
}) {
  final app = shellQuote(appBundlePath);
  final zip = shellQuote(zipPath);
  return '''
#!/bin/bash
# סקריפט עדכון אוצריא — נוצר אוטומטית על ידי מנגנון העדכון ונמחק בסיומו.
set -euo pipefail

# בדיקת ההרשאה מתבצעת כאן, שם מתבצעת הכתיבה בפועל (למשל התקנה מערכתית).
APPDIR=\$(dirname $app)
if [ ! -w "\$APPDIR" ]; then
  echo "שגיאה: אין הרשאת כתיבה אל \$APPDIR" >&2
  echo "להתקנת העדכון יש להוריד את קובץ ה-DMG מדף ההורדות ולהתקין ידנית." >&2
  exit 1
fi

echo "ממתין לסגירת אוצריא..."
while kill -0 $appPid 2>/dev/null; do sleep 0.2; done

WORK=\$(mktemp -d)
trap 'rm -rf "\$WORK"' EXIT

echo "מחלץ את העדכון..."
ditto -x -k $zip "\$WORK"
NEW_APP=\$(find "\$WORK" -maxdepth 1 -name '*.app' -print -quit)
if [ -z "\$NEW_APP" ]; then
  echo "שגיאה: לא נמצאה אפליקציה בקובץ העדכון" >&2
  exit 1
fi

echo "מחליף את הגרסה המותקנת..."
OLD=$app.old.\$\$
mv $app "\$OLD"
if ! ditto "\$NEW_APP" $app; then
  echo "שגיאה בהתקנה — משחזר את הגרסה הקודמת" >&2
  rm -rf $app
  mv "\$OLD" $app
  exit 1
fi
rm -rf "\$OLD"
rm -f $zip
echo "העדכון הושלם בהצלחה"
${relaunchApp ? 'open -n $app\n' : ''}rm -f "\$0" || true
''';
}

/// כותבת את סקריפט העדכון לצד קובץ ה-zip ומשגרת אותו דרך `open`
/// (Terminal, כתהליך עצמאי). זורקת חריגה אם השיגור נכשל — הקורא מציג
/// את מצב השגיאה.
Future<void> installMacUpdate({
  required File zipFile,
  required String appBundlePath,
  required bool relaunchApp,
}) async {
  final scriptFile = File(
    p.join(p.dirname(zipFile.path), 'otzaria-update.command'),
  );
  await scriptFile.writeAsString(
    buildMacUpdateScript(
      zipPath: zipFile.absolute.path,
      appBundlePath: appBundlePath,
      appPid: pid,
      relaunchApp: relaunchApp,
    ),
  );
  await Process.run('chmod', ['+x', scriptFile.path]);

  final result = await Process.run('open', [scriptFile.path]);
  if (result.exitCode != 0) {
    throw Exception('Failed to launch macOS update script: ${result.stderr}');
  }
}
