import 'dart:io';
import 'package:flutter/foundation.dart' show visibleForTesting;
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

  static bool? _isPortableCache;

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
    if (Platform.isWindows) {
      final exeDir = p.dirname(Platform.resolvedExecutable);
      // ה-marker (נכתב ע"י ה-installer בהתקנת מנהל) וה-exe תחת Program Files
      // הם אותות יציבים שאינם משתנים כשהמשתמש מעביר את הספרייה. בכוונה אין
      // כאן fallback לפי נתיב הספרייה — הוא היה גורם לזיהוי להתהפך ל-perUser
      // (וברירת מחדל ל-AppData) ברגע שהספרייה הועברה מחוץ ל-ProgramData.
      if (File(p.join(exeDir, 'system_install.marker')).existsSync()) {
        return InstallMode.systemWide;
      }
      final exeDirLower = exeDir.toLowerCase();
      final pf = (Platform.environment['ProgramFiles'] ?? r'C:\Program Files')
          .toLowerCase();
      final pfX86 =
          (Platform.environment['ProgramFiles(x86)'] ??
                  r'C:\Program Files (x86)')
              .toLowerCase();
      if (exeDirLower.startsWith(pf) || exeDirLower.startsWith(pfX86)) {
        return InstallMode.systemWide;
      }
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

    // תאימות אחורה: בעבר האינדקס תמיד נוצר תחת dataRoot (APPDATA וכדומה).
    // אם קיים שם אינדקס – ממשיכים להשתמש בו כדי לא לאבד עבודה.
    final legacyPath = p.join(await getDataRootPath(), 'index');
    if (await Directory(legacyPath).exists()) {
      return legacyPath;
    }

    // ברירת מחדל חדשה: האינדקס יושב ליד תיקיית הספרייה. כך אם המשתמש
    // העביר את הספרייה לכונן אחר (למשל D:), גם האינדקס יישב שם.
    final libraryPath = await getLibraryPath();
    return p.join(p.dirname(libraryPath), 'index');
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

  /// Returns the backup path inside the writable app data root.
  static Future<String> getDefaultBackupPath() async {
    return p.join(await getDataRootPath(), 'backups');
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
