import 'package:flutter_settings_screens/flutter_settings_screens.dart';

/// מנהל הגדרות צורת הדף - שומר ומטעין את בחירת המפרשים לכל ספר
class PageShapeSettingsManager {
  static const String _highlightPrefix = 'page_shape_highlight_';

  /// טעינת ההגדרות עבור ספר מסוים
  static Map<String, String?>? loadConfiguration(String bookTitle) {
    final savedConfig = Settings.getValue<String>('page_shape_$bookTitle');

    if (savedConfig == null) {
      return null;
    }

    // פורמט: "left|רשי||right|תוספות||bottom|מהרש"א||bottomRight|null"
    // משתמשים ב-|| כמפריד בין שדות ו-| כמפריד בין מפתח לערך
    // כדי לתמוך בשמות ספרים עם פסיקים
    final parts = savedConfig.split('||');
    final config = <String, String?>{};

    for (final part in parts) {
      final keyValue = part.split('|');
      if (keyValue.length == 2) {
        final key = keyValue[0];
        final value = keyValue[1] == 'null' ? null : keyValue[1];
        config[key] = value;
      }
    }

    return config;
  }

  /// שמירת ההגדרות עבור ספר מסוים
  static Future<void> saveConfiguration(
    String bookTitle,
    Map<String, String?> config,
  ) async {
    // פורמט: "left|רשי||right|תוספות||bottom|מהרש"א||bottomRight|null"
    final parts = <String>[];

    config.forEach((key, value) {
      parts.add('$key|${value ?? 'null'}');
    });

    final savedConfig = parts.join('||');
    await Settings.setValue<String>('page_shape_$bookTitle', savedConfig);
  }

  /// שמירת הגדרת הדגשה עבור ספר מסוים
  static Future<void> saveHighlightSetting(
      String bookTitle, bool enabled) async {
    await Settings.setValue<bool>('$_highlightPrefix$bookTitle', enabled);
  }

  /// טעינת הגדרת הדגשה עבור ספר מסוים
  /// ברירת מחדל: false (כבוי)
  static bool getHighlightSetting(String bookTitle) {
    return Settings.getValue<bool>('$_highlightPrefix$bookTitle') ?? false;
  }

  static const String _visibilityPrefix = 'page_shape_visibility_';

  /// פונקציית עזר ליצירת מפתח visibility
  static String _visibilityKey(String column, String bookTitle) =>
      '$_visibilityPrefix${column}_$bookTitle';

  /// שמירת הגדרות הצגת טורים עבור ספר מסוים
  static Future<void> saveColumnVisibility(
    String bookTitle,
    Map<String, bool> visibility,
  ) async {
    // שמירה נפרדת לכל טור - פשוט ובטוח יותר
    await Settings.setValue<bool>(
        _visibilityKey('left', bookTitle), visibility['left'] ?? true);
    await Settings.setValue<bool>(
        _visibilityKey('right', bookTitle), visibility['right'] ?? true);
    await Settings.setValue<bool>(
        _visibilityKey('bottom', bookTitle), visibility['bottom'] ?? true);
  }

  /// טעינת הגדרות הצגת טורים עבור ספר מסוים
  /// ברירת מחדל: כל הטורים מוצגים
  static Map<String, bool> getColumnVisibility(String bookTitle) {
    return {
      'left':
          Settings.getValue<bool>(_visibilityKey('left', bookTitle)) ?? true,
      'right':
          Settings.getValue<bool>(_visibilityKey('right', bookTitle)) ?? true,
      'bottom':
          Settings.getValue<bool>(_visibilityKey('bottom', bookTitle)) ?? true,
    };
  }
}
