import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:logging/logging.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/settings/engine/settings_wrapper.dart';
import 'package:otzaria/settings/services/custom_folders/custom_folder.dart';

import '../../data/data_providers/sqlite_data_provider.dart';
import '../../data/data_providers/user_books_database_holder.dart';
import 'background_db_sync_worker.dart';
import 'file_sync_service.dart';

/// Initializes background file sync after app startup.
///
/// This class ensures that the sync runs AFTER the app is fully loaded,
/// without blocking the user experience.
class BackgroundSyncInitializer {
  static final _log = Logger('BackgroundSyncInitializer');
  static bool _hasRun = false;
  static bool _customFoldersSyncedThisSession = false;
  static Completer<FileSyncResult?>? _syncCompleter;
  static SettingsWrapper settings = SettingsWrapper();

  /// מסמן שסריקת תיקיות אישיות ידנית כבר הסתיימה בסשן — כדי שסנכרון הרקע
  /// בהפעלה ידלג על סריקה חוזרת של אותן תיקיות.
  static void markCustomFoldersSyncedThisSession() {
    _customFoldersSyncedThisSession = true;
  }

  /// Initialize background sync after a delay.
  ///
  /// This should be called from the app's main widget after it's built.
  /// The sync will run in the background without blocking the UI.
  ///
  /// [delaySeconds] - How long to wait after app startup before syncing.
  ///                  Default is 3 seconds to ensure UI is responsive.
  static Future<void> initializeAfterDelay({
    int delaySeconds = 5,
    void Function(FileSyncResult result)? onComplete,
  }) async {
    if (_hasRun) {
      _log.info('Background sync already initiated, skipping');
      return;
    }

    _hasRun = true;
    _syncCompleter = Completer<FileSyncResult?>();

    _log.info('Scheduling background sync in $delaySeconds seconds...');

    // Wait for the specified delay
    await Future.delayed(Duration(seconds: delaySeconds));

    // Run sync in background
    _runBackgroundSync(onComplete: onComplete);
  }

  /// Run the background sync
  static Future<void> _runBackgroundSync({
    void Function(FileSyncResult result)? onComplete,
  }) async {
    try {
      if (!shouldRunBackgroundSync()) {
        _log.info(
          'Background file sync skipped because offline mode is active '
          'or software and book updates are disabled',
        );
        _syncCompleter?.complete(null);
        return;
      }

      if (_customFoldersSyncedThisSession) {
        _log.info(
          'Custom-folders sync already ran this session, skipping background '
          'sync',
        );
        _syncCompleter?.complete(null);
        return;
      }

      _log.info('Starting background file sync...');

      final sqliteProvider = SqliteDataProvider.instance;
      if (!sqliteProvider.isInitialized) {
        await sqliteProvider.initialize();
      }

      if (!sqliteProvider.isInitialized) {
        _log.warning('SQLite database not initialized, skipping sync');
        _syncCompleter?.complete(null);
        return;
      }

      final dbPath = sqliteProvider.dbPath;
      final libraryPath = Settings.getValue<String>(
        SettingsRepository.keyLibraryPath,
      );
      if (libraryPath == null || libraryPath.isEmpty) {
        _log.warning('Library path not set, skipping sync');
        _syncCompleter?.complete(null);
        return;
      }

      final customFoldersJson = Settings.getValue<String>(
        SettingsRepository.keyCustomFolders,
      );
      final customFolders = CustomFoldersManager.loadFolders(customFoldersJson);
      final folderName =
          Settings.getValue<String>(SettingsRepository.keyLibraryFolderName) ??
          '';

      final userBooksDbPath = await UserBooksDatabaseHolder.resolveDbPath();

      // הסנכרון כותב אך ורק ל-user_books.db ופותח את seforim.db read-only,
      // ולכן חיבור ה-RO הראשי נשאר פתוח לכל אורכו.
      final result = await runCustomFoldersDbSyncInIsolate(
        dbPath: dbPath,
        userBooksDbPath: userBooksDbPath,
        libraryPath: libraryPath,
        customFolders: customFolders,
        folderName: folderName,
      );

      _log.info('Background sync completed: $result');

      if (result.addedBooks > 0 ||
          result.updatedBooks > 0 ||
          result.addedLinks > 0) {
        debugPrint(
          '📚 סנכרון קבצים הושלם: '
          '${result.addedBooks} ספרים חדשים, '
          '${result.updatedBooks} ספרים עודכנו, '
          '${result.addedLinks} קישורים נוספו',
        );
      }

      onComplete?.call(result);
      _syncCompleter?.complete(result);
    } catch (e, stackTrace) {
      _log.severe('Error during background sync', e, stackTrace);
      _syncCompleter?.completeError(e);
    }
  }

  /// Check if sync has already run
  static bool get hasRun => _hasRun;

  /// Wait for sync to complete (useful for testing)
  static Future<FileSyncResult?> waitForCompletion() async {
    if (_syncCompleter == null) return null;
    return _syncCompleter!.future;
  }

  /// Reset state (useful for testing)
  @visibleForTesting
  static void reset() {
    _hasRun = false;
    _customFoldersSyncedThisSession = false;
    _syncCompleter = null;
    settings = SettingsWrapper();
  }

  @visibleForTesting
  static bool shouldRunBackgroundSync({SettingsWrapper? settingsWrapper}) {
    final wrapper = settingsWrapper ?? settings;
    final isOfflineMode = wrapper.getValue<bool>(
      SettingsRepository.keyOfflineMode,
      defaultValue: false,
    );
    final softwareAndBookUpdatesEnabled = wrapper.getValue<bool>(
      SettingsRepository.keySoftwareAndBookUpdatesEnabled,
      defaultValue: true,
    );

    return !isOfflineMode && softwareAndBookUpdatesEnabled;
  }
}
