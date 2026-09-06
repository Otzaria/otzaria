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
import 'package:flutter/scheduler.dart' show FrameCallback;
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:flutter_single_instance/flutter_single_instance.dart';
import 'package:window_manager/window_manager.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:provider/provider.dart';
import 'package:hive_ce/hive.dart';
import 'package:otzaria/app.dart';
import 'package:otzaria/bookmarks/bloc/bookmark_bloc.dart';
import 'package:otzaria/bookmarks/repository/bookmark_repository.dart';
import 'package:otzaria/find_ref/bloc/find_ref_bloc.dart';
import 'package:otzaria/find_ref/repository/find_ref_factory.dart';
import 'package:otzaria/core/focus_repository.dart';
import 'package:otzaria/history/bloc/history_bloc.dart';
import 'package:otzaria/history/history_repository.dart';
import 'package:otzaria/indexing/bloc/indexing_bloc.dart';
import 'package:otzaria/indexing/services/release_index_builder_cli.dart';
import 'package:otzaria/library/bloc/library_bloc.dart';
import 'package:otzaria/settings/services/custom_folders/bloc/custom_folders_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_event.dart';
import 'package:otzaria/navigation/bloc/navigation_state.dart';
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
import 'package:otzaria/data/data_providers/cache_database_holder.dart';
import 'package:otzaria/data/data_providers/hive_data_provider.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_bloc.dart';
import 'package:otzaria/data/constants/database_constants.dart';
import 'package:otzaria/empty_library/bloc/empty_library_bloc.dart';
import 'package:otzaria/library_update/bloc/library_update_bloc.dart';
import 'package:otzaria/library_update/repository/library_update_repository.dart';
import 'package:otzaria/library_update/services/companion_assets_service.dart';
import 'package:otzaria/library_update/services/startup_recovery_check.dart';
import 'package:seforim_library_updater/seforim_library_updater.dart';
import 'package:zstandard/zstandard.dart';
import 'package:otzaria/work_status/work_status_cubit.dart';
import 'package:otzaria/plugins/bloc/plugin_system_bloc.dart';
import 'package:otzaria/plugins/bloc/plugin_system_event.dart';
import 'package:otzaria/plugins/bloc/plugin_updates_cubit.dart';
import 'package:otzaria/plugins/repository/plugin_registry_repository.dart';
import 'package:otzaria/plugins/declarative/services/declarative_library_book_access.dart';
import 'package:otzaria/plugins/services/plugin_reader_actions.dart';
import 'package:otzaria/plugins/declarative/services/declarative_plugin_host_service.dart';
import 'package:otzaria/utils/navigation/book_open_coordinator.dart';

import 'package:otzaria_search_engine/otzaria_search_engine.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/core/data_root_writability_warning.dart';
import 'package:otzaria/core/cli_command.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/core/error_log_file.dart';
import 'package:otzaria/core/messages/window_messages.dart';
import 'package:otzaria/core/update_check_frequency.dart';
import 'package:otzaria/core/info/app_info_cli.dart';
import 'package:otzaria/core/info/app_install_timeline.dart';
import 'package:otzaria/core/external_activation_queue.dart';
import 'package:otzaria/core/portable_paths.dart';
import 'package:otzaria/core/startup_timeline.dart';
import 'package:otzaria/core/window_listener.dart';
import 'package:otzaria/core/window_persistence.dart';
import 'package:otzaria/core/windowing/app_window_scope.dart';
import 'package:otzaria/core/windowing/multi_window_service.dart';
import 'package:otzaria/core/windowing/window_bus_host.dart';
import 'package:otzaria/core/windowing/window_bus.dart';
import 'package:otzaria/core/windowing/window_role.dart';
import 'package:otzaria/core/windowing/window_manager_app_window_controller.dart';
import 'package:otzaria/tools/shamor_zachor/providers/shamor_zachor_data_provider.dart';
import 'package:otzaria/tools/shamor_zachor/providers/shamor_zachor_progress_provider.dart';
import 'package:otzaria/settings/services/backup_service.dart';
import 'package:otzaria/core/http_client_registry.dart';
import 'package:otzaria/plugins/services/plugin_report_service.dart';
import 'package:otzaria/services/direct_error_report_service.dart';
import 'package:otzaria/data/cache/books_cache.dart';
import 'package:otzaria/data/cache/acronyms_cache.dart';
import 'package:otzaria/data/cache/generation_cache.dart';
import 'package:otzaria/find_ref/repository/reference_books_cache.dart';
import 'package:otzaria/tools/dictionary/repository/dictionary_lookup_repository.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:otzaria/tools/calendar/services/notification_service.dart';
import 'package:otzaria/plugins/database/plugin_database_bootstrap.dart';
import 'package:logging/logging.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:otzaria/theme/app_fonts.dart';
import 'package:otzaria/widgets/misc/app_cursors.dart';
import 'package:otzaria/widgets/misc/restart_widget.dart';
import 'package:otzaria/core/splash_screen.dart';
import 'package:otzaria/plugins/services/plugin_crash_guard.dart';
import 'package:otzaria/plugins/services/plugin_background_policy.dart';
import 'package:otzaria/plugins/services/plugin_install_report_service.dart';
import 'package:otzaria/plugins/services/plugin_packager_cli.dart';
import 'package:otzaria/plugins/services/plugin_store_link_parser.dart';
import 'package:otzaria/plugins/services/plugin_protocol_registration_service.dart';
import 'package:otzaria/plugins/utils/plugin_dev_tools_mode.dart';
import 'package:otzaria/plugins/view/webview_environment_holder.dart';
import 'package:otzaria/core/sentry_event_filter.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

// Updated automatically by version update scripts - do not edit manually
const int _latestReleasedBuildNumber = 99701;

/// החלון של ה-isolate הזה. מקור אמת אחד לכל מי שצריך אותו כאן: ה-listener,
/// [WindowPersistence] ו-[AppWindowScope] מקבלים את אותו מופע.
///
/// `windowManager` הוא סינגלטון פר-isolate ולכן הבקר פונה תמיד לחלון של
/// ה-isolate שבו הוא רץ — גם בחלון משני.
const _appWindow = WindowManagerAppWindowController();

AppWindowListener? _appWindowListener;
const ExternalActivationQueue _externalActivationQueue =
    ExternalActivationQueue();

// מושלם כשהחלון הראשי נחשף ([presentMainWindow]). חימומי המטמון ממתינים לו
// כדי שלא יתחרו בטעינת תוכן הספר הפעיל על ה-main isolate ועל seforim.db.
final _mainWindowRevealedCompleter = Completer<void>();

void _markMainWindowRevealed() {
  if (!_mainWindowRevealedCompleter.isCompleted) {
    _mainWindowRevealedCompleter.complete();
  }
  if (!WindowRole.isSecondary) StartupTimeline.instance.finishAtReveal();
}

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

const String _kLastSeenVersion = 'last_seen_app_version';

void _clearErrorLogOnVersionChange() {
  final currentVersion = ErrorLogFile.appVersion;
  final lastSeen = Settings.getValue<String>(_kLastSeenVersion);
  if (lastSeen != null && lastSeen != currentVersion) {
    try {
      final logFile = ErrorLogFile.resolveFile();
      if (logFile.existsSync()) {
        logFile.deleteSync();
      }
    } catch (error) {
      // ניקוי לא-קריטי: הלוג הישן יישאר, אבל שלא בשקט מוחלט.
      if (kDebugMode) {
        debugPrint('Failed to clear old error log: $error');
      }
    }
  }
  Settings.setValue(_kLastSeenVersion, currentVersion);
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
void main(List<String> args) async {
  // debugPrint פזור במאות נקודות קריאה בלי עטיפת kDebugMode; ב-release הפלט
  // עדיין מפורמט ונשלח ל-stdout שאיש לא רואה — מנוטרל כאן במרוכז לכל התוכנה.
  if (kReleaseMode) {
    debugPrint = (String? message, {int? wrapWidth}) {};
  }

  // טיפול בפקודות CLI שאינן דורשות אתחול GUI (כגון אריזת תוסף).
  // חייב לרוץ לפני SentryWidgetsFlutterBinding.ensureInitialized() כדי שלא
  // ייפתח חלון Flutter ולא יתבצע אתחול מסד נתונים מיותר.
  if (await _maybeRunCliCommand(args)) {
    return;
  }
  StartupTimeline.instance.start();

  PluginDevToolsMode.initFromArgs(args);

  SentryWidgetsFlutterBinding.ensureInitialized();

  // אישור קבלה מוקדם לאתר החנות עבור קישורי התקנת תוסף שהגיעו כארגומנטים —
  // נורה כאן, לפני כל אתחול כבד ולפני עליית החלון, כדי שדף החנות יידע תוך
  // שנייה-שתיים שאוצריא קיבלה את הבקשה (גם בעלייה קרה). במופע משני (כשאוצריא
  // כבר רצה) ההמתנה לסיום נעשית לפני exit ב-_runAppBootstrap.
  _sendEarlyInstallAcks(args);

  // מנטרל את ההבהוב המובנה (הפרטי ב-EditableTextState) כדי ש-RtlTextField
  // ינהל אותו בעצמו. ראו "ניהול הבהוב הסמן" ב-rtl_text_field.dart.
  EditableText.debugDeterministicCursor = true;

  unawaited(AppCursors.ensureInitialized());

  await StartupTimeline.instance.phase('earlyInit', () async {
    await _initializeDataRootForEarlyLogging();
    await _initializeLogMetadata();
    hierarchicalLoggingEnabled = true;
    await _enqueueExternalActivationArgs(args);
  });

  _installGlobalErrorHandlers();

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

/// מתקין את מטפלי השגיאות הגלובליים של ה-isolate.
///
/// ⚠️ נקרא משתי נקודות הכניסה. בלי הקריאה מ-`secondaryWindowMain` כל חריגה
/// בחלון משני הייתה שקטה לחלוטין ב-release, שבו `debugPrint` הוא no-op.
void _installGlobalErrorHandlers() {
  // Set up custom error handlers before Sentry initialization
  // Sentry will automatically wrap these handlers
  FlutterError.onError = (FlutterErrorDetails details) {
    final errorString = details.exceptionAsString();

    // Flutter's desktop accessibility bridge can report stale AXTree nodes.
    if ((Platform.isWindows || Platform.isMacOS || Platform.isLinux) &&
        isFlutterAccessibilityNoise(errorString)) {
      return; // Silently ignore these errors
    }

    // Skip HardwareKeyboard assertion error - happens when window loses focus while
    // a key is held down; onWindowFocus releases stuck keys but filter as fallback
    if (_isIgnorableHardwareKeyboardAssertion(errorString)) {
      return; // Silently ignore - stuck keys are released on window focus
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

    // Flutter's desktop accessibility bridge can report stale AXTree nodes.
    if ((Platform.isWindows || Platform.isMacOS || Platform.isLinux) &&
        isFlutterAccessibilityNoise(errorString)) {
      return true; // Silently ignore these errors
    }

    // Skip HardwareKeyboard assertion error - stuck keys are released on window focus
    if (_isIgnorableHardwareKeyboardAssertion(errorString)) {
      return true; // Silently ignore
    }

    // Log all other errors normally
    if (kDebugMode) {
      FlutterError.dumpErrorToConsole(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
        ),
      );
    } else {
      _appendUnhandledErrorToLocalLog(
        title: 'Unhandled Error',
        error: error,
        stackTrace: stack,
      );
    }
    return true;
  };
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
        // Sentry משמש לדיווח שגיאות בלבד; עסקאות ביצועים אינן נשלחות.
        options.tracesSampleRate = 0.0;

        options.beforeSend = (event, hint) {
          return shouldReportSentryEvent(
                event: event,
                currentBuild: currentBuild,
                latestReleasedBuildNumber: _latestReleasedBuildNumber,
              )
              ? event
              : null;
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
    // שם התהליך משמש רק לשם קובץ ה-pid. בלעדיו החבילה מריצה tasklist/ps
    // באופן חוסם לפני runApp — במחשב שסוכן סינון מאט בו יצירת תהליכים זה
    // עיכב את העלייה בעשרות שניות (issue #989). חייב לגזור אותו כמו החבילה
    // (שם ה-EXE בלי סיומת), אחרת מופע ישן וחדש לא יזהו זה את זה.
    FlutterSingleInstance.processName ??= Platform.resolvedExecutable
        .split(Platform.pathSeparator)
        .last
        .replaceAll(RegExp(r'\.exe$', caseSensitive: false), '');
    FlutterSingleInstance flutterSingleInstance = FlutterSingleInstance();
    bool isFirstInstance = await StartupTimeline.instance.phase(
      'singleInstance',
      flutterSingleInstance.isFirstInstance,
    );
    if (!isFirstInstance) {
      // אם נשלח ack מוקדם לאתר החנות — ממתינים לסיומו לפני היציאה, אחרת
      // התהליך מת לפני שהבקשה יוצאת (לשירות יש timeout פנימי של 10 שניות).
      final ackFuture = _earlyInstallAckFuture;
      if (ackFuture != null) {
        try {
          await ackFuture;
        } catch (_) {}
      }
      exit(0);
    }
  }

  Bloc.observer = AppBlocObserver();

  if (kDebugMode) {
    Logger.root.level = Level.ALL;
    Logger('fwfh').level = Level.INFO;
    Logger.root.onRecord.listen((record) {
      debugPrint(
        '${record.level.name}: ${record.loggerName}: ${record.message}',
      );
    });
  }

  // הגדרת window_manager לפני runApp.
  if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
    // נשאר על ה-singleton: אתחול ה-backend קודם לקיומו של כל חלון.
    await StartupTimeline.instance.phase(
      'windowManager',
      windowManager.ensureInitialized,
    );
    WindowPersistence.splashMode = true;
    // WindowPersistence היא static ואין לה BuildContext — היא מקבלת את
    // אותו מופע שנכנס ל-AppWindowScope, כדי שיהיה מקור אמת אחד.
    WindowPersistence.bindWindow(
      controller: _appWindow,
      geometry: _appWindow,
    );

    await StartupTimeline.instance.phase(
      'windowCloseHandling',
      _installWindowCloseHandling,
    );

    // ה-splash נייטיבי ב-runner והחלון הראשי נשאר מוסתר עד presentMainWindow,
    // שם הוא נחשף ישר בגבולותיו הסופיים — לכן אין כאן waitUntilReadyToShow.
  }

  _claimWindowBusSlot();

  // ה-scope עוטף את כל העץ כדי שכל widget יוכל להגיע לחלון שהוא יושב בו
  // בלי לפנות ל-singleton גלובלי. היום יש חלון אחד, ולכן הבקר הוא של
  // החלון הראשי; ריבוי חלונות יזריק כאן בקר אחר לכל עץ.
  _maybeScheduleDebugSecondWindow();

  runApp(
    AppWindowScope(
      controller: _appWindow,
      geometry: _appWindow,
      child: SentryWidget(
        child: RestartWidget(
          child: const AppBootstrap(),
        ),
      ),
    ),
  );
}

/// ערוץ לסגירת חלון ה-splash הנייטיב (ראה windows/linux/macos runner). נתמך בכל
/// פלטפורמות הדסקטופ.
const MethodChannel _splashChannel = MethodChannel('otzaria/splash');

Future<void> _closeNativeSplash() async {
  if (kIsWeb || !(Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
    return;
  }
  try {
    await _splashChannel.invokeMethod<void>('close');
  } catch (_) {
    // לא קריטי — חלון ה-splash ייהרס ממילא עם התהליך.
  }
}

/// חשיפת החלון הראשי: מציג את החלון המוסתר (שכבר בגבולותיו הסופיים, עם
/// התוכן שצויר), ממקסם אם נדרש, וסוגר את ה-splash הנייטיב באותו רגע — כך החלון
/// מופיע בבת אחת עם תוכן והסמל הצף מתפוגג, ללא קפיצה וללא פער. נקרא אחרי שהתוכן
/// נחשף ונצבע.
Future<void> presentMainWindow() async {
  if (kIsWeb || !(Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
    _markMainWindowRevealed();
    return;
  }
  try {
    // show/maximize זורקים את ה-swapchain (חלון שקוף עד פריים חדש) — תחת cloak
    // זה בלתי-נראה; החשיפה היא ביטול ה-cloak הנייטיבי ב-flutter_window.cpp.
    if (!kIsWeb && Platform.isWindows && !await _appWindow.isVisible()) {
      try {
        await _splashChannel.invokeMethod<void>('cloak');
      } catch (_) {
        // לא קריטי — בלי cloak נשארת ההתנהגות הקודמת (חשיפה לא-אטומית).
      }
    }
    // ⚠️ **החשיפה של חלון משני שייכת לנייטיב בלבד.**
    //
    // `RevealOnFirstFrame` כבר הציג אותו והביא אותו לחזית ברגע הפריים
    // הראשון — כלומר שניות לפני שהאתחול כאן מסתיים. חזרה על
    // `show`/`focus`/`raiseSelf` בנקודה הזו חוטפת את הפוקוס מהמשתמש
    // שבינתיים כבר חזר לעבוד בחלון הראשי, וזו הייתה מחצית "מריבת
    // הפוקוסים" בין החלונות. המחצית השנייה הייתה ב-`SetChildContent`.
    if (!WindowRole.isSecondary) {
      await _appWindow.show();
      await _appWindow.focus();
    }
    if (WindowRole.isSecondary) {
      final startup = _secondaryWindowStartup;
      if (startup != null && startup.isRunning) {
        startup.stop();
        // נמדד ולא משוער: כל צעד שמדולג בחלון משני צריך להיראות כאן.
        debugPrint(
          '[window] חלון משני עלה תוך ${startup.elapsedMilliseconds}ms',
        );
      }
    }
    // maximize חייב לקרות *אחרי* show (show מבצע restore לגודל הקודם).
    await WindowPersistence.applyPendingMaximize();
    // חייב אחרי show (setFullScreen על חלון מוסתר מאבד WS_VISIBLE) ואחרי
    // maximize (כדי שיציאה ממסך מלא תחזיר את החלון למצבו הממוקסם).
    await WindowPersistence.applyPendingFullscreen();
    // מכאן והלאה מותר לשמור את גודל החלון.
    WindowPersistence.splashMode = false;
  } catch (error, stackTrace) {
    _logNonFatalInitializationError('Present main window', error, stackTrace);
  } finally {
    // הסגירה מבצעת בצד הנייטיבי את ה-uncloak; חייבת לרוץ גם אם שלב הצגה
    // נכשל — אחרת החלון נשאר cloaked (בלתי-נראה) לתמיד.
    await _closeNativeSplash();
    // משחרר את חימומי המטמון הדחויים גם אם אחת מפעולות החלון נכשלה.
    _markMainWindowRevealed();
  }
}

/// אתחול כבד שרץ בזמן שה-splash מוצג.
Future<void> _initializeProcessSingletons() async {
  // שרשרת ההגדרות/חלון חייבת להישאר סדרתית: WindowPersistence קורא את גבולות
  // החלון השמורים מ-Settings.
  Future<void> initSettingsAndWindow() async {
    try {
      await Settings.init(cacheProvider: HiveCache());
    } catch (error, stackTrace) {
      // ה-fallback משנה את מקור ההגדרות; קוד אחר (גיבוי, טיוטות) ניגש
      // ישירות ל-Hive box ויקבל ריק — חובה שהכשל יהיה גלוי בלוג.
      _logNonFatalInitializationError(
        'Settings.init with HiveCache',
        error,
        stackTrace,
      );
      await Settings.init(cacheProvider: SharePreferenceCache());
    }

    // ⚠️ פר-תהליך, לא פר-חלון. ניקוי יומן השגיאות בשינוי גרסה ורישום
    // ההפעלה מתארים את **התהליך**; חלון נוסף שרושם "הפעלה" מזייף את
    // הנתונים, וניקוי היומן פעם שנייה עלול למחוק שגיאות שנרשמו בינתיים.
    if (!WindowRole.isSecondary) {
      _clearErrorLogOnVersionChange();
      await AppInstallTimelineStore.recordLaunch(ErrorLogFile.appVersion);
    }

    if (!kIsWeb &&
        (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      // ⚠️ חלון משני אינו משחזר גבולות שמורים.
      //
      // הגבולות השמורים הם של החלון הראשי, ובדרך כלל ממוקסמים — ולכן כל
      // חלון נוסף נפתח על מסך מלא ובאותו מקום בדיוק, ומכסה את הקודם.
      // ה-runner כבר יצר אותו בגודל ובהיסט סבירים, וזה מה שצריך להישאר.
      if (!WindowRole.isSecondary) {
        await WindowPersistence.restoreIfAny();
      }
      // מחילים את הגבולות הסופיים כאן — מוקדם, בזמן שה-splash הנייטיב מוצג
      // והחלון הראשי עדיין מוסתר — ולא ברגע החשיפה. החלון נוצר ב-(10,10) על
      // המסך הראשי; אם הגבולות השמורים נמצאים על מסך עם DPI שונה, ה-setBounds
      // משגר WM_DPICHANGED. בכך שמחילים אותו כאן (ולא frame אחד לפני show),
      // המנוע מספיק לעבד את שינוי ה-DPI ולצייר מחדש ב-devicePixelRatio הנכון
      // הרבה לפני שהחלון נחשף — מונע מצב שבו כל הממשק מופיע "מוגדל" כי הוצג
      // לפני שה-DPR התעדכן.
      if (!WindowRole.isSecondary) {
        await WindowPersistence.applyRestoredBounds();
      }
      // גם מסגרת החלון מוגדרת כאן — מוקדם, בעוד החלון מוסתר — ולא ברגע
      // החשיפה: הסתרת ה-title bar (החלון נוצר ב-runner עם WS_OVERLAPPEDWINDOW)
      // משנה את גודל אזור-הלקוח, מה שמאתחל את ה-swapchain של המנוע וזורק את
      // כל התוכן שכבר צויר. כשזה רץ ברגע החשיפה, show() הציג חלון ריק לשבריר
      // שנייה עד שפריים חדש הספיק להתרסטר. כאן השינוי קורה לפני שפריים התוכן
      // הראשון מצויר בכלל — והוא נצבע ישר במסגרת ובגודל הסופיים.
      await _appWindow.setMinimumSize(WindowPersistence.minSize);
      // windowButtonVisibility ברירת מחדל true — חובה false מפורש כדי להסתיר
      // את כפתורי המערכת של macOS (traffic lights) שאחרת יופיעו כפול לצד
      // הכפתורים המותאמים.
      await _appWindow.setTitleBarStyle(
        TitleBarStyle.hidden,
        windowButtonVisibility: false,
      );
    }
  }

  // RustLib (טעינת FFI) ו-loadCerts (קריאת asset קטן) אינם תלויים בהגדרות
  // ולא זה בזה — רצים במקביל לשרשרת ההגדרות/חלון במקום בזה אחר זה.
  await _timedPhase('rustlib+certs+settings', () async {
    await Future.wait([
      RustLib.init(),
      loadCerts(),
      initSettingsAndWindow(),
    ]);
  });

  await _timedPhase('initHive', initHive);
  // מצב נייד: אם תיקיית הנתונים זזה (אות כונן אחרת / מיקום אחר), הנתיבים
  // האבסולוטיים השמורים משוכתבים לפני שכל קוד אחר צורך אותם. חייב לרוץ
  // אחרי Settings.init ואחרי initHive (ה-boxes פתוחים), ולפני
  // SqliteDataProvider ו-FileSystemData שקוראים את נתיב הספרייה.
  // ⚠️ פר-תהליך. המיגרציה משכתבת נתיבים אבסולוטיים בהגדרות המשותפות;
  // החלון הראשון כבר ביצע אותה, וחלון משני שיריץ אותה שוב יעבוד על
  // ה-Hive הפרטי שלו ולא על המשותף — כלומר בזבוז במקרה הטוב.
  if (!WindowRole.isSecondary) {
    await _timedPhase('portablePaths', PortablePaths.migrateIfMoved);
    // נתיב הספרייה נרשם לקובץ טקסט שה-uninstaller קורא; ההגדרות עצמן
    // ב-Hive בינארי שאינו נגיש לו (issue #1020). פר-תהליך — קובץ אחד.
    unawaited(AppPaths.recordLibraryPathForUninstaller());
  }

  // שירות ההתראות (לוח השנה) ושירות דיווחי השגיאות אינם חיוניים להצגת
  // המסך הראשי. tz.initializeTimeZones + plugin init של flutter_local_notifications
  // יכולים לקחת מאות מילי-שניות ב-Windows, ודיווחי השגיאות הם רק Timer.periodic.
  // ⚠️ פר-תהליך, לא פר-חלון. שירות ההתראות רושם התראות מערכת, ושטיפת
  // דיווחי השגיאות שולחת את אותו תור — חלון משני שמריץ אותם שוב מייצר
  // התראות כפולות ודיווחים כפולים.
  if (!WindowRole.isSecondary) {
    unawaited(_runDeferredNotificationService());
    unawaited(_runDeferredErrorReportFlush());
  } else {
    // ⚠️ אבל מסד אזורי הזמן **כן** נדרש, והוא פר-isolate.
    //
    // חסימת השירות כולו הפילה את לוח השנה בחלון משני עם "Tried to get
    // location before initializing timezone database". מה שפר-תהליך הוא
    // רישום ההתראות, לא בסיס הנתונים שמאחוריו.
    unawaited(_initializeTimeZonesOnly());
  }
}

/// משחזר עדכון ספרייה שנקטע (marker+backup) לפני פתיחת ה-DB.
Future<void> _recoverInterruptedLibraryUpdate() {
  return StartupRecoveryCheck(
    readPref: Settings.getValue<String>,
    writePref: (key, value) => Settings.setValue(key, value),
    logError: (title, message) => _appendUnhandledErrorToLocalLog(
      title: title,
      error: message,
      details: const {'Phase': 'initialize', 'Component': 'Library recovery'},
    ),
  ).run(DatabaseConstants.getDatabasePath());
}

/// seforim.db שהוזז לגיבוי זמני בעדכון ספרייה שנהרג באמצע חוזר לספרייה —
/// אחרת היא נראית ריקה והמשתמש מוריד הכול מחדש, על גבי הגיבוי שנשאר.
Future<void> _recoverOrphanedDbBackup() async {
  final libraryPath = Settings.getValue<String>(
    SettingsRepository.keyLibraryPath,
  );
  if (libraryPath == null || libraryPath.isEmpty) return;
  try {
    await EmptyLibraryBloc.recoverOrphanedDbBackup(
      DatabaseConstants.getDatabaseDirectoryPath(),
    );
  } catch (error, stackTrace) {
    _logNonFatalInitializationError(
      'Orphaned DB backup recovery',
      error,
      stackTrace,
    );
  }
}

Future<void> _initializeRestartableRuntime() async {
  // שני השחזורים חייבים לרוץ לפני פתיחת ה-DB ולפני בדיקת "ספרייה ריקה".
  // שחזור עדכון ספרייה שנקטע (marker+backup) קודם: הוא כותב DB משלו, ולהחזיר
  // לפניו גיבוי יתום פירושו העתקת ~5.5GB שתידרס מיד.
  //
  // ⚠️ פר-תהליך, **שניהם**. הם נוגעים בקובצי הספרייה המשותפים, ושני
  // חלונות שמריצים אותם במקביל היו מתנגשים על אותם קבצים — כולל אותה
  // העתקה של ~5.5GB פעמיים. החלון הראשון כבר ביצע אותם לפני שהחלון הזה
  // בכלל נוצר.
  if (!WindowRole.isSecondary) {
    await _timedPhase(
      'recoverInterruptedUpdate',
      _recoverInterruptedLibraryUpdate,
    );
    await _timedPhase('recoverOrphanedBackup', _recoverOrphanedDbBackup);
  }

  // initHive נקרא כבר ב-_initializeProcessSingletons. הקריאה הכפולה כאן
  // הייתה no-op (Hive.openBox מחזיר box קיים), אבל בכל זאת חוסכת קצת זמן
  // בקריאה הראשונה. ב-restart אין צורך לפתוח שוב — boxes לא נסגרים.
  await _timedPhase('sqlite', SqliteDataProvider.instance.initialize);

  // הגדרת cache של pdfrx — לא חיונית להצגת המסך הראשי. PDF הראשון יקבל
  // cache ברירת מחדל אם זה עוד לא הוגדר.
  unawaited(_runDeferredPdfrxCacheInit());

  // initPluginDatabaseSources היא רישום סינכרוני קצר (in-memory only) של
  // המקורות שהאפליקציה מציעה לתוספים. חייב לרוץ לפני שתוסף יקרא ל-
  // database.listSources — אחרת תוסף שנפתח מוקדם יראה את כל המקורות
  // כלא-זמינים (regression: ראה PluginDatabaseService._registry.getSource).
  await _timedPhase('pluginDbSources', initPluginDatabaseSources);

  // PluginCrashGuard.ensureInitialized חייב להסתיים לפני שטעינת תוסף מתחילה.
  // PluginTabPage.markLoadAttemptSync דורש state אתחל (אחרת ה-canary לא נשמר
  // והתוסף לא ייכנס ל-quarantine אם יקרוס), ו-PluginCrashGuard.isBlocked
  // מחזיר false כל עוד _blocked הוא null. הקריאה זולה (קריאת JSON קטן).
  await _timedPhase(
    'pluginCrashGuard',
    () => PluginCrashGuard.ensureInitialized().catchError((
      Object error,
      StackTrace stackTrace,
    ) {
      _logNonFatalInitializationError(
        'Plugin crash guard initialization',
        error,
        stackTrace,
      );
    }),
  );

  // גיבוי אוטומטי ורישום פרוטוקול אינם נחוצים להצגת ה-UI הראשי (טאבים,
  // ספרים, ניווט). הם מועברים ל-unawaited כדי שלא יעכבו את ה-bootstrap —
  // אחרת ב-Windows רישום הפרוטוקול לבדו מריץ 10 תת-תהליכי reg.exe סדרתית,
  // מה שמוסיף כמה שניות עד שהטאבים השמורים נטענים. ראה
  // _runDeferredAutoBackup ו-_runDeferredProtocolRegistration למטה.
  unawaited(_runDeferredAutoBackup());
  unawaited(_runDeferredProtocolRegistration());
  unawaited(_logJobObjectContainmentFailure());
  unawaited(_runDeferredDataRootWritabilityWarning());

  // מסלול התאימות הישן זקוק ל-WebView מיד; החימום רץ ברקע ואינו מעכב bootstrap.
  unawaited(_preWarmWebViewEnvironment());
}

/// כשקונטיינמנט ה-Job Object לא הוקם, תהליכי msedgewebview2.exe שורדים את
/// סגירת התוכנה ונועלים את פרופיל ה-WebView2 (תוספים ריקים) — נרשם ל-errors.txt.
Future<void> _logJobObjectContainmentFailure() async {
  // פר-תהליך: ה-Job Object אחד לתהליך, ורישום מכל חלון משכפל את אותה שורה.
  if (kIsWeb || !Platform.isWindows || kDebugMode || WindowRole.isSecondary) {
    return;
  }
  try {
    final status = await AppWindowListener.jobObjectStatus();
    if (status.ready) return;
    _appendUnhandledErrorToLocalLog(
      title: 'Job Object containment unavailable',
      error: status.failure ?? 'unknown failure',
      details: const {
        'Phase': 'initialize',
        'Component': 'Job Object (WebView2 process containment)',
      },
    );
  } catch (error, stackTrace) {
    _logNonFatalInitializationError('Job Object status', error, stackTrace);
  }
}

/// מאתחל את מסד אזורי הזמן בלבד, בלי לרשום התראות מערכת.
///
/// חלון משני צריך את `tz.local` (לוח השנה, זמני היום) אבל אסור לו לרשום
/// התראות — הן היו נשלחות פעמיים.
Future<void> _initializeTimeZonesOnly() async {
  try {
    // מקור אחד עם [NotificationService.init] — כולל אזור הזמן.
    NotificationService.initializeTimeZones();
  } catch (error, stackTrace) {
    _logNonFatalInitializationError('Timezone database', error, stackTrace);
  }
}

Future<void> _runDeferredNotificationService() async {
  try {
    await NotificationService().init();
  } catch (error, stackTrace) {
    _logNonFatalInitializationError('Notification service', error, stackTrace);
  }
}

Future<void> _runDeferredErrorReportFlush() async {
  try {
    // המופע הארוך-טווח: רץ עם Timer.periodic של 5 דקות, מחזיק http.Client
    // עם connection pool שעלול לתקוע את היציאה ב-Windows admin install.
    // רק המופע הזה נרשם ב-HttpClientRegistry; מופעים קצרי-טווח אחרים שנוצרים
    // לפי דרישה (בדיאלוגים/הגדרות) אינם נרשמים כדי למנוע memory leak.
    final reportService = DirectErrorReportService();
    HttpClientRegistry.register(reportService.closeHttpClient);
    await reportService.startAutomaticFlush();
    // תור דיווחי התוספים משתמש ב-client סטטי שכבר רשום ב-HttpClientRegistry.
    await PluginReportService().startAutomaticFlush();
  } catch (error, stackTrace) {
    _logNonFatalInitializationError(
      'Direct error report queue',
      error,
      stackTrace,
    );
  }
}

Future<void> _runDeferredPdfrxCacheInit() async {
  try {
    final cacheDir = await getTemporaryDirectory();
    Pdfrx.cacheDirectoryPath = cacheDir.path;
    debugPrint('Pdfrx cache directory set to: ${cacheDir.path}');
  } catch (error, stackTrace) {
    _logNonFatalInitializationError('Pdfrx cache directory', error, stackTrace);
  }
}

Future<void> _runDeferredAutoBackup() async {
  // ⚠️ פר-תהליך. הגיבוי קורא `Hive.box` ישירות — בחלון משני זהו שורש פרטי
  // בלי תורי הדיווחים — ומשדר `key-last-auto-backup` שדורס את מועד הבעלים.
  if (WindowRole.isSecondary) return;
  try {
    if (await BackupService.shouldPerformAutoBackup()) {
      await BackupService.performAutoBackup();
    }
  } catch (error, stackTrace) {
    _logNonFatalInitializationError('Automatic backup', error, stackTrace);
  }
}

/// אזהרה על שורש נתונים חסום-לכתיבה. ממתינה לחשיפת החלון — דיאלוג לפניה
/// אינו מוצג כי עדיין אין Navigator.
Future<void> _runDeferredDataRootWritabilityWarning() async {
  try {
    await _mainWindowRevealedCompleter.future.timeout(
      const Duration(seconds: 15),
    );
  } on TimeoutException {
    // ממשיכים בכל זאת — אם ה-Navigator עדיין חסר, ההצגה תדולג בשקט.
  }
  await DataRootWritabilityWarning.showIfNeeded();
}

Future<void> _runDeferredProtocolRegistration() async {
  // פר-תהליך: רישום ברג'יסטרי של המכונה, עשרה תת-תהליכי `reg.exe` בכל חלון.
  if (WindowRole.isSecondary) return;
  try {
    await PluginProtocolRegistrationService().ensureRegistered();
  } catch (error, stackTrace) {
    _logNonFatalInitializationError(
      'Plugin protocol registration',
      error,
      stackTrace,
    );
  }
}

/// חימומי מטמון שאינם חיוניים להצגת המסך הראשי (איתור מקורות, מילון, גופני
/// מערכת, היברובוקס מקומי). ממתינים לחשיפת החלון ([presentMainWindow]) לפני
/// שמתחילים — אחרת השאילתות הכבדות על seforim.db והעיבוד על ה-main isolate
/// (BooksCache/AcronymsCache סורקים עשרות אלפי שורות) מתחרים בטעינת תוכן
/// הספר הפעיל ומעכבים את הופעתו. ה-timeout הוא רשת ביטחון בלבד: בזרימה רגילה
/// החשיפה קורית תוך שניות (כולל failsafe של 8 שניות ב-MainWindowScreen).
Future<void> _runDeferredCacheWarmups() async {
  try {
    await _mainWindowRevealedCompleter.future.timeout(
      const Duration(seconds: 15),
    );
  } on TimeoutException {
    // ממשיכים בכל זאת — עדיף חימום מאוחר מאשר אף פעם.
  }
  // ⚠️ חלון משני מדלג: לכל השאר יש חימום לפי דרישה באתרי הקריאה, והרצתו
  // כאן שכפלה `VACUUM` על `cache.db` המשותף ושני isolates לכל חלון נוסף.
  // הגופנים נשארים, כי הנפילה שלהם היא סריקה סינכרונית על ה-thread הראשי.
  if (WindowRole.isSecondary) {
    unawaited(
      AppFonts.warmUpSystemFontsCache().catchError((e) {
        if (kDebugMode) debugPrint('Failed to warm up system fonts: $e');
      }),
    );
    return;
  }
  // כיווץ cache.db — ה-prune-ים של מטמוני ה-docx/PDF משחררים דפים במהלך
  // הסשן אך לא מקטינים את הקובץ. רץ *לפני* החימומים ולא במקביל להם, כי
  // ה-warmUp של ReferenceBooksCache מנקה את מטמון ה-PDF מול אותו קובץ —
  // וכתיבה שנתקלת ב-VACUUM נחסמת סינכרונית עד ל-busy_timeout.
  await CacheDatabaseHolder.instance.compactIfFragmented().catchError((
    Object e,
  ) {
    if (kDebugMode) debugPrint('Failed to compact cache.db: $e');
    return false;
  });
  unawaited(
    DictionaryLookupRepository.instance.ensureLoaded().catchError((e) {
      if (kDebugMode) debugPrint('Failed to warm up dictionary: $e');
    }),
  );
  unawaited(
    BooksCache.instance.warmUp().catchError((e) {
      if (kDebugMode) debugPrint('Failed to warm up BooksCache: $e');
    }),
  );
  unawaited(
    AcronymsCache.instance.warmUp().catchError((e) {
      if (kDebugMode) debugPrint('Failed to warm up AcronymsCache: $e');
    }),
  );
  unawaited(
    GenerationCache.instance.warmUp().catchError((e) {
      if (kDebugMode) debugPrint('Failed to warm up GenerationCache: $e');
    }),
  );
  unawaited(
    AppFonts.warmUpSystemFontsCache().catchError((e) {
      if (kDebugMode) debugPrint('Failed to warm up system fonts: $e');
    }),
  );
  unawaited(
    ReferenceBooksCache.instance.warmUp().catchError((e) {
      if (kDebugMode) {
        debugPrint('Failed to warm up ReferenceBooksCache: $e');
      }
    }),
  );
  // פרי-וורם של ספרי היברובוקס המקומיים (אם הוגדרה תיקייה): סריקת
  // התיקייה וטעינת המטא-דאטה מהקטלוג מבוצעות ברקע כדי שהחיפוש הראשון
  // לא ישלם עבורן. כשאין תיקייה — הקריאה מתקצרת מיד ללא עלות.
  unawaited(() async {
    try {
      await DataRepository.instance.localHebrewBooks;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Failed to warm up local HebrewBooks: $e');
      }
    }
  }());
}

Future<void> _preWarmWebViewEnvironment() async {
  // ⚠️ החימום נוגע בתיקיית ה-user-data המשותפת. חלון משני שפותח תוסף
  // מאתחל את הסביבה בעצמו (`PluginTabPage` / `PluginBackgroundHost`).
  if (kIsWeb || !Platform.isWindows || WindowRole.isSecondary) return;
  try {
    // תוסף דקלרטיבי נשאר עצל גם אם אושרה לו הפעלה ברקע.
    final installed = await PluginRegistryRepository().getAllPlugins();
    final hasStartupRunner = installed.any(usesLegacyStartupRunner);
    if (!hasStartupRunner) {
      if (kDebugMode) {
        debugPrint('WebView2 pre-warm skipped: no startup plugins');
      }
      return;
    }
    // אם WebView2 Runtime אינו מותקן, אתחול הסביבה ייכשל ממילא. מדלגים כדי
    // לא לזרוק חריגה מיותרת ולא להצמיח תהליכי Edge חלקיים.
    if (!await WebViewEnvironmentHolder.isRuntimeAvailable()) {
      if (kDebugMode) {
        debugPrint('WebView2 pre-warm skipped: runtime not installed');
      }
      return;
    }
    await WebViewEnvironmentHolder.initialize();
  } catch (error, stackTrace) {
    _logNonFatalInitializationError(
      'WebView2 environment pre-warm',
      error,
      stackTrace,
    );
  }
}

Future<void>? _processInitializationFuture;

Future<void> _ensureBootstrapInitialized() {
  return (_processInitializationFuture ??= _initializeProcessSingletons())
      .then((_) => _initializeRestartableRuntime())
      .then((_) => StartupTimeline.instance.mark('bootstrapDone'));
}

@visibleForTesting
void scheduleAfterTwoFrames(
  VoidCallback action, {
  WidgetsBinding? binding,
  void Function(FrameCallback callback)? scheduleFrameCallback,
}) {
  final schedule =
      scheduleFrameCallback ??
      (binding ?? WidgetsBinding.instance).addPostFrameCallback;
  schedule((_) {
    schedule((_) {
      action();
    });
  });
}

/// ה-ack המוקדם שנשלח מ-[_sendEarlyInstallAcks] — נשמר כדי שמופע משני יוכל
/// להמתין לסיומו לפני exit(0) (אחרת התהליך מת לפני שהבקשה יוצאת).
Future<void>? _earlyInstallAckFuture;

/// סורק את ארגומנטי ההפעלה אחר קישורי `otzaria://plugin/install` עם token,
/// ושולח לכל אחד אישור קבלה (fire-and-forget). האישור נשלח שוב גם מה-bloc
/// בעת הטיפול בבקשה — השרת אידמפוטנטי לכך.
void _sendEarlyInstallAcks(List<String> args) {
  final futures = <Future<void>>[];
  for (final raw in args) {
    final arg = raw.trim();
    if (!arg.toLowerCase().startsWith('otzaria:')) continue;
    final uri = Uri.tryParse(arg);
    if (uri == null) continue;
    final reportContext = PluginStoreLinkParser.parseUri(uri)?.reportContext;
    if (reportContext != null) {
      futures.add(PluginInstallReportService.acknowledge(reportContext));
    }
  }
  if (futures.isNotEmpty) {
    _earlyInstallAckFuture = Future.wait(futures);
  }
}

Future<void> _enqueueExternalActivationArgs(List<String> args) async {
  final activationUris = <String>[];

  for (final raw in args) {
    final arg = raw.trim();
    if (arg.isEmpty) continue;

    if (arg.toLowerCase().startsWith('otzaria:')) {
      activationUris.add(arg);
      continue;
    }

    // לחיצה כפולה על קובץ `.otzplugin` משויך — המערכת מעבירה את הנתיב כארגומנט.
    // ב-Linux/macOS, ה-desktop entry משתמש ב-‎%u (URL), כך שהמערכת מעבירה
    // ‎file:///abs/path. ממירים ל-נתיב מקומי לפני שמירה בתור.
    final localPath = _resolveLocalPluginPath(arg);
    if (localPath != null) {
      activationUris.add(_buildLocalPluginInstallUri(localPath));
    }
  }

  for (final uriString in activationUris) {
    try {
      await _externalActivationQueue.enqueueUriString(uriString);
    } catch (error, stackTrace) {
      _appendUnhandledErrorToLocalLog(
        title: 'External Activation Queue Error',
        error: error,
        stackTrace: stackTrace,
        details: {
          'Uri': uriString,
        },
      );
    }
  }
}

/// מחזירה נתיב קובץ מקומי `.otzplugin` אם הארגומנט הוא כזה — או null אחרת.
/// תומך גם ב-`file://` URIs (Linux/macOS) וגם בנתיב גולמי (Windows).
@visibleForTesting
String? resolveLocalPluginPathForTesting(String arg) =>
    _resolveLocalPluginPath(arg);

String? _resolveLocalPluginPath(String arg) {
  String candidate = arg;
  if (arg.toLowerCase().startsWith('file:')) {
    try {
      final uri = Uri.parse(arg);
      if (uri.scheme == 'file') {
        candidate = uri.toFilePath();
      }
    } catch (_) {
      // לא URI תקני — נמשיך עם הערך המקורי.
    }
  }

  if (candidate.toLowerCase().endsWith('.otzplugin')) {
    return candidate;
  }
  return null;
}

String _buildLocalPluginInstallUri(String filePath) {
  final encoded = Uri.encodeQueryComponent(filePath);
  return 'otzaria://plugin/install-local?path=$encoded';
}

/// מזהה ארגומנטים של ממשק שורת פקודה (CLI). אם זוהתה פקודה — מריצה
/// אותה ומחזירה `true` (האפליקציה צריכה לעצור מיד ולא להעלות GUI).
///
/// פקודות נתמכות:
///   `otzaria.exe pack-plugin [path] [--force] [--output <file>]`
///       אורז תיקיית תוסף לקובץ `.otzplugin`. אם `path` חסר — נעשה
///       שימוש בתיקייה הנוכחית.
///   `otzaria.exe pack-plugin --help` / `-h` — הצגת מסך עזרה.
///   `otzaria build-release-index --library <dir> --index <dir> --data <dir>`
///       בונה אינדקס חיפוש מבודד עבור חבילת ההפצה המלאה.
///   `otzaria info [<נושא>] [--limit=<n>] [--compact] [--out=<path>]`
///       מדפיס דוח JSON על ההתקנה ל-stdout (ראה [AppInfoCli]).
///
/// הלוגיקה עצמה ב-[PluginPackagerCli.run] כדי לשתף בדיוק את אותו הקוד
/// עם `tool/plugins/package_plugin.dart`.
Future<bool> _maybeRunCliCommand(List<String> args) async {
  if (args.isEmpty) return false;

  final normalized = normalizeCliCommand(args.first);

  if (normalized == 'pack-plugin') {
    final exitCode = await PluginPackagerCli.run(args.skip(1).toList());
    await stdout.flush();
    await stderr.flush();
    exit(exitCode);
  }

  if (normalized == 'build-release-index') {
    final exitCode = await ReleaseIndexBuilderCli.run(args.skip(1).toList());
    await stdout.flush();
    await stderr.flush();
    exit(exitCode);
  }

  if (normalized == 'info') {
    final exitCode = await AppInfoCli.run(args.skip(1).toList());
    await stdout.flush();
    await stderr.flush();
    exit(exitCode);
  }

  return false;
}

class AppBootstrap extends StatefulWidget {
  const AppBootstrap({super.key});

  @override
  State<AppBootstrap> createState() => _AppBootstrapState();
}

class _AppBootstrapState extends State<AppBootstrap> {
  bool _ready = false;
  Object? _error;
  HistoryRepository? _historyRepository;
  SettingsRepository? _settingsRepository;

  @override
  void initState() {
    super.initState();
    _ensureBootstrapInitialized()
        .then((_) {
          if (!mounted) return;
          setState(() {
            _historyRepository = HistoryRepository();
            _settingsRepository = SettingsRepository();
            _ready = true;
          });
          unawaited(_runDeferredCacheWarmups());
        })
        .catchError((Object error, StackTrace stackTrace) {
          _appendUnhandledErrorToLocalLog(
            title: 'Bootstrap Error',
            error: error,
            stackTrace: stackTrace,
          );
          if (!mounted) return;
          setState(() {
            _error = error;
            _ready = true;
          });
        });
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) return const SplashApp();

    if (_error != null) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: Center(
            child: Text(
              'שגיאת אתחול: $_error',
              textDirection: TextDirection.rtl,
            ),
          ),
        ),
      );
    }

    final historyRepository = _historyRepository!;
    final settingsRepository = _settingsRepository!;

    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider<FocusRepository>(
          create: (_) => FocusRepository(),
        ),
        RepositoryProvider<SettingsRepository>(
          create: (_) => settingsRepository,
        ),
      ],
      child: MultiBlocProvider(
        providers: [
          BlocProvider<SettingsBloc>(
            create: (_) => SettingsBloc(
              repository: settingsRepository,
            )..add(LoadSettings()),
          ),
          BlocProvider<LibraryBloc>(
            // ה-LoadLibrary אינו נשלח כאן יותר: בניית הקטלוג (~300ms CPU על
            // ה-main thread) הייתה חונקת את שאילתת תוכן הספר הפעיל ומעכבת את
            // הופעתו. ההפעלה עברה ל-MainWindowScreen._revealMainWindowOnce,
            // שמעדיף את טעינת הספר הפעיל ורק אז מתחיל את בניית הקטלוג.
            create: (_) => LibraryBloc(),
          ),
          BlocProvider<CustomFoldersBloc>(
            create: (context) => CustomFoldersBloc(
              addLibraryEvent: (event) =>
                  context.read<LibraryBloc>().add(event),
            )..add(const LoadCustomFolders()),
          ),
          BlocProvider<IndexingBloc>(
            create: (_) => IndexingBloc.create(),
          ),
          BlocProvider<HistoryBloc>(
            create: (_) => HistoryBloc(historyRepository),
          ),
          BlocProvider<TabsBloc>(
            create: (_) {
              final bloc = TabsBloc(repository: TabsRepository())
                ..add(LoadTabs());
              // חלון שנפתח עם מטען מקבל את הכרטיסיה שהועברה אליו. `LoadTabs`
              // נשלח קודם כדי שסדר האירועים יהיה זהה לחלון רגיל — הכרטיסיה
              // המועברת נכנסת אחריו, ולכן היא זו שתהיה פעילה.
              // הפענוח כאן ולא בנקודת הכניסה: בשלב הזה `Settings` כבר
              // מאותחל, ו-`TextBookTab.fromJson` תלוי בו.
              final payload = secondaryWindowPayload;
              secondaryWindowPayload = null;
              final transferred = MultiWindowService.decodePayload(payload);
              if (transferred != null) {
                bloc.add(AddTab(transferred));
              } else if (MultiWindowService.payloadHasTab(payload)) {
                // ⚠️ המטען **הכיל** כרטיסיה והפענוח נכשל. עד כה זה היה
                // כשל שקט: חלון חדש נפתח ריק, המקור כבר מחק את הכרטיסיה,
                // והשורה היחידה שהסבירה למה נכתבה ל-stdout שאיש אינו רואה
                // בהפעלה מהסייר.
                //
                // ההודעה נדחית לאחרי הבנייה — `UiSnack` זקוק ל-navigator,
                // ובנקודה הזו העץ עוד לא הורכב.
                debugPrint('⚠️ פענוח הכרטיסיה שהועברה נכשל — החלון ייפתח ריק');
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  UiSnack.showError(
                    WindowMessages.transferredTabDecodeFailed,
                  );
                });
                try {
                  ErrorLogFile.append(
                    title: 'פענוח כרטיסיה שהועברה לחלון חדש נכשל',
                    error:
                        'decodePayload returned null for a payload with a tab',
                    stackTrace: StackTrace.current,
                  );
                } catch (_) {
                  // רישום הוא best-effort ולעולם אינו חוסם את עליית החלון.
                }
              }
              return bloc;
            },
          ),
          BlocProvider<NavigationBloc>(
            create: (context) {
              final nav = NavigationBloc(
                repository: NavigationRepository(),
                tabsRepository: TabsRepository(),
                // "חיפוש" ו"עיון" הם אותו עמוד טאבים; היישור לפי החלונית
                // הפעילה שומר שהאייקון המודגש בסרגל יתאים למה שמוצג בפועל.
                activePaneStream: context
                    .read<TabsBloc>()
                    .stream
                    .map((tabsState) => tabsState.activePane)
                    .distinct(),
              )..add(const CheckLibrary());
              // ⚠️ אחרי `CheckLibrary` ולא במקומו. `CheckLibrary` מחליט
              // לאן לנווט לפי מצב הספרייה, ובחלון שנפתח עם כרטיסיה מועברת
              // ההחלטה שגויה: הוא היה נשאר במסך הספרייה בעוד הכרטיסיה
              // פתוחה מאחוריו — בדיוק מה שנצפה. הניווט נשלח אחריו ולכן
              // גובר עליו.
              if (WindowRole.openedWithTab) {
                nav.add(const NavigateToScreen(Screen.reading));
              }
              return nav;
            },
          ),
          BlocProvider<FindRefBloc>(
            create: (_) => FindRefBloc(
              findRefRepository: buildFindRefRepository(),
            ),
          ),
          BlocProvider<PersonalNotesBloc>(
            create: (_) => PersonalNotesBloc(),
          ),
          BlocProvider<BookmarkBloc>(
            create: (_) => BookmarkBloc(BookmarkRepository()),
          ),
          BlocProvider<WorkspaceBloc>(
            create: (context) {
              final tabsBloc = context.read<TabsBloc>();
              return WorkspaceBloc(
                repository: WorkspaceRepository(),
                onWorkspaceTabsChanged:
                    (
                      List<OpenedTab> tabs,
                      int activeIndex,
                      String? activePane,
                    ) async {
                      // ⚠️ ההמתנה נרשמת **לפני** השליחה: `ReplaceAllTabs`
                      // מטופל סינכרונית, ורישום אחריו היה מפספס את המצב
                      // שהוא מחפש ומחכה לנצח.
                      final replaced = tabsBloc.stream.firstWhere(
                        (state) =>
                            identical(state.tabs, tabs) &&
                            state.currentTabIndex == activeIndex,
                      );
                      tabsBloc.add(
                        ReplaceAllTabs(
                          tabs,
                          activeIndex,
                          activePane: activePane,
                        ),
                      );
                      await replaced;
                    },
              )..add(LoadWorkspaces());
            },
          ),
          ChangeNotifierProvider<ShamorZachorDataProvider>(
            lazy: true,
            create: (_) => ShamorZachorDataProvider(),
          ),
          ChangeNotifierProvider<ShamorZachorProgressProvider>(
            lazy: true,
            create: (_) => ShamorZachorProgressProvider(),
          ),
          BlocProvider<WorkStatusCubit>(
            create: (_) => WorkStatusCubit(),
          ),
          BlocProvider<LibraryUpdateBloc>(
            lazy: true,
            create: (context) => LibraryUpdateBloc(
              repository: LibraryUpdateRepository(
                discovery: LibraryUpdateDiscovery(
                  client: GithubLibraryReleaseClient(),
                ),
                downloader: PatchDownloader(
                  decompress: (bytes) => Zstandard().decompress(bytes),
                ),
              ),
              companionAssets: CompanionAssetsService(),
              isOfflineMode: () =>
                  Settings.getValue<bool>(SettingsRepository.keyOfflineMode) ??
                  false,
              // ⚠️ חלון משני לעולם אינו בודק עדכונים. עדכון ספרייה הוא
              // פעולה פר-תהליך: שני חלונות ששאלו את GitHub במקביל קיבלו
              // 403, והמשתמש ראה "שגיאה בקבלת רשימת ה-releases" בכל
              // פתיחת חלון.
              areUpdatesEnabled: () =>
                  !WindowRole.isSecondary &&
                  (Settings.getValue<bool>(
                        SettingsRepository.keySoftwareAndBookUpdatesEnabled,
                      ) ??
                      true),
              // עדכוני ספרייה תמיד ליציב בלבד — מנותק מערוץ הפיתוח, שמשפיע רק
              // על עדכוני התוכנה.
              allowPrerelease: () => false,
              onCheckSucceeded: () => recordSuccessfulUpdateCheck(
                SettingsRepository.keyLastLibraryUpdateCheck,
              ),
            ),
          ),
          BlocProvider<PluginUpdatesCubit>(
            lazy: true,
            create: (_) => PluginUpdatesCubit(),
          ),
          BlocProvider<PluginSystemBloc>(
            create: (context) {
              final repository = PluginRegistryRepository();
              final tabsBloc = context.read<TabsBloc>();
              final coordinator = BookOpenCoordinator(
                tabsBloc: tabsBloc,
                historyBloc: context.read<HistoryBloc>(),
                navigationBloc: context.read<NavigationBloc>(),
              );
              final bookAccess = DeclarativeLibraryBookAccess.otzaria(
                coordinator,
              );
              final host = DeclarativePluginHostService(
                loadPlugin: repository.getPlugin,
                loadPermissions: (pluginId) async =>
                    (await repository.getGrantedPermissionNames(
                      pluginId,
                    )).toSet(),
                bookResolver: bookAccess,
                bookOpener: bookAccess,
                parallelEditionsFinder: bookAccess.parallelEditionsForIdentity,
                readerScroller: PluginDeclarativeReaderScroller(
                  tabsBloc: tabsBloc,
                ),
                searchOpener: PluginDeclarativeSearchOpener(coordinator),
                onError: (pluginId, error, stackTrace) => debugPrint(
                  'Declarative plugin host [$pluginId]: $error\n$stackTrace',
                ),
              );
              return PluginSystemBloc(
                  repository: repository,
                  declarativeHost: host,
                  readerStates: tabsBloc.stream,
                  initialReaderState: tabsBloc.state,
                )
                ..add(const SeedBundledPlugins())
                ..add(LoadPlugins());
            },
          ),
        ],
        // מתחת לכל ה-blocs: האפיק עונה על בקשות מחלונות אחרים, ושתי
        // הבקשות הנתמכות — "תאר את עצמך" ו"קלוט כרטיסיה" — זקוקות
        // ל-TabsBloc ול-NavigationBloc.
        child: const WindowBusHost(child: App()),
      ),
    );
  }
}

Future<void> initHive() async {
  // ⚠️ החלון הראשון, וכל עוד אין חלון נוסף חי. שורש Hive פרטי שנשאר תחת
  // `<dataRoot>/windows` הוא שארית מהפעלה קודמת ואף אחד לא ימחק אותו
  // אחרת — נמדדו 69 תיקיות ו-33MB. תנאי `hasOtherWindows` מגן על המסלול
  // של `RestartWidget`, שמריץ את האתחול מחדש בזמן שחלון משני חי ופתח שם
  // קבצים.
  if (!WindowRole.isSecondary && !WindowBus.instance.hasOtherWindows) {
    await deleteStaleWindowRoots();
  }
  // ⚠️ `hiveRootPath` ולא `getDataRootPath`: בחלון משני קובצי ה-Hive
  // יושבים בתיקייה נפרדת, אבל שאר שורש הנתונים — תוספים, WebView2,
  // מסדי נתונים — נשאר משותף. ראו `configureHiveRootForWindow`.
  Hive.init(await hiveRootPath());
  // כל box הוא קובץ נפרד ועצמאי — הפתיחות רצות במקביל במקום בזו אחר זו.
  await Future.wait([
    Hive.openBox<dynamic>('tabs'),
    Hive.openBox<dynamic>('workspaces'),
    Hive.openBox<dynamic>('history'),
    Hive.openBox<dynamic>('bookmarks'),
    Hive.openBox<dynamic>(DirectErrorReportService.queueBoxName),
    Hive.openBox<dynamic>(PluginReportService.queueBoxName),
  ]);
  // ⚠️ כאן ולא ב-`TabsBloc`. שני קוראים שונים טוענים את הכרטיסיות
  // (`TabsBloc` דרך `LoadTabs`, ו-`NavigationBloc` בקונסטרוקטור שלו), והסדר
  // ביניהם תלוי בתזמון של תור האירועים. איחוד שמוחק מפתחות חייב לרוץ פעם
  // אחת, לפני שניהם.
  await TabsRepository.adoptOrphanWindowSessions();
}

Future<void> loadCerts() async {
  final certs = ['assets/ca/netfree_cas.pem'];
  for (var cert in certs) {
    final certBytes = await rootBundle.load(cert);
    SecurityContext.defaultContext.setTrustedCertificatesBytes(
      certBytes.buffer.asUint8List(),
    );
  }
}

/// Clean up resources when the app is closing
void cleanup() {
  _appWindowListener?.dispose();

  // Clear shared book/acronym caches
  BooksCache.instance.clear();
  AcronymsCache.instance.clear();
  GenerationCache.instance.clear();
}

// Note: TOC parsing helper moved to lib/utils/toc_parser.dart for reuse

/// נקודת הכניסה של חלון אוצריא נוסף.
///
/// רץ ב-isolate נפרד משלו, באותו תהליך ועל **ה-thread הראשי כמו כל
/// המנועים** (ראו [MultiWindowService]). זו **אינה** `main()`: אין בדיקת
/// מופע יחיד (היא הייתה סוגרת את החלון מיד), אין splash נייטיב, ואין תור
/// הפעלות חיצוניות — כל אלה שייכים לתהליך, וכבר רצו בחלון הראשון.
///
/// ⚠️ שורש Hive פרטי. `hive_ce` נועל את קובצי ה-`.lock` בלעדית, והנעילה
/// היא פר-handle ולא פר-תהליך: שני isolates באותו תהליך נכשלים באותו
/// errno 33 כמו שני תהליכים. לכן ההיסטוריה, הסימניות, שולחנות העבודה
/// והכרטיסיות **מנותבים לחלון הראשון** (`SharedHiveStore`), וההגדרות
/// נזרעות פעם אחת ומסונכרנות חי (`SettingsSync`). הספרייה עצמה —
/// הספרים, SQLite ואינדקס Tantivy — משותפת, כי אלה **כן** נפתחים פעמיים
/// בהצלחה. ראו `docs/multi-window.md`.
@pragma('vm:entry-point')
void secondaryWindowMain(List<String> args) async {
  if (kReleaseMode) {
    debugPrint = (String? message, {int? wrapWidth}) {};
  }
  WindowRole.isSecondary = true;
  _secondaryWindowStartup = Stopwatch()..start();
  SentryWidgetsFlutterBinding.ensureInitialized();
  EditableText.debugDeterministicCursor = true;

  // ⚠️ מטפלי השגיאות הם פר-isolate. בלעדיהם כל חריגה בחלון הזה נעלמה
  // ב-release, שבו `debugPrint` הוא no-op — בלי לוג ובלי דיווח.
  await _initializeLogMetadata();
  _installGlobalErrorHandlers();

  // ⚠️ **לפני** הקמת שורש ה-Hive: המשבצת היא שם התיקייה. `register` נשען
  // על [IsolateNameServer] בלבד ואינו תלוי ב-Hive, ולכן אין מניעה להקדים.
  _claimWindowBusSlot();

  try {
    // ⚠️ **רק** הפניית קובצי ה-Hive נעשית כאן.
    //
    // את כל שאר האתחול — `RustLib.init`, `Settings.init`, `initHive`,
    // `SqliteDataProvider`, `windowManager.ensureInitialized` — מבצע
    // `AppBootstrap` דרך `_initializeProcessSingletons`, בדיוק כמו בחלון
    // הראשון. שכפול שלהם כאן נכשל ב-"Should not initialize
    // flutter_rust_bridge twice": `RustLib` שומר את מצבו על
    // `RustLib.instance`, שהוא סטטי פר-isolate, ולכן שתי קריאות **באותו**
    // isolate הן שגיאה — גם אם החלון חדש.
    //
    // הכלל: נקודת הכניסה של חלון משני קובעת רק מה **שונה** בו. כל השאר
    // עובר במסלול היחיד והמשותף.
    final sharedRoot = await AppPaths.getDataRootPath();
    // ⚠️ שם קבוע פר-משבצת ולא חותמת זמן. חותמת זמן יצרה תיקייה חדשה בכל
    // פתיחת חלון ואף אחד לא מחק אותן — 69 תיקיות ו-33MB נמדדו במחשב אחד.
    // התיקיות האלה נמחקות בהפעלה קרה של החלון הראשון ([initHive]), שבה אין
    // עוד חלונות משניים ולכן כולן שאריות.
    final windowRoot = p.join(
      sharedRoot,
      windowRootsDirName,
      'slot-${WindowBus.instance.slot ?? 0}',
    );
    await Directory(windowRoot).create(recursive: true);
    // ⚠️ Hive בלבד, ולא `configureDataRootPathForProcess`. הפניית שורש
    // הנתונים כולו רוקנה את `<dataRoot>/plugins` — תפריט הכלים בחלון
    // משני היה ריק, וכרטיסיית תוסף נעלמה מהמקור במקום להיפתח ביעד.
    configureHiveRootForWindow(windowRoot);

    // ⚠️ **חובה לפני כל שימוש ב-PDF בחלון הזה.** ראו
    // [_isolatePdfiumForThisWindow].
    await _isolatePdfiumForThisWindow(windowRoot);

    // זריעת ההעדפות של החלון שפתח אותנו.
    //
    // ⚠️ חייבת לקרות **לפני** ש-`AppBootstrap` מריץ את `Settings.init`,
    // אחרת החלון יעלה בלי נתיב ספרייה ויציג את מסך ההתחלה כאילו זו התקנה
    // חדשה. הכתיבה היא ל-box של שורש הנתונים הפרטי, ולכן אין התנגשות
    // נעילה; `Settings.init` יפתח מאוחר יותר את אותו box הפתוח ויראה את
    // הערכים.
    final seed = MultiWindowService.decodePreferences(
      args.isEmpty ? null : args.first,
    );
    if (seed.isNotEmpty) {
      Hive.init(windowRoot);
      final box = await Hive.openBox<dynamic>(
        HiveCache.keyName,
        path: windowRoot,
      );
      await box.putAll(seed);
    }
  } catch (e, st) {
    // ⚠️ אין להמשיך. בלי `configureHiveRootForWindow` שורש ה-Hive נופל
    // לשורש המשותף, `initHive` נכשל בנעילה בלעדית (errno 33), והמשתמש מקבל
    // חלון ריק או קורס. ב-release `debugPrint` מושתק ולכן אין שום עקבה —
    // הכתיבה ללוג המקומי היא הראיה היחידה.
    debugPrint('secondaryWindowMain: data root setup failed: $e\n$st');
    try {
      ErrorLogFile.append(
        title: 'Secondary window data root setup failed',
        error: e,
        stackTrace: st,
      );
    } catch (_) {
      // כתיבת הלוג היא best-effort ולא תמנע את הסגירה.
    }
    await const MultiWindowService().closeSelf();
    return;
  }

  Bloc.observer = AppBlocObserver();
  unawaited(AppCursors.ensureInitialized());

  // ⚠️ המטען נשמר **גולמי** ומפוענח מאוחר יותר, ב-`TabsBloc`.
  //
  // `TextBookTab.fromJson` קורא ל-`Settings.getValue('key-splited-view')`,
  // ו-`Settings` מאותחל רק בתוך `AppBootstrap`. פענוח כאן זרק, נתפס והחזיר
  // null — הכרטיסיה נעלמה מהחלון המקורי ולא נפתחה בחדש. `ToolTab.fromJson`
  // אינו נוגע ב-Settings, ולכן דווקא כלים עברו בהצלחה והבאג נראה אקראי.
  secondaryWindowPayload = args.isEmpty || args.first.isEmpty
      ? null
      : args.first;
  WindowRole.openedWithTab = MultiWindowService.payloadHasTab(
    secondaryWindowPayload,
  );

  // ⚠️ נדרש לפני `runApp`: בלעדיו `setTitleBarStyle(hidden)` שב-bootstrap
  // אינו נתפס, והחלון עולה עם מסגרת Windows סטנדרטית **מעל** סרגל הכותרת
  // המותאם של האפליקציה — "חלון בתוך חלון". החלון הראשון עושה זאת
  // ב-`main()`, ולכן הבעיה לא נראתה בו.
  if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
    try {
      await windowManager.ensureInitialized();
      // ⚠️ בדיוק כמו בחלון הראשון. בלי זה לחיצה על X בחלון משני עוקפת את
      // Dart לגמרי — ראו [_installWindowCloseHandling].
      await _installWindowCloseHandling();
    } catch (e) {
      debugPrint('secondaryWindowMain: windowManager init failed: $e');
    }
  }

  runApp(
    AppWindowScope(
      controller: _appWindow,
      geometry: _appWindow,
      child: SentryWidget(
        child: RestartWidget(
          child: const AppBootstrap(),
        ),
      ),
    ),
  );
}

/// פותח חלון נוסף אחרי השהיה, לבדיקה מקצה לקצה בלי אינטראקציה ידנית.
///
/// עובר במסלול המלא — כולל צילום ההעדפות — ולכן הוא בודק את מה שהמשתמש
/// יקבל, ולא רק את הצד הנייטיב. מופעל רק כאשר `OTZARIA_DEBUG_OPEN_WINDOW_MS`
/// מוגדר.
void _maybeScheduleDebugSecondWindow() {
  // ⚠️ מגודר ב-`kDebugMode`: פתיחת חלון אוטומטית לפי משתנה סביבה אינה
  // התנהגות שצריכה להיות נגישה בבנייה שהמשתמש מריץ, וגם קריאת
  // `Platform.environment` בכל עלייה מתייתרת שם.
  if (!kDebugMode) return;
  final ms = int.tryParse(
    Platform.environment['OTZARIA_DEBUG_OPEN_WINDOW_MS'] ?? '',
  );
  if (ms == null || ms <= 0) return;
  Timer(Duration(milliseconds: ms), () async {
    final opened = await const MultiWindowService().openWindow();
    debugPrint('[debug] openWindow -> $opened');
  });
}

/// נותן לחלון הזה **עותק פרטי של `pdfium.dll`**, ומכוון אליו את pdfrx.
///
/// ## למה זה נדרש: PDFium גלובלי לתהליך, והקולבקים שלו שייכים ל-isolate
///
/// `FPDF_InitLibrary` ו-`FPDF_SetSystemFontInfo` הם מצב של **התהליך** (C
/// globals במודול), בעוד ש-pdfrx מחזיק את כל מצבו במשתנים ברמת הקובץ —
/// כלומר **פר isolate group**, וכל חלון הוא group משלו. התוצאה:
///
/// 1. החלון הראשון מתקין font mapper ו-`FPDF_SetSystemFontInfo(A)`.
/// 2. החלון השני אינו רואה את `_fontMapper` של הראשון (משתנה פר-group),
///    מתקין mapper משלו, ו-`FPDF_SetSystemFontInfo(B)` **דורס** את המצביע.
/// 3. הקולבקים של ה-mapper הם `NativeCallable.isolateLocal`, כלומר קשורים
///    ל-`PdfrxEngineWorker` של אותו group. ה-`FPDF_LoadPage` הבא בחלון
///    הראשון קורא ל-`MapFont` של B מתוך worker A, וה-VM נופל בשגיאה
///    `Cannot invoke native callback from a different isolate` — קריסה
///    קטלנית שאי אפשר לתפוס.
///
/// ה-pre-warm של תוכני העניינים ב-`ReferenceBooksCache` פותח עשרות קובצי
/// PDF בכל חלון, ולכן די היה בפתיחת חלון שני כדי לחמש את הקריסה.
///
/// ## הפתרון: מודול נפרד לכל חלון
///
/// `DynamicLibrary.open('pdfium.dll')` בשם בלבד מחזיר את המודול **שכבר
/// טעון** בתהליך. עותק בנתיב אחר ובשם אחר נטען כמודול נפרד עם סגמנט
/// נתונים משלו, ולכן לכל חלון יש PDFium משלו — כולל font mapper משלו.
/// המחיר: עותק DLL בתיקיית החלון (נמחקת בהפעלה קרה) ומודול נוסף בזיכרון.
///
/// כשל כאן עוצר את החלון המשני לפני הפעלת Flutter, כדי שלא ישתף PDFium
/// עם החלון הראשי ויפיל את ה-VM בעת פתיחת PDF.
Future<void> _isolatePdfiumForThisWindow(String windowRoot) async {
  if (kIsWeb || !Platform.isWindows) return;
  try {
    final source = File(
      p.join(p.dirname(Platform.resolvedExecutable), 'pdfium.dll'),
    );
    if (!await source.exists()) {
      throw FileSystemException('pdfium.dll not found', source.path);
    }
    // ⚠️ גם **שם** שונה ולא רק נתיב שונה: הלוודר של Windows מזהה מודולים
    // לפי שם הבסיס במקרים מסוימים, ושם ייחודי מסיר כל ספק.
    final slot = WindowBus.instance.slot ?? 0;
    final target = File(p.join(windowRoot, 'pdfium-window-$slot.dll'));
    if (!await target.exists() ||
        await target.length() != await source.length()) {
      await source.copy(target.path);
    }
    Pdfrx.pdfiumModulePath = target.path;
    debugPrint('[pdf] מודול PDFium פרטי לחלון: ${target.path}');
  } catch (e, st) {
    debugPrint('⚠️ _isolatePdfiumForThisWindow failed: $e\n$st');
    try {
      ErrorLogFile.append(
        title: 'Private PDFium module for secondary window failed',
        error: e,
        stackTrace: st,
        details: const {
          'impact':
              'PDF rendering in this window shares the process-global PDFium '
              'with the main window and can abort the VM',
        },
      );
    } catch (_) {
      // רישום ללוג הוא best-effort.
    }
    rethrow;
  }
}

/// מעביר את סגירת החלון הזה דרך Dart.
///
/// ⚠️ חייב לרוץ **בכל** חלון, לא רק בראשון. בלי `setPreventClose(true)`
/// הפלאגין מעביר את `WM_CLOSE` הלאה ל-`Win32Window::MessageHandler`, שמסתיר
/// את החלון — ואף שורת Dart של הסגירה אינה רצה: לא ה-flush של ההיסטוריה
/// והכרטיסיות ([PreCloseRegistry]), לא השאלה על שינויים שלא נשמרו, ולא
/// מחיקת סשן החלון. חלון משני נסגר כך בשקט תוך אובדן כתיבות תלויות.
Future<void> _installWindowCloseHandling() async {
  _appWindowListener = AppWindowListener(window: _appWindow);
  windowManager.addListener(_appWindowListener!);
  await windowManager.setPreventClose(true);
}

/// תופס את משבצת החלון באפיק ההודעות, **לפני `runApp`**.
///
/// ⚠️ העיתוי אינו נוחות. התפיסה הייתה ב-`WindowBusHost.initState`, שהוא
/// **צאצא** של `MultiBlocProvider` — כלומר ה-blocs נבנים לפניו, ושניים
/// מהם ניגשים למצב שתלוי במשבצת עוד לפני שהיא קיימת:
///
/// * `TabsRepository.saveTabs` בחלון משני זקוק למשבצת כדי לדעת לאיזה מפתח
///   סשן לכתוב, ובלעדיה הוא **מדלג על השמירה** במכוון (הנפילה למפתח של
///   החלון הראשון הייתה דורסת את הכרטיסיות שלו). כלומר הכרטיסיה שהועברה
///   לחלון החדש עלולה לא להישמר עד השינוי הבא.
/// * הבעלים רושם כאן את הכינוי `otzaria.window.owner`, שדרכו כל חלון משני
///   מאתר אותו.
///
/// הסדר בין `BlocProvider.create` ל-`initState` תלוי בעצלנות של הספק, ולכן
/// הוא אינו משהו שאפשר להישען עליו. `register` אידמפוטנטי, ולכן הקריאה
/// ב-`WindowBusHost` נשארת כרשת ביטחון.
void _claimWindowBusSlot() {
  // ⚠️ מגודר בפלטפורמה: בלי זה גם מובייל פתח `ReceivePort` ורשם כינוי
  // בעלים בשביל אפיק שאף אחד לא ידבר בו.
  if (!MultiWindowService.isSupported) return;
  final slot = WindowBus.instance.register(asOwner: !WindowRole.isSecondary);
  if (slot == null) {
    debugPrint('⚠️ כל משבצות האפיק תפוסות — החלון הזה לא יוכל לשתף מצב');
  }
}

/// מודד את זמן העלייה של חלון משני, מנקודת הכניסה ועד החשיפה.
Stopwatch? _secondaryWindowStartup;

/// מריץ שלב אתחול ומודד אותו — בחלון משני בלבד.
///
/// ⚠️ אין למדוד בחלון הראשון: שם השלבים רצים תחת ה-splash הנייטיב וזמנם
/// אינו מורגש, וההדפסות היו רק רעש בלוג.
Future<T> _timedPhase<T>(String name, Future<T> Function() body) async {
  final sw = Stopwatch()..start();
  try {
    return await StartupTimeline.instance.phase(name, body);
  } finally {
    if (WindowRole.isSecondary) {
      debugPrint('[window-phase] $name: ${sw.elapsedMilliseconds}ms');
    }
  }
}

/// המטען הגולמי שאיתו נפתח החלון, אם נפתח כחלון משני.
///
/// נצרך **פעם אחת** ביצירת `TabsBloc` ומתאפס שם, כדי ש-`RestartWidget`
/// לא יוסיף את הכרטיסיה שוב בהפעלה מחדש של העץ. הפענוח קורה שם ולא
/// כאן — ראו ההערה ב-[secondaryWindowMain].
String? secondaryWindowPayload;
