import 'dart:io';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
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
  }

  static String get _resolvedExecutable =>
      _resolvedExecutableOverride ?? Platform.resolvedExecutable;

  /// Returns the default writable root for user-scoped app data.
  static Future<String> getDataRootPath() async {
    if (_cachedDataRootPath != null && _cachedDataRootPath!.isNotEmpty) {
      return _cachedDataRootPath!;
    }

    final String rootPath;
    if (Platform.isAndroid || Platform.isIOS) {
      rootPath = (await getApplicationDocumentsDirectory()).path;
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

  /// Detects whether the app is installed system-wide or per-user.
  static Future<InstallMode> detectInstallMode() async {
    if (Platform.isMacOS) {
      if (await Directory('/Library/Application Support/Otzaria').exists()) {
        return InstallMode.systemWide;
      }
    }
    if (Platform.isWindows) {
      final exeDir = p.dirname(Platform.resolvedExecutable);
      if (File(p.join(exeDir, 'system_install.marker')).existsSync()) {
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

  /// Default library path.
  ///
  /// On system-wide desktop installs this remains in the shared data root.
  /// Otherwise it lives under the user-scoped app data root.
  ///
  /// On Linux and macOS, if the app is launched from a FULL bundle (אוצריא/
  /// folder sitting next to the executable with a marker file inside), that
  /// bundled library wins over the per-user default. Windows handles this
  /// case via the Inno Setup installer, so detection is skipped there.
  static Future<String> getDefaultLibraryPath() async {
    final bundled = await _detectBundledLibraryPath();
    if (bundled != null) {
      return bundled;
    }

    final systemWideRoot = await _getSystemWideLibraryRootIfNeeded();
    if (systemWideRoot != null) {
      return p.join(systemWideRoot, 'books');
    }

    return p.join(await getDataRootPath(), 'books');
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
            p.join(exeDir, '..', '..', '..', _bundledLibraryFolderName)),
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
    final currentPath =
        Settings.getValue<String>(SettingsRepository.keyLibraryPath);

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
    final dbDir =
        folderName.isEmpty ? libraryPath : p.join(libraryPath, folderName);

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
    final savedIndex =
        Settings.getValue<String>(SettingsRepository.keyIndexPath);
    if (savedIndex != null && savedIndex.isNotEmpty) return savedIndex;

    return _getDefaultIndexPath();
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
    final dbDir = Directory(p.join(await getDataRootPath(), 'databases'));
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

  /// Creates startup directories when eagerly required.
  static Future<void> createNecessaryDirectories() async {
    // Directories are created lazily by the services that actually use them.
  }

  /// Gets the root path for all plugin data.
  static Future<String> getPluginsRootPath() async {
    return p.join(await getDataRootPath(), 'plugins');
  }

  /// Gets the root path for user overrides.
  static Future<String> getUserOverridesRootPath() async {
    return p.join(await getDataRootPath(), 'user_overrides');
  }

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
}
