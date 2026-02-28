import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:path/path.dart' as path;

/// Database configuration constants
class DatabaseConstants {
  /// The name of the main database file
  static const String databaseFileName = 'seforim.db';

  /// The default name of the Otzaria folder
  static const String otzariaFolderName = 'אוצריא';

  /// Gets the full database path based on the library path setting
  static String getDatabasePath() {
    final libraryPath = Settings.getValue<String>('key-library-path') ?? '.';
    final folderName = Settings.getValue<String>('key-library-folder-name') ??
        otzariaFolderName;
    return _buildDbPath(libraryPath, folderName);
  }

  /// Gets the database path for a specific file path
  /// If the file is a .db file, returns it directly
  /// If the file is a .zip file, returns the extracted database path
  static String getDatabasePathForLibrary(String filePath,
      [String? folderName]) {
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
    final folder = folderName ??
        Settings.getValue<String>('key-library-folder-name') ??
        otzariaFolderName;
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
