import 'dart:io';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/data/constants/database_constants.dart';
import 'package:otzaria/settings/settings_repository.dart';

class NavigationRepository {
  /// בודק אם הספרייה ריקה - כלומר אם קובץ seforim.db לא קיים
  bool checkLibraryIsEmpty() {
    final libraryPath =
        Settings.getValue<String>(SettingsRepository.keyLibraryPath);
    if (libraryPath == null || libraryPath.isEmpty) {
      return true;
    }

    // בדיקה שקובץ seforim.db קיים בנתיב המתאים
    final databasePath =
        DatabaseConstants.getDatabasePathForLibrary(libraryPath);
    final databaseFile = File(databasePath);

    if (!databaseFile.existsSync()) {
      return true;
    }

    return false;
  }

  Future<void> refreshLibrary() async {
    // This will be implemented when we migrate the library bloc
    // For now, it's a placeholder for the refresh functionality
  }
}
