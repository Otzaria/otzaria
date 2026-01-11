import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';

import '../../data/data_providers/sqlite_data_provider.dart';
import 'file_sync_service.dart';

/// Initializes background file sync after app startup.
///
/// This class ensures that the sync runs AFTER the app is fully loaded,
/// without blocking the user experience.
class BackgroundSyncInitializer {
  static final _log = Logger('BackgroundSyncInitializer');
  static bool _hasRun = false;
  static Completer<FileSyncResult?>? _syncCompleter;

  /// Initialize background sync after a delay.
  ///
  /// This should be called from the app's main widget after it's built.
  /// The sync will run in the background without blocking the UI.
  ///
  /// [delaySeconds] - How long to wait after app startup before syncing.
  ///                  Default is 3 seconds to ensure UI is responsive.
  static Future<void> initializeAfterDelay({
    int delaySeconds = 5,
    void Function(double progress, String message)? onProgress,
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
    _runBackgroundSync(onProgress: onProgress, onComplete: onComplete);
  }

  /// Run the background sync
  static Future<void> _runBackgroundSync({
    void Function(double progress, String message)? onProgress,
    void Function(FileSyncResult result)? onComplete,
  }) async {
    try {
      _log.info('Starting background file sync...');

      // Get SQLite provider
      final sqliteProvider = SqliteDataProvider.instance;

      // Ensure database is initialized
      if (!sqliteProvider.isInitialized) {
        await sqliteProvider.initialize();
      }

      if (!sqliteProvider.isInitialized) {
        _log.warning('SQLite database not initialized, skipping sync');
        _syncCompleter?.complete(null);
        return;
      }

      // Get repository
      final repository = sqliteProvider.repository;
      if (repository == null) {
        _log.warning('Repository not available, skipping sync');
        _syncCompleter?.complete(null);
        return;
      }

      // Create sync service
      final syncService = await FileSyncService.getInstance(repository);
      if (syncService == null) {
        _log.warning('Could not create sync service, skipping sync');
        _syncCompleter?.complete(null);
        return;
      }

      // Run sync
      final result = await syncService.syncFiles(onProgress: onProgress);

      _log.info('Background sync completed: $result');

      if (result.addedBooks > 0 ||
          result.updatedBooks > 0 ||
          result.addedLinks > 0) {
        debugPrint('📚 סנכרון קבצים הושלם: '
            '${result.addedBooks} ספרים חדשים, '
            '${result.updatedBooks} ספרים עודכנו, '
            '${result.addedLinks} קישורים נוספו');
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
    _syncCompleter = null;
  }
}
