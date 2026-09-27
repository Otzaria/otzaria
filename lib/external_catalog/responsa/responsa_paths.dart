import 'dart:io';

import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/data/constants/database_constants.dart';
import 'package:path/path.dart' as path;

/// ליד שאר הקטלוגים ולא ב-`%LOCALAPPDATA%`, כדי שגיבוי והעברה יכללו אותו.
/// הקטלוג תלוי במחשב, ולכן נושא `install_path` לזיהוי ספרייה שעברה מחשב.
class ResponsaPaths {
  ResponsaPaths._();

  /// שם קובץ הקטלוג, באותו דפוס כמו `otzar-HB_catalog.db`.
  static const String catalogFileName = 'responsa_catalog.db';

  /// האייקון שחולץ מההתקנה - סימן מסחרי של צד שלישי, ולכן אינו נכס בחבילה.
  static const String iconFileName = 'responsa_icon.ico';

  /// קוראת מההגדרות, ולכן רק באיזולט הראשי - שכבת הבנייה מקבלת נתיב מוחלט.
  static String? get baseDirectory {
    if (!Platform.isWindows) return null;
    // מיקום הספרייה נקרא מההגדרות. לפני שהן אותחלו אין תשובה, והקריאה
    // עצמה זורקת — וכל הקוראים כאן מטפלים ב-`null` ממילא.
    if (!Settings.isInitialized) return null;
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
