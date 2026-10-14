import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/data/cache/acronyms_cache.dart';
import 'package:otzaria/data/cache/generation_cache.dart';
import 'package:otzaria/data/constants/database_constants.dart';
import 'package:otzaria/data/cache/books_cache.dart';
import 'package:otzaria/data/data_providers/file_system_data_provider.dart';
import 'package:otzaria/data/data_providers/library_provider_manager.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:otzaria/data/sqlite/sqlite3_api.dart' as sqlite3;
import 'package:otzaria/data/data_providers/database_library_provider.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/data/data_providers/tantivy_data_provider.dart';
import 'package:otzaria/divine_names/repository/divine_names_repository.dart';
import 'package:otzaria/text_book/repository/book_notes_repository.dart';
import 'package:otzaria/find_ref/repository/find_ref_repository.dart';
import 'package:otzaria/services/commentary_service.dart';
import 'package:otzaria/services/target_line_links_service.dart';
import 'package:otzaria/find_ref/repository/reference_books_cache.dart';
import 'package:otzaria/settings/settings_exports.dart';

class NavigationRepository {
  NavigationRepository({Future<void> Function()? reopenIndex})
    : _reopenIndex =
          reopenIndex ?? (() => TantivyDataProvider.instance.reopenIndex());

  final Future<void> Function() _reopenIndex;

  @visibleForTesting
  static bool? debugIsAndroidOverride;

  @visibleForTesting
  static bool Function(String path)? debugCanOpenSqliteOverride;

  static bool get _isAndroid => debugIsAndroidOverride ?? Platform.isAndroid;

  /// בודק אם הספרייה ריקה או ש-SQLite אינו יכול לפתוח את המסד באנדרואיד.
  Future<bool> checkLibraryIsEmpty() async {
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

    if (_isAndroid) {
      final canOpen = await DatabaseLibraryProvider.operationQueue.enqueue(() {
        final canOpenSqlite = debugCanOpenSqliteOverride;
        return canOpenSqlite == null
            ? Isolate.run(() => _canOpenSqlite(databasePath))
            : Future.value(canOpenSqlite(databasePath));
      });
      if (!canOpen) return true;
    }

    return false;
  }

  static bool _canOpenSqlite(String path) {
    sqlite3.Database? database;
    try {
      database = sqlite3.sqlite3.open(path, mode: sqlite3.OpenMode.readOnly);
      return true;
    } on FileSystemException {
      return false;
    } on sqlite3.SqliteException {
      return false;
    } finally {
      database?.close();
    }
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
      TargetLineLinksService.instance.clearCache();
      DivineNamesRepository.instance.clear();
      BookNotesRepository.instance.clear();

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
