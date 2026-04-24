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
import 'package:hive_ce/hive.dart';
import 'package:otzaria/app.dart';
import 'package:otzaria/bookmarks/bloc/bookmark_bloc.dart';
import 'package:otzaria/bookmarks/repository/bookmark_repository.dart';
import 'package:otzaria/find_ref/find_ref_bloc.dart';
import 'package:otzaria/find_ref/find_ref_repository.dart';
import 'package:otzaria/core/focus_repository.dart';
import 'package:otzaria/history/bloc/history_bloc.dart';
import 'package:otzaria/history/history_repository.dart';
import 'package:otzaria/indexing/bloc/indexing_bloc.dart';
import 'package:otzaria/library/bloc/library_bloc.dart';
import 'package:otzaria/library/bloc/library_event.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_event.dart';
import 'package:otzaria/navigation/navigation_repository.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
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
import 'package:otzaria/file_sync/file_sync_bloc.dart';
import 'package:otzaria/file_sync/file_sync_repository.dart';
import 'package:otzaria/work_status/work_status_cubit.dart';
import 'package:otzaria/plugins/bloc/plugin_system_bloc.dart';
import 'package:otzaria/plugins/bloc/plugin_system_event.dart';
import 'package:otzaria/plugins/repository/plugin_registry_repository.dart';

import 'package:search_engine/search_engine.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/core/shared_prefs_setup.dart';
import 'package:otzaria/core/error_log_file.dart';
import 'package:otzaria/core/window_listener.dart';
import 'package:otzaria/core/window_persistence.dart';
import 'package:otzaria/tools/shamor_zachor/providers/shamor_zachor_data_provider.dart';
import 'package:otzaria/tools/shamor_zachor/providers/shamor_zachor_progress_provider.dart';
import 'package:otzaria/settings/services/backup_service.dart';
import 'package:otzaria/services/direct_error_report_service.dart';
import 'package:otzaria/data/cache/books_cache.dart';
import 'package:otzaria/data/cache/acronyms_cache.dart';
import 'package:otzaria/tools/dictionary/repository/dictionary_lookup_repository.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:otzaria/tools/calendar/services/notification_service.dart';
import 'package:otzaria/plugins/database/plugin_database_bootstrap.dart';
import 'package:logging/logging.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:otzaria/product_tour/product_tour_exports.dart';
import 'package:otzaria/widgets/restart_widget.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

// Updated automatically by version update scripts - do not edit manually
const int _latestReleasedBuildNumber = 9900;

// Global reference to window listener for cleanup
AppWindowListener? _appWindowListener;

/// Getter for accessing the window listener from other parts of the app
AppWindowListener? get appWindowListener => _appWindowListener;

void _appendUnhandledErrorToLocalLog({
  required String title,
  required Object error,
  StackTrace? stackTrace,
  Map<String, String?> details = const {},
}) {
  try {
    ErrorLogFile.append(
      title: title,
      error: error,
      stackTrace: stackTrace,
      details: details,
    );
  } catch (writeError, writeStackTrace) {
    final formattedMessage = ErrorLogFile.formatEntry(
      title: title,
      error: error,
      stackTrace: stackTrace,
      details: details,
    );
    stderr.writeln(
      'Failed to write error log to ${ErrorLogFile.resolvePath()}: $writeError',
    );
    stderr.writeln(writeStackTrace);
    stderr.writeln(formattedMessage);
  }
}

Map<String, String?> _flutterErrorDetailsForLog(FlutterErrorDetails details) {
  final informationCollector = details.informationCollector;
  final collectedInformation = informationCollector == null
      ? null
      : informationCollector()
          .map((node) => node.toDescription())
          .where((description) => description.trim().isNotEmpty)
          .join('\n');

  return {
    'Library': details.library,
    'Context': details.context?.toString(),
    'Information': collectedInformation,
  };
}

String _formatAppVersion(PackageInfo packageInfo) {
  final version = packageInfo.version.trim();
  final buildNumber = packageInfo.buildNumber.trim();

  if (version.isEmpty) {
    return buildNumber.isEmpty ? 'unknown' : buildNumber;
  }

  if (buildNumber.isEmpty || version.endsWith('+$buildNumber')) {
    return version;
  }

  return '$version+$buildNumber';
}

Future<void> _initializeDataRootForEarlyLogging() async {
  try {
    await AppPaths.getDataRootPath();
  } catch (error, stackTrace) {
    if (kDebugMode) {
      debugPrint('Failed to resolve app data root early: $error\n$stackTrace');
    }
  }
}

Future<void> _initializeLogMetadata() async {
  try {
    final packageInfo = await PackageInfo.fromPlatform();
    ErrorLogFile.setAppVersion(_formatAppVersion(packageInfo));
  } catch (error, stackTrace) {
    ErrorLogFile.setAppVersion('unknown');
    if (kDebugMode) {
      debugPrint('Failed to load app version for logs: $error\n$stackTrace');
    }
  }
}

void _logNonFatalInitializationError(
  String component,
  Object error,
  StackTrace stackTrace,
) {
  if (kDebugMode) {
    debugPrint(
      'Non-fatal initialization error in $component: $error\n$stackTrace',
    );
    return;
  }

  _appendUnhandledErrorToLocalLog(
    title: 'Initialization Warning',
    error: error,
    stackTrace: stackTrace,
    details: {
      'Phase': 'initialize',
      'Component': component,
    },
  );
}

bool _isIgnorableHardwareKeyboardAssertion(String errorString) {
  return errorString.contains('!_pressedKeys.containsKey(event.physicalKey)') ||
      errorString.contains(
        'A KeyDownEvent is dispatched, but the state shows that the physical key is already pressed',
      ) ||
      errorString.contains(
        'A KeyUpEvent is dispatched, but the state shows that the physical key is not pressed',
      );
}

/// Application entry point that initializes necessary components and launches the app.
///
/// This function performs the following initialization steps:
/// 1. Sets up custom error handlers
/// 2. Initializes Sentry for error tracking
/// 3. Ensures Flutter bindings are initialized
/// 4. Calls [initialize] to set up required services and configurations
/// 5. Launches the main application widget
void main() async {
  SentryWidgetsFlutterBinding.ensureInitialized();
  await _initializeDataRootForEarlyLogging();
  await _initializeLogMetadata();
  hierarchicalLoggingEnabled = true;

  // Set up custom error handlers before Sentry initialization
  // Sentry will automatically wrap these handlers
  FlutterError.onError = (FlutterErrorDetails details) {
    final errorString = details.exceptionAsString();

    // Skip accessibility tree errors on Windows - they're harmless noise
    if (Platform.isWindows &&
        (errorString.contains('Failed to update ui::AXTree') ||
            errorString.contains('accessibility_bridge.cc'))) {
      return; // Silently ignore these errors
    }

    // Skip HardwareKeyboard assertion error - happens when window loses focus while
    // a key is held down; fixed by clearState() in onWindowFocus but filter as fallback
    if (_isIgnorableHardwareKeyboardAssertion(errorString)) {
      return; // Silently ignore - handled by HardwareKeyboard.instance.clearState() on focus
    }

    // Log all other errors normally
    if (kDebugMode) {
      FlutterError.dumpErrorToConsole(details);
    } else {
      _appendUnhandledErrorToLocalLog(
        title: 'FlutterError',
        error: details.exceptionAsString(),
        stackTrace: details.stack,
        details: _flutterErrorDetailsForLog(details),
      );
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
    if (_isIgnorableHardwareKeyboardAssertion(errorString)) {
      return true; // Silently ignore
    }

    // Log all other errors normally
    if (kDebugMode) {
      FlutterError.dumpErrorToConsole(FlutterErrorDetails(
        exception: error,
        stack: stack,
      ));
    } else {
      _appendUnhandledErrorToLocalLog(
        title: 'Unhandled Error',
        error: error,
        stackTrace: stack,
      );
    }
    return true;
  };

  if (!kDebugMode) {
    try {
      ErrorLogFile.ensureExists();
    } catch (error, stackTrace) {
      stderr.writeln(
        'Failed to prepare error log file at ${ErrorLogFile.resolvePath()}: $error',
      );
      stderr.writeln(stackTrace);
    }
  }

  // Start Sentry in parallel to avoid blocking app startup.
  unawaited(_initializeSentry());

  await _runAppBootstrap();
}

Future<void> _initializeSentry() async {
  try {
    final info = await PackageInfo.fromPlatform();
    final currentBuild = int.tryParse(info.buildNumber.trim()) ?? 0;

    await SentryFlutter.init(
      (options) {
        // Use environment variable for DSN, with fallback to default
        options.dsn = const String.fromEnvironment(
          'SENTRY_DSN',
          defaultValue:
              'https://79d3003f822fa62bce0c928656308121@o4510914530902016.ingest.us.sentry.io/4510914532868096',
        );
        options.release = '${info.appName}@${info.version}+${info.buildNumber}';
        // Privacy: Do not collect IP addresses and request headers
        options.sendDefaultPii = false;
        // Use lower sampling rates in production to reduce overhead
        options.tracesSampleRate = kDebugMode ? 1.0 : 0.1;

        options.beforeSend = (event, hint) {
          // Only report from the latest released version
          if (currentBuild != _latestReleasedBuildNumber) return null;

          final exception = event.throwable?.toString() ?? '';
          if (Platform.isWindows &&
              (exception.contains('Failed to update ui::AXTree') ||
                  exception.contains('accessibility_bridge.cc'))) {
            return null;
          }
          // Filter HardwareKeyboard assertion - handled by clearState() on window focus
          if (_isIgnorableHardwareKeyboardAssertion(exception)) {
            return null;
          }
          return event;
        };
        options.beforeSendTransaction = (transaction, hint) {
          if (currentBuild != _latestReleasedBuildNumber) return null;
          return transaction;
        };
      },
    );
  } catch (error, stackTrace) {
    if (kDebugMode) {
      debugPrint('Sentry initialization failed: $error\n$stackTrace');
    }
  }
}

Future<void> _runAppBootstrap() async {
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
  final productTourRepository = ProductTourRepository();

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
            RepositoryProvider<ProductTourRepository>(
              create: (context) => productTourRepository,
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
              BlocProvider<ProductTourBloc>(
                create: (context) => ProductTourBloc(
                  repository: productTourRepository,
                )..add(const BootstrapTour()),
              ),
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
                  final dataProvider = context.read<ShamorZachorDataProvider>();
                  return ShamorZachorProgressProvider(
                      dataProvider: dataProvider);
                },
              ),
              BlocProvider<WorkStatusCubit>(
                create: (_) => WorkStatusCubit(),
              ),
              BlocProvider<FileSyncBloc>(
                lazy: true,
                create: (context) => FileSyncBloc(
                  repository: FileSyncRepository(
                    githubOwner: 'Otzaria',
                    repositoryName: 'SeforimLibrary',
                  ),
                  workStatusCubit: context.read<WorkStatusCubit>(),
                ),
              ),
              BlocProvider<PluginSystemBloc>(
                create: (context) => PluginSystemBloc(
                  repository: PluginRegistryRepository(),
                )..add(LoadPlugins()),
              ),
            ],
            child: const App(),
          ),
        ),
      ),
    ),
  );

  // טעינת מילוני ארמי, ראשי תיבות וספרים ברקע – אחרי הפריים הראשון, כדי לא להתחרות עם ה-paint.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(
      DictionaryLookupRepository.instance.ensureLoaded().catchError((e) {
        if (kDebugMode) {
          debugPrint('Failed to warm up dictionary: $e');
        }
      }),
    );
    unawaited(BooksCache.instance.warmUp().catchError((e) {
      if (kDebugMode) debugPrint('Failed to warm up BooksCache: $e');
    }));
    unawaited(AcronymsCache.instance.warmUp().catchError((e) {
      if (kDebugMode) debugPrint('Failed to warm up AcronymsCache: $e');
    }));
  });
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
    await windowManager.ensureInitialized();

    // Configure window manager for proper close handling
    WindowOptions windowOptions = const WindowOptions(
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.hidden,
      windowButtonVisibility: false,
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
  await configureSharedPreferencesPath();
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

  // נדרש לטעינת PDF דרך pdfrx: הגדרת תקיית cache
  try {
    final cacheDir = await getTemporaryDirectory();
    Pdfrx.getCacheDirectory = () => cacheDir.path;
    debugPrint('Pdfrx cache directory set to: ${cacheDir.path}');
  } catch (error, stackTrace) {
    _logNonFatalInitializationError(
      'Pdfrx cache directory',
      error,
      stackTrace,
    );
  }

  // Check and perform automatic backup if needed
  try {
    if (await BackupService.shouldPerformAutoBackup()) {
      await BackupService.performAutoBackup();
    }
  } catch (error, stackTrace) {
    _logNonFatalInitializationError(
      'Automatic backup',
      error,
      stackTrace,
    );
  }

  // Register SQLite sources for plugin database API
  await initPluginDatabaseSources();

  // Initialize Notification Service
  try {
    await NotificationService().init();
  } catch (error, stackTrace) {
    _logNonFatalInitializationError(
      'Notification service',
      error,
      stackTrace,
    );
  }

  try {
    await DirectErrorReportService().startAutomaticFlush();
  } catch (error, stackTrace) {
    _logNonFatalInitializationError(
      'Direct error report queue',
      error,
      stackTrace,
    );
  }
}

/// Creates the necessary directory structure for the application.
///
/// Sets up the unified writable app-data root and its subdirectories.
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

Future<void> initHive() async {
  Hive.init(await AppPaths.getDataRootPath());
  await Hive.openBox<dynamic>('tabs');
  await Hive.openBox<dynamic>('workspaces');
  await Hive.openBox<dynamic>('history');
  await Hive.openBox<dynamic>('bookmarks');
  await Hive.openBox<dynamic>('error_reports_queue');
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
