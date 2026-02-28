import 'dart:io';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/data/constants/database_constants.dart';
import 'package:otzaria/settings/bloc/settings_repository.dart';
import 'package:otzaria/data/data_providers/file_system_data_provider.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/data/data_providers/tantivy_data_provider.dart';

class NavigationRepository {
  /// בודק אם הספרייה ריקה - כלומר אם קובץ seforim.db לא קיים
  bool checkLibraryIsEmpty() {
    final libraryPath =
        Settings.getValue<String>(SettingsRepository.keyLibraryPath);

    if (libraryPath == null || libraryPath.isEmpty) {
      return true;
    }

    // בדיקה שקובץ seforim.db קיים בנתיב המתאים
    final databasePath = DatabaseConstants.getDatabasePath();
    final databaseFile = File(databasePath);

    if (!databaseFile.existsSync()) {
      return true;
    }

    return false;
  }

  Future<void> refreshLibrary() async {
    // טעינת הספרייה מחדש
    final libraryPath =
        Settings.getValue<String>(SettingsRepository.keyLibraryPath);
    if (libraryPath != null) {
      // עדכון נתיב הספרייה
      FileSystemData.instance.libraryPath = libraryPath;

      // טעינת הספרייה מחדש
      DataRepository.instance.library = FileSystemData.instance.getLibrary();

      // פתיחה מחדש של אינדקס החיפוש
      try {
        await TantivyDataProvider.instance.reopenIndex();
      } catch (e) {
        // Continue without search index if it fails
      }
    }
  }
}
