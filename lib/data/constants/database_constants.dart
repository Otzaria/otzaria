import 'dart:io';

import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:path/path.dart' as path;

/// Database configuration constants
class DatabaseConstants {
  /// The name of the main database file
  static const String databaseFileName = 'seforim.db';

  /// The name of the compressed main database archive (as published on releases).
  static const String databaseArchiveFileName = 'seforim.db.zst';

  /// The morphology dictionary used by fuzzy search.
  static const String lexicalDatabaseFileName = 'lexical.db';

  /// The name of the external catalogs database file
  static const String externalCatalogDatabaseFileName = 'otzar-HB_catalog.db';

  /// The name of the compressed external catalogs database file
  static const String externalCatalogArchiveFileName =
      'otzar-HB_catalog.db.zst';

  /// The bundled PDF directory name for Talmud Bavli.
  static const String talmudBavliFolderName = 'תלמוד בבלי';

  /// The name of the compressed Talmud Bavli PDF archive (tar.zst).
  static const String talmudBavliArchiveFileName =
      'talmud_bavli_latest.tar.zst';

  /// שם קובץ הגרסה בתיקיית התלמוד, וערך הסימון בזמן חילוץ שטרם הסתיים.
  static const String talmudBavliVersionFileName = '.version';
  static const String talmudBavliInstallingMarker = 'installing';

  /// The name of the external catalogs version file in GitHub releases
  static const String externalCatalogVersionFileName = 'version.txt';

  /// The default name of the Otzaria folder
  static const String otzariaFolderName = 'Otzaria';

  /// שמות הקבצים והתיקיות שהתוכנה מנהלת בתוך תיקיית הספרייה. בהעברת מיקום
  /// הספרייה מעבירים רק אותם — קבצים שהמשתמש הוסיף לתיקייה נשארים במקומם.
  /// כולל קובצי לוואי של SQLite (-wal/-shm) שעשויים להישאר ליד ה-DB.
  /// קבצי ארכיון דחוסים (zst) אינם כאן בכוונה — אינם נצרכים ולא מועברים.
  static Set<String> libraryManagedEntryNames() => {
    databaseFileName,
    '$databaseFileName-wal',
    '$databaseFileName-shm',
    lexicalDatabaseFileName,
    externalCatalogDatabaseFileName,
    '$externalCatalogDatabaseFileName-wal',
    '$externalCatalogDatabaseFileName-shm',
    externalCatalogVersionFileName,
    talmudBavliFolderName,
    'files_manifest.json',
  };

  /// Gets the full database path based on the library path setting.
  ///
  /// On Android, if the user selected a directory in external/scoped storage,
  /// the DB is copied/moved to internal storage and [keyDbEffectivePath] is set
  /// as an override so sqlite3 native can open it.
  static String getDatabasePath() {
    // Android: check for an internal-storage override first
    final effectivePath =
        Settings.getValue<String>(SettingsRepository.keyDbEffectivePath) ?? '';
    if (effectivePath.isNotEmpty) {
      return effectivePath;
    }
    final libraryPath =
        Settings.getValue<String>(SettingsRepository.keyLibraryPath) ?? '.';
    final folderName =
        Settings.getValue<String>(SettingsRepository.keyLibraryFolderName) ??
        '';
    return _buildDbPath(libraryPath, folderName);
  }

  /// Gets the directory that contains the main database file.
  /// When keyDbEffectivePath is set (Android copy to internal storage),
  /// this still returns the ORIGINAL library directory so that sibling
  /// files (external-catalog DB, links, metadata) are found correctly.
  static String getDatabaseDirectoryPath() {
    final libraryPath =
        Settings.getValue<String>(SettingsRepository.keyLibraryPath) ?? '.';
    final folderName =
        Settings.getValue<String>(SettingsRepository.keyLibraryFolderName) ??
        '';
    return path.dirname(_buildDbPath(libraryPath, folderName));
  }

  /// Gets the full path for the external catalogs database.
  static String getExternalCatalogDatabasePath() {
    return path.join(
      getDatabaseDirectoryPath(),
      externalCatalogDatabaseFileName,
    );
  }

  /// Gets the full path for the compressed external catalogs archive.
  static String getExternalCatalogArchivePath() {
    return path.join(
      getDatabaseDirectoryPath(),
      externalCatalogArchiveFileName,
    );
  }

  /// Gets the full path for the bundled Talmud Bavli PDF directory.
  static String getTalmudBavliDirectoryPath([
    String? libraryPath,
    String? folderName,
  ]) {
    final basePath =
        libraryPath ??
        Settings.getValue<String>(SettingsRepository.keyLibraryPath) ??
        '.';
    final folder =
        folderName ??
        Settings.getValue<String>(SettingsRepository.keyLibraryFolderName) ??
        '';
    final databaseDirectory = path.dirname(_buildDbPath(basePath, folder));
    return path.join(databaseDirectory, talmudBavliFolderName);
  }

  /// Gets candidate paths for the bundled Talmud Bavli PDF directory.
  ///
  /// The preferred location is next to the active DB. A fallback at the
  /// library root is also supported for manual extractions.
  static List<String> getTalmudBavliDirectoryPaths([
    String? libraryPath,
    String? folderName,
  ]) {
    final basePath =
        libraryPath ??
        Settings.getValue<String>(SettingsRepository.keyLibraryPath) ??
        '.';
    final primary = getTalmudBavliDirectoryPath(libraryPath, folderName);
    final fallback = path.join(basePath, talmudBavliFolderName);

    if (path.normalize(primary) == path.normalize(fallback)) {
      return [primary];
    }

    return [primary, fallback];
  }

  /// הנתיב לקובץ סימון הגרסה בתוך תיקיית תלמוד נתונה.
  static String talmudBavliVersionFilePath(String talmudDirPath) =>
      path.join(talmudDirPath, talmudBavliVersionFileName);

  /// חילוץ שנקטע משאיר את התיקייה עם הסימון [talmudBavliInstallingMarker];
  /// זיהוי כזה מאפשר לשכבת הספרייה להתעלם מהתקנה חלקית.
  static bool isTalmudBavliInstallInProgress(String talmudDirPath) {
    final marker = File(talmudBavliVersionFilePath(talmudDirPath));
    if (!marker.existsSync()) return false;
    return marker.readAsStringSync().trim() == talmudBavliInstallingMarker;
  }

  /// Returns whether [filePath] points to a file inside the bundled
  /// Talmud Bavli directory.
  static bool isTalmudBavliFilePath(
    String? filePath, {
    String? libraryPath,
    String? folderName,
    String? talmudBavliDirectoryPath,
  }) {
    if (filePath == null || filePath.isEmpty) {
      return false;
    }

    final normalizedFilePath = path.normalize(filePath);

    final candidateDirs =
        (talmudBavliDirectoryPath != null &&
            talmudBavliDirectoryPath.isNotEmpty)
        ? [talmudBavliDirectoryPath]
        : getTalmudBavliDirectoryPaths(libraryPath, folderName);

    for (final candidateDir in candidateDirs) {
      final bundledDir = path.normalize(candidateDir);
      if (normalizedFilePath == bundledDir ||
          path.isWithin(bundledDir, normalizedFilePath)) {
        return true;
      }
    }

    return false;
  }

  /// Gets the database path for a specific file path
  /// If the file is a .db file, returns it directly
  /// If the file is a .zip file, returns the extracted database path
  static String getDatabasePathForLibrary(
    String filePath, [
    String? folderName,
  ]) {
    // If it's a .db file, return it directly
    if (filePath.toLowerCase().endsWith('.db')) {
      return filePath;
    }

    // If it's a .zip file, return the extracted path
    if (filePath.toLowerCase().endsWith('.zip')) {
      final fileName = path.basenameWithoutExtension(filePath);
      final directory = path.dirname(filePath);
      return path.join(directory, fileName, databaseFileName);
    }

    // Fallback for directory paths (legacy support)
    final folder =
        folderName ??
        Settings.getValue<String>(SettingsRepository.keyLibraryFolderName) ??
        '';
    return _buildDbPath(filePath, folder);
  }

  /// Builds a database file path from a base directory and folder name.
  static String _buildDbPath(String basePath, String folderName) {
    if (folderName.isEmpty) {
      return path.join(basePath, databaseFileName);
    }
    return path.join(basePath, folderName, databaseFileName);
  }

  /// Private constructor to prevent instantiation
  DatabaseConstants._();
}
