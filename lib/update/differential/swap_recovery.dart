/// זיהוי החלפת עדכון שנקטעה, והפניית המעדכן העצמאי לסיים אותה.
///
/// השחזור עצמו אינו יכול לרוץ כאן: אוצריא רצה מתיקיית ההתקנה ומחזיקה את
/// קובצי ההרצה שלה נעולים. היא רק מזהה את העדות ומעירה את המעדכן, שממתין
/// ליציאתה בדיוק כמו בעדכון רגיל.
library;

import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../windows_installer.dart';
import 'swap_plan.dart';

/// תיקיית העבודה של העדכון המצומצם. חייבת להיות מחוץ לתיקיית ההתקנה —
/// הגיבוי שבתוכה הוא מה שמשחזר התקנה שההחלפה נקטעה באמצעה.
Directory differentialWorkDirectory() =>
    Directory(p.join(Directory.systemTemp.path, 'otzaria_small_update'));

/// שם קובץ המעדכן העצמאי בתיקיית ההתקנה.
const String kUpdaterHelperFileName = 'otzaria_updater.exe';

/// תוכנית ההחלפה שנקטעה באמצעה, או `null` כשאין כזו.
///
/// שתי בדיקות קיום בלבד — הבדיקה רצה בכל עלייה, והמקרה הרגיל חייב לעלות
/// כמעט כלום. תיקיית הגיבוי נוצרת רגע לפני שההחלפה נוגעת בהתקנה ונמחקת
/// בסיומה, ולכן קיומה לצד התוכנית הוא העדות שההחלפה לא הסתיימה.
File? pendingInterruptedSwapPlan(Directory workRoot) {
  final plan = File(p.join(workRoot.path, kSwapPlanFileName));
  if (!plan.existsSync()) return null;
  if (!Directory(p.join(workRoot.path, kSwapBackupDirName)).existsSync()) {
    return null;
  }
  return plan;
}

/// משגר את המעדכן כדי שישלים או יבטל את ההחלפה שנקטעה. מחזיר `true` רק אם
/// התהליך נוצר בפועל.
bool requestInterruptedSwapRecovery({
  required File planFile,
  required Directory installRoot,
  required int waitForPid,
  bool Function(String, {List<String> arguments}) launch =
      launchWindowsDetachedProcess,
}) {
  final helper = File(p.join(installRoot.path, kUpdaterHelperFileName));
  if (!helper.existsSync()) return false;
  return launch(
    helper.absolute.path,
    arguments: [
      '--plan',
      planFile.absolute.path,
      '--recover',
      '--no-relaunch',
      '--wait-pid',
      '$waitForPid',
    ],
  );
}

/// ממתין לסימן שהמעדכן ויתר על ההמתנה ליציאת אוצריא (חלון שסירב להיסגר).
/// בגילוי: מוחק את הסימן, עוצר, וקורא ל-[onGaveUp]. ה-staging נשאר שלם —
/// המעדכן מוותר לפני שנגע בדבר.
Timer watchForUpdaterGiveUp(
  Directory workRoot,
  void Function() onGaveUp, {
  Duration interval = const Duration(seconds: 3),
}) {
  final marker = File(p.join(workRoot.path, kSwapGaveUpFileName));
  return Timer.periodic(interval, (timer) {
    if (!marker.existsSync()) return;
    timer.cancel();
    try {
      marker.deleteSync();
    } on FileSystemException {
      // שיגור חוזר מוחק אותו בכל מקרה (writeSwapPlanFile).
    }
    onGaveUp();
  });
}
