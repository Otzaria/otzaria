import 'dart:io';

import 'package:seforim_library_updater/seforim_library_updater.dart';

/// `<tempPath>.meta` הוא sidecar מפורמט ההורדה המקומי הישן, שכבר לא נכתב;
/// נשאר רק לניקוי שרידים ליד קובץ ה-temp.
String _sidecarPath(String tempPath) => '$tempPath.meta';

/// מוחק את ה-sidecar של [tempPath] (מתעלם מהיעדרו). יש לקרוא בכל מקום שבו
/// קובץ ה-temp נמחק.
Future<void> deleteDownloadSidecar(String tempPath) async {
  final file = File(_sidecarPath(tempPath));
  await file.delete().catchError((_) => file);
}

/// מוחק את ההורדה ב-[tempPath] ואת קובצי הצד שלה (`.meta` ו-`.resume`).
///
/// ⚠️ אם מחיקת הקובץ נכשלה, קובצי הצד נשמרים: בלעדיהם הניסיון הבא עלול
/// למחוק הורדה שלמה/חלקית תקינה או לחדש אותה ללא ולידטור.
Future<void> deleteDownloadWithSidecars(String tempPath) async {
  final file = File(tempPath);
  await file.delete().catchError((_) => file);
  if (await file.exists()) return;
  await deleteDownloadSidecar(tempPath);
  final resume = File(PatchDownloader.resumeSidecarPath(tempPath));
  await resume.delete().catchError((_) => resume);
}
