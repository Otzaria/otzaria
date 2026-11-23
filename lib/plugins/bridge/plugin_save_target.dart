import 'package:otzaria/utils/file/save_target_name.dart';

/// שם קובץ בטוח לדיאלוג „שמור בשם”: מסיר תווים שאינם חוקיים ומשלים סיומת.
///
/// התווים מוסרים כאן ולא נסמכים על הדיאלוג, שמתנהג שונה בכל פלטפורמה.
String pluginSaveFileName(String? requested, String? extension) =>
    saveTargetFileName(requested, extension);

/// מרכיב את נתיב היעד בתוך [folder], או `null` אם [fileName] חורג ממנה.
///
/// התוסף שולט בשם המוצע שממלא את שדה השם, ושם כמו ".." היה מפנה את הכתיבה
/// אל מחוץ לתיקייה שהמשתמש בחר.
String? pluginSaveTargetPath({
  required String folder,
  required String fileName,
}) => saveTargetPath(folder: folder, fileName: fileName);

/// כותרת לדיאלוג בחירת התיקייה בשלב הראשון של „שמור בשם” של תוסף.
String pluginSaveFolderDialogTitle(String? pluginTitle) =>
    saveTargetFolderDialogTitle(pluginTitle);
