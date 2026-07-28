import 'package:otzaria/data/data_providers/file_system_data_provider.dart';
import 'package:otzaria/settings/engine/settings_state.dart';

/// מחזיר האם יש להסיר ניקוד עבור ספר נתון.
///
/// [defaultRemoveNikud] - האם ברירת המחדל היא להסיר ניקוד.
/// [removeNikudFromTanach] - האם להסיר ניקוד גם מספרי תנ"ך.
/// [isTanach] - האם הספר הנוכחי שייך לתנ"ך.
bool shouldRemoveNikudForBook({
  required bool defaultRemoveNikud,
  required bool removeNikudFromTanach,
  required bool isTanach,
}) {
  return defaultRemoveNikud && (removeNikudFromTanach || !isTanach);
}

/// מחזיר האם יש להסיר פיסוק עבור ספר נתון. הסרת פיסוק אינה חלה על תנ"ך
/// (הכפתור מוסתר שם), ולכן ההחרגה היא חלק מהחוזה ולא מהמסך.
bool shouldRemovePunctuationForBook({
  required bool defaultRemovePunctuation,
  required bool isTanach,
}) {
  return defaultRemovePunctuation && !isTanach;
}

/// מחזיר האם שינוי מצב ההגדרות מחייב טעינה מחדש של ספר פתוח.
bool shouldReloadForNikudSettingsChange({
  required SettingsState previous,
  required SettingsState current,
}) {
  return previous.defaultRemoveNikud != current.defaultRemoveNikud ||
      previous.removeNikudFromTanach != current.removeNikudFromTanach;
}

/// מחזיר האם ברירת המחדל הגלובלית להסרת פיסוק השתנתה (מחייב טעינה מחדש).
bool shouldReloadForPunctuationSettingsChange({
  required SettingsState previous,
  required SettingsState current,
}) {
  return previous.defaultRemovePunctuation != current.defaultRemovePunctuation;
}

/// פותר האם להסיר ניקוד עבור ספר יעד, לפי הגדרות הניקוד והסיווג שלו.
Future<bool> resolveRemoveNikudForBook({
  required String title,
  required bool defaultRemoveNikud,
  required bool removeNikudFromTanach,
  int? categoryId,
  String? fileType,
}) async {
  if (!defaultRemoveNikud) {
    return false;
  }

  final isTanach = await FileSystemData.instance.isTanachBook(
    title,
    categoryId: categoryId,
    fileType: fileType,
  );

  return shouldRemoveNikudForBook(
    defaultRemoveNikud: defaultRemoveNikud,
    removeNikudFromTanach: removeNikudFromTanach,
    isTanach: isTanach,
  );
}
