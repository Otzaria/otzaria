import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';
import 'package:otzaria/plugins/services/startup_crash_counter.dart';
import 'package:otzaria/app_report/services/app_crash_session.dart';
import 'package:otzaria/app_report/services/app_hang_report.dart';
import 'package:otzaria/core/http_client_registry.dart';
import 'package:otzaria/core/pre_close_registry.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/core/messages/plugin_messages.dart';
import 'package:otzaria/core/window_persistence.dart';
import 'package:otzaria/core/windowing/app_window_controller.dart';
import 'package:otzaria/core/windowing/app_window_id.dart';
import 'package:otzaria/core/windowing/window_manager_app_window_controller.dart';
import 'package:otzaria/core/windowing/app_window_keys.dart';
import 'package:otzaria/core/windowing/runner_window_channel.dart';
import 'package:otzaria/core/windowing/multiview/view_window_registry.dart';
import 'package:otzaria/core/windowing/multiview/in_process_tab_drop.dart';
import 'package:otzaria/core/windowing/multiview/view_focus_sync.dart';
import 'package:otzaria/core/windowing/multiview/view_window_opener.dart';
import 'package:otzaria/core/windowing/window_opener.dart';
import 'package:otzaria/core/user_state/user_state_database.dart';
import 'package:otzaria/data/data_providers/cache_database_holder.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:otzaria/data/data_providers/user_books_database_holder.dart';
import 'package:otzaria/indexing/utils/indexing_crash_canary.dart';
import 'package:otzaria/personal_notes/storage/personal_notes_database.dart';
import 'package:otzaria/plugins/storage/plugin_system_database.dart';
import 'package:otzaria/plugins/services/plugin_correction_session_service.dart';
import 'package:otzaria/plugins/services/plugin_crash_guard.dart';
import 'package:otzaria/plugins/services/plugin_runtime_dispatcher.dart';
import 'package:otzaria/plugins/view/webview_environment_holder.dart';
import 'package:otzaria/printing/print_work_status.dart';
import 'package:otzaria/tabs/utils/confirm_close_tabs.dart';
import 'package:otzaria/tabs/tabs_repository.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

/// Callback type for fullscreen state changes
typedef FullscreenCallback = void Function(bool isFullscreen);

/// Window listener that handles window events properly to prevent crashes
class AppWindowListener extends WindowListener {
  AppWindowListener({
    this.windowId = AppWindowId.primary,
    AppWindowController? window,
  }) : _window = window ?? const WindowManagerAppWindowController() {
    // כיבוי מערכת מבקש מ-Dart לשטוף כתיבות לפני סיום התהליך.
    _processControlChannel.setMethodCallHandler(_handleProcessControlCall);
    if (!kIsWeb && Platform.isMacOS) {
      _macTerminationChannel.setMethodCallHandler(_handleMacTerminationCall);
    }
  }

  Future<Object?> _handleMacTerminationCall(MethodCall call) async {
    if (call.method == 'quitRequested') {
      await handleWindowClose(quit: true);
    }
    return null;
  }

  /// האם שטיפת סיום הסשן כבר רצה. `WM_QUERYENDSESSION` מגיע לא פעם יותר
  /// מפעם אחת (המערכת שואלת כל אפליקציה, ולעיתים חוזרת), והשטיפה כבדה.
  bool _sessionEndFlushStarted = false;

  Future<Object?> _handleProcessControlCall(MethodCall call) async {
    switch (call.method) {
      case 'prepareForSessionEnd':
        await _flushForSessionEnd();
        return null;
      case 'sessionEndCancelled':
        // הכיבוי בוטל (`shutdown /a`) — כתיבות חדשות שיצטברו מכאן ואילך
        // חייבות להישטף בפעם הבאה.
        _sessionEndFlushStarted = false;
        unawaited(AppCrashSession.restoreSessionLockIfReleased());
        return null;
      case 'appHangRecovered':
        // ה-UI isolate חזר להגיב; הדיווח לא יעכב את המשך הטיפול בהודעות.
        unawaited(AppHangReport.onRecovered(call.arguments));
        return null;
      default:
        return null;
    }
  }

  /// שוטפת את הכתיבות התלויות כשהמערכת שואלת אם מותר לסיים את הסשן.
  ///
  /// ⚠️ הנייטיב **חוסם** את ה-platform thread עד שנקרא ל-`sessionEndFlushDone`
  /// או עד פקיעת זמן. לכן החוזה כאן: לסמן תמיד, גם בכשל — אחרת המשתמש
  /// מקבל שלוש שניות של תקיעה בכל כיבוי.
  Future<void> _flushForSessionEnd() async {
    try {
      if (!_sessionEndFlushStarted) {
        _sessionEndFlushStarted = true;
        AppCrashSession.markCleanExitSync();
        Object? flushFailure;
        try {
          // הטיוטות של כל החלונות באותו isolate.
          final flushed = await PluginCorrectionSessionService.instance
              .flushAll(timeout: const Duration(seconds: 3));
          if (!flushed) {
            flushFailure = StateError(
              'One or more correction drafts could not be flushed.',
            );
          }
        } catch (error) {
          flushFailure = error;
        }
        final closeFailure = await _closeWindowScoped();
        flushFailure ??= closeFailure;
        if (flushFailure != null) {
          // אותו טיפול כמו במסלול הסגירה הרגיל: הכשל הוא האות היחיד
          // לכך שכתיבות תלויות לא נשמרו.
          try {
            await Sentry.captureException(
              flushFailure,
              stackTrace: StackTrace.current,
            );
          } catch (_) {
            // דיווח הוא best-effort ולעולם אינו חוסם את הכיבוי.
          }
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Session-end flush failed: $e');
      }
    } finally {
      try {
        await _processControlChannel.invokeMethod('sessionEndFlushDone');
      } catch (_) {
        // אם הערוץ מת, הנייטיב ישתחרר בפקיעת הזמן שלו.
      }
    }
  }

  /// החלון שה-listener סוגר. מוזרק ולא נשלף מעץ ה-widgets: הסגירה רצה
  /// כשהעץ כבר מתפרק.
  final AppWindowController _window;

  static const MethodChannel _processControlChannel = MethodChannel(
    'otzaria/process_control',
  );

  static const MethodChannel _macTerminationChannel = MethodChannel(
    'otzaria/macos_termination',
  );

  /// מפעיל ב-runner את ניתוב ⌘Q למסלול הסגירה של Dart.
  ///
  /// נקרא רק אחרי ש-`setPreventClose(true)` כבר הותקן: לפני כן סגירה
  /// שמנותבת ל-`performClose` עלולה לעקוף את ה-listener עצמו.
  static Future<void> enableMacOSCloseHandling() async {
    if (kIsWeb || !Platform.isMacOS) return;
    try {
      await _macTerminationChannel.invokeMethod<void>('enableCloseHandling');
    } on MissingPluginException {
      // בינארי ישן עם Dart חדש שומר על ההתנהגות הקודמת, בלי לחסום עלייה.
    } on PlatformException catch (error) {
      debugPrint('Could not enable macOS close handling: $error');
    }
  }

  /// האם סגירת החלון האחרון משאירה את התהליך חי (macOS: האפליקציה נשארת
  /// ב-Dock ורק ⌘Q יוצא). דריסה לבדיקות בלבד.
  @visibleForTesting
  static bool? debugKeepsProcessAfterLastWindowOverride;

  static bool get _keepsProcessAfterLastWindow =>
      debugKeepsProcessAfterLastWindowOverride ?? (!kIsWeb && Platform.isMacOS);

  /// מתיר ל-AppKit להשלים `NSApplication.terminate` אחרי שכל רצף הסגירה
  /// של Dart הסתיים. בלי ההיתר, ⌘Q הבא היה חוזר ל-Dart.
  static Future<void> allowMacOSApplicationTermination() async {
    if (kIsWeb || !Platform.isMacOS) return;
    await _macTerminationChannel.invokeMethod<void>('allowTermination');
  }

  /// סטטוס קונטיינמנט ה-Job Object מה-runner (Windows בלבד):
  /// כשההקמה נכשלה [failure] מתאר את השלב שנכשל ואת קוד השגיאה.
  static Future<({bool ready, String? failure})> jobObjectStatus() async {
    final raw = await _processControlChannel.invokeMapMethod<String, Object?>(
      'jobObjectStatus',
    );
    return (ready: raw?['ready'] == true, failure: raw?['failure'] as String?);
  }

  FullscreenCallback? onFullscreenChanged;

  /// נקרא לאחר אירועי מצב חלון דיסקרטיים שעלולים לגרום לאיבוד פוקוס:
  /// maximize, unmaximize, restore, כניסה/יציאה ממסך מלא.
  VoidCallback? onWindowStateChanged;

  /// נקרא כשהחלון חזר ממיזעור — וזה בלבד.
  ///
  /// החזרה מגיעה כ-`restore`, ואם החלון היה מוגדל לפני המיזעור היא מגיעה
  /// כ-`maximize`; שניהם נספרים, ורק אם קדם להם מיזעור.
  VoidCallback? onWindowRestoredFromMinimize;

  /// האם החלון מוזער ועדיין לא חזר.
  bool _minimized = false;

  void _notifyRestoredFromMinimize() {
    if (!_minimized) return;
    _minimized = false;
    // לפני ה-callback: בקשת הפוקוס שלו צריכה למצוא את התוסף בדרך לחידוש.
    PluginRuntimeDispatcher.instance.setWindowMinimized(false);
    onWindowRestoredFromMinimize?.call();
  }

  /// נקרא בכל אירוע resize רציף — מיועד ל-debounced restore.
  VoidCallback? onWindowResizeOccurred;
  ({Future<void> done, bool quit})? _activeClose;
  Future<void>? _queuedClose;

  /// הכנת עדכון פר-isolate, אחרי אישור הסגירה ולפני תחילת הכיבוי.
  static Future<void> Function()? prepareUpdateForClose;

  Future<void> _runBestEffortShutdownStep(
    String stepName,
    Future<void> Function() action, {
    required Duration timeout,
  }) async {
    try {
      await action().timeout(timeout);
    } on TimeoutException {
      if (kDebugMode) {
        debugPrint('WebView shutdown step timed out: $stepName');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('WebView shutdown step failed ($stepName): $e');
      }
    }
  }

  Future<void> _closeWritableDatabases() async {
    await CacheDatabaseHolder.instance.close();
    await PersonalNotesDatabase.instance.close();
    await PluginSystemDatabase.instance.close();
    UserStateDatabase.instance.close();
  }

  Future<void> _armForceExitWatchdog() async {
    if (kIsWeb || !Platform.isWindows) {
      return;
    }

    await _processControlChannel.invokeMethod('armForceExitWatchdog', {
      'timeoutMs': 15000,
    });
  }

  @override
  void onWindowEnterFullScreen() {
    if (kDebugMode) {
      debugPrint('Window entered fullscreen');
    }
    onFullscreenChanged?.call(true);
    onWindowStateChanged?.call();
  }

  @override
  void onWindowLeaveFullScreen() {
    if (kDebugMode) {
      debugPrint('Window left fullscreen');
    }
    onFullscreenChanged?.call(false);
    onWindowStateChanged?.call();
  }

  /// האם זה החלון האחרון, כלומר האם סגירתו היא סגירת התהליך.
  ///
  /// כשהתשובה אינה ידועה נופלים לרשימת חלונות ה-Dart, ולא להנחה "אני
  /// האחרון", שמסיימת את התהליך.
  Future<bool> _isLastWindowClosing() async {
    try {
      // ⚠️ timeout חובה: השאלה קודמת לחימוש שעון היציאה הכפויה, ותשובה
      // שלא מגיעה הייתה משאירה את החלון פתוח ואת התהליך חי לנצח.
      final info = await WindowOpener.current.windowCount().timeout(
        const Duration(seconds: 2),
      );
      if (info != null) return info.count <= 1;
    } catch (e) {
      debugPrint('windowCount failed during close: $e');
    }
    return ViewWindowRegistry.instance.windows.isEmpty;
  }

  @override
  void onWindowClose() {
    unawaited(handleWindowClose());
  }

  /// גוף הסגירה, כ-`Future` שאפשר להמתין לו.
  ///
  /// ⚠️ נפרד מ-[onWindowClose] כי החוזה של `window_manager` הוא `void`,
  /// ורצף הסגירה — ה-flush, מחיקת הסשן והסגירה עצמה — הוא בדיוק מה שצריך
  /// להיות ניתן לבדיקה.
  ///
  /// [quit] — יציאה מהאפליקציה (⌘Q) ולא סגירת חלון: מסיים את התהליך תמיד.
  @visibleForTesting
  Future<void> handleWindowClose({
    bool Function()? canClose,
    bool quit = false,
  }) {
    if (quit) _queuedClose = null;
    final active = _activeClose;
    if (active != null) {
      if (!quit || active.quit) return Future.value();
      return active.done.then(
        (_) => handleWindowClose(canClose: canClose, quit: true),
      );
    }
    if (quit) {
      return _startWindowClose(canClose: canClose, quit: true);
    }
    final pending = _queuedClose;
    if (pending != null) return Future.value();
    late final Future<void> queued;
    queued = ViewWindowOpener.instance
        .serializeClose(() async {
          // יציאה מלאה מחליפה סגירה רגילה שעדיין ממתינה בתור.
          if (!identical(_queuedClose, queued)) return false;
          _queuedClose = null;
          await _startWindowClose(canClose: canClose, quit: false);
          return true;
        })
        .then<void>((_) {});
    _queuedClose = queued;
    return queued;
  }

  Future<void> _startWindowClose({
    bool Function()? canClose,
    required bool quit,
  }) {
    final done = _handleWindowClose(
      canClose: canClose,
      quit: quit,
    ).whenComplete(() => _activeClose = null);
    _activeClose = (done: done, quit: quit);
    return done;
  }

  Future<void> _handleWindowClose({
    bool Function()? canClose,
    required bool quit,
  }) async {
    var correctionQuitFinished = false;
    try {
      if (canClose != null && !canClose()) return;
      // יציאה מחלון Dart האחרון שואלת בו (הוא הופעל); סגירה רגילה — בחלון הזה.
      final closing = quit ? null : AppWindowKeys.byId(windowId);
      if (!await confirmAppCloseWithUnsavedChanges(
        allWindows: quit,
        window: closing,
      )) {
        return;
      }
      if (!await confirmCloseWhilePrinting()) return;
      if (canClose != null && !canClose()) return;

      // הגיבוב עשוי להימשך מעבר לכלב השמירה של הכיבוי.
      // לכן הוא רץ אחרי האישור ולפני חימושו.
      await prepareUpdateForClose?.call();

      // סגירה מסודרת: מנקה את מעקב הקריסות של התוספים ושל האתחול.
      await _runBestEffortShutdownStep(
        'pluginCrashGuardCleanShutdown',
        PluginCrashGuard.markCleanShutdown,
        timeout: const Duration(seconds: 2),
      );
      StartupCrashCounter.markStableSync();

      // מכריעים פעם אחת: ספירה חוזרת אחרי ה-flush עלולה להשלים חצי כיבוי.
      final isLast = quit || await _isLastWindowClosing();
      final endsProcess = isLast && (quit || !_keepsProcessAfterLastWindow);

      if (endsProcess) {
        if (!quit &&
            !await confirmAppCloseWithUnsavedChanges(
              allWindows: true,
              window: closing,
            )) {
          return;
        }
        if (!await finishPreparedProcessCorrectionQuit()) {
          await cancelPreparedProcessCorrectionQuit();
          UiSnack.showError(PluginMessages.correctionQuitFlushFailed);
          return;
        }
        correctionQuitFinished = true;
        // לפני הפירוק: כשל בהמשך הסגירה אינו קריסה שכדאי להציע לדווח עליה.
        AppCrashSession.markCleanExitSync();
        await _shutdownProcessUpToFlush();
      }
      // ה-flush חייב להישאר בין שני חלקי כיבוי התהליך.
      final flushFailure = await _closeWindowScoped();
      if (endsProcess) {
        await _shutdownProcessAfterFlush(flushFailure);
      } else {
        // אחרי ה-flush מוחקים סשן שנסגר במכוון; החלון האחרון במק שומר אותו.
        if (!isLast) {
          await TabsRepository().discardWindowSession();
        }

        // ה-flush של החלון האחרון ירוץ גם כאן (isolate אחד): בלי השהיה
        // הסשן שנמחק היה נכתב מחדש. הטיוטות שייכות לכל החלונות ונשארות.
        WindowTabsSession.current.suspend();
        await ViewWindowOpener.instance.beforeMainWindowHides();
        InProcessTabDrops.instance.setMainShown(false);
        // הנראות נשמרת לפי חלון: רק התוספים של הראשי מושהים.
        PluginRuntimeDispatcher.instance.setWindowShown(false);

        // ⚠️ דרך ה-runner ולא `quitApplication()`: האחרון הוא
        // `PostQuitMessage` — הוא סוגר את התוכנה כולה ולא את החלון הזה.
        await const RunnerWindowChannel().closeSelf();
      }
    } finally {
      if (!correctionQuitFinished) {
        unawaited(cancelPreparedProcessCorrectionQuit());
      }
    }
  }

  /// סגירת חלון ה-Dart האחרון כשהחלון הראשי מוסתר: יציאה מלאה מהתוכנה.
  Future<void> quitFromLastViewWindow() => handleWindowClose(quit: true);

  /// הצעדים שקודמים ל-flush — כולם פר-תהליך.
  Future<void> _shutdownProcessUpToFlush() async {
    if (kDebugMode) {
      debugPrint('Window close requested');
    }

    await _runBestEffortShutdownStep(
      'armForceExitWatchdog',
      _armForceExitWatchdog,
      timeout: const Duration(seconds: 1),
    );

    // WebView2 שנסגר משחיר את החלון והוא נראה תקוע (#3735); הכיבוי ממשיך מוסתר.
    // לא במק: הסתרה במסך מלא משאירה Space שחור (#3551).
    if (!kIsWeb && Platform.isWindows) {
      await _runBestEffortShutdownStep(
        'hideWindow',
        windowManager.hide,
        timeout: const Duration(seconds: 1),
      );
    }

    await _runBestEffortShutdownStep(
      'finishIndexingCanary',
      () async => IndexingCrashCanary.current?.finish(),
      timeout: const Duration(seconds: 1),
    );

    // סוגרים את כל ה-HTTP clients המתמשכים לפני כל ניקוי אחר. כל socket
    // פתוח מחזיק handle של kernel + state של TLS; ב-Windows admin install
    // + ריצה לא-elevated, ניקוי ה-I/O ע"י הקרנל ביציאה לוקח מספר שניות
    // (Defender real-time scan + מדיניות אמון נמוך). סגירה מקדימה משחררת
    // את ה-resources בזמן שה-UI thread עוד פעיל, ומונעת "Not Responding".
    await _runBestEffortShutdownStep(
      'closeHttpClients',
      HttpClientRegistry.closeAll,
      timeout: const Duration(seconds: 1),
    );

    await _runBestEffortShutdownStep(
      'prepareForAppShutdown',
      PluginRuntimeDispatcher.instance.prepareForAppShutdown,
      timeout: const Duration(seconds: 2),
    );
    await Future<void>.delayed(Duration.zero);
    await _runBestEffortShutdownStep(
      'shutdownForAppExit',
      WebViewEnvironmentHolder.shutdownForAppExit,
      timeout: const Duration(seconds: 8),
    );

    // Step 1: Non-critical cleanup — errors here must not block Hive.close().
    try {
      await UserBooksDatabaseHolder.instance.close();
      await SqliteDataProvider.instance.dispose(forAppExit: true);
    } catch (e) {
      if (kDebugMode) print('Non-critical cleanup error: $e');
    }
  }

  /// Step 2: Flush pending in-memory writes to Hive.
  ///
  /// הצעד היחיד שרץ גם כשהראשי רק מוסתר: [PreCloseRegistry] שוטף את
  /// הכתיבות התלויות של כל החלונות (isolate אחד).
  ///
  /// A flush failure must NOT prevent Hive.close() — closing Hive without
  /// flushing first is safe, but skipping Hive.close() would corrupt the DB.
  /// הכשל **מוחזר** לקורא ואינו נבלע כאן: [_shutdownProcessAfterFlush] הוא
  /// שמדווח עליו ל-Sentry, ובלי ההחזרה היה נעלם האות היחיד לכך שה-flush
  /// נכשל.
  Future<Object?> _closeWindowScoped() async {
    try {
      await PreCloseRegistry.runAll();
      return null;
    } on PreCloseFlushFailure catch (e) {
      if (kDebugMode) print('Flush failed at exit: $e');
      return e;
    }
  }

  /// מסלול הסגירה המלא מסתיים ב-`exit(0)` ואינו ניתן לבדיקה, אבל דווקא
  /// צעד ה-flush הוא זה שחייב להחזיר את הכשל ולא לבלוע אותו.
  @visibleForTesting
  Future<Object?> closeWindowScopedForTest() => _closeWindowScoped();

  /// Step 3: Error reporting and window destruction — כולם פר-תהליך.
  Future<void> _shutdownProcessAfterFlush(Object? flushFailure) async {
    //
    // הוסרו במכוון:
    //   - `WindowPersistence.saveNow()` — `Settings.setValue` כותב ל-Hive
    //     `app_preferences`; הקריאה תוקעת את ה-isolate ב-admin install
    //     (`Program Files\אוצריא\`) כי Defender real-time scan חוסם את
    //     ה-CloseHandle של הקובץ. מצב החלון נשמר רציף ב-`scheduleSave`
    //     (debounce 400ms על כל move/resize/maximize), אז ההלך הסופי
    //     היה belt-and-suspenders מיותר.
    //   - `await Hive.close()` — סגירת ה-handles של 7 קבצי `.hive` ב-
    //     `%APPDATA%\otzaria\` נחסמת באותה צורה. כל `box.put()` כבר כותב
    //     מיד דרך FFI ל-OS file buffer; ה-OS שוטף buffers בעת
    //     `ExitProcess`/`TerminateProcess` כשהוא סוגר את ה-handles.
    //     hive_ce שורד dirty shutdown מעיצוב (checksum על כל record).
    //     `PreCloseRegistry.runAll()` ב-step2 כבר flushed את ההיסטוריה.
    try {
      // סשני החלונות נכתבים ב-isolate; בלי ההמתנה exit חותך את הכתיבה האחרונה.
      await _runBestEffortShutdownStep(
        'flushUserStateWrites',
        UserStateDatabase.instance.flushWrites,
        timeout: const Duration(seconds: 10),
      );
      // אחרי ה-flush, שכותב ל-user_state.db — אחרת הוא היה פותח אותו מחדש.
      await _runBestEffortShutdownStep(
        'closeWritableDatabases',
        _closeWritableDatabases,
        timeout: const Duration(seconds: 2),
      );

      if (flushFailure != null) {
        // Report BEFORE Sentry.close() so the event can still be sent.
        try {
          await Sentry.captureException(
            flushFailure,
            stackTrace: StackTrace.current,
          );
        } catch (_) {
          // Sentry reporting is best-effort; never block the close path.
        }
      }

      if (!kIsWeb && Platform.isWindows) {
        // Sentry.close() calls sentry_close() through synchronous FFI on
        // Windows and can block while the native worker flushes. This path
        // exits the process immediately below, so don't delay app shutdown
        // for telemetry cleanup.
      } else {
        await Sentry.close();
      }

      // ⚠️ אחרי השטיפה, כך שהסשנים שלהם נשמרים; בלי Job Object היו נשארים
      // על המסך עד `exit(0)`.
      ViewWindowOpener.instance.destroyAllForQuit();

      if (!kIsWeb &&
          (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
        if (Platform.isWindows) {
          // קריאה ל-TerminateProcess(GetCurrentProcess(), 0) דרך ה-runner.
          // קופצת מעל atexit (כולל sentry-native flush שלוקח כמה שניות),
          // DLL_PROCESS_DETACH, Dart VM teardown, ומסירה את צורך לבנות
          // graceful shutdown. תהליכי WebView2 ילדים נהרגים אוטומטית דרך
          // ה-Job Object שאליו ה-runner משייך אותם. כל נתון חיוני שלנו
          // (Hive write-through, SQLite WAL) כבר מסומן עמיד ל-dirty
          // shutdown לפני הנקודה הזו.
          //
          // ההנדלר הילידי מחזיר false כאשר ה-Job Object לא הוקם בהצלחה
          // (סביבות sandboxed, debugger jobs, MDM/AV). במקרה כזה אסור
          // לקרוא ל-TerminateProcess משלנו כי תהליכי WebView2 ילדים
          // יהיו יתומים — אנחנו נופלים בחזרה ל-graceful close המקורי.
          bool? terminateAttempted;
          try {
            terminateAttempted = await _processControlChannel
                .invokeMethod<bool>('forceTerminate');
          } catch (e, stackTrace) {
            _logForceTerminateFailure(
              'invokeMethod threw: $e',
              stackTrace.toString(),
            );
            terminateAttempted = null;
          }
          if (terminateAttempted == true) {
            // לעולם לא אמורים להגיע לכאן — TerminateProcess הרגה אותנו
            // ב-handler הילידי. אם בכל זאת חזרנו, התהליך הילידי הצליח
            // להשיב true אבל TerminateProcess עצמו נכשל איכשהו (תרחיש
            // תיאורטי). exit(0) כ-last resort.
            _logForceTerminateFailure(
              'forceTerminate returned true but did not terminate',
              null,
            );
            exit(0);
          }
          if (terminateAttempted == false) {
            // job_object_ready=false ב-runner — סביבה sandboxed / debugger
            // / MDM שמנעה את ה-Job Object containment. אין כאן fallback
            // מקסימלי באמת: `quitApplication()` הוא `PostQuitMessage`, שמפיל
            // את המנוע תחת Dart רץ, ואין דרך אחרת להבטיח הריגה אטומית של
            // תהליכי WebView2 ילדים.
            //
            // מה שאנחנו עושים: נותנים ל-IPC של WebView2 SDK חלון של ~500ms
            // לסיים את ה-shutdown של תהליכי Edge — `shutdownForAppExit`
            // למעלה כבר יזם dispose של ה-environment, אבל ההודעות לילדים
            // אסינכרוניות. אחרי ההמתנה אנחנו פולטים ל-exit(0) הרגיל —
            // **אותה התנהגות בדיוק שהייתה לפני שינוי forceTerminate**.
            // המשמעות: סביבות שבהן Job Object נכשל לא מקבלות את ה-fast
            // exit, אבל גם לא מאבדות שום הגנה שהייתה להן קודם.
            _logForceTerminateFailure(
              'Job Object not ready in native runner — degraded close, '
              'WebView2 children may still orphan',
              null,
            );
            await Future<void>.delayed(const Duration(milliseconds: 500));
          }
          // ב-Windows `exit(0)` ולא `quitApplication()`. כשה-Job Object הוקם
          // (המצב הרגיל) TerminateProcess כבר הרג אותנו ולא נגיע לכאן.
          exit(0);
        }

        // ⚠️ `setPreventClose(true)` נקבע לפני `runApp`, ולכן
        // `window_manager` בולע את `WM_CLOSE` ומחזיר `-1` — כלומר מסלול
        // ה-hide אינו נגיש בחלון הראשי, וכל מסלולי הסגירה שלו (X, Alt+F4,
        // "סיים משימה") עוברים דרך Dart. זו הסיבה שהמעבר ל"מוסתר ולא
        // נהרס" לא השאיר את התהליך תלוי.
        await windowManager.setPreventClose(false);
        // ⚠️ macOS/Linux בלבד. ב-Windows המסלול הסתיים ב-`exit(0)` שמעל —
        // ראו האזהרה בתיעוד של `quitApplication`.
        await allowMacOSApplicationTermination();
        await _window.quitApplication();
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error during window close: $e');
      }
      // נשמור על exit(0) רק למקרה חירום של קריסה בתהליך הסגירה
      exit(0);
    }
  }

  /// כותב שורה לקובץ `%TEMP%\otzaria_shutdown_errors.log` כשמסלול ה-fast-exit
  /// נכשל. עוזר לאבחן תלונות עתידיות של "לפעמים הסגירה איטית" — בלי הלוג
  /// הזה אין שום אינדיקציה למה ה-Job Object לא הוקם או למה ה-channel
  /// כשל. ה-I/O סינכרוני כדי להבטיח שהשורה נכתבת לפני exit(0).
  void _logForceTerminateFailure(String reason, String? stackTrace) {
    if (!Platform.isWindows) return;
    try {
      final temp = Platform.environment['TEMP'] ?? r'C:\Users\Public';
      final logPath = '$temp\\otzaria_shutdown_errors.log';
      final timestamp = DateTime.now().toIso8601String();
      final line = stackTrace == null
          ? '$timestamp | $reason\n'
          : '$timestamp | $reason\n  $stackTrace\n';
      File(logPath).writeAsStringSync(line, mode: FileMode.append);
    } catch (_) {
      // I/O failure must never block exit.
    }
  }

  /// מזהה החלון שה-listener הזה משרת. היום יש חלון אחד.
  final AppWindowId windowId;

  @override
  void onWindowEvent(String eventName) {
    // window_manager forwards native show/hide through the generic callback.
    // They have no dedicated WindowListener callbacks and need not change focus.
    if (eventName == 'hide') {
      PluginRuntimeDispatcher.instance.setWindowShown(false);
    } else if (eventName == 'show') {
      PluginRuntimeDispatcher.instance.setWindowShown(true);
    }
  }

  @override
  void onWindowFocus() {
    // מקש שהוחזק במעבר חלון ושוחרר בחוץ נשאר "תקוע" (אין KeyUpEvent) וגורם
    // ל-assertion במקש הבא. משחררים אותו דרך מסלול האירועים הרגיל — לא
    // clearState(), שמוחק את כל ה-handlers (קיצורי המפרשים, issue #1071).
    final keyboard = HardwareKeyboard.instance;
    for (final physicalKey in keyboard.physicalKeysPressed.toList()) {
      final logicalKey = keyboard.lookUpLayout(physicalKey);
      if (logicalKey == null) continue;
      keyboard.handleKeyEvent(
        KeyUpEvent(
          physicalKey: physicalKey,
          logicalKey: logicalKey,
          timeStamp: Duration.zero,
          synthesized: true,
        ),
      );
    }
    AppWindowKeys.activateWindow(windowId);
    ViewFocusSync.mainWindowActivated();
    // חלון שהוחזר מהסתרה מקבל פוקוס — זה האות שהוא מוצג שוב.
    PluginRuntimeDispatcher.instance.setWindowShown(true);
    WindowTabsSession.current.resume();
    InProcessTabDrops.instance.setMainShown(true);
  }

  @override
  void onWindowBlur() {
    if (kDebugMode) {
      //print('Window blurred');
    }
  }

  @override
  void onWindowMinimize() {
    if (kDebugMode) {
      debugPrint('Window minimized');
    }
    _minimized = true;
    // ממוזער אינו מוצג: התוספים שבו מושהים עד השחזור.
    PluginRuntimeDispatcher.instance.setWindowMinimized(true);
  }

  @override
  void onWindowRestore() {
    if (kDebugMode) {
      debugPrint('Window restored');
    }
    _notifyRestoredFromMinimize();
    onWindowStateChanged?.call();
  }

  @override
  void onWindowResize() {
    if (kDebugMode) {
      debugPrint('Window resized');
    }

    if (WindowPersistence.isRestoring) return;
    WindowPersistence.scheduleSave();
    onWindowResizeOccurred?.call();
  }

  @override
  void onWindowMove() {
    if (kDebugMode) {
      debugPrint('Window moved');
    }

    if (WindowPersistence.isRestoring) return;
    WindowPersistence.scheduleSave();
  }

  @override
  void onWindowMaximize() {
    if (kDebugMode) {
      debugPrint('Window maximized');
    }
    // חלון שהיה מוגדל לפני המיזעור חוזר כ-maximize ולא כ-restore.
    _notifyRestoredFromMinimize();
    if (WindowPersistence.isRestoring) return;
    WindowPersistence.scheduleSave();
    onWindowStateChanged?.call();
  }

  @override
  void onWindowUnmaximize() {
    if (kDebugMode) {
      debugPrint('Window unmaximized');
    }
    if (WindowPersistence.isRestoring) return;
    WindowPersistence.scheduleSave();
    onWindowStateChanged?.call();
  }
}
