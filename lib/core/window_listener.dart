import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';
import 'package:otzaria/core/http_client_registry.dart';
import 'package:otzaria/core/pre_close_registry.dart';
import 'package:otzaria/core/window_persistence.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:otzaria/data/data_providers/user_books_database_holder.dart';
import 'package:otzaria/plugins/services/plugin_runtime_dispatcher.dart';
import 'package:otzaria/plugins/view/webview_environment_holder.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

/// Callback type for fullscreen state changes
typedef FullscreenCallback = void Function(bool isFullscreen);

/// Window listener that handles window events properly to prevent crashes
class AppWindowListener extends WindowListener {
  static const MethodChannel _processControlChannel = MethodChannel(
    'otzaria/process_control',
  );

  FullscreenCallback? onFullscreenChanged;

  /// נקרא לאחר אירועי מצב חלון דיסקרטיים שעלולים לגרום לאיבוד פוקוס:
  /// maximize, unmaximize, restore, כניסה/יציאה ממסך מלא.
  VoidCallback? onWindowStateChanged;

  /// נקרא בכל אירוע resize רציף — מיועד ל-debounced restore.
  VoidCallback? onWindowResizeOccurred;
  bool _isClosing = false;

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

  @override
  void onWindowClose() async {
    if (_isClosing) {
      return;
    }
    _isClosing = true;

    if (kDebugMode) {
      debugPrint('Window close requested');
    }

    await _runBestEffortShutdownStep(
      'armForceExitWatchdog',
      _armForceExitWatchdog,
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
      await SqliteDataProvider.instance.dispose();
    } catch (e) {
      if (kDebugMode) print('Non-critical cleanup error: $e');
    }

    // Step 2: Flush pending in-memory writes to Hive.
    // A flush failure must NOT prevent Hive.close() — closing Hive without
    // flushing first is safe, but skipping Hive.close() would corrupt the DB.
    Object? flushFailure;
    try {
      await PreCloseRegistry.runAll();
    } on PreCloseFlushFailure catch (e) {
      flushFailure = e;
      if (kDebugMode) print('Flush failed at exit: $e');
    }

    // Step 3: Error reporting and window destruction.
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
            // מקסימלי באמת: `windowManager.destroy()` ידוע שעוצר את ה-
            // Engine מיד וזה מסוכן בנתיב הזה (ראה ההערה המקורית למטה),
            // ואין דרך אחרת להבטיח הריגה אטומית של תהליכי WebView2 ילדים.
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
              'WebView2 children may still orphan (pre-fix behavior)',
              null,
            );
            await Future<void>.delayed(const Duration(milliseconds: 500));
          }
          // Windows path מאז ומעולם — exit(0) במקום windowManager.destroy.
          // כשה-Job Object כן הוקם (המצב הרגיל), TerminateProcess כבר
          // הרג אותנו ולא נגיע לכאן.
          exit(0);
        }

        await windowManager.setPreventClose(false);
        // סגירה רגילה דרך ה-WindowManager
        await windowManager.destroy();
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

  @override
  void onWindowFocus() {
    if (kDebugMode) {
      //print('Window focused');
    }
    // איפוס מצב המקלדת בעת קבלת פוקוס, למנוע AssertionError ב-HardwareKeyboard
    // כאשר המשתמש מחזיק מקש, מחליף חלון, ומשחרר - Flutter לא מקבל KeyUpEvent
    // ובעת חזרה לחלון, מקש ה-KeyDown הבא גורם ל-assertion failure
    // ignore: invalid_use_of_visible_for_testing_member
    HardwareKeyboard.instance.clearState();
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
  }

  @override
  void onWindowRestore() {
    if (kDebugMode) {
      debugPrint('Window restored');
    }
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

  /// Clean up the listener when disposing
  void dispose() {
    // Remove this listener from window manager
    if (!kIsWeb &&
        (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      windowManager.removeListener(this);
    }
  }
}
