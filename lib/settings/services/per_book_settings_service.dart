import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/models/books.dart';

/// מחלקה לניהול הגדרות פר-ספר
class PerBookSettings {
  /// מפתח קובץ יציב וייחודי לספר. שני ספרים עם אותו [Book.title] (ספר אישי מול
  /// רשמי, או קטגוריות שונות) חייבים מפתחות נפרדים כדי שלא ידרסו זה את הגדרות זה.
  /// קובצי PDF/קובץ ממופתחים לפי הנתיב הייחודי; ספרי DB לפי scope+קטגוריה+שם.
  static String bookKey(Book book) {
    final scope = book.isUserBook ? 'u' : 'o';
    if (book is FileBook) return '${scope}__${book.path}';
    final cat = book.categoryId?.toString() ?? 'x';
    return '${scope}__${cat}__${book.title}';
  }

  /// שם קובץ יציב באורך קבוע מהמפתח (hash). מונע התנגשות מהמרה לא-חד-חד-ערכית
  /// של נתיבים (a_b.pdf מול a\b.pdf) וחריגה ממגבלת אורך שם הקובץ.
  static String _hashKey(String key) =>
      sha1.convert(utf8.encode(key)).toString();

  /// תור סדרתי לפי קובץ (hash), למניעת דריסה הדדית בין קריאה-שינוי-כתיבה של
  /// שמירות, מחיקות וניקוי הרצות במקביל על אותו קובץ. ממופתח ב-hash כדי
  /// שגם הניקוי (שמכיר רק את שם הקובץ) וגם השמירות (שמכירות את המפתח) ינעלו
  /// על אותו ערך.
  static final Map<String, Future<void>> _fileLocks = {};

  /// מריץ [action] בזו-אחר-זו עם שאר הפעולות על אותו [lockKey] (hash הקובץ).
  static Future<T> runLocked<T>(
    String lockKey,
    Future<T> Function() action,
  ) async {
    final previous = _fileLocks[lockKey] ?? Future.value();
    // התעלמות מכשל קודם רק לצורך המשכיות התור; כל קורא מקבל את שגיאתו דרך await.
    final current = previous
        .then<void>((_) {}, onError: (_) {})
        .then((_) => action());
    final gate = current.then((_) {}, onError: (_) {});
    _fileLocks[lockKey] = gate;
    try {
      return await current;
    } finally {
      if (identical(_fileLocks[lockKey], gate)) {
        _fileLocks.remove(lockKey);
      }
    }
  }

  /// גרסת נוחות הנועלת לפי [key] של ספר (ממיר ל-hash פנימית).
  static Future<T> runLockedForKey<T>(
    String key,
    Future<T> Function() action,
  ) => runLocked(_hashKey(key), action);

  /// ממתין לסיום כל פעולות ההגדרות הפר-ספריות שיצאו לדרך.
  ///
  /// חובה לפני מחיקת תיקיית ההגדרות: שמירה שלא ממתינים לה מחזיקה את הקובץ
  /// פתוח (המחיקה נכשלת ב-Windows) ומחזירה אותו לחיים אחרי המחיקה.
  /// אינו זורק (ה-gates בולעים שגיאות). אין לקרוא מתוך [runLocked] — המתנה
  /// לתור שאתה עצמך חוסם היא דדלוק. מכסה פעולה מרגע כניסתה לתור;
  /// [cleanupRedundantSettings] סורק את התיקייה לפני כן, ולכן מגן על עצמו
  /// בבדיקות קיום בתוך הנעילה במקום להסתמך על ה-barrier.
  static Future<void> settle() async {
    // כל ערך הוא הפעולה האחרונה בתור של קובץ, והתור סדרתי — ההמתנה לו
    // מכסה את כולו. הלולאה קולטת פעולות שנוספו בזמן ההמתנה.
    while (_fileLocks.isNotEmpty) {
      await Future.wait(_fileLocks.values.toList());
    }
  }

  /// תאימות לאחור: קבצים ישנים מופתחו לפי שם הספר בלבד. אם אין קובץ למפתח
  /// החדש אך קיים קובץ-מורשת לפי השם — מעתיקים אותו (copy, לא rename) כדי
  /// שגם ספר נוסף בעל אותו שם יוכל לרשת את ההגדרות הישנות. בהעתקה, שדות
  /// ששווים לברירת המחדל הגלובלית מנורמלים החוצה כדי שהספר יירש שינויים
  /// עתידיים בברירת המחדל במקום לקבע override מיושן.
  static Future<void> _migrateLegacyFile(String key, String legacyName) async {
    try {
      final dir = await _getSettingsDirectory();
      final newPath = '${dir.path}/settings_${_hashKey(key)}.json';
      if (await File(newPath).exists()) return;
      final legacyPath =
          '${dir.path}/settings_${_sanitizeBookName(legacyName)}.json';
      if (newPath == legacyPath) return;
      final legacyFile = File(legacyPath);
      if (!await legacyFile.exists()) return;

      final normalized = _normalizeAgainstGlobalDefaults(
        await legacyFile.readAsString(),
      );
      if (normalized == null) {
        await legacyFile.copy(newPath);
      } else if (normalized.isEmpty) {
        // הכל זהה לברירת המחדל: tombstone מונע מיגרציה חוזרת שתחיה את
        // ה-override אם ברירת המחדל תשתנה בעתיד.
        await saveSettings(key, const {resetMarker: true});
      } else {
        await saveSettings(key, normalized);
      }
    } catch (e) {
      debugPrint('❌ Error migrating per-book settings: $e');
    }
  }

  /// מסיר מ-JSON של legacy שדות ששווים לברירת המחדל הגלובלית הנוכחית.
  /// מחזיר null כשאי-אפשר לנרמל (JSON פגום או Settings לא מאותחל) —
  /// ואז ההעתקה נשארת גולמית כבעבר.
  static Map<String, dynamic>? _normalizeAgainstGlobalDefaults(String raw) {
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final cleaned = Map<String, dynamic>.of(json);
      if (cleaned['fontSize'] ==
          (Settings.getValue<double>('key-font-size') ?? 25.0)) {
        cleaned.remove('fontSize');
      }
      if (cleaned['removeNikud'] ==
          (Settings.getValue<bool>('key-default-nikud') ?? false)) {
        cleaned.remove('removeNikud');
      }
      _removeRedundantPunctuationFields(
        cleaned,
        defaultRemovePunctuation:
            Settings.getValue<bool>('key-default-remove-punctuation') ?? false,
      );
      if (cleaned['commentatorsBelow'] ==
          !(Settings.getValue<bool>('key-splited-view') ?? true)) {
        cleaned.remove('commentatorsBelow');
      }
      if (cleaned['continuousReadingMode'] ==
          (Settings.getValue<bool>('key-continuous-reading-mode') ?? false)) {
        cleaned.remove('continuousReadingMode');
      }
      return cleaned;
    } catch (_) {
      return null;
    }
  }

  /// מסיר override של פיסוק ששווה לברירת המחדל האפקטיבית של הספר.
  /// בתנ"ך (דגל isTanach שנשמר לצד ה-override) הסרת פיסוק אינה חלה —
  /// ברירת המחדל האפקטיבית בו תמיד false, ללא תלות בהגדרה הגלובלית.
  static void _removeRedundantPunctuationFields(
    Map<String, dynamic> cleaned, {
    required bool defaultRemovePunctuation,
  }) {
    final effectiveDefault =
        defaultRemovePunctuation && cleaned['isTanach'] != true;
    if (cleaned['removePunctuation'] == effectiveDefault) {
      cleaned.remove('removePunctuation');
    }
    // הדגל הוא לוויין של ה-override; בלעדיו אין לו משמעות.
    if (!cleaned.containsKey('removePunctuation')) {
      cleaned.remove('isTanach');
    }
  }

  /// סמן "אופס" בקובץ ההגדרות. נכתב במקום מחיקה כשקיים קובץ-מורשת, כדי
  /// שהמיגרציה לא תשחזר את ההגדרות הישנות מ-legacy בפתיחה הבאה.
  static const String resetMarker = '__reset__';

  /// איפוס/מחיקת הגדרות ספר. אם קיים קובץ-מורשת לאותו שם — כותבים tombstone
  /// במקום מחיקה (כך שהמיגרציה לא תשחזר, וה-legacy המשותף נשאר לספרים אחרים
  /// בעלי אותו שם שטרם עברו מיגרציה). אחרת — מחיקה רגילה ונקייה.
  static Future<void> _clearOrTombstone(String key, String legacyName) async {
    final dir = await _getSettingsDirectory();
    final legacyFile = File(
      '${dir.path}/settings_${_sanitizeBookName(legacyName)}.json',
    );
    if (await legacyFile.exists()) {
      await saveSettings(key, const {resetMarker: true});
    } else {
      await deleteSettings(key);
    }
  }

  /// קבלת נתיב תיקיית ההגדרות
  /// נשמרת תחת שורש הנתונים האחיד של האפליקציה.
  static Future<Directory> _getSettingsDirectory() async {
    final settingsDir = Directory(await AppPaths.getPerBookSettingsPath());
    if (!await settingsDir.exists()) {
      await settingsDir.create(recursive: true);
    }
    return settingsDir;
  }

  /// יצירת שם קובץ בטוח מתוך שם ספר
  static String _sanitizeBookName(String bookName) {
    // הסרת תווים לא חוקיים משם הקובץ
    return bookName
        .replaceAll(RegExp(r'[<>:"/\\|?*]'), '_')
        .replaceAll(' ', '_');
  }

  /// קבלת נתיב קובץ הגדרות לספר (לפי hash של המפתח)
  static Future<File> _getSettingsFile(String key) async {
    final dir = await _getSettingsDirectory();
    return File('${dir.path}/settings_${_hashKey(key)}.json');
  }

  /// שמירת הגדרות לספר
  static Future<void> saveSettings(
    String bookName,
    Map<String, dynamic> settings,
  ) async {
    try {
      final file = await _getSettingsFile(bookName);
      debugPrint('📁 Saving to file: ${file.path}');
      final json = jsonEncode(settings);
      debugPrint('📄 JSON content: $json');
      await file.writeAsString(json);
      debugPrint('✅ Saved per-book settings for: $bookName');
    } catch (e) {
      debugPrint('❌ Error saving per-book settings: $e');
      rethrow;
    }
  }

  /// טעינת הגדרות של ספר
  static Future<Map<String, dynamic>?> loadSettings(String bookName) async {
    try {
      final file = await _getSettingsFile(bookName);
      debugPrint('📁 Looking for file: ${file.path}');
      if (!await file.exists()) {
        debugPrint('📁 File does not exist');
        return null;
      }
      final json = await file.readAsString();
      debugPrint('📄 JSON content: $json');
      final settings = jsonDecode(json) as Map<String, dynamic>;
      debugPrint('✅ Loaded per-book settings for: $bookName');
      return settings;
    } catch (e) {
      debugPrint('❌ Error loading per-book settings: $e');
      return null;
    }
  }

  /// מחיקת הגדרות של ספר
  static Future<void> deleteSettings(String bookName) async {
    try {
      final file = await _getSettingsFile(bookName);
      if (await file.exists()) {
        await file.delete();
        debugPrint('✅ Deleted per-book settings for: $bookName');
      }
    } catch (e) {
      debugPrint('❌ Error deleting per-book settings: $e');
    }
  }

  /// מחיקת כל קבצי ההגדרות. מחזיר האם המחיקה הושלמה.
  ///
  /// ה-[settle] מחייב: בלעדיו שמירה תלויה מכשילה את המחיקה או כותבת את
  /// הקובץ מחדש אחריה. הנתיב נבנה ישירות ולא דרך [_getSettingsDirectory],
  /// שיוצר את התיקייה — אין טעם ליצור תיקייה רק כדי למחוק אותה.
  static Future<bool> deleteAllSettings() async {
    await settle();
    try {
      final dir = Directory(await AppPaths.getPerBookSettingsPath());
      if (await dir.exists()) {
        await dir.delete(recursive: true);
        debugPrint('✅ Deleted all per-book settings');
      }
      return true;
    } catch (e) {
      debugPrint('❌ Error deleting all per-book settings: $e');
      return false;
    }
  }

  /// ניקוי קבצי הגדרות שהפכו למיותרים (זהים לברירת המחדל)
  static Future<void> cleanupRedundantSettings({
    required double defaultFontSize,
    required bool defaultRemoveNikud,
    required bool defaultShowSplitView,
    bool defaultRemovePunctuation = false,
    bool defaultContinuousReadingMode = false,
  }) async {
    try {
      final dir = await _getSettingsDirectory();
      if (!await dir.exists()) {
        return;
      }

      final files = (await dir.list().toList()).whereType<File>();
      int cleanedCount = 0;

      // hash של קובץ פר-ספר הוא SHA-1 (40 תווי hex). קובצי legacy (שם מ-
      // sanitize של כותרת) אינם נוגעים כאן: הם read-only artifact, וה-override
      // שלהם מנוקה כשהם היגרו לקובץ hash — בלי להתנגש עם מיגרציה מקבילה.
      final hashPattern = RegExp(r'settings_([0-9a-f]{40})\.json$');

      for (final file in files) {
        final match = hashPattern.firstMatch(file.path);
        if (match == null) continue;

        // כל קובץ hash מטופל דרך תור הנעילה שלו (עקבי עם mutate/save/delete),
        // כדי שקריאה-שינוי-כתיבה לא תדרוס פעולה פר-ספרית מקבילה. הקריאה נעשית
        // בתוך הנעילה כי הקובץ עלול להשתנות בזמן ההמתנה בתור.
        await runLocked(match.group(1)!, () async {
          try {
            if (!await file.exists()) return;
            final json =
                jsonDecode(await file.readAsString()) as Map<String, dynamic>;

            // קובץ tombstone (איפוס) חייב לשרוד את הניקוי, אחרת המיגרציה
            // תשחזר את ה-legacy בפתיחה הבאה.
            if (json.containsKey(resetMarker)) return;

            // הסרת שדות שהפכו זהים לברירת המחדל הגלובלית — הספר יירש אותה.
            // מסירים שדה-שדה (לא קובץ שלם) כדי שגם קובץ עם שדה פר-ספר אמיתי
            // (מפרשים/רוחבים) לא ישאיר override מיושן שסותר את ברירת המחדל.
            final cleaned = Map<String, dynamic>.of(json);
            if (cleaned['fontSize'] == defaultFontSize) {
              cleaned.remove('fontSize');
            }
            if (cleaned['removeNikud'] == defaultRemoveNikud) {
              cleaned.remove('removeNikud');
            }
            _removeRedundantPunctuationFields(
              cleaned,
              defaultRemovePunctuation: defaultRemovePunctuation,
            );
            if (cleaned['commentatorsBelow'] == !defaultShowSplitView) {
              cleaned.remove('commentatorsBelow');
            }
            if (cleaned['continuousReadingMode'] ==
                defaultContinuousReadingMode) {
              cleaned.remove('continuousReadingMode');
            }

            if (cleaned.isEmpty) {
              await file.delete();
              cleanedCount++;
              debugPrint('🧹 Cleaned redundant settings file: ${file.path}');
            } else if (cleaned.length != json.length) {
              await file.writeAsString(jsonEncode(cleaned));
              cleanedCount++;
              debugPrint('🧹 Trimmed redundant fields from: ${file.path}');
            }
          } catch (e) {
            debugPrint('❌ Error processing file ${file.path}: $e');
          }
        });
      }

      if (cleanedCount > 0) {
        debugPrint('🧹 Cleaned $cleanedCount redundant settings files');
      }
    } catch (e) {
      debugPrint('❌ Error cleaning redundant settings: $e');
    }
  }
}

/// הגדרות פר-ספר לספרי טקסט
class TextBookPerBookSettings {
  final double? fontSize;
  final bool? commentatorsBelow; // true = מתחת, false = בצד
  final bool? removeNikud;
  final bool? removePunctuation;

  /// נשמר לצד [removePunctuation]: בתנ"ך ברירת המחדל האפקטיבית לפיסוק היא
  /// תמיד false, והניקוי (שרואה רק קובץ hash) זקוק לדגל כדי לחשב אותה.
  final bool? isTanach;
  final bool? continuousReadingMode;

  /// המפרשים הנבחרים בספר זה. נשמר תמיד (לא תלוי ב-enablePerBookSettings) כדי
  /// שבחירת המשתמש תיטען בכל פתיחה. רשימה ריקה = המשתמש ביטל את כל הבחירה.
  final List<String>? activeCommentators;

  // רוחב/גודל הטורים בצורת הדף (נשמר רק אם המשתמש שינה אותם בתצוגה זו)
  final double? pageShapeLeftWidth; // רוחב טור המפרש השמאלי
  final double? pageShapeRightWidth; // רוחב טור המפרש הימני
  final double? pageShapeBottomHeight; // גובה הטור התחתון
  final double? pageShapeBottomLeftWidth; // רוחב המפרש התחתון-שמאלי

  TextBookPerBookSettings({
    this.fontSize,
    this.commentatorsBelow,
    this.removeNikud,
    this.removePunctuation,
    this.isTanach,
    this.continuousReadingMode,
    this.activeCommentators,
    this.pageShapeLeftWidth,
    this.pageShapeRightWidth,
    this.pageShapeBottomHeight,
    this.pageShapeBottomLeftWidth,
  });

  Map<String, dynamic> toJson() => {
    if (fontSize != null) 'fontSize': fontSize,
    if (commentatorsBelow != null) 'commentatorsBelow': commentatorsBelow,
    if (removeNikud != null) 'removeNikud': removeNikud,
    if (removePunctuation != null) 'removePunctuation': removePunctuation,
    if (isTanach != null) 'isTanach': isTanach,
    if (continuousReadingMode != null)
      'continuousReadingMode': continuousReadingMode,
    if (activeCommentators != null) 'activeCommentators': activeCommentators,
    if (pageShapeLeftWidth != null) 'pageShapeLeftWidth': pageShapeLeftWidth,
    if (pageShapeRightWidth != null) 'pageShapeRightWidth': pageShapeRightWidth,
    if (pageShapeBottomHeight != null)
      'pageShapeBottomHeight': pageShapeBottomHeight,
    if (pageShapeBottomLeftWidth != null)
      'pageShapeBottomLeftWidth': pageShapeBottomLeftWidth,
  };

  factory TextBookPerBookSettings.fromJson(Map<String, dynamic> json) {
    return TextBookPerBookSettings(
      fontSize: json['fontSize'] as double?,
      commentatorsBelow: json['commentatorsBelow'] as bool?,
      removeNikud: json['removeNikud'] as bool?,
      removePunctuation: json['removePunctuation'] as bool?,
      isTanach: json['isTanach'] as bool?,
      continuousReadingMode: json['continuousReadingMode'] as bool?,
      activeCommentators: (json['activeCommentators'] as List<dynamic>?)
          ?.cast<String>(),
      pageShapeLeftWidth: (json['pageShapeLeftWidth'] as num?)?.toDouble(),
      pageShapeRightWidth: (json['pageShapeRightWidth'] as num?)?.toDouble(),
      pageShapeBottomHeight: (json['pageShapeBottomHeight'] as num?)
          ?.toDouble(),
      pageShapeBottomLeftWidth: (json['pageShapeBottomLeftWidth'] as num?)
          ?.toDouble(),
    );
  }

  TextBookPerBookSettings copyWith({
    double? fontSize,
    bool? commentatorsBelow,
    bool? removeNikud,
    bool? removePunctuation,
    bool? continuousReadingMode,
    List<String>? activeCommentators,
    double? pageShapeLeftWidth,
    double? pageShapeRightWidth,
    double? pageShapeBottomHeight,
    double? pageShapeBottomLeftWidth,
  }) {
    return TextBookPerBookSettings(
      fontSize: fontSize ?? this.fontSize,
      commentatorsBelow: commentatorsBelow ?? this.commentatorsBelow,
      removeNikud: removeNikud ?? this.removeNikud,
      removePunctuation: removePunctuation ?? this.removePunctuation,
      isTanach: isTanach,
      continuousReadingMode:
          continuousReadingMode ?? this.continuousReadingMode,
      activeCommentators: activeCommentators ?? this.activeCommentators,
      pageShapeLeftWidth: pageShapeLeftWidth ?? this.pageShapeLeftWidth,
      pageShapeRightWidth: pageShapeRightWidth ?? this.pageShapeRightWidth,
      pageShapeBottomHeight:
          pageShapeBottomHeight ?? this.pageShapeBottomHeight,
      pageShapeBottomLeftWidth:
          pageShapeBottomLeftWidth ?? this.pageShapeBottomLeftWidth,
    );
  }

  /// עדכון אטומי של ההגדרות הפר-ספריות לספר נתון.
  ///
  /// [transform] מקבלת את ההגדרות הקיימות (או null אם אין) ומחזירה את
  /// ההגדרות לשמירה. אם התוצאה null או ריקה (כל השדות null) — הקובץ נמחק.
  /// כל הפעולות על אותו קובץ מבוצעות בזו אחר זו (דרך תור הנעילה המשותף), כך
  /// שה-load תמיד רואה את התוצאה של הכתיבה הקודמת.
  static Future<void> mutate(
    Book book,
    FutureOr<TextBookPerBookSettings?> Function(
      TextBookPerBookSettings? existing,
    )
    transform,
  ) async {
    final key = PerBookSettings.bookKey(book);
    await PerBookSettings.runLockedForKey(key, () async {
      await PerBookSettings._migrateLegacyFile(key, book.title);
      final existingJson = await PerBookSettings.loadSettings(key);
      final existing = existingJson == null
          ? null
          : TextBookPerBookSettings.fromJson(existingJson);
      final updated = await transform(existing);
      if (updated == null || updated.toJson().isEmpty) {
        await PerBookSettings._clearOrTombstone(key, book.title);
      } else {
        await PerBookSettings.saveSettings(key, updated.toJson());
      }
    });
  }

  /// טעינת הגדרות
  static Future<TextBookPerBookSettings?> load(Book book) async {
    final key = PerBookSettings.bookKey(book);
    return PerBookSettings.runLockedForKey(key, () async {
      await PerBookSettings._migrateLegacyFile(key, book.title);
      final json = await PerBookSettings.loadSettings(key);
      if (json == null) return null;
      return TextBookPerBookSettings.fromJson(json);
    });
  }

  /// מחיקת הגדרות
  static Future<void> delete(Book book) async {
    final key = PerBookSettings.bookKey(book);
    await PerBookSettings.runLockedForKey(
      key,
      () => PerBookSettings._clearOrTombstone(key, book.title),
    );
  }
}

/// מצב תצוגת PDF
enum PdfLayoutMode {
  regularView, // תצוגה רגילה
  bookView, // תצוגת ספר
}

/// הגדרות פר-ספר לספרי PDF
class PdfBookPerBookSettings {
  final double? zoom;
  final List<String>? activeCommentators;
  final PdfLayoutMode? layoutMode;

  PdfBookPerBookSettings({
    this.zoom,
    this.activeCommentators,
    this.layoutMode,
  });

  PdfBookPerBookSettings copyWith({
    double? zoom,
    List<String>? activeCommentators,
    PdfLayoutMode? layoutMode,
  }) {
    return PdfBookPerBookSettings(
      zoom: zoom ?? this.zoom,
      activeCommentators: activeCommentators ?? this.activeCommentators,
      layoutMode: layoutMode ?? this.layoutMode,
    );
  }

  Map<String, dynamic> toJson() => {
    if (zoom != null) 'zoom': zoom,
    if (activeCommentators != null) 'activeCommentators': activeCommentators,
    if (layoutMode != null) 'layoutMode': layoutMode!.name,
  };

  factory PdfBookPerBookSettings.fromJson(Map<String, dynamic> json) {
    return PdfBookPerBookSettings(
      zoom: json['zoom'] as double?,
      activeCommentators: (json['activeCommentators'] as List<dynamic>?)
          ?.cast<String>(),
      layoutMode: json['layoutMode'] != null
          ? PdfLayoutMode.values.firstWhere(
              (e) => e.name == json['layoutMode'],
              orElse: () => PdfLayoutMode.regularView,
            )
          : null,
    );
  }

  /// שמירת הגדרות
  Future<void> save(Book book) async {
    final key = PerBookSettings.bookKey(book);
    await PerBookSettings.runLockedForKey(key, () async {
      await PerBookSettings._migrateLegacyFile(key, book.title);
      final existingJson = await PerBookSettings.loadSettings(key);
      final existingSettings = existingJson == null
          ? null
          : PdfBookPerBookSettings.fromJson(existingJson);
      final settingsToSave =
          existingSettings?.copyWith(
            zoom: zoom,
            activeCommentators: activeCommentators,
            layoutMode: layoutMode,
          ) ??
          this;

      await PerBookSettings.saveSettings(key, settingsToSave.toJson());
    });
  }

  /// טעינת הגדרות
  static Future<PdfBookPerBookSettings?> load(Book book) async {
    final key = PerBookSettings.bookKey(book);
    return PerBookSettings.runLockedForKey(key, () async {
      await PerBookSettings._migrateLegacyFile(key, book.title);
      final json = await PerBookSettings.loadSettings(key);
      if (json == null) return null;
      return PdfBookPerBookSettings.fromJson(json);
    });
  }

  /// מחיקת הגדרות
  static Future<void> delete(Book book) async {
    final key = PerBookSettings.bookKey(book);
    await PerBookSettings.runLockedForKey(
      key,
      () => PerBookSettings._clearOrTombstone(key, book.title),
    );
  }
}
