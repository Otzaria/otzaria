import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/settings/bloc/settings_repository.dart';

/// Utility class for managing application paths.
/// Centralizes path construction logic to avoid duplication.
class AppPaths {
  /// Gets the main library path from settings. Defaults to 'C:/אוצריא' for Windows if not set.
  static Future<String> getLibraryPath() async {
    // Check existing library path setting
    final currentPath = Settings.getValue(SettingsRepository.keyLibraryPath);

    if (currentPath != null) {
      return currentPath;
    }

    // Determine default path based on platform
    String libraryPath;
    if (Platform.isIOS) {
      libraryPath = (await getApplicationDocumentsDirectory()).path;
    } else if (Platform.isAndroid) {
      try {
        libraryPath = (await getExternalStorageDirectory())?.path ??
            (await getApplicationDocumentsDirectory()).path;
      } catch (_) {
        libraryPath = (await getApplicationDocumentsDirectory()).path;
      }
    } else if (Platform.isWindows) {
      libraryPath = 'C:/אוצריא';
    } else {
      // Linux, macOS: use application support directory for consistency
      libraryPath = (await getApplicationSupportDirectory()).path;
    }

    await Settings.setValue(SettingsRepository.keyLibraryPath, libraryPath);
    return libraryPath;
  }

  /// Gets the search index path (library_path/index)
  static Future<String> getIndexPath() async {
    final libraryPath = await getLibraryPath();
    return p.join(libraryPath, 'index');
  }

  /// Gets the manifest file path (library_path/files_manifest.json)
  static Future<String> getManifestPath() async {
    final libraryPath = await getLibraryPath();
    return p.join(libraryPath, 'files_manifest.json');
  }

  /// Resolves the notes database path - for cross-platform compatibility
  static Future<String> resolveNotesDbPath(String fileName) async {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      // Windows, Linux, macOS: this will go into application support directory
      final support = await getApplicationSupportDirectory();
      final dbDir = Directory(p.join(support.path, 'databases'));
      if (!await dbDir.exists()) await dbDir.create(recursive: true);
      return p.join(dbDir.path, fileName);
    } else {
      // Mobile: the standard path for sqflite
      final dbs = await getDatabasesPath();
      final dbDir = Directory(dbs);
      if (!await dbDir.exists()) await dbDir.create(recursive: true);
      return p.join(dbs, fileName);
    }
  }

  /// Creates necessary directories for the application
  /// Note: Does NOT create the library path itself - only index directories
  /// The library path should be created by the user or during library download
  static Future<void> createNecessaryDirectories() async {
    final libraryPath = await getLibraryPath();
    final checkDir = Directory(libraryPath);

    if (await checkDir.exists()) {
      final dirs = [
        await getIndexPath(),
      ];

      for (final dirPath in dirs) {
        final directory = Directory(dirPath);
        if (!await directory.exists()) {
          await directory.create(recursive: true);
        }
      }
    }
  }
}
