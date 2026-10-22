import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:otzaria/attached_libraries/repository/attached_library_registry.dart';
import 'package:otzaria/core/user_state/user_state_database.dart';
import 'package:otzaria/data/data_providers/cache_database_holder.dart';
import 'package:otzaria/data/data_providers/db_read_worker.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:otzaria/data/data_providers/user_books_database_holder.dart';
import 'package:otzaria/marker/storage/marker_database.dart';
import 'package:otzaria/migration/database/sqlite3_utils.dart';
import 'package:otzaria/personal_notes/storage/personal_notes_database.dart';
import 'package:otzaria/plugins/storage/plugin_system_database.dart';

/// משחרר את מטמון הדפים של כל חיבורי SQLite שכבר פתוחים; לא פותח חדשים.
/// מוותר על תור האירועים בין חיבור לחיבור, כדי לא לחסום פריים.
Future<void> releaseSqliteMemory() async {
  final steps = <void Function()>[
    () => SqliteDataProvider.instance.repository?.database.shrinkMemoryIfOpen(),
    () => CacheDatabaseHolder.instance.repositoryIfInitialized?.database
        .shrinkMemoryIfOpen(),
    () => UserBooksDatabaseHolder.instance.repositoryIfInitialized?.database
        .shrinkMemoryIfOpen(),
    () => shrinkMemoryBestEffort(UserStateDatabase.instance.openDatabase),
    () => shrinkMemoryBestEffort(PersonalNotesDatabase.instance.openDatabase),
    () => shrinkMemoryBestEffort(MarkerDatabase.instance.openDatabase),
    () => shrinkMemoryBestEffort(PluginSystemDatabase.instance.openDatabase),
  ];
  final worker = DbReadWorker.shrinkMemoryIfRunning();
  for (final step in steps) {
    step();
    await Future<void>.delayed(Duration.zero);
  }
  for (final repo in AttachedLibraryRegistry.instance.openRepositories) {
    repo.database.shrinkMemoryIfOpen();
    await Future<void>.delayed(Duration.zero);
  }
  await worker;
}

/// מפעיל את [releaseSqliteMemory] בלחץ זיכרון ובמעבר לרקע (hidden/paused).
/// inactive לבדו — איבוד פוקוס בדסקטופ — אינו מפעיל.
class SqliteMemoryPressureObserver with WidgetsBindingObserver {
  SqliteMemoryPressureObserver({Future<void> Function()? release})
    : _release = release ?? releaseSqliteMemory;

  final Future<void> Function() _release;
  bool _releasedInBackground = false;
  Future<void>? _running;

  @override
  void didHaveMemoryPressure() => _run();

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        // hidden ואחריו paused באותו מעבר: שחרור אחד מספיק.
        if (_releasedInBackground) return;
        _releasedInBackground = true;
        _run();
      case AppLifecycleState.resumed:
        _releasedInBackground = false;
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        break;
    }
  }

  void _run() {
    if (_running != null) return;
    _running = _release()
        .catchError((Object e) {
          debugPrint('[SqliteMemory] release failed: $e');
        })
        .whenComplete(() => _running = null);
  }
}
