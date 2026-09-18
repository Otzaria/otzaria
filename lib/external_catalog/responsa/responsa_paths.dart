import 'dart:io';

import 'package:path/path.dart' as path;

/// המיקום של קטלוג פרויקט השו"ת המקומי.
///
/// הקטלוג יושב תחת `%LOCALAPPDATA%` ולא ליד `seforim.db`, ובכוונה: הוא
/// נבנה מההתקנה שעל המחשב הזה ותלוי בה, בעוד שתיקיית `seforim.db`
/// מנוהלת על ידי המשתמש ועשויה לעבור בין מחשבים. קטלוג שיעבור איתה
/// יתאר התקנה שאינה קיימת.
class ResponsaPaths {
  ResponsaPaths._();

  static const String directoryName = 'ResponsaBridge';
  static const String catalogFileName = 'responsa_catalog.db';

  /// עוקף את תיקיית הבסיס בבדיקות.
  static String? debugBaseDirectoryOverride;

  /// תיקיית הבסיס, או `null` בכל פלטפורמה שאינה Windows — פרויקט השו"ת
  /// הוא Win32 בלבד.
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
}
