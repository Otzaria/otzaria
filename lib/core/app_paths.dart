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

  @visibleForTesting
  static void debugOverrideDataRootPath(String? path) {
    _cachedDataRootPath = path;
  }

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
  static Future<String> getDefaultLibraryPath() async {
    final systemWideRoot = await _getSystemWideLibraryRootIfNeeded();
    if (systemWideRoot != null) {
      return p.join(systemWideRoot, 'books');
    }

    return p.join(await getDataRootPath(), 'books');
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

    return p.join(await getDataRootPath(), 'index');
  }

  /// Gets the main library path from settings, or gracefully falls back to default paths.
  static Future<String> getLibraryPath() async {
    // Check existing library path setting
    final currentPath =
        Settings.getValue<String>(SettingsRepository.keyLibraryPath);

    if (currentPath != null && currentPath.isNotEmpty) {
      return currentPath;
    }

    // Determine default path based on platform
    String libraryPath = await getDefaultLibraryPath();

    await Settings.setValue(SettingsRepository.keyLibraryPath, libraryPath);
    return libraryPath;
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

  /// Gets the shared directory used for Tantivy lock/state files.
  /// It is kept next to the active index directory.
  static Future<String> getTantivyLockPath() async {
    final indexPath = await getIndexPath();
    final lockDir = Directory(p.join(p.dirname(indexPath), 'tantivy.lock'));
    if (!await lockDir.exists()) {
      await lockDir.create(recursive: true);
    }
    return lockDir.path;
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
