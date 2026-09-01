import 'dart:io';
import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/data/constants/database_constants.dart';
import 'package:otzaria/settings/settings_exports.dart';

enum InstallMode { systemWide, perUser }

/// Utility class for managing application paths.
/// Centralizes path construction logic to avoid duplication.
class AppPaths {
  static String? _cachedDataRootPath;
  static String? _cachedBundledLibraryPath;
  static bool _bundledLibraryProbed = false;
  static String? _resolvedExecutableOverride;

  /// קובץ marker שמסמן שתיקייה היא "ספרייה מצורפת" של חבילת FULL.
  /// נוצר ע"י ה-CI workflow בתוך תיקיית "אוצריא" של ה-bundle, וקיומו נדרש
  /// כדי שתיקיית "אוצריא" שאקראית קיימת ליד ה-executable לא תיתפס בטעות
  /// כספרייה מצורפת.
  static const String _bundledLibraryMarkerFileName =
      '.otzaria_bundled_library';

  /// מסמן אינדקס מוכן שמצורף לחבילת ספרייה מלאה.
  static const String prebuiltIndexMarkerFileName = '.otzaria_prebuilt_index';

  /// שם תיקיית הספרייה בתוך חבילות FULL ל-Linux ו-macOS.
  static const String _bundledLibraryFolderName = 'אוצריא';

  /// קובץ marker שמפעיל מצב נייד (portable): כשהוא קיים ליד ה-executable,
  /// כל נתוני האפליקציה נשמרים בתיקיית [_portableDataFolderName] ליד
  /// ה-executable במקום בתיקיית המשתמש (APPDATA וכדומה). רלוונטי לדסקטופ
  /// בלבד.
  static const String portableMarkerFileName = 'portable.marker';

  /// שם תיקיית הנתונים במצב נייד. לא 'data' — תיקייה בשם זה כבר קיימת
  /// ליד ה-executable בחבילות Flutter ל-Windows ול-Linux (flutter_assets).
  static const String _portableDataFolderName = 'otzaria_data';

  /// שם הקובץ שבו נרשם נתיב הספרייה הפעיל עבור ה-uninstaller.
  static const String libraryPathRecordFileName = 'library_path.txt';

  /// שם תיקיית ארכיוני התוספים שהמתקין מניח ליד ה-executable.
  static const String bundledPluginsFolderName = 'bundled_plugins';

  static bool? _isPortableCache;

  static String? _documentsRootPathOverride;

  /// דורס את תיקיית המסמכים של המשתמש לצורכי בדיקה. מחרוזת ריקה מדמה
  /// פלטפורמה שאינה מספקת תיקיית מסמכים.
  @visibleForTesting
  static void debugOverrideDocumentsRootPath(String? path) {
    _documentsRootPathOverride = path;
  }

  /// קובע את שורש נתוני התהליך לפני אתחול השירותים.
  ///
  /// מיועד לפקודות headless שעובדות בסביבת staging מבודדת.
  static void configureDataRootPathForProcess(String path) {
    _cachedDataRootPath = path;
  }

  @visibleForTesting
  static void debugOverrideDataRootPath(String? path) {
    _cachedDataRootPath = path;
  }

  /// דורס את [Platform.resolvedExecutable] לצורכי בדיקה — נדרש כדי לדמות
  /// מבנה תיקיות של חבילת FULL ב-tmpdir.
  @visibleForTesting
  static void debugOverrideResolvedExecutable(String? path) {
    _resolvedExecutableOverride = path;
    _bundledLibraryProbed = false;
    _cachedBundledLibraryPath = null;
    // זיהוי מצב נייד נגזר ממיקום ה-executable — חייב להתאפס יחד איתו.
    _isPortableCache = null;
  }

  static String get _resolvedExecutable =>
      _resolvedExecutableOverride ?? Platform.resolvedExecutable;

  /// האם האפליקציה רצה במצב נייד — קובץ [portableMarkerFileName] קיים
  /// ליד ה-executable. במובייל תמיד false.
  static bool get isPortable {
    final cached = _isPortableCache;
    if (cached != null) return cached;

    var result = false;
    if (!Platform.isAndroid && !Platform.isIOS) {
      final exeDir = p.dirname(_resolvedExecutable);
      result = File(p.join(exeDir, portableMarkerFileName)).existsSync();
    }
    _isPortableCache = result;
    return result;
  }

  /// Returns the default writable root for user-scoped app data.
  ///
  /// במצב נייד ([isPortable]) — תיקיית [_portableDataFolderName] ליד
  /// ה-executable, כך שכל הנתונים נודדים יחד עם התוכנה.
  static Future<String> getDataRootPath() async {
    if (_cachedDataRootPath != null && _cachedDataRootPath!.isNotEmpty) {
      return _cachedDataRootPath!;
    }

    final String rootPath;
    if (Platform.isAndroid || Platform.isIOS) {
      rootPath = (await getApplicationDocumentsDirectory()).path;
    } else if (isPortable) {
      rootPath = p.join(
        p.dirname(_resolvedExecutable),
        _portableDataFolderName,
      );
    } else if (Platform.isWindows) {
      final appData = Platform.environment['APPDATA'] ?? '';
      rootPath = p.join(appData, 'otzaria');
    } else if (Platform.isMacOS) {
      final home = Platform.environment['HOME'] ?? '';
      rootPath = p.join(home, 'Library', 'Application Support', 'otzaria');
    } else {
      // Linux
      final home = Platform.environment['HOME'] ?? '';
      rootPath = p.join(home, '.local', 'share', 'otzaria');
    }

    _cachedDataRootPath = rootPath;
    return _cachedDataRootPath!;
  }

  static String? get cachedDataRootPath => _cachedDataRootPath;

  /// שורש הספרייה שבחר המשתמש ב-Android (כרטיס SD), אם קיים ונגיש כרגע.
  /// משפיע רק על מיקום הספרייה (ספרים/אינדקס/מסדי נתונים) — לא על שורש הנתונים
  /// הכללי (Hive, תוספים, גיבויים) שנשאר תמיד באחסון הפנימי.
  static Future<String?> _androidLibraryRootOverride() async {
    if (!Platform.isAndroid) return null;
    final override = Settings.getValue<String>(
      SettingsRepository.keyAndroidLibraryRoot,
    );
    if (override != null &&
        override.isNotEmpty &&
        await Directory(override).exists()) {
      return override;
    }
    return null;
  }

  /// שומר את שורש הספרייה לבחירת המשתמש ב-Android (או מנקה לחזרה לאחסון
  /// הפנימי כש-[path] ריק/null).
  static Future<void> setAndroidLibraryRoot(String? path) async {
    await Settings.setValue<String>(
      SettingsRepository.keyAndroidLibraryRoot,
      path ?? '',
    );
  }

  /// סימון פנימי שספרייה נטענה בהצלחה אי-פעם. יושב באחסון הפנימי ולכן שורד
  /// ניקוי מטמון (שמוחק ספרייה על כרטיס SD) אך נמחק עם הסרת האפליקציה.
  static Future<void> markLibraryLoadedOnce() async {
    try {
      final marker = File(
        p.join(await getDataRootPath(), 'library_loaded.marker'),
      );
      if (!await marker.exists()) await marker.create(recursive: true);
    } catch (_) {}
  }

  /// האם הספרייה שעל כרטיס ה-SD נמחקה — הייתה ספרייה (לפי הסימון הפנימי),
  /// המשתמש בחר כרטיס SD, ועכשיו הספרייה ריקה. משמש להסבר במסך הספרייה הריקה.
  static Future<bool> wasSdLibraryWiped() async {
    if (!Platform.isAndroid) return false;
    final override = Settings.getValue<String>(
      SettingsRepository.keyAndroidLibraryRoot,
    );
    if (override == null || override.isEmpty) return false;
    return File(
      p.join(await getDataRootPath(), 'library_loaded.marker'),
    ).exists();
  }

  /// האם ההתקנה ב-Windows מערכתית (כמנהל). מקור אמת יחיד — גם למנגנון
  /// העדכון, שגוזר ממנו את דגלי המתקין השקט.
  ///
  /// ה-marker (נכתב ע"י ה-installer בהתקנת מנהל) וה-exe תחת Program Files
  /// הם אותות יציבים שאינם משתנים כשהמשתמש מעביר את הספרייה. בכוונה אין
  /// כאן fallback לפי נתיב הספרייה — הוא היה גורם לזיהוי להתהפך ל-perUser
  /// (וברירת מחדל ל-AppData) ברגע שהספרייה הועברה מחוץ ל-ProgramData.
  static bool get isWindowsSystemInstall {
    if (!Platform.isWindows || isPortable) {
      return false;
    }
    final exeDir = p.dirname(_resolvedExecutable);
    if (File(p.join(exeDir, 'system_install.marker')).existsSync()) {
      return true;
    }
    final exeDirLower = exeDir.toLowerCase();
    final pf = (Platform.environment['ProgramFiles'] ?? r'C:\Program Files')
        .toLowerCase();
    final pfX86 =
        (Platform.environment['ProgramFiles(x86)'] ?? r'C:\Program Files (x86)')
            .toLowerCase();
    return exeDirLower.startsWith(pf) || exeDirLower.startsWith(pfX86);
  }

  /// מזהה אם ההתקנה מערכתית (כמנהל) או התקנת משתמש.
  static Future<InstallMode> detectInstallMode() async {
    // מצב נייד לעולם אינו התקנה מערכתית — הנתונים יושבים ליד ה-executable
    // ואסור ליפול לנתיבים משותפים כמו ProgramData.
    if (isPortable) {
      return InstallMode.perUser;
    }
    if (Platform.isMacOS) {
      if (await Directory('/Library/Application Support/Otzaria').exists()) {
        return InstallMode.systemWide;
      }
    }
    if (Platform.isWindows && isWindowsSystemInstall) {
      return InstallMode.systemWide;
    }
    if (Platform.isLinux) {
      if (await Directory('/var/lib/otzaria').exists()) {
        return InstallMode.systemWide;
      }
    }
    return InstallMode.perUser;
  }

  /// תיקיית השורש (ההורה של books/index) עבור נתיב ספרייה נתון. כשהנתיב הוא
  /// תת-תיקיית "books" — השורש הוא ההורה; אחרת (למשל חבילת FULL עם ספרייה
  /// מצורפת שאינה בתת-תיקיית books) הנתיב עצמו הוא השורש.
  static String libraryRootOf(String libraryPath) =>
      p.basename(libraryPath).toLowerCase() == 'books'
      ? p.dirname(libraryPath)
      : libraryPath;

  /// מחזיר את נתיב ברירת המחדל של הספרייה.
  ///
  /// בהתקנה מערכתית הנתיב נשאר תחת שורש הנתונים המשותף. אחרת הוא יושב תחת
  /// שורש הנתונים של המשתמש. ב-Linux וב-macOS חבילת FULL עם marker תקין
  /// ליד ה-executable מנצחת את ברירת המחדל; ב-Windows ה-installer מטפל בכך.
  static Future<String> getDefaultLibraryPath() async {
    final bundled = await _detectBundledLibraryPath();
    if (bundled != null) {
      return bundled;
    }

    // Android: אם המשתמש בחר לשמור את הספרייה על כרטיס SD, מיקום ברירת המחדל
    // של הספרייה יושב שם. שאר נתוני האפליקציה נשארים באחסון הפנימי.
    final androidLibraryRoot = await _androidLibraryRootOverride();
    if (androidLibraryRoot != null) {
      return p.join(androidLibraryRoot, 'books');
    }

    final systemWideRoot = await _getSystemWideLibraryRootIfNeeded();
    if (systemWideRoot != null) {
      return p.join(systemWideRoot, 'books');
    }

    return p.join(await getDataRootPath(), 'books');
  }

  /// תיקיית הספרים האישיים המיובאים במובייל.
  ///
  /// באנדרואיד/iOS אין לאפליקציה גישה קבועה לתיקיות שהמשתמש בוחר (Scoped
  /// Storage), ולכן קבצים שנבחרו דרך בורר המערכת מועתקים לתיקייה קבועה זו
  /// בתוך אחסון האפליקציה, והיא נרשמת כתיקייה מותאמת אישית רגילה.
  static Future<String> getPersonalBooksImportPath() async =>
      p.join(await getDataRootPath(), 'הספרים שלי');

  /// תיקיית ארכיוני התוספים שהמתקין ארז, ליד ה-executable. `null` במובייל,
  /// שאין בו מתקין. התיקייה עצמה אינה קיימת כשהמתקין נבנה בלי תוספים.
  static String? getBundledPluginsPath() {
    if (Platform.isAndroid || Platform.isIOS) return null;
    return p.join(p.dirname(_resolvedExecutable), bundledPluginsFolderName);
  }

  /// מזהה תיקיית ספרייה מצורפת ליד ה-executable עבור חבילות FULL.
  ///
  ///   Linux:  bundle/app/otzaria             → bundle/אוצריא/
  ///   macOS:  bundle/אוצריא.app/Contents/MacOS/exe → bundle/אוצריא/
  ///
  /// הזיהוי מותנה בקובץ marker שנוצר ע"י ה-CI workflow, כדי למנוע
  /// false-positive על תיקייה בשם "אוצריא" שאקראית קיימת בנתיב.
  /// ב-Windows יש installer שמטפל בנתיב בעצמו (כותב ל-shared_preferences),
  /// ב-Android/iOS אין משמעות ל-resolvedExecutable מבחינת sandbox.
  static Future<String?> _detectBundledLibraryPath() async {
    if (_bundledLibraryProbed) return _cachedBundledLibraryPath;
    _bundledLibraryProbed = true;
    _cachedBundledLibraryPath = null;

    if (Platform.isWindows || Platform.isAndroid || Platform.isIOS) {
      return null;
    }

    final exeDir = p.dirname(_resolvedExecutable);
    final candidates = <String>[];
    if (Platform.isLinux) {
      candidates.add(
        p.normalize(p.join(exeDir, '..', _bundledLibraryFolderName)),
      );
    } else if (Platform.isMacOS) {
      candidates.add(
        p.normalize(
          p.join(exeDir, '..', '..', '..', _bundledLibraryFolderName),
        ),
      );
    }

    for (final dir in candidates) {
      final marker = File(p.join(dir, _bundledLibraryMarkerFileName));
      final db = File(p.join(dir, 'seforim.db'));
      if (await marker.exists() && await db.exists()) {
        _cachedBundledLibraryPath = dir;
        return dir;
      }
    }
    return null;
  }

  static Future<String?> _getSystemWideLibraryRootIfNeeded() async {
    if (Platform.isAndroid || Platform.isIOS) {
      return null;
    }

    final mode = await detectInstallMode();
    if (mode != InstallMode.systemWide) {
      return null;
    }

    if (Platform.isWindows) {
      final pd = Platform.environment['ProgramData'] ?? r'C:\ProgramData';
      return p.join(pd, 'otzaria');
    }
    if (Platform.isMacOS) {
      return '/Library/Application Support/otzaria';
    }
    if (Platform.isLinux) {
      return '/var/lib/otzaria';
    }

    return null;
  }

  static Future<String> _getDefaultIndexPath() async {
    final systemWideRoot = await _getSystemWideLibraryRootIfNeeded();
    if (systemWideRoot != null) {
      return p.join(systemWideRoot, 'index');
    }

    final libraryPath = await getLibraryPath();
    final adjacentPath = p.join(p.dirname(libraryPath), 'index');
    final prebuiltMarker = File(
      p.join(adjacentPath, prebuiltIndexMarkerFileName),
    );
    if (await prebuiltMarker.exists()) {
      return adjacentPath;
    }

    // תאימות אחורה: בעבר האינדקס תמיד נוצר תחת dataRoot (APPDATA וכדומה).
    // אם קיים שם אינדקס – ממשיכים להשתמש בו כדי לא לאבד עבודה.
    final legacyPath = p.join(await getDataRootPath(), 'index');
    if (await Directory(legacyPath).exists()) {
      return legacyPath;
    }

    // ברירת מחדל חדשה: האינדקס יושב ליד תיקיית הספרייה. כך אם המשתמש
    // העביר את הספרייה לכונן אחר (למשל D:), גם האינדקס יישב שם.
    return adjacentPath;
  }

  /// רושם את נתיב הספרייה הפעיל לקובץ טקסט עבור ה-uninstaller של Windows.
  /// ההגדרות יושבות ב-Hive בינארי שהמתקין אינו יכול לקרוא, ובלעדיו
  /// ספרייה שהועברה שורדת את ההסרה (issue #1020).
  static Future<void> recordLibraryPathForUninstaller() async {
    if (!Platform.isWindows) return;
    try {
      final path = await getLibraryPath();
      if (path.isEmpty) return;
      // BOM: בלעדיו LoadStringsFromFile של Inno קורא את הקובץ כ-ANSI ושובר
      // נתיב בעברית.
      await File(
        p.join(await getDataRootPath(), libraryPathRecordFileName),
      ).writeAsString('﻿$path');
    } catch (e) {
      debugPrint('Failed to record library path for uninstaller: $e');
    }
  }

  /// Gets the main library path from settings, or gracefully falls back to default paths.
  static Future<String> getLibraryPath() async {
    final currentPath = Settings.getValue<String>(
      SettingsRepository.keyLibraryPath,
    );

    // אם ה-executable הנוכחי שייך ל-FULL bundle, הספרייה המצורפת אמורה
    // לנצח על keyLibraryPath שמור — אבל רק אם השמור לא מייצג בחירה ידנית
    // תקפה של המשתמש. זה מבטיח שני דברים הפוכים:
    //   1) משתמש שהעביר/החליף את ה-bundle לא נשאר תקוע על נתיב ישן ושבור.
    //   2) משתמש שבחר במפורש תיקיית ספרייה אחרת (דרך ההגדרות) ימשיך לעבוד
    //      איתה גם כשהוא מפעיל מ-bundle.
    // ההבחנה: נתיב נחשב "בחירה ידנית" אם יש בו seforim.db ואין בו את ה-
    // marker של FULL bundle. נתיב bundle ישן מזוהה ע"י קיום ה-marker;
    // נתיב שבור מזוהה ע"י היעדר ה-DB.
    final bundled = await _detectBundledLibraryPath();
    if (bundled != null) {
      if (currentPath != null && currentPath.isNotEmpty) {
        if (await _isUserChosenLibraryPath(currentPath)) {
          return currentPath;
        }
      }
      // אין בחירה ידנית תקפה — ה-bundle הנוכחי מנצח, ומתעדכן ב-settings כדי
      // שקריאות ישירות ל-Settings.getValue (למשל מ-DatabaseConstants) יקבלו
      // את הנתיב הנכון.
      //
      // איפוס ה-folderName חייב להיבדק *בנפרד* מ-currentPath. דוגמה לתרחיש
      // שמחמיץ אחרת: currentPath == bundled (משמירה קודמת) אבל
      // keyLibraryFolderName הוא ערך stale כמו 'Otzaria'. במצב כזה לא נשמור
      // נתיב מחדש, אבל ה-folderName הישן יישאר וגורם ל-DatabaseConstants
      // לחשב bundled/Otzaria/seforim.db במקום bundled/seforim.db.
      if (currentPath != bundled) {
        await Settings.setValue(SettingsRepository.keyLibraryPath, bundled);
      }
      final currentFolderName =
          Settings.getValue<String>(SettingsRepository.keyLibraryFolderName) ??
          '';
      if (currentFolderName.isNotEmpty) {
        await Settings.setValue(SettingsRepository.keyLibraryFolderName, '');
      }
      return bundled;
    }

    if (currentPath != null && currentPath.isNotEmpty) {
      return currentPath;
    }

    // Determine default path based on platform
    String libraryPath = await getDefaultLibraryPath();

    await Settings.setValue(SettingsRepository.keyLibraryPath, libraryPath);
    return libraryPath;
  }

  /// מחזיר true אם [libraryPath] נראה כבחירה ידנית תקפה של המשתמש —
  /// תיקייה שמכילה את ה-DB אבל אינה ספריית FULL bundle (אין בה marker).
  ///
  /// בהתאם ל-DatabaseConstants._buildDbPath, הנתיב האפקטיבי של ה-DB
  /// תלוי גם ב-keyLibraryFolderName: אם הוא ריק ה-DB נמצא ישירות תחת
  /// [libraryPath], ואחרת תחת תת-תיקייה. הבדיקה חייבת לחקות את אותה
  /// לוגיקה כדי לא להחשיב תצורת משתמש חוקית כ-stale.
  static Future<bool> _isUserChosenLibraryPath(String libraryPath) async {
    final folderName =
        Settings.getValue<String>(SettingsRepository.keyLibraryFolderName) ??
        '';
    final dbDir = folderName.isEmpty
        ? libraryPath
        : p.join(libraryPath, folderName);

    final db = File(p.join(dbDir, 'seforim.db'));
    if (!await db.exists()) {
      return false;
    }
    // ה-marker יושב באותה רמה כמו ה-DB (זה מבנה ה-FULL bundle שה-CI יוצר).
    final marker = File(p.join(dbDir, _bundledLibraryMarkerFileName));
    if (await marker.exists()) {
      return false;
    }
    return true;
  }

  /// Gets the search index path.
  ///
  /// On system-wide desktop installs this remains next to the shared library.
  static Future<String> getIndexPath() async {
    // Check if there is a separate index path assigned
    final savedIndex = Settings.getValue<String>(
      SettingsRepository.keyIndexPath,
    );
    if (savedIndex != null && savedIndex.isNotEmpty) return savedIndex;

    return _getDefaultIndexPath();
  }

  /// מחזיר את תיקיית מסדי הנתונים האישיים של המשתמש.
  ///
  /// התקנות קיימות עם `<dataRoot>/databases` ממשיכות להשתמש בו. התקנות
  /// חדשות יוצרות את התיקייה ליד הספרייה, כך שהיא ניידת יחד עם הספרייה.
  static Future<String> getDatabasesPath() async {
    final saved = Settings.getValue<String>(
      SettingsRepository.keyDatabasesPath,
    );
    if (saved != null && saved.isNotEmpty) return saved;

    final legacyPath = p.join(await getDataRootPath(), 'databases');
    if (await Directory(legacyPath).exists()) {
      return legacyPath;
    }

    final libraryPath = await getLibraryPath();
    return p.join(p.dirname(libraryPath), 'databases');
  }

  /// נתיב קובץ המילון המורפולוגי (`lexical.db`) של החיפוש המקורב.
  ///
  /// יושב לצד `seforim.db`. בהיעדרו החיפוש המקורב נופל חזרה ל-fuzzy רגיל.
  static Future<String> getMagicDictionaryPath() async {
    return p.join(
      DatabaseConstants.getDatabaseDirectoryPath(),
      DatabaseConstants.lexicalDatabaseFileName,
    );
  }

  /// נתיב העותק המעודכן של קובץ הביוגרפיות, שמערכת העדכונים מורידה בזמן
  /// ריצה. גובר על הקובץ הארוז באפליקציה, שאינו בר-כתיבה.
  static Future<String> getBiographiesPath() async {
    return p.join(await getDataRootPath(), 'biographies.tsb');
  }

  /// מחזיר רשימת נתיבי ברירת מחדל לאינדקס שאינם הנתיב הפעיל כעת.
  ///
  /// משמש בעת איפוס אינדקס: אינדקסים ישנים בנתיבים אלו (למשל אינדקס
  /// ישן שנותר ב-APPDATA אחרי שהמשתמש העביר את הספרייה לכונן אחר)
  /// ימחקו כדי שלא "יתפסו" את ברירת המחדל ב-[getIndexPath] בהפעלה הבאה.
  static Future<List<String>> getStaleDefaultIndexPaths() async {
    final activePath = p.normalize(await getIndexPath());
    final candidates = <String>{};

    final systemWideRoot = await _getSystemWideLibraryRootIfNeeded();
    if (systemWideRoot != null) {
      candidates.add(p.normalize(p.join(systemWideRoot, 'index')));
    }

    // ברירת המחדל הישנה: תחת תיקיית הנתונים (APPDATA וכדומה).
    candidates.add(p.normalize(p.join(await getDataRootPath(), 'index')));

    // ברירת המחדל הנוכחית: ליד הספרייה.
    final libraryPath = await getLibraryPath();
    candidates.add(p.normalize(p.join(p.dirname(libraryPath), 'index')));

    return candidates.where((c) => c != activePath).toList();
  }

  /// שם תיקיית ברירת המחדל לגיבויים תחת מסמכי המשתמש בדסקטופ.
  static const String _documentsBackupFolderName = 'אוצריא - גיבויים';
  static const String _legacyBackupMigrationMarker =
      '.otzaria-legacy-migration-complete';

  /// מחזיר את תיקיית ברירת המחדל לגיבויים.
  ///
  /// בדסקטופ התיקייה יושבת תחת מסמכי המשתמש ולא תחת תיקיית הנתונים, כדי
  /// שהסרת התוכנה או מחיקת תיקיית הנתונים לא ימחקו את הגיבויים. במצב נייד
  /// ובמובייל הגיבויים נשארים תחת תיקיית הנתונים כדי שינדדו יחד איתה.
  static Future<String> getDefaultBackupPath() async {
    final dataRootBackups = p.join(await getDataRootPath(), 'backups');
    if (Platform.isAndroid || Platform.isIOS || isPortable) {
      return dataRootBackups;
    }

    final documentsRoot = await _documentsRootPath();
    if (documentsRoot == null) return dataRootBackups;
    final documentsBackups = p.join(documentsRoot, _documentsBackupFolderName);

    // נתיב מותאם אישית מנוהל בידי המשתמש: העברת התיקייה הישנה מתחתיו הייתה
    // מייתמת את הגיבויים, כי getBackupPath ממשיך להחזיר את הנתיב השמור.
    final saved = Settings.getValue<String>(SettingsRepository.keyBackupPath);
    if (saved != null && saved.isNotEmpty) return documentsBackups;

    // העברה חד-פעמית של גיבויים מהנתיב הישן שבתיקיית הנתונים.
    final migrationKey = '$dataRootBackups|$documentsBackups';
    if (_legacyBackupMigrationKey != migrationKey) {
      _legacyBackupMigrationKey = migrationKey;
      _legacyBackupMigration = _migrateLegacyBackups(
        from: dataRootBackups,
        to: documentsBackups,
      );
    }
    return _legacyBackupMigration!;
  }

  static String? _legacyBackupMigrationKey;
  static Future<String>? _legacyBackupMigration;

  /// מעביר את כל תיקיית הגיבויים הישנה, לרבות מחסן ה־blobs.
  static Future<String> _migrateLegacyBackups({
    required String from,
    required String to,
    Future<Directory> Function(Directory source, String destination)?
    moveLegacyDirectory,
    Future<void> Function(Directory source, Directory destination)?
    copyLegacyDirectory,
    Future<void> Function(Directory source)? deleteLegacyDirectory,
  }) async {
    final legacy = Directory(from);
    final target = Directory(to);
    final marker = File(p.join(to, _legacyBackupMigrationMarker));
    final moveLegacy =
        moveLegacyDirectory ??
        (Directory source, String destination) => source.rename(destination);
    final copyLegacy = copyLegacyDirectory ?? _copyDirectory;
    final deleteLegacy =
        deleteLegacyDirectory ??
        (Directory source) async => source.delete(recursive: true);

    // marker קיים רק אחרי פרסום עותק שלם; המקור הוא שארית לניקוי בלבד.
    if (await marker.exists()) {
      await _deleteLegacyBackupSource(legacy, marker, deleteLegacy);
      return to;
    }

    final sourceType = await FileSystemEntity.type(from, followLinks: false);
    if (sourceType == FileSystemEntityType.link) {
      debugPrint('⚠️ תיקיית הגיבויים הישנה היא קישור — ההעברה בוטלה: $from');
      return from;
    }

    final bool legacyHasEntries;
    try {
      legacyHasEntries = await _directoryHasEntries(from);
    } catch (e) {
      debugPrint('⚠️ קריאת תיקיית הגיבויים הישנה $from נכשלה: $e');
      return to;
    }
    if (!legacyHasEntries) return to;

    if (await _containsSymbolicLink(legacy)) {
      debugPrint('⚠️ נמצא קישור בתיקיית הגיבויים — ההעברה בוטלה: $from');
      return from;
    }

    try {
      if (await _directoryHasEntries(to)) {
        debugPrint('⚠️ היעד $to אינו ריק — הגיבויים נשארים בנתיב הישן $from');
        return from;
      }

      await Directory(p.dirname(to)).create(recursive: true);
      if (await target.exists()) await target.delete();
      await moveLegacy(legacy, to);
      return to;
    } catch (_) {
      // rename בין כוננים נכשל; מפרסמים עותק שלם דרך staging באותו יעד.
    }

    final staging = Directory('$to.migrating');
    try {
      if (await staging.exists()) await staging.delete(recursive: true);
      await copyLegacy(legacy, staging);
      await File(
        p.join(staging.path, _legacyBackupMigrationMarker),
      ).writeAsString('complete', flush: true);
      if (await target.exists()) await target.delete();
      await staging.rename(to);
    } catch (e) {
      debugPrint('⚠️ העברת הגיבויים מ-$from ל-$to נכשלה: $e');
      try {
        if (await staging.exists()) await staging.delete(recursive: true);
      } catch (_) {}
      return from;
    }

    await _deleteLegacyBackupSource(legacy, marker, deleteLegacy);
    return to;
  }

  static Future<void> _deleteLegacyBackupSource(
    Directory legacy,
    File marker,
    Future<void> Function(Directory source) deleteLegacy,
  ) async {
    try {
      if (await legacy.exists()) await deleteLegacy(legacy);
      if (!await legacy.exists() && await marker.exists()) {
        await marker.delete();
      }
    } catch (e) {
      debugPrint('⚠️ ניקוי תיקיית הגיבויים הישנה נכשל: $e');
    }
  }

  static Future<bool> _containsSymbolicLink(Directory root) async {
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is Link) return true;
    }
    return false;
  }

  /// מעתיק עץ בלי לעקוב אחר קישורים, כדי שהמקור יוכל להימחק בבטחה.
  static Future<void> _copyDirectory(Directory from, Directory to) async {
    await to.create(recursive: true);
    await for (final entity in from.list(followLinks: false)) {
      final destination = p.join(to.path, p.basename(entity.path));
      if (entity is Directory) {
        await _copyDirectory(entity, Directory(destination));
      } else if (entity is File) {
        await entity.copy(destination);
      } else {
        throw FileSystemException(
          'קישור סימבולי בתיקיית הגיבויים — ההעברה בוטלה',
          entity.path,
        );
      }
    }
  }

  @visibleForTesting
  static Future<String> debugMigrateLegacyBackups({
    required String from,
    required String to,
    Future<Directory> Function(Directory source, String destination)?
    moveLegacyDirectory,
    Future<void> Function(Directory source, Directory destination)?
    copyLegacyDirectory,
    Future<void> Function(Directory source)? deleteLegacyDirectory,
  }) => _migrateLegacyBackups(
    from: from,
    to: to,
    moveLegacyDirectory: moveLegacyDirectory,
    copyLegacyDirectory: copyLegacyDirectory,
    deleteLegacyDirectory: deleteLegacyDirectory,
  );

  /// מחזיר את תיקיית המסמכים של המשתמש, או null כשהפלטפורמה לא מספקת אותה.
  static Future<String?> _documentsRootPath() async {
    final override = _documentsRootPathOverride;
    if (override != null) return override.isEmpty ? null : override;
    try {
      return (await getApplicationDocumentsDirectory()).path;
    } catch (_) {
      return null;
    }
  }

  static Future<bool> _directoryHasEntries(String path) async {
    final dir = Directory(path);
    if (!await dir.exists()) return false;
    return !await dir.list().isEmpty;
  }

  /// Gets backup path from settings.
  static Future<String> getBackupPath() async {
    final saved = Settings.getValue<String>(SettingsRepository.keyBackupPath);
    if (saved != null && saved.isNotEmpty) return saved;
    return getDefaultBackupPath();
  }

  /// Gets the manifest file path (library_path/files_manifest.json)
  static Future<String> getManifestPath() async {
    final libraryPath = await getLibraryPath();
    return p.join(libraryPath, 'files_manifest.json');
  }

  /// Resolves the notes database path - for cross-platform compatibility.
  static Future<String> resolveNotesDbPath(String fileName) async {
    final dbDir = Directory(await getDatabasesPath());
    if (!await dbDir.exists()) await dbDir.create(recursive: true);
    return p.join(dbDir.path, fileName);
  }

  /// מחזיר את הנתיב של ה-DB של ספרי המשתמש (תיקיות מותאמות אישית).
  ///
  /// מאוחסן באותה תיקייה כמו DBs אחרים של נתוני משתמש, נפרד מ-`seforim.db`
  /// של הספרייה הרשמית. כך שינויים ב-DB הרשמי לא משפיעים על ספרי המשתמש,
  /// ולהפך.
  static Future<String> resolveUserBooksDbPath() async {
    return resolveNotesDbPath('user_books.db');
  }

  /// Gets the root path for all plugin data.
  static Future<String> getPluginsRootPath() async {
    return p.join(await getDataRootPath(), 'plugins');
  }

  // [EDITING DISABLED]
  // static Future<String> getUserOverridesRootPath() async {
  //   return p.join(await getDataRootPath(), 'user_overrides');
  // }

  /// Gets the root path for per-book settings files.
  static Future<String> getPerBookSettingsPath() async {
    return p.join(await getDataRootPath(), 'per_book_settings');
  }

  /// Gets the path where downloaded/extracted plugins are installed.
  static Future<String> getInstalledPluginsPath() async {
    final root = await getPluginsRootPath();
    return p.join(root, 'installed');
  }

  /// Gets the path for a specific plugin installation.
  static Future<String> getPluginInstallPath(String pluginId) async {
    final installed = await getInstalledPluginsPath();
    return p.join(installed, pluginId, 'current');
  }

  /// Gets the generic data path for a specific plugin.
  static Future<String> getPluginDataPath(String pluginId) async {
    final root = await getPluginsRootPath();
    return p.join(root, 'data', pluginId);
  }

  /// Gets the cache path for a specific plugin.
  static Future<String> getPluginCachePath(String pluginId) async {
    final root = await getPluginsRootPath();
    return p.join(root, 'cache', pluginId);
  }

  /// Resolves the plugin system database path.
  static Future<String> resolvePluginsDbPath() async {
    return resolveNotesDbPath('plugins_host.db');
  }

  /// מחזיר את הנתיב של ה-DB הכתיב למטמונים תפעוליים (למשל מטמון ה-outline
  /// של קובצי PDF חיצוניים).
  ///
  /// נפרד מ-`seforim.db` הרשמי כדי ש-`seforim.db` יוכל להיפתח read-only —
  /// כתיבות מטמון בזמן ריצה זורמות לקובץ כתיב זה בתיקיית מסדי הנתונים הפעילה.
  static Future<String> resolveCacheDbPath() async {
    return resolveNotesDbPath('cache.db');
  }
}
