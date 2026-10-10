import 'dart:io';

/// גרסת מערכת ההפעלה לתצוגה ולדיווח.
///
/// ב-Windows 11 שם המוצר נשאר "Windows 10" לתאימות; Build 22000 ומעלה הוא
/// Windows 11. [raw] ו-[isWindows] נועדו לבדיקות.
String displayOsVersion({String? raw, bool? isWindows}) {
  final version = raw ?? Platform.operatingSystemVersion;
  if (!(isWindows ?? Platform.isWindows)) return version;
  final build = RegExp(r'Build (\d+)').firstMatch(version)?.group(1);
  if ((int.tryParse(build ?? '') ?? 0) < 22000) return version;
  return version.replaceFirst('Windows 10', 'Windows 11');
}
