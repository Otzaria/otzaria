import 'package:path/path.dart' as p;

/// שם קובץ בטוח לדיאלוג „שמור בשם”: מסיר תווים שאינם חוקיים ומשלים סיומת.
///
/// התווים מוסרים כאן ולא נסמכים על הדיאלוג, שמתנהג שונה בכל פלטפורמה.
String pluginSaveFileName(String? requested, String? extension) {
  final cleaned = (requested ?? '')
      .replaceAll(RegExp(r'[\\/:*?"<>|]'), '')
      .trim();
  final base = cleaned.isEmpty ? 'מסמך' : cleaned;
  if (extension == null || extension.isEmpty) return base;
  return base.toLowerCase().endsWith('.$extension') ? base : '$base.$extension';
}

/// מרכיב את נתיב היעד בתוך [folder], או `null` אם [fileName] חורג ממנה.
///
/// התוסף שולט בשם המוצע שממלא את שדה השם, ושם כמו ".." היה מפנה את הכתיבה
/// אל מחוץ לתיקייה שהמשתמש בחר.
String? pluginSaveTargetPath({
  required String folder,
  required String fileName,
}) {
  final root = p.normalize(folder);
  final target = p.normalize(p.join(root, fileName));
  if (p.dirname(target) != root || p.basename(target) != fileName) return null;
  return target;
}
