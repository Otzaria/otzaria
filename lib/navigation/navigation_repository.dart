import 'dart:io';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/data/cache/acronyms_cache.dart';
import 'package:otzaria/data/cache/generation_cache.dart';
import 'package:otzaria/data/constants/database_constants.dart';
import 'package:otzaria/data/cache/books_cache.dart';
import 'package:otzaria/data/data_providers/file_system_data_provider.dart';
import 'package:otzaria/data/data_providers/library_provider_manager.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/data/data_providers/tantivy_data_provider.dart';
import 'package:otzaria/find_ref/repository/find_ref_repository.dart';
import 'package:otzaria/services/commentary_service.dart';
import 'package:otzaria/find_ref/repository/reference_books_cache.dart';
import 'package:otzaria/settings/settings_exports.dart';

class NavigationRepository {
  NavigationRepository({Future<void> Function()? reopenIndex})
    : _reopenIndex =
          reopenIndex ?? (() => TantivyDataProvider.instance.reopenIndex());

  final Future<void> Function() _reopenIndex;

  /// בודק אם הספרייה ריקה - כלומר אם קובץ seforim.db לא קיים
  bool checkLibraryIsEmpty() {
    final libraryPath = Settings.getValue<String>(
      SettingsRepository.keyLibraryPath,
    );

    if (libraryPath == null || libraryPath.isEmpty) {
      return true;
    }

    // בדיקה שקובץ seforim.db קיים בנתיב המתאים
    final databasePath = DatabaseConstants.getDatabasePath();
    final databaseFile = File(databasePath);

    if (!databaseFile.existsSync()) {
      return true;
    }

    // Android: גם אם הקובץ "קיים" (stat עובד), ייתכן שה-native sqlite3
    // לא יכול לפתוח אותו מאחסון Scoped Storage חיצוני.
    // אם אין keyDbEffectivePath, המשמעות היא שה-flow לא הושלם — נחזיר true
    // כדי שהמשתמש יגיע למסך הבחירה עם הדיאלוג המתאים.
    if (Platform.isAndroid && !_isNativeAccessible(databasePath)) {
      final effectivePath =
          Settings.getValue<String>(SettingsRepository.keyDbEffectivePath) ??
          '';
      if (effectivePath.isEmpty) {
        return true;
      }
    }

    return false;
  }

  /// בודק אם נתיב נגיש ל-sqlite3 native ב-Android.
  static bool _isNativeAccessible(String filePath) {
    if (filePath.startsWith('/data/')) return true;
    if (filePath.contains('/Android/data/')) return true;
    if (filePath.contains('/Android/obb/')) return true;
    return false;
  }

  Future<void> refreshLibrary() async {
    // טעינת הספרייה מחדש
    final libraryPath = Settings.getValue<String>(
      SettingsRepository.keyLibraryPath,
    );
    if (libraryPath != null) {
      await SqliteDataProvider.instance.dispose();
      LibraryProviderManager.instance.resetRuntimeState();
      ReferenceBooksCache.instance.clear();
      BooksCache.instance.clear();
      AcronymsCache.instance.clear();
      GenerationCache.instance.clear();
      // ה-FindRefRepository מחזיק caches פנימיים (מפרשים, AltToc שטוח) שלא
      // ניזונים מהקאשים שלמעלה. בלי איפוס יזום הם ישרדו עד restart מלא.
      FindRefRepository.clearAllCaches();
      CommentaryService.clearEraCache();

      // עדכון נתיב הספרייה
      FileSystemData.instance.libraryPath = libraryPath;
      FileSystemData.instance.clearBookCache();

      // טעינת הספרייה מחדש
      DataRepository.instance.library = FileSystemData.instance.getLibrary();
      DataRepository.instance.invalidateExternalBooksCache();

      // פתיחה מחדש של אינדקס החיפוש
      try {
        await _reopenIndex();
      } catch (e) {
        // Continue without search index if it fails
      }
    }
  }
}
