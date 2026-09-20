import 'dart:io';

import 'package:otzaria/data/constants/database_constants.dart';
import 'package:path/path.dart' as path;

/// המיקום של קטלוג פרויקט השו"ת ושל האייקון שנגזר מההתקנה.
///
/// **באותה תיקייה שבה יושב `otzar-HB_catalog.db`** — כלומר ליד
/// `seforim.db`, ולא תחת `%LOCALAPPDATA%`. לשלושת הקטלוגים החיצוניים אותו
/// תפקיד ואותו מחזור חיים מבחינת המשתמש, ומיקום נפרד לאחד מהם פירושו
/// שגיבוי הספרייה אינו כולל אותו והעברת הספרייה משאירה אותו מאחור.
///
/// המחיר ידוע ומטופל: הקטלוג הזה **תלוי במחשב** — הוא נבנה מההתקנה
/// שעליו — ואילו שני האחרים אינם. ספרייה שעוברת בין מחשבים תביא איתה
/// קטלוג שנבנה מהתקנה אחרת. לכן הקטלוג נושא את `install_path` ואת טביעת
/// האצבע של ההתקנה שממנה נבנה, ומסך ההגדרות מציג בקשת רענון כשהם אינם
/// תואמים למה שיש על המחשב.
class ResponsaPaths {
  ResponsaPaths._();

  /// שם קובץ הקטלוג, באותו דפוס כמו `otzar-HB_catalog.db`.
  static const String catalogFileName = 'responsa_catalog.db';

  /// האייקון שחולץ מקובץ ההרצה של ההתקנה.
  ///
  /// לאוצר החכמה ולהיברובוקס הלוגו הוא נכס בחבילה; כאן הוא אינו יכול
  /// להיות כזה — זה סימן מסחרי של צד שלישי — ולכן הוא נגזר מההתקנה.
  /// המיקום עדיין זהה, כדי ששני הקבצים שהשילוב מייצר יישבו יחד.
  static const String iconFileName = 'responsa_icon.ico';

  /// עוקף את תיקיית הבסיס בבדיקות.
  static String? debugBaseDirectoryOverride;

  /// תיקיית הקטלוגים, או `null` בכל פלטפורמה שאינה Windows — פרויקט
  /// השו"ת הוא Win32 בלבד.
  ///
  /// קוראת מההגדרות, ולכן היא שייכת לאיזולט הראשי בלבד. שכבת הבנייה
  /// מקבלת נתיב מוחלט ואינה קוראת לכאן.
  static String? get baseDirectory {
    if (debugBaseDirectoryOverride case final override?) return override;
    if (!Platform.isWindows) return null;
    final directory = DatabaseConstants.getDatabaseDirectoryPath();
    return directory.isEmpty ? null : directory;
  }

  static String? get catalogPath => _in(catalogFileName);

  static String? get iconPath => _in(iconFileName);

  static String? _in(String fileName) {
    final base = baseDirectory;
    return base == null ? null : path.join(base, fileName);
  }
}
