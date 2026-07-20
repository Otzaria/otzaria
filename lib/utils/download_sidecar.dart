import 'dart:io';

/// קושר קובץ temp של הורדה-עם-resume לגרסת הקובץ המרוחק, כדי ששריד ישן לא
/// יחולץ כאילו הוא עדכני ולא ייווצר franken-file מול release חדש.
///
/// ליד כל קובץ temp נשמר `<tempPath>.meta` המכיל מחרוזת זהות (etag/tag + גודל).
/// אם הזהות הנוכחית שונה מזו שנשמרה — או שאין sidecar כלל — יש למחוק את ה-temp
/// ולהתחיל מחדש.
String _sidecarPath(String tempPath) => '$tempPath.meta';

/// מחזיר את הזהות השמורה ליד [tempPath], או `null` אם אין sidecar.
Future<String?> readDownloadIdentity(String tempPath) async {
  final file = File(_sidecarPath(tempPath));
  if (!await file.exists()) return null;
  return (await file.readAsString()).trim();
}

/// כותב את מחרוזת ה-[identity] ל-sidecar של [tempPath] (בהתחלת הורדה טרייה).
Future<void> writeDownloadIdentity(String tempPath, String identity) async {
  await File(_sidecarPath(tempPath)).writeAsString(identity, flush: true);
}

/// מוחק את ה-sidecar של [tempPath] (מתעלם מהיעדרו). יש לקרוא בכל מקום שבו
/// קובץ ה-temp נמחק.
Future<void> deleteDownloadSidecar(String tempPath) async {
  final file = File(_sidecarPath(tempPath));
  await file.delete().catchError((_) => file);
}
