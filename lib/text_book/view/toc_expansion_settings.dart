import 'package:flutter/foundation.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';

/// העדפות פתיחת עץ הניווט בעיון, משותפות לכל הספרים (#3236).
class TocExpansionSettings {
  TocExpansionSettings._();

  static const String levelKey = 'key-toc-expand-level';
  static const String autoExpandKey = 'key-toc-auto-expand';

  /// ערך [loadLevel] של "הרחב הכל".
  static const int expandAll = 0;

  /// עד איזו רמה העץ נפתח: 1 מכווץ, [expandAll] הכל, null ברירת המחדל
  /// (רמה 1 ושרשרת הילדים הראשונים).
  static int? loadLevel() =>
      Settings.isInitialized ? Settings.getValue<int>(levelKey) : null;

  static Future<void> saveLevel(int level) async {
    if (Settings.isInitialized) await Settings.setValue<int>(levelKey, level);
  }

  /// האם העץ פותח ענפים כדי להראות את הכותרת של מיקום הקריאה. ערך משותף
  /// כדי שכיבוי בספר אחד יחול מיד גם על ספרים פתוחים אחרים.
  static final ValueNotifier<bool> autoExpand = ValueNotifier<bool>(
    Settings.isInitialized
        ? Settings.getValue<bool>(autoExpandKey, defaultValue: true) ?? true
        : true,
  );

  static Future<void> saveAutoExpand(bool value) {
    autoExpand.value = value;
    return Settings.isInitialized
        ? Settings.setValue<bool>(autoExpandKey, value)
        : Future.value();
  }
}
