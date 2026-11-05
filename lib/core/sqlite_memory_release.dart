import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:otzaria/attached_libraries/repository/attached_library_registry.dart';
import 'package:otzaria/core/user_state/user_state_database.dart';
import 'package:otzaria/data/data_providers/cache_database_holder.dart';
import 'package:otzaria/data/data_providers/db_read_worker.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:otzaria/data/data_providers/tantivy_data_provider.dart';
import 'package:otzaria/data/data_providers/user_books_database_holder.dart';
import 'package:otzaria/migration/database/sqlite3_utils.dart';
import 'package:otzaria/personal_notes/storage/personal_notes_database.dart';
import 'package:otzaria/plugins/storage/plugin_system_database.dart';
import 'package:otzaria/search/search_engine_gateway.dart';

/// משחרר את מטמון הדפים של כל חיבורי SQLite שכבר פתוחים; לא פותח חדשים.
/// מוותר על תור האירועים בין חיבור לחיבור, כדי לא לחסום פריים.
Future<void> releaseSqliteMemory({bool Function()? shouldContinue}) async {
  bool canContinue() => shouldContinue?.call() ?? true;
  final steps = <void Function()>[
    () => SqliteDataProvider.instance.repository?.database.shrinkMemoryIfOpen(),
    () => CacheDatabaseHolder.instance.repositoryIfInitialized?.database
        .shrinkMemoryIfOpen(),
    () => UserBooksDatabaseHolder.instance.repositoryIfInitialized?.database
        .shrinkMemoryIfOpen(),
    () => shrinkMemoryBestEffort(UserStateDatabase.instance.openDatabase),
    () => shrinkMemoryBestEffort(PersonalNotesDatabase.instance.openDatabase),
    () => shrinkMemoryBestEffort(PluginSystemDatabase.instance.openDatabase),
  ];
  for (final step in steps) {
    if (!canContinue()) return;
    step();
    await Future<void>.delayed(Duration.zero);
  }
  for (final repo in AttachedLibraryRegistry.instance.openRepositories) {
    if (!canContinue()) return;
    repo.database.shrinkMemoryIfOpen();
    await Future<void>.delayed(Duration.zero);
  }
  if (canContinue()) await DbReadWorker.shrinkMemoryIfRunning();
}

/// מתאם פינוי SQLite ומטמוני החיפוש פעם אחת לתהליך, אחרי חשיפת החלון.
/// לחץ מהמערכת דחוף; מעבר לרקע ממתין לשקט ואינו מפנה עבור חלון אחר.
class SqliteMemoryPressureObserver with WidgetsBindingObserver {
  SqliteMemoryPressureObserver({
    Future<void> Function()? release,
    bool Function()? isBusy,
    int Function()? windowCount,
    DateTime Function()? now,
    this.backgroundDelay = const Duration(seconds: 5),
    this.retryDelay = const Duration(seconds: 2),
    this.minimumInterval = const Duration(seconds: 30),
    this.pressureInterval = const Duration(seconds: 2),
  }) : _release = release,
       _isBusy = isBusy ?? _hasActiveWork,
       _windowCount = windowCount ?? _openWindowCount,
       _now = now ?? DateTime.now;

  final Future<void> Function()? _release;
  final bool Function() _isBusy;
  final int Function() _windowCount;
  final DateTime Function() _now;
  final Duration backgroundDelay;
  final Duration retryDelay;
  final Duration minimumInterval;
  final Duration pressureInterval;
  bool _inBackground = false;
  bool _backgroundPending = false;
  bool _pressurePending = false;
  bool _disposed = false;
  Future<void>? _running;
  Timer? _timer;
  DateTime? _lastRelease;
  DateTime? _lastPressureRelease;

  static bool _hasActiveWork() =>
      SearchEngineGateway.hasActiveOperations ||
      (TantivyDataProvider.instanceIfCreated?.isIndexing.value ?? false) ||
      DbReadWorker.hasPendingReads;

  static int _openWindowCount() =>
      WidgetsBinding.instance.platformDispatcher.views.length;

  @override
  void didHaveMemoryPressure() {
    if (_disposed) return;
    _pressurePending = true;
    _schedule(Duration.zero);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_disposed) return;
    switch (state) {
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        if (_inBackground) return;
        _inBackground = true;
        _backgroundPending = true;
        _schedule(_pressurePending ? Duration.zero : backgroundDelay);
      case AppLifecycleState.resumed:
        _inBackground = false;
        _backgroundPending = false;
        if (!_pressurePending) {
          _timer?.cancel();
          _timer = null;
        }
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        break;
    }
  }

  void _schedule(Duration delay) {
    if (_disposed || _running != null) return;
    _timer?.cancel();
    _timer = Timer(delay, _run);
  }

  bool get _canReleaseInBackground =>
      _inBackground && _windowCount() <= 1 && !_isBusy();

  void _run() {
    _timer = null;
    if (_disposed || _running != null) return;
    final pressure = _pressurePending;
    if (!pressure && !_backgroundPending) return;
    if (!pressure && (!_inBackground || _windowCount() > 1)) {
      _backgroundPending = false;
      return;
    }
    if (!pressure && _isBusy()) {
      _schedule(retryDelay);
      return;
    }
    final lastRelease = pressure ? _lastPressureRelease : _lastRelease;
    if (lastRelease != null) {
      final interval = pressure ? pressureInterval : minimumInterval;
      final remaining = interval - _now().difference(lastRelease);
      if (remaining > Duration.zero) {
        _schedule(remaining);
        return;
      }
    }
    _pressurePending = false;
    _backgroundPending = false;
    bool canContinue() => !_disposed && (pressure || _canReleaseInBackground);
    _running =
        Future<void>.sync(() async {
              final release = _release;
              if (release != null) {
                await release();
              } else {
                await releaseSqliteMemory(shouldContinue: canContinue);
                if (canContinue()) {
                  await TantivyDataProvider.instanceIfCreated
                      ?.releaseMemoryIfInitialized();
                }
              }
            })
            .catchError((Object error) {
              debugPrint('[Memory] release failed: $error');
            })
            .whenComplete(() {
              _lastRelease = _now();
              if (pressure) _lastPressureRelease = _lastRelease;
              _running = null;
              if (_pressurePending || _backgroundPending)
                _schedule(Duration.zero);
            });
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
  }
}
