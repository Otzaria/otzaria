import 'package:flutter_settings_screens/flutter_settings_screens.dart';

/// מנהל הגדרות צורת הדף - שומר ומטעין את בחירת המפרשים
/// תומך בהגדרות גלובליות והגדרות פר-ספר (override)
class PageShapeSettingsManager {
  // מפתחות גלובליים
  static const String _globalConfigKey = 'page_shape_global_config';
  static const String _globalHighlightKey = 'page_shape_global_highlight';
  static const String _globalVisibilityPrefix = 'page_shape_global_visibility_';
  static const String _commentaryFontSizeKey = 'page_shape_commentary_font_size';
  
  // מפתחות פר-ספר
  static const String _bookConfigPrefix = 'page_shape_book_';
  static const String _bookHighlightPrefix = 'page_shape_highlight_';
  static const String _bookVisibilityPrefix = 'page_shape_visibility_';
  static const String _useBookSettingsPrefix = 'page_shape_use_book_settings_';
  
  static const double defaultCommentaryFontSize = 16.0;

  // ==================== גודל גופן (גלובלי בלבד) ====================
  
  /// שמירת גודל גופן המפרשים (הגדרה גלובלית)
  static Future<void> saveCommentaryFontSize(double size) async {
    await Settings.setValue<double>(_commentaryFontSizeKey, size);
  }

  /// טעינת גודל גופן המפרשים
  static double getCommentaryFontSize() {
    return Settings.getValue<double>(_commentaryFontSizeKey) ?? defaultCommentaryFontSize;
  }

  // ==================== בדיקה אם יש הגדרות פר-ספר ====================
  
  /// בדיקה אם הספר משתמש בהגדרות פר-ספר
  static bool hasBookSpecificSettings(String bookTitle) {
    return Settings.getValue<bool>('$_useBookSettingsPrefix$bookTitle') ?? false;
  }
  
  /// הפעלה/כיבוי של הגדרות פר-ספר
  static Future<void> setUseBookSpecificSettings(String bookTitle, bool useBookSettings) async {
    await Settings.setValue<bool>('$_useBookSettingsPrefix$bookTitle', useBookSettings);
  }

  // ==================== הגדרות מפרשים ====================
  
  /// טעינת הגדרות מפרשים - קודם בודק פר-ספר, אחר כך גלובלי
  static Map<String, String?>? loadConfiguration(String bookTitle) {
    // אם יש הגדרות פר-ספר, השתמש בהן
    if (hasBookSpecificSettings(bookTitle)) {
      final bookConfig = _loadBookConfiguration(bookTitle);
      if (bookConfig != null) {
        return bookConfig;
      }
    }
    
    // אחרת, השתמש בהגדרות גלובליות
    return _loadGlobalConfiguration();
  }
  
  /// טעינת הגדרות גלובליות
  static Map<String, String?>? _loadGlobalConfiguration() {
    final savedConfig = Settings.getValue<String>(_globalConfigKey);
    return _parseConfiguration(savedConfig);
  }
  
  /// טעינת הגדרות פר-ספר
  static Map<String, String?>? _loadBookConfiguration(String bookTitle) {
    final savedConfig = Settings.getValue<String>('$_bookConfigPrefix$bookTitle');
    return _parseConfiguration(savedConfig);
  }
  
  /// פענוח מחרוזת הגדרות
  static Map<String, String?>? _parseConfiguration(String? savedConfig) {
    if (savedConfig == null) {
      return null;
    }

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

  /// שמירת הגדרות מפרשים
  static Future<void> saveConfiguration(
    String bookTitle,
    Map<String, String?> config, {
    bool saveAsGlobal = true,
  }) async {
    final configString = _serializeConfiguration(config);
    
    if (saveAsGlobal) {
      // שמירה גלובלית
      await Settings.setValue<String>(_globalConfigKey, configString);
    } else {
      // שמירה פר-ספר
      await Settings.setValue<String>('$_bookConfigPrefix$bookTitle', configString);
      await setUseBookSpecificSettings(bookTitle, true);
    }
  }
  
  /// המרת הגדרות למחרוזת
  static String _serializeConfiguration(Map<String, String?> config) {
    final parts = <String>[];
    config.forEach((key, value) {
      parts.add('$key|${value ?? 'null'}');
    });
    return parts.join('||');
  }

  // ==================== הגדרת הדגשה ====================
  
  /// טעינת הגדרת הדגשה - קודם פר-ספר, אחר כך גלובלי
  static bool getHighlightSetting(String bookTitle) {
    if (hasBookSpecificSettings(bookTitle)) {
      final bookSetting = Settings.getValue<bool>('$_bookHighlightPrefix$bookTitle');
      if (bookSetting != null) {
        return bookSetting;
      }
    }
    return Settings.getValue<bool>(_globalHighlightKey) ?? false;
  }

  /// שמירת הגדרת הדגשה
  static Future<void> saveHighlightSetting(
    String bookTitle,
    bool enabled, {
    bool saveAsGlobal = true,
  }) async {
    if (saveAsGlobal) {
      await Settings.setValue<bool>(_globalHighlightKey, enabled);
    } else {
      await Settings.setValue<bool>('$_bookHighlightPrefix$bookTitle', enabled);
      await setUseBookSpecificSettings(bookTitle, true);
    }
  }

  // ==================== הגדרות הצגת טורים ====================
  
  /// טעינת הגדרות הצגת טורים - קודם פר-ספר, אחר כך גלובלי
  static Map<String, bool> getColumnVisibility(String bookTitle) {
    if (hasBookSpecificSettings(bookTitle)) {
      final bookVisibility = _getBookColumnVisibility(bookTitle);
      if (bookVisibility != null) {
        return bookVisibility;
      }
    }
    return _getGlobalColumnVisibility();
  }
  
  static Map<String, bool> _getGlobalColumnVisibility() {
    return {
      'left': Settings.getValue<bool>('${_globalVisibilityPrefix}left') ?? true,
      'right': Settings.getValue<bool>('${_globalVisibilityPrefix}right') ?? true,
      'bottom': Settings.getValue<bool>('${_globalVisibilityPrefix}bottom') ?? true,
    };
  }
  
  static Map<String, bool>? _getBookColumnVisibility(String bookTitle) {
    final left = Settings.getValue<bool>('${_bookVisibilityPrefix}left_$bookTitle');
    final right = Settings.getValue<bool>('${_bookVisibilityPrefix}right_$bookTitle');
    final bottom = Settings.getValue<bool>('${_bookVisibilityPrefix}bottom_$bookTitle');
    
    // אם אף אחד לא הוגדר, החזר null
    if (left == null && right == null && bottom == null) {
      return null;
    }
    
    return {
      'left': left ?? true,
      'right': right ?? true,
      'bottom': bottom ?? true,
    };
  }

  /// שמירת הגדרות הצגת טורים
  static Future<void> saveColumnVisibility(
    String bookTitle,
    Map<String, bool> visibility, {
    bool saveAsGlobal = true,
  }) async {
    if (saveAsGlobal) {
      await Settings.setValue<bool>('${_globalVisibilityPrefix}left', visibility['left'] ?? true);
      await Settings.setValue<bool>('${_globalVisibilityPrefix}right', visibility['right'] ?? true);
      await Settings.setValue<bool>('${_globalVisibilityPrefix}bottom', visibility['bottom'] ?? true);
    } else {
      await Settings.setValue<bool>('${_bookVisibilityPrefix}left_$bookTitle', visibility['left'] ?? true);
      await Settings.setValue<bool>('${_bookVisibilityPrefix}right_$bookTitle', visibility['right'] ?? true);
      await Settings.setValue<bool>('${_bookVisibilityPrefix}bottom_$bookTitle', visibility['bottom'] ?? true);
      await setUseBookSpecificSettings(bookTitle, true);
    }
  }

  // ==================== איפוס הגדרות פר-ספר ====================
  
  /// איפוס הגדרות פר-ספר (חזרה לגלובלי)
  static Future<void> resetBookSettings(String bookTitle) async {
    await setUseBookSpecificSettings(bookTitle, false);
    // מחיקת ההגדרות הספציפיות
    await Settings.setValue<String?>('$_bookConfigPrefix$bookTitle', null);
    await Settings.setValue<bool?>('$_bookHighlightPrefix$bookTitle', null);
    await Settings.setValue<bool?>('${_bookVisibilityPrefix}left_$bookTitle', null);
    await Settings.setValue<bool?>('${_bookVisibilityPrefix}right_$bookTitle', null);
    await Settings.setValue<bool?>('${_bookVisibilityPrefix}bottom_$bookTitle', null);
  }
}
