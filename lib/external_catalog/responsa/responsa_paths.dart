import 'dart:io';

import 'package:path/path.dart' as path;

/// המיקומים המוסכמים בין אוצריא לגשר פרויקט השו"ת.
///
/// שני הקבצים נכתבים על ידי הגשר ונקראים כאן. הם יושבים תחת
/// `%LOCALAPPDATA%` של המשתמש ולא ליד `seforim.db`, ובכוונה: קטלוג
/// פרויקט השו"ת נבנה מההתקנה המקומית ותלוי בה, בעוד שהתיקייה של
/// `seforim.db` מנוהלת על ידי המשתמש ועשויה לעבור בין מחשבים.
class ResponsaPaths {
  ResponsaPaths._();

  static const String directoryName = 'ResponsaBridge';
  static const String catalogFileName = 'responsa_catalog.db';
  static const String discoveryFileName = 'responsa_bridge.json';

  /// עוקף את תיקיית הבסיס בבדיקות.
  static String? debugBaseDirectoryOverride;

  /// תיקיית הבסיס, או `null` כשאין `%LOCALAPPDATA%` (כל פלטפורמה שאינה
  /// Windows — ופרויקט השו"ת הוא Win32 בלבד).
  static String? get baseDirectory {
    if (debugBaseDirectoryOverride case final override?) return override;
    if (!Platform.isWindows) return null;
    final localAppData = Platform.environment['LOCALAPPDATA'];
    if (localAppData == null || localAppData.isEmpty) return null;
    return path.join(localAppData, directoryName);
  }

  static String? get catalogPath {
    final base = baseDirectory;
    return base == null ? null : path.join(base, catalogFileName);
  }

  static String? get discoveryPath {
    final base = baseDirectory;
    return base == null ? null : path.join(base, discoveryFileName);
  }
}
