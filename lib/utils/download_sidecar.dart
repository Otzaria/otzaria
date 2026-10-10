import 'dart:io';

/// `<tempPath>.meta` הוא sidecar מפורמט ההורדה המקומי הישן, שכבר לא נכתב;
/// נשאר רק לניקוי שרידים ליד קובץ ה-temp.
String _sidecarPath(String tempPath) => '$tempPath.meta';

/// מוחק את ה-sidecar של [tempPath] (מתעלם מהיעדרו). יש לקרוא בכל מקום שבו
/// קובץ ה-temp נמחק.
Future<void> deleteDownloadSidecar(String tempPath) async {
  final file = File(_sidecarPath(tempPath));
  await file.delete().catchError((_) => file);
}
