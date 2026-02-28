/// This is the main entry point for the Otzaria application.
///
/// The application is a Flutter-based digital library system that supports
/// RTL (Right-to-Left) languages, particularly Hebrew.
/// It includes features for dark mode, customizable themes, and local storage management.
library;

import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_single_instance/flutter_single_instance.dart';
import 'package:window_manager/window_manager.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:provider/provider.dart';
import 'package:hive/hive.dart';
import 'package:otzaria/app.dart';
import 'package:otzaria/bookmarks/bloc/bookmark_bloc.dart';
import 'package:otzaria/bookmarks/repository/bookmark_repository.dart';
import 'package:otzaria/find_ref/find_ref_bloc.dart';
import 'package:otzaria/find_ref/find_ref_repository.dart';
import 'package:otzaria/focus/focus_repository.dart';
import 'package:otzaria/history/bloc/history_bloc.dart';
import 'package:otzaria/history/history_repository.dart';
import 'package:otzaria/indexing/bloc/indexing_bloc.dart';
import 'package:otzaria/library/bloc/library_bloc.dart';
import 'package:otzaria/library/bloc/library_event.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_event.dart';
import 'package:otzaria/navigation/navigation_repository.dart';
import 'package:otzaria/settings/bloc/settings_bloc.dart';
import 'package:otzaria/settings/bloc/settings_event.dart';
import 'package:otzaria/settings/bloc/settings_repository.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/tabs_repository.dart';
import 'package:otzaria/workspaces/bloc/workspace_bloc.dart';
import 'package:otzaria/workspaces/bloc/workspace_event.dart';
import 'package:otzaria/workspaces/workspace_repository.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:path_provider/path_provider.dart';
import 'package:otzaria/app_bloc_observer.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/data/data_providers/hive_data_provider.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_bloc.dart';
import 'package:otzaria/personal_notes/migration/file_to_db_migrator.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:search_engine/search_engine.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/core/window_listener.dart';
import 'package:otzaria/core/window_persistence.dart';
import 'package:otzaria/tools/shamor_zachor/providers/shamor_zachor_data_provider.dart';
import 'package:otzaria/tools/shamor_zachor/providers/shamor_zachor_progress_provider.dart';
import 'package:otzaria/settings/backup_service.dart';
import 'package:otzaria/data/cache/books_cache.dart';
import 'package:otzaria/data/cache/acronyms_cache.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:otzaria/services/notification_service.dart';
import 'package:logging/logging.dart';
import 'package:otzaria/widgets/restart_widget.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

// Global reference to window listener for cleanup
AppWindowListener? _appWindowListener;

/// Getter for accessing the window listener from other parts of the app
AppWindowListener? get appWindowListener => _appWindowListener;

/// Application entry point that initializes necessary components and launches the app.
///
/// This function performs the following initialization steps:
/// 1. Sets up custom error handlers
/// 2. Initializes Sentry for error tracking
/// 3. Ensures Flutter bindings are initialized
/// 4. Calls [initialize] to set up required services and configurations
/// 5. Launches the main application widget
void main() async {
  hierarchicalLoggingEnabled = true;

  // Set up custom error handlers before Sentry initialization
  // Sentry will automatically wrap these handlers
  FlutterError.onError = (FlutterErrorDetails details) {
    final errorString = details.toString();

    // Skip accessibility tree errors on Windows - they're harmless noise
    if (Platform.isWindows &&
        (errorString.contains('Failed to update ui::AXTree') ||
            errorString.contains('accessibility_bridge.cc'))) {
      return; // Silently ignore these errors
    }

    // Skip HardwareKeyboard assertion error - happens when window loses focus while
    // a key is held down; fixed by clearState() in onWindowFocus but filter as fallback
    if (errorString.contains('!_pressedKeys.containsKey(event.physicalKey)') ||
        errorString.contains(
            'A KeyDownEvent is dispatched, but the state shows that the physical key is already pressed')) {
      return; // Silently ignore - handled by HardwareKeyboard.instance.clearState() on focus
    }

    // Log all other errors normally
    if (kDebugMode) {
      FlutterError.dumpErrorToConsole(details);
    } else {
      File('errors.txt')
          .writeAsStringSync(details.toString(), mode: FileMode.append);
    }
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    final errorString = error.toString();

    // Skip accessibility tree errors on Windows
    if (Platform.isWindows &&
        (errorString.contains('Failed to update ui::AXTree') ||
            errorString.contains('accessibility_bridge.cc'))) {
      return true; // Silently ignore these errors
    }

    // Skip HardwareKeyboard assertion error - handled by clearState() on window focus
    if (errorString.contains('!_pressedKeys.containsKey(event.physicalKey)') ||
        errorString.contains(
            'A KeyDownEvent is dispatched, but the state shows that the physical key is already pressed')) {
      return true; // Silently ignore
    }

    // Log all other errors normally
    if (kDebugMode) {
      FlutterError.dumpErrorToConsole(FlutterErrorDetails(
        exception: error,
        stack: stack,
      ));
    } else {
      File('errors.txt')
          .writeAsStringSync(error.toString(), mode: FileMode.append);
    }
    return true;
  };

  // Initialize Sentry - it will wrap the error handlers above
  await SentryFlutter.init(
    (options) {
      // Use environment variable for DSN, with fallback to default
      options.dsn = const String.fromEnvironment(
        'SENTRY_DSN',
        defaultValue:
            'https://79d3003f822fa62bce0c928656308121@o4510914530902016.ingest.us.sentry.io/4510914532868096',
      );
      // Privacy: Do not collect IP addresses and request headers
      options.sendDefaultPii = false;
      // Use lower sampling rates in production to reduce overhead
      options.tracesSampleRate = kDebugMode ? 1.0 : 0.1;

      // Filter out Windows accessibility errors from being sent to Sentry
      options.beforeSend = (event, hint) {
        final exception = event.throwable?.toString() ?? '';
        if (Platform.isWindows &&
            (exception.contains('Failed to update ui::AXTree') ||
                exception.contains('accessibility_bridge.cc'))) {
          return null; // Don't send to Sentry
        }
        // Filter HardwareKeyboard assertion - handled by clearState() on window focus
        if (exception
                .contains('!_pressedKeys.containsKey(event.physicalKey)') ||
            exception.contains(
                'A KeyDownEvent is dispatched, but the state shows that the physical key is already pressed')) {
          return null; // Don't send to Sentry
        }
        return event;
      };
    },
    appRunner: () async {
      SentryWidgetsFlutterBinding.ensureInitialized();

      // Check for single instance - skip on Apple platforms (macOS/iOS) due to sandbox restrictions
      if (!Platform.isMacOS && !Platform.isIOS) {
        FlutterSingleInstance flutterSingleInstance = FlutterSingleInstance();
        bool isFirstInstance = await flutterSingleInstance.isFirstInstance();
        if (!isFirstInstance) {
          // If not the first instance, exit the app
          exit(0);
        }
      }

      // Initialize bloc observer for debugging
      Bloc.observer = AppBlocObserver();

      // Configure logging level for debug mode
      if (kDebugMode) {
        Logger.root.level = Level.ALL;
        // Silence verbose logs from flutter_widget_from_html
        Logger('fwfh').level = Level.INFO;
        Logger.root.onRecord.listen((record) {
          debugPrint(
              '${record.level.name}: ${record.loggerName}: ${record.message}');
        });
      }

      // Remove legacy debug log setup

      await initialize();

      // No-op: removed verbose debug printing

      final historyRepository = HistoryRepository();
      final settingsRepository = SettingsRepository();

      runApp(
        SentryWidget(
          child: RestartWidget(
            child: MultiRepositoryProvider(
              providers: [
                RepositoryProvider<FocusRepository>(
                  create: (context) => FocusRepository(),
                ),
                RepositoryProvider<SettingsRepository>(
                  create: (context) => settingsRepository,
                ),
              ],
              child: MultiBlocProvider(
                providers: [
                  BlocProvider<SettingsBloc>(
                    create: (context) => SettingsBloc(
                      repository: settingsRepository,
                    )..add(LoadSettings()),
                  ),
                  BlocProvider<LibraryBloc>(
                    create: (context) => LibraryBloc()..add(LoadLibrary()),
                  ),
                  BlocProvider<IndexingBloc>(
                    create: (context) => IndexingBloc.create(),
                  ),
                  BlocProvider<HistoryBloc>(
                      create: (context) => HistoryBloc(historyRepository)),
                  BlocProvider<TabsBloc>(
                    create: (context) => TabsBloc(
                      repository: TabsRepository(),
                    )..add(LoadTabs()),
                  ),
                  BlocProvider<NavigationBloc>(
                    create: (context) => NavigationBloc(
                      repository: NavigationRepository(),
                      tabsRepository: TabsRepository(),
                    )..add(const CheckLibrary()),
                  ),
                  BlocProvider<FindRefBloc>(
                      create: (context) => FindRefBloc(
                          findRefRepository: FindRefRepository(
                              dataRepository: DataRepository.instance))),
                  BlocProvider<PersonalNotesBloc>(
                    create: (context) => PersonalNotesBloc(),
                  ),
                  BlocProvider<BookmarkBloc>(
                    create: (context) => BookmarkBloc(BookmarkRepository()),
                  ),
                  BlocProvider<WorkspaceBloc>(
                    create: (context) {
                      final tabsBloc = context.read<TabsBloc>();
                      return WorkspaceBloc(
                        repository: WorkspaceRepository(),
                        onWorkspaceTabsChanged:
                            (List<OpenedTab> tabs, int activeIndex) {
                          // This callback coordinates workspace switching with TabsBloc
                          tabsBloc.add(ReplaceAllTabs(
                            tabs,
                            activeIndex,
                          ));
                        },
                      )..add(LoadWorkspaces());
                    },
                  ),
                  ChangeNotifierProvider<ShamorZachorDataProvider>(
                    lazy: true, // Create only when needed
                    create: (context) => ShamorZachorDataProvider(),
                  ),
                  ChangeNotifierProvider<ShamorZachorProgressProvider>(
                    lazy: true, // Create only when needed
                    create: (context) {
                      final dataProvider =
                          context.read<ShamorZachorDataProvider>();
                      return ShamorZachorProgressProvider(
                          dataProvider: dataProvider);
                    },
                  ),
                ],
                child: const App(),
              ),
            ),
          ),
        ),
      );
    },
  );
}

/// Initializes all required services and configurations for the application.
///
/// This function handles the following initialization steps:
/// 1. Settings initialization with Hive cache
/// 2. Library path configuration
/// 3. Rust library initialization
/// 4. Hive storage boxes setup
/// 5. Required directory structure creation
/// 6. Shamor Zachor dynamic data loader initialization
Future<void> initialize() async {
  // Initialize SQLite FFI for desktop platforms
  if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await windowManager.ensureInitialized();

    // Configure window manager for proper close handling
    WindowOptions windowOptions = const WindowOptions(
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.hidden,
    );

    // Add window listener for proper close handling
    _appWindowListener = AppWindowListener();
    windowManager.addListener(_appWindowListener!);

    await windowManager.setPreventClose(true);

    windowManager.waitUntilReadyToShow(windowOptions, () async {
      await WindowPersistence.restoreIfAny();
      await windowManager.show();
      await windowManager.focus();
    });
  }

  await RustLib.init();
  await Settings.init(cacheProvider: HiveCache());
  await initHive();
  await createDirs();
  await loadCerts();

  // Initialize SQLite Database Provider
  await SqliteDataProvider.instance.initialize();

  // Migrate personal notes from file storage to SQLite database
  await FileToDbMigrator.runMigration();

  // If the migration created the DB file on a first run, initialize again.
  await SqliteDataProvider.instance.initialize();

  // Warm up shared in-memory caches for books and acronyms.
  // BooksCache is shared between library screen and FindRef.
  // AcronymsCache is used exclusively by FindRef.
  try {
    await BooksCache.instance.warmUp();
    await AcronymsCache.instance.warmUp();
  } catch (e) {
    if (kDebugMode) {
      debugPrint('Failed to warm up book/acronym caches: $e');
    }
  }

  // נדרש לטעינת PDF דרך pdfrx: הגדרת תקיית cache
  try {
    final cacheDir = await getTemporaryDirectory();
    Pdfrx.getCacheDirectory = () => cacheDir.path;
    debugPrint('Pdfrx cache directory set to: ${cacheDir.path}');
  } catch (e) {
    debugPrint('Failed to set Pdfrx cache directory: $e');
  }

  // Check and perform automatic backup if needed
  try {
    if (await BackupService.shouldPerformAutoBackup()) {
      await BackupService.performAutoBackup();
    }
  } catch (e) {
    if (kDebugMode) {
      debugPrint('Failed to perform automatic backup: $e');
    }
    // Continue without backup if it fails
  }

  // Initialize Notification Service
  try {
    await NotificationService().init();
  } catch (e) {
    if (kDebugMode) {
      debugPrint('Failed to initialize notification service: $e');
    }
  }
}

/// Creates the necessary directory structure for the application.
///
/// Sets up two main directories:
/// - Main library directory ('אוצריא')
/// - Index directory for search functionality
Future<void> createDirs() async {
  await AppPaths.createNecessaryDirectories();
}

/// Creates a directory if it doesn't already exist.
///
/// [path] The full path of the directory to create
///
/// Prints status messages indicating whether the directory was created
/// or already existed.
void createDirectoryIfNotExists(String path) {
  Directory directory = Directory(path);
  if (!directory.existsSync()) {
    directory.createSync(recursive: true);
  }
}

initHive() async {
  Hive.defaultDirectory = (await getApplicationSupportDirectory()).path;
  Hive.box(name: 'tabs', maxSizeMiB: 100);
  Hive.box(name: 'workspaces', maxSizeMiB: 100);
  Hive.box(name: 'history', maxSizeMiB: 100);
  Hive.box(name: 'bookmarks', maxSizeMiB: 100);
}

Future<void> loadCerts() async {
  final certs = ['assets/ca/netfree_cas.pem'];
  for (var cert in certs) {
    final certBytes = await rootBundle.load(cert);
    SecurityContext.defaultContext
        .setTrustedCertificatesBytes(certBytes.buffer.asUint8List());
  }
}

/// Clean up resources when the app is closing
void cleanup() {
  _appWindowListener?.dispose();

  // Clear shared book/acronym caches
  BooksCache.instance.clear();
  AcronymsCache.instance.clear();
}

// Note: TOC parsing helper moved to lib/utils/toc_parser.dart for reuse
