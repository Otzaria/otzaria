import 'package:path/path.dart' as p;

/// הנתיב המוחלט של קובץ ספר ([rawPath] מעמודת `book.filePath`) במסד מצורף
/// שב-[databasePath], או null כשהנתיב אינו מותר.
///
/// נתיב נפתר יחסית לתיקיית המסד בלבד. נדחים: נתיב מוחלט, UNC, אות כונן,
/// ונתיב שיוצא מהתיקייה (`..`) — מסד שאינו בשליטת התוכנה לא יפנה לקובץ אחר
/// במחשב.
String? resolveAttachedBookFilePath(String databasePath, String? rawPath) {
  final raw = rawPath?.trim();
  if (raw == null || raw.isEmpty) return null;
  final unified = raw.replaceAll('\\', '/');
  if (unified.startsWith('/') ||
      p.windows.isAbsolute(raw) ||
      p.posix.isAbsolute(unified) ||
      RegExp(r'^[A-Za-z]:').hasMatch(unified) ||
      unified.contains('\u0000')) {
    return null;
  }
  final segments = unified.split('/');
  // Windows מקצץ נקודות ורווחים בסוף רכיב, ו-':' פותח stream חלופי.
  if (unified.contains(':') ||
      segments.any((s) => s != '.' && RegExp(r'^[. ]+$').hasMatch(s))) {
    return null;
  }

  final folder = p.dirname(p.absolute(databasePath));
  final resolved = p.normalize(p.joinAll([folder, ...segments]));
  return p.isWithin(folder, resolved) ? resolved : null;
}
