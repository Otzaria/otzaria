import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/book_common/utils/commentator_name_matching.dart';
import 'package:otzaria/book_common/utils/category_settings_utils.dart'
    as category_utils;
import 'package:otzaria/text_book/view/page_shape/utils/page_shape_commentary_selection.dart';

/// תחום השמירה של הגדרות התצוגה בצורת הדף.
enum PageShapeDisplaySettingsScope {
  book,
  workspace,
  global,
}

/// מנהל הגדרות צורת הדף - שומר ומטעין את בחירת המפרשים
///
/// סדר עדיפות בטעינה: ספר בשולחן העבודה → ספר → קטגוריה → ברירת מחדל (JSON)
class PageShapeSettingsManager {
  // מפתחות גלובליים (להגדרות תצוגה בלבד - לא למפרשים!)
  static const String _globalHighlightKey = 'page_shape_global_highlight';
  static const String _globalVisibilityPrefix = 'page_shape_global_visibility_';
  static const String _commentaryFontSizeKey =
      'page_shape_commentary_font_size';
  static const String _applyTextMaxWidthKey = 'page_shape_apply_text_max_width';

  // מפתחות פר-ספר
  static const String _bookConfigPrefix = 'page_shape_book_';
  static const String _bookHighlightPrefix = 'page_shape_highlight_';
  static const String _bookVisibilityPrefix = 'page_shape_visibility_';
  static const String _useBookSettingsPrefix = 'page_shape_use_book_settings_';
  static const String _bookViewModePrefix = 'page_shape_view_mode_';

  // מפתחות פר-שולחן עבודה
  static const String _workspaceConfigPrefix = 'page_shape_ws_config_';
  static const String _workspaceHighlightPrefix =
      'page_shape_workspace_highlight_';
  static const String _workspaceVisibilityPrefix =
      'page_shape_workspace_visibility_';
  static const String _useWorkspaceSettingsPrefix =
      'page_shape_use_workspace_settings_';

  // מפתחות פר-קטגוריה (חדש!)
  static const String _categoryConfigPrefix = 'page_shape_category_';

  // הטורים המוסתרים נשמרים לצד בחירת המפרשים, תחת מפתחה + סיומת זו
  static const String _hiddenColumnsSuffix = '_hidden_columns';
  static const List<String> _columns = [
    'left',
    'right',
    'bottom',
    'bottomRight',
  ];

  static const double defaultCommentaryFontSize = 16.0;

  // ==================== עזר לקטגוריות ====================
  // הלוגיקה המשותפת (פירוק heCategories, סינון קטגוריות כלליות) יושבת
  // ב-category_settings_utils.dart ומשותפת גם למפרשים הקבועים לקטגוריה.

  /// חילוץ רשימת קטגוריות מ-heCategories (מסנן קטגוריות כלליות מדי).
  static List<String> parseCategories(String? heCategories) =>
      category_utils.parseBookCategories(heCategories);

  /// קבלת קטגוריית האב הראשית (למשל "משנה תורה" מתוך "הלכה, משנה תורה, ספר מדע")
  static String? getParentCategory(String? heCategories) =>
      category_utils.parentBookCategory(heCategories);

  /// חילוץ שם בסיסי של מפרש (בלי שם הספר המפורש)
  /// למשל: "רמב"ן על ברכות" → "רמב"ן"
  /// למשל: "יכין מקואות" עם [commentedBookTitle] "משנה מקואות" → "יכין"
  static String? extractBaseCommentatorName(
    String? fullName, {
    String? commentedBookTitle,
  }) {
    return commentatorBaseName(
      fullName,
      commentedBookTitle: commentedBookTitle,
    );
  }

  // ==================== גודל גופן (גלובלי בלבד) ====================

  /// שמירת גודל גופן המפרשים (הגדרה גלובלית)
  static Future<void> saveCommentaryFontSize(double size) async {
    await Settings.setValue<double>(_commentaryFontSizeKey, size);
  }

  /// טעינת גודל גופן המפרשים
  static double getCommentaryFontSize() {
    return Settings.getValue<double>(_commentaryFontSizeKey) ??
        defaultCommentaryFontSize;
  }

  // ==================== החלת רוחב הטקסט (גלובלי) ====================

  /// שמירת הבחירה אם הגדרת "רוחב הטקסט" תחול גם בצורת הדף
  static Future<void> saveApplyTextMaxWidth(bool value) async {
    await Settings.setValue<bool>(_applyTextMaxWidthKey, value);
  }

  /// ברירת המחדל כבויה: בצורת הדף כל תיבה צרה ממילא,
  /// והצרה נוספת מבטלת את התצוגה במסכים קטנים (issue #1005).
  static bool getApplyTextMaxWidth() {
    return Settings.getValue<bool>(_applyTextMaxWidthKey) ?? false;
  }

  // ==================== בדיקה אם יש הגדרות פר-ספר ====================

  /// בדיקה אם הספר משתמש בהגדרות פר-ספר
  static bool hasBookSpecificSettings(String bookTitle) {
    return Settings.getValue<bool>('$_useBookSettingsPrefix$bookTitle') ??
        false;
  }

  /// הפעלה/כיבוי של הגדרות פר-ספר
  static Future<void> setUseBookSpecificSettings(
    String bookTitle,
    bool useBookSettings,
  ) async {
    await Settings.setValue<bool>(
      '$_useBookSettingsPrefix$bookTitle',
      useBookSettings,
    );
  }

  /// בדיקה אם שולחן העבודה משתמש בהגדרות תצוגה משלו.
  static bool hasWorkspaceSpecificSettings(String? workspaceId) {
    if (workspaceId == null || workspaceId.isEmpty) return false;
    return Settings.getValue<bool>(
          '$_useWorkspaceSettingsPrefix$workspaceId',
        ) ??
        false;
  }

  /// הפעלה/כיבוי של הגדרות תצוגה פר-שולחן עבודה.
  static Future<void> setUseWorkspaceSpecificSettings(
    String workspaceId,
    bool useWorkspaceSettings,
  ) async {
    await Settings.setValue<bool>(
      '$_useWorkspaceSettingsPrefix$workspaceId',
      useWorkspaceSettings,
    );
  }

  /// תחום התצוגה הפעיל: ספר קודם לשולחן עבודה, ושניהם קודמים לגלובלי.
  static PageShapeDisplaySettingsScope getDisplaySettingsScope(
    String bookTitle, {
    String? workspaceId,
  }) {
    if (hasBookSpecificSettings(bookTitle)) {
      return PageShapeDisplaySettingsScope.book;
    }
    if (hasWorkspaceSpecificSettings(workspaceId)) {
      return PageShapeDisplaySettingsScope.workspace;
    }
    return PageShapeDisplaySettingsScope.global;
  }

  // ==================== הגדרות מפרשים ====================

  /// מפתח בחירת המפרשים של ספר בשולחן עבודה מסוים.
  static String _workspaceConfigKey(String workspaceId, String bookTitle) {
    return '$_workspaceConfigPrefix${workspaceId}_$bookTitle';
  }

  /// טעינת הגדרות מפרשים - קודם שולחן העבודה, אחר כך ספר, אחר כך קטגוריה
  /// סדר עדיפות: שולחן עבודה + ספר → ספר → קטגוריה → null (יטען מ-JSON)
  static Map<String, String?>? loadConfiguration(
    String bookTitle, {
    String? heCategories,
    String? workspaceId,
  }) {
    final key = _activeConfigurationKey(
      bookTitle,
      heCategories: heCategories,
      workspaceId: workspaceId,
    );
    if (key == null) return null;
    return _parseConfiguration(Settings.getValue<String>(key));
  }

  /// מפתח ההגדרה השמורה שחלה על הספר, או null אם אין (ייטען מ-JSON).
  static String? _activeConfigurationKey(
    String bookTitle, {
    String? heCategories,
    String? workspaceId,
  }) {
    final candidates = [
      if (workspaceId != null && workspaceId.isNotEmpty)
        _workspaceConfigKey(workspaceId, bookTitle),
      '$_bookConfigPrefix$bookTitle',
      // מהקטגוריה הספציפית ביותר לכללית ביותר
      ...parseCategories(
        heCategories,
      ).reversed.map((category) => '$_categoryConfigPrefix$category'),
    ];
    for (final key in candidates) {
      if (Settings.getValue<String>(key) != null) return key;
    }
    return null;
  }

  /// טעינת בחירת המפרשים של ספר בשולחן עבודה מסוים (null אם אין).
  static Map<String, String?>? loadWorkspaceConfiguration(
    String? workspaceId,
    String bookTitle,
  ) {
    if (workspaceId == null || workspaceId.isEmpty) return null;
    return _parseConfiguration(
      Settings.getValue<String>(_workspaceConfigKey(workspaceId, bookTitle)),
    );
  }

  /// האם לשולחן העבודה יש בחירת מפרשים משלו לספר זה.
  static bool hasWorkspaceCommentatorConfig(
    String? workspaceId,
    String bookTitle,
  ) {
    return loadWorkspaceConfiguration(workspaceId, bookTitle) != null;
  }

  /// שולחן העבודה שאליו יש לשמור שינוי מפרשים, או null אם השמירה אינה
  /// פר-שולחן. משמש למסלולי השמירה שאינם עוברים בפאנל ההגדרות.
  static String? commentatorWorkspaceTarget(
    String? workspaceId,
    String bookTitle,
  ) {
    return hasWorkspaceCommentatorConfig(workspaceId, bookTitle)
        ? workspaceId
        : null;
  }

  /// בדיקה אם יש הגדרות לקטגוריה מסוימת
  static bool hasCategorySettings(String category) {
    final savedConfig = Settings.getValue<String>(
      '$_categoryConfigPrefix$category',
    );
    return savedConfig != null && savedConfig.isNotEmpty;
  }

  /// קבלת הקטגוריה שממנה נטענו ההגדרות (אם יש)
  static String? getActiveCategory(String? heCategories) =>
      category_utils.findActiveCategory(heCategories, hasCategorySettings);

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

  /// שמירת הגדרות מפרשים - לספר, לשולחן עבודה או לקטגוריה.
  /// [columnVisibility] נשמר לאותו יעד; null משאיר את הטורים המוסתרים כמות שהם.
  static Future<void> saveConfiguration(
    String bookTitle,
    Map<String, String?> config, {
    String? saveToCategory, // אם מוגדר - שומר לקטגוריה במקום לספר
    String? saveToWorkspaceId, // אם מוגדר - שומר לספר בשולחן עבודה זה
    Map<String, bool>? columnVisibility,
  }) async {
    final String key;
    if (saveToWorkspaceId != null && saveToWorkspaceId.isNotEmpty) {
      key = _workspaceConfigKey(saveToWorkspaceId, bookTitle);
      await Settings.setValue<String>(key, _serializeConfiguration(config));
    } else if (saveToCategory != null) {
      key = '$_categoryConfigPrefix$saveToCategory';
      // שמירה לקטגוריה - שומרים רק את השמות הבסיסיים של המפרשים
      final baseConfig = config.map((key, value) {
        if (isPageShapeRemainingCommentatorsValue(value) ||
            value == pageShapeMultipleCommentatorsModeValue) {
          return MapEntry(key, value);
        }

        return MapEntry(
          key,
          encodePageShapeCommentatorsSelection(
            decodePageShapeCommentatorsSelection(value)
                .map(
                  (name) => extractBaseCommentatorName(
                    name,
                    commentedBookTitle: bookTitle,
                  ),
                )
                .whereType<String>(),
            forceMultipleMode: isPageShapeMultipleCommentatorsMode(value),
          ),
        );
      });
      await Settings.setValue<String>(key, _serializeConfiguration(baseConfig));
    } else {
      // שמירה לספר ספציפי - שומרים את השמות המלאים
      key = '$_bookConfigPrefix$bookTitle';
      await Settings.setValue<String>(key, _serializeConfiguration(config));
    }

    if (columnVisibility != null) {
      await Settings.setValue<String>(
        '$key$_hiddenColumnsSuffix',
        _columns.where((c) => columnVisibility[c] == false).join(','),
      );
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

  /// טעינת הגדרת הדגשה - קודם פר-ספר, אחר כך פר-שולחן עבודה, ואז גלובלי.
  static bool getHighlightSetting(String bookTitle, {String? workspaceId}) {
    if (hasBookSpecificSettings(bookTitle)) {
      final bookSetting = Settings.getValue<bool>(
        '$_bookHighlightPrefix$bookTitle',
      );
      if (bookSetting != null) {
        return bookSetting;
      }
    }
    if (hasWorkspaceSpecificSettings(workspaceId)) {
      final workspaceSetting = Settings.getValue<bool>(
        '$_workspaceHighlightPrefix$workspaceId',
      );
      if (workspaceSetting != null) {
        return workspaceSetting;
      }
    }
    return Settings.getValue<bool>(_globalHighlightKey) ?? false;
  }

  /// שמירת הגדרת הדגשה
  static Future<void> saveHighlightSetting(
    String bookTitle,
    bool enabled, {
    bool saveAsGlobal = true,
    PageShapeDisplaySettingsScope? scope,
    String? workspaceId,
  }) async {
    final targetScope =
        scope ??
        (saveAsGlobal
            ? PageShapeDisplaySettingsScope.global
            : PageShapeDisplaySettingsScope.book);

    switch (targetScope) {
      case PageShapeDisplaySettingsScope.book:
        await Settings.setValue<bool>(
          '$_bookHighlightPrefix$bookTitle',
          enabled,
        );
        await setUseBookSpecificSettings(bookTitle, true);
      case PageShapeDisplaySettingsScope.workspace:
        if (workspaceId == null || workspaceId.isEmpty) {
          await Settings.setValue<bool>(_globalHighlightKey, enabled);
          return;
        }
        await Settings.setValue<bool>(
          '$_workspaceHighlightPrefix$workspaceId',
          enabled,
        );
        await setUseWorkspaceSpecificSettings(workspaceId, true);
      case PageShapeDisplaySettingsScope.global:
        await Settings.setValue<bool>(_globalHighlightKey, enabled);
    }
  }

  // ==================== הגדרות הצגת טורים ====================

  /// טעינת הצגת הטורים מאותה הגדרה שממנה נטענו המפרשים (שולחן עבודה ← ספר
  /// ← קטגוריה). אם שם לא נשמרו טורים - ההגדרה הישנה: ספר ← שולחן עבודה ← גלובלי.
  static Map<String, bool> getColumnVisibility(
    String bookTitle, {
    String? heCategories,
    String? workspaceId,
  }) {
    final configKey = _activeConfigurationKey(
      bookTitle,
      heCategories: heCategories,
      workspaceId: workspaceId,
    );
    final hidden = configKey == null
        ? null
        : Settings.getValue<String>('$configKey$_hiddenColumnsSuffix');
    if (hidden != null) {
      final hiddenColumns = hidden.split(',').toSet();
      return {for (final c in _columns) c: !hiddenColumns.contains(c)};
    }

    if (hasBookSpecificSettings(bookTitle)) {
      final bookVisibility = _getBookColumnVisibility(bookTitle);
      if (bookVisibility != null) {
        return bookVisibility;
      }
    }
    if (hasWorkspaceSpecificSettings(workspaceId)) {
      final workspaceVisibility = _getWorkspaceColumnVisibility(workspaceId!);
      if (workspaceVisibility != null) {
        return workspaceVisibility;
      }
    }
    return _getGlobalColumnVisibility();
  }

  static Map<String, bool> _getGlobalColumnVisibility() {
    return {
      'left': Settings.getValue<bool>('${_globalVisibilityPrefix}left') ?? true,
      'right':
          Settings.getValue<bool>('${_globalVisibilityPrefix}right') ?? true,
      'bottom':
          Settings.getValue<bool>('${_globalVisibilityPrefix}bottom') ?? true,
      'bottomRight':
          Settings.getValue<bool>('${_globalVisibilityPrefix}bottomRight') ??
          true,
    };
  }

  static Map<String, bool>? _getBookColumnVisibility(String bookTitle) {
    final left = Settings.getValue<bool>(
      '${_bookVisibilityPrefix}left_$bookTitle',
    );
    final right = Settings.getValue<bool>(
      '${_bookVisibilityPrefix}right_$bookTitle',
    );
    final bottom = Settings.getValue<bool>(
      '${_bookVisibilityPrefix}bottom_$bookTitle',
    );
    final bottomRight = Settings.getValue<bool>(
      '${_bookVisibilityPrefix}bottomRight_$bookTitle',
    );

    // אם אף אחד לא הוגדר, החזר null
    if (left == null &&
        right == null &&
        bottom == null &&
        bottomRight == null) {
      return null;
    }

    return {
      'left': left ?? true,
      'right': right ?? true,
      'bottom': bottom ?? true,
      'bottomRight': bottomRight ?? true,
    };
  }

  static Map<String, bool>? _getWorkspaceColumnVisibility(String workspaceId) {
    final left = Settings.getValue<bool>(
      '${_workspaceVisibilityPrefix}left_$workspaceId',
    );
    final right = Settings.getValue<bool>(
      '${_workspaceVisibilityPrefix}right_$workspaceId',
    );
    final bottom = Settings.getValue<bool>(
      '${_workspaceVisibilityPrefix}bottom_$workspaceId',
    );
    final bottomRight = Settings.getValue<bool>(
      '${_workspaceVisibilityPrefix}bottomRight_$workspaceId',
    );

    if (left == null &&
        right == null &&
        bottom == null &&
        bottomRight == null) {
      return null;
    }

    return {
      'left': left ?? true,
      'right': right ?? true,
      'bottom': bottom ?? true,
      'bottomRight': bottomRight ?? true,
    };
  }

  // ==================== העדפת תצוגה (page shape view) ====================

  /// שמירת העדפת תצוגה לספר - האם לפתוח בתצוגת צורת הדף
  static Future<void> saveViewModePreference(
    String bookTitle,
    bool showPageShapeView,
  ) async {
    await Settings.setValue<bool>(
      '$_bookViewModePrefix$bookTitle',
      showPageShapeView,
    );
  }

  /// טעינת העדפת תצוגה לספר - מחזיר null אם אין העדפה שמורה
  static bool? getViewModePreference(String bookTitle) {
    return Settings.getValue<bool>('$_bookViewModePrefix$bookTitle');
  }

  // ==================== איפוס הגדרות ====================

  /// איפוס הגדרות מפרשים פר-ספר בלבד
  static Future<void> resetBookCommentatorConfig(String bookTitle) async {
    await _removeConfiguration('$_bookConfigPrefix$bookTitle');
  }

  /// איפוס בחירת המפרשים של ספר בשולחן עבודה מסוים.
  static Future<void> resetWorkspaceCommentatorConfig(
    String? workspaceId,
    String bookTitle,
  ) async {
    if (workspaceId == null || workspaceId.isEmpty) return;
    await _removeConfiguration(_workspaceConfigKey(workspaceId, bookTitle));
  }

  /// מחיקת בחירת מפרשים יחד עם הטורים המוסתרים שנשמרו לצידה.
  static Future<void> _removeConfiguration(String key) async {
    await Settings.setValue<String?>(key, null);
    await Settings.setValue<String?>('$key$_hiddenColumnsSuffix', null);
  }

  /// איפוס הגדרות תצוגה פר-ספר בלבד (הדגשה ונראות טורים)
  static Future<void> resetBookDisplaySettings(String bookTitle) async {
    await setUseBookSpecificSettings(bookTitle, false);
    await Settings.setValue<bool?>('$_bookHighlightPrefix$bookTitle', null);
    await Settings.setValue<bool?>(
      '${_bookVisibilityPrefix}left_$bookTitle',
      null,
    );
    await Settings.setValue<bool?>(
      '${_bookVisibilityPrefix}right_$bookTitle',
      null,
    );
    await Settings.setValue<bool?>(
      '${_bookVisibilityPrefix}bottom_$bookTitle',
      null,
    );
    await Settings.setValue<bool?>(
      '${_bookVisibilityPrefix}bottomRight_$bookTitle',
      null,
    );
    await Settings.setValue<bool?>('$_bookViewModePrefix$bookTitle', null);
  }

  /// איפוס הגדרות תצוגה פר-שולחן עבודה בלבד.
  static Future<void> resetWorkspaceDisplaySettings(String? workspaceId) async {
    if (workspaceId == null || workspaceId.isEmpty) return;
    await setUseWorkspaceSpecificSettings(workspaceId, false);
    await Settings.setValue<bool?>(
      '$_workspaceHighlightPrefix$workspaceId',
      null,
    );
    await Settings.setValue<bool?>(
      '${_workspaceVisibilityPrefix}left_$workspaceId',
      null,
    );
    await Settings.setValue<bool?>(
      '${_workspaceVisibilityPrefix}right_$workspaceId',
      null,
    );
    await Settings.setValue<bool?>(
      '${_workspaceVisibilityPrefix}bottom_$workspaceId',
      null,
    );
    await Settings.setValue<bool?>(
      '${_workspaceVisibilityPrefix}bottomRight_$workspaceId',
      null,
    );
  }
}
