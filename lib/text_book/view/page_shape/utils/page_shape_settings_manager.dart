import 'package:flutter_settings_screens/flutter_settings_screens.dart';

/// מנהל הגדרות צורת הדף - שומר ומטעין את בחירת המפרשים
/// תומך בהגדרות גלובליות, הגדרות פר-קטגוריה, והגדרות פר-ספר (override)
/// 
/// סדר עדיפות בטעינה: ספר ספציפי → קטגוריה → ברירת מחדל (JSON)
class PageShapeSettingsManager {
  // מפתחות גלובליים (להגדרות תצוגה בלבד - לא למפרשים!)
  static const String _globalHighlightKey = 'page_shape_global_highlight';
  static const String _globalVisibilityPrefix = 'page_shape_global_visibility_';
  static const String _commentaryFontSizeKey = 'page_shape_commentary_font_size';
  
  // מפתחות פר-ספר
  static const String _bookConfigPrefix = 'page_shape_book_';
  static const String _bookHighlightPrefix = 'page_shape_highlight_';
  static const String _bookVisibilityPrefix = 'page_shape_visibility_';
  static const String _useBookSettingsPrefix = 'page_shape_use_book_settings_';
  
  // מפתחות פר-קטגוריה (חדש!)
  static const String _categoryConfigPrefix = 'page_shape_category_';
  
  static const double defaultCommentaryFontSize = 16.0;
  
  // קטגוריות כלליות מדי שלא כדאי לשמור עליהן הגדרות
  static const List<String> _tooGeneralCategories = [
    'אוצריא',
    'הלכה',
    'מדרש',
    'תנ"ך',
    'תלמוד',
    'קבלה',
    'מוסר',
    'מחשבה',
    'שו"ת',
  ];

  // ==================== עזר לקטגוריות ====================
  
  /// חילוץ רשימת קטגוריות מ-heCategories (מסנן קטגוריות כלליות מדי)
  /// למשל: "הלכה, משנה תורה, ספר מדע" → ["משנה תורה", "ספר מדע"]
  static List<String> parseCategories(String? heCategories) {
    if (heCategories == null || heCategories.isEmpty) {
      return [];
    }
    return heCategories
        .split(',')
        .map((c) => c.trim())
        .where((c) => c.isNotEmpty && !_tooGeneralCategories.contains(c))
        .toList();
  }
  
  /// קבלת קטגוריית האב הראשית (למשל "משנה תורה" מתוך "הלכה, משנה תורה, ספר מדע")
  static String? getParentCategory(String? heCategories) {
    final categories = parseCategories(heCategories);
    // מחזיר את הקטגוריה הראשונה (אחרי סינון הכלליות)
    if (categories.isNotEmpty) {
      return categories[0]; // למשל "משנה תורה"
    }
    return null;
  }
  
  /// חילוץ שם בסיסי של מפרש (בלי "על X")
  /// למשל: "רמב"ן על ברכות" → "רמב"ן"
  /// למשל: "השגות הראב"ד על משנה תורה, הלכות דעות" → "השגות הראב"ד"
  static String? extractBaseCommentatorName(String? fullName) {
    if (fullName == null) return null;
    
    // מחפשים "על " ולוקחים את מה שלפניו
    final onIndex = fullName.indexOf(' על ');
    if (onIndex > 0) {
      return fullName.substring(0, onIndex).trim();
    }
    
    // אם אין "על", מחזירים את השם כמו שהוא
    return fullName;
  }

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
  
  /// טעינת הגדרות מפרשים - קודם ספר, אחר כך קטגוריה
  /// סדר עדיפות: ספר ספציפי → קטגוריה → null (יטען מ-JSON)
  static Map<String, String?>? loadConfiguration(String bookTitle, {String? heCategories}) {
    // 1. קודם בודקים אם יש הגדרות לספר הספציפי
    final bookConfig = _loadBookConfiguration(bookTitle);
    if (bookConfig != null) {
      return bookConfig;
    }
    
    // 2. אם אין, בודקים אם יש הגדרות לקטגוריה
    if (heCategories != null) {
      final categoryConfig = _loadCategoryConfiguration(heCategories);
      if (categoryConfig != null) {
        return categoryConfig;
      }
    }
    
    // 3. אם אין - מחזירים null (יטען מ-JSON)
    return null;
  }
  
  /// טעינת הגדרות פר-ספר
  static Map<String, String?>? _loadBookConfiguration(String bookTitle) {
    final savedConfig = Settings.getValue<String>('$_bookConfigPrefix$bookTitle');
    return _parseConfiguration(savedConfig);
  }
  
  /// טעינת הגדרות פר-קטגוריה
  static Map<String, String?>? _loadCategoryConfiguration(String heCategories) {
    final categories = parseCategories(heCategories);
    
    // מחפשים מהקטגוריה הספציפית ביותר לכללית ביותר
    // למשל: "ספר מדע" → "משנה תורה" → "הלכה"
    for (int i = categories.length - 1; i >= 0; i--) {
      final category = categories[i];
      final savedConfig = Settings.getValue<String>('$_categoryConfigPrefix$category');
      final config = _parseConfiguration(savedConfig);
      if (config != null) {
        return config;
      }
    }
    
    return null;
  }
  
  /// בדיקה אם יש הגדרות לקטגוריה מסוימת
  static bool hasCategorySettings(String category) {
    final savedConfig = Settings.getValue<String>('$_categoryConfigPrefix$category');
    return savedConfig != null && savedConfig.isNotEmpty;
  }
  
  /// קבלת הקטגוריה שממנה נטענו ההגדרות (אם יש)
  static String? getActiveCategory(String? heCategories) {
    if (heCategories == null) return null;
    
    final categories = parseCategories(heCategories);
    for (int i = categories.length - 1; i >= 0; i--) {
      final category = categories[i];
      if (hasCategorySettings(category)) {
        return category;
      }
    }
    return null;
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

  /// שמירת הגדרות מפרשים - לספר או לקטגוריה
  static Future<void> saveConfiguration(
    String bookTitle,
    Map<String, String?> config, {
    String? saveToCategory, // אם מוגדר - שומר לקטגוריה במקום לספר
  }) async {
    if (saveToCategory != null) {
      // שמירה לקטגוריה - שומרים רק את השמות הבסיסיים של המפרשים
      final baseConfig = <String, String?>{};
      config.forEach((key, value) {
        baseConfig[key] = extractBaseCommentatorName(value);
      });
      final configString = _serializeConfiguration(baseConfig);
      await Settings.setValue<String>('$_categoryConfigPrefix$saveToCategory', configString);
    } else {
      // שמירה לספר ספציפי - שומרים את השמות המלאים
      final configString = _serializeConfiguration(config);
      await Settings.setValue<String>('$_bookConfigPrefix$bookTitle', configString);
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

  // ==================== איפוס הגדרות ====================
  
  /// איפוס כל הגדרות פר-ספר (מפרשים + תצוגה)
  static Future<void> resetBookSettings(String bookTitle) async {
    await resetBookCommentatorConfig(bookTitle);
    await resetBookDisplaySettings(bookTitle);
  }
  
  /// איפוס הגדרות מפרשים פר-ספר בלבד
  static Future<void> resetBookCommentatorConfig(String bookTitle) async {
    await Settings.setValue<String?>('$_bookConfigPrefix$bookTitle', null);
  }
  
  /// איפוס הגדרות תצוגה פר-ספר בלבד (הדגשה ונראות טורים)
  static Future<void> resetBookDisplaySettings(String bookTitle) async {
    await setUseBookSpecificSettings(bookTitle, false);
    await Settings.setValue<bool?>('$_bookHighlightPrefix$bookTitle', null);
    await Settings.setValue<bool?>('${_bookVisibilityPrefix}left_$bookTitle', null);
    await Settings.setValue<bool?>('${_bookVisibilityPrefix}right_$bookTitle', null);
    await Settings.setValue<bool?>('${_bookVisibilityPrefix}bottom_$bookTitle', null);
  }
  
  /// איפוס הגדרות קטגוריה
  static Future<void> resetCategorySettings(String category) async {
    await Settings.setValue<String?>('$_categoryConfigPrefix$category', null);
  }
}
