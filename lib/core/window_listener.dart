import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';
import 'package:otzaria/core/http_client_registry.dart';
import 'package:otzaria/core/pre_close_registry.dart';
import 'package:otzaria/core/window_persistence.dart';
import 'package:otzaria/core/windowing/app_window_controller.dart';
import 'package:otzaria/core/windowing/app_window_id.dart';
import 'package:otzaria/core/windowing/window_manager_app_window_controller.dart';
import 'package:otzaria/core/windowing/last_active_window.dart';
import 'package:otzaria/core/windowing/multi_window_service.dart';
import 'package:otzaria/core/windowing/window_bus.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:otzaria/data/data_providers/user_books_database_holder.dart';
import 'package:otzaria/plugins/services/plugin_crash_guard.dart';
import 'package:otzaria/plugins/services/plugin_runtime_dispatcher.dart';
import 'package:otzaria/plugins/view/webview_environment_holder.dart';
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
    // הערוץ היה חד-כיווני (Dart → נייטיב) עד כאן. כיבוי מערכת הוא המקרה
    // הראשון שבו הנייטיב צריך לקרוא **לנו**.
    _processControlChannel.setMethodCallHandler(_handleProcessControlCall);
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
        final flushFailure = await _closeWindowScoped();
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

  /// האם זה החלון האחרון, כלומר האם סגירתו היא סגירת התהליך.
  ///
  /// ⚠️ ה-runner הוא מקור האמת. ה-isolate של כל חלון רואה רק את עצמו,
  /// ולכן חלון אינו יכול לדעת מ-Dart בלבד אם נותרו אחרים. כשהתשובה אינה
  /// ידועה נופלים ל-[WindowBus.hasOtherWindows] — בדיקה סינכרונית שאינה
  /// יכולה לפקוע — ולא להנחה, שהרי "אני האחרון" מסתיים ב-`exit(0)` שהורג
  /// גם את החלונות האחרים.
  Future<bool> _isLastWindowClosing() async {
    try {
      // ⚠️ timeout חובה. השאלה הזו יושבת **לפני** חימוש שעון היציאה הכפויה
      // (הצעד הראשון ב-`_shutdownProcessUpToFlush`), ולכן ערוץ שלא עונה
      // היה משאיר את החלון פתוח ואת התהליך חי בלי שום רשת ביטחון —
      // המשתמש לוחץ X ושום דבר לא קורה, לנצח.
      final info = await const MultiWindowService().windowCount().timeout(
        const Duration(seconds: 2),
      );
      if (info != null) return info.count <= 1;
    } catch (e) {
      debugPrint('windowCount failed during close: $e');
    }
    return !WindowBus.instance.hasOtherWindows;
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
  @visibleForTesting
  Future<void> handleWindowClose() async {
    if (_isClosing) {
      return;
    }
    // לפני _isClosing וכלב-השמירה: ביטול חייב להשאיר את התוכנה שלמה.
    if (!await confirmAppCloseWithUnsavedChanges()) return;
    if (_isClosing) {
      return;
    }
    _isClosing = true;

    // ⚠️ **לפני** ההכרעה מי האחרון. סגירה של כמה חלונות יחד יכולה לגמור
    // ב-`TerminateProcess` של ה-runner בלי ששום חלון ריץ את הכיבוי המסודר,
    // ואז ה-canary נשאר וההפעלה הבאה מסרבת לטעון את התוספים. אידמפוטנטי.
    PluginCrashGuard.markCleanShutdownSync();

    // ⚠️ הפיצול הוא לפי *בעלות* — מה פר-חלון ומה פר-תהליך — ולא לפי סדר.
    // הצעד הפר-חלוני היחיד הוא ה-flush, והוא יושב באמצע רצף פר-תהליכי:
    // אחרי סגירת ה-DB ולפני הדיווח והריגת התהליך. לכן החלק הפר-תהליכי
    // מפוצל לשניים סביבו. **הסדר בין שלושת החלקים זהה לסדר המקורי של
    // הצעדים, ואסור לשנותו** — הרצת ה-flush ראשון תקדים אותו לסגירת ה-DB.
    // ⚠️ נשאל **פעם אחת**, בתחילת הסגירה. שאלה חוזרת אחרי ה-flush עלולה
    // לקבל תשובה אחרת אם חלון אחר נסגר בינתיים, והתוצאה תהיה חצי כיבוי:
    // הצעדים שלפני ה-flush רצו והצעדים שאחריו לא, או להפך.
    final isLast = await _isLastWindowClosing();

    if (isLast) {
      await _shutdownProcessUpToFlush();
    }
    final flushFailure = await _closeWindowScoped();
    if (isLast) {
      await _shutdownProcessAfterFlush(flushFailure);
    } else {
      // חלון אחד מתוך כמה: לסגור רק אותו. `setPreventClose(true)` מנע את
      // הסגירה הרגילה, ובלי הסגירה המפורשת החלון היה נשאר פתוח.
      //
      // ⚠️ אחרי ה-flush ולפני הסגירה. המשתמש סגר את החלון הזה במכוון,
      // ולכן הסשן שלו אינו "פתוח" יותר: השארתו הייתה מחזירה בהפעלה הבאה
      // כרטיסיות שהוא בחר לסגור (`adoptOrphanWindowSessions`).
      // `Ctrl+Shift+T` אינו נשען עליו אלא על המנוע שנשאר חי בזיכרון.
      await TabsRepository().discardWindowSession();

      // ⚠️ דרך ה-runner ולא `_window.destroy()`: זה האחרון הורס את החלון
      // מתוך טיפול בערוץ, והריסת מנוע משם היא ריאנטרנטית ומפילה את
      // התהליך. ה-runner דוחה את ההריסה לאיטרציה הבאה של לולאת ההודעות.
      await const MultiWindowService().closeSelf();
      // ⚠️ החלון מוסתר ולא נהרס, וה-listener שלו חי. חלון שיוחזר לשימוש
      // (`ReviveWith` / Ctrl+Shift+T) חייב שסגירה חוזרת שלו תעבוד — עם
      // דגל שנשאר דלוק לחיצה על X פשוט לא הייתה עושה כלום.
      _isClosing = false;
    }
  }

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
  }

  /// Step 2: Flush pending in-memory writes to Hive.
  ///
  /// זהו הצעד הפר-חלוני היחיד ברצף: [PreCloseRegistry] הוא סינגלטון
  /// פר-isolate, ולכן הוא שוטף את הכתיבות התלויות של החלון הזה בלבד.
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
  /// הצעד הפר-חלוני הוא זה שחייב להחזיר את הכשל ולא לבלוע אותו.
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
            // ⚠️ מספר המנועים החיים נרשם כאן, וזה המידע שחסר לאבחון.
            //
            // המסלול הזה מסתיים ב-`exit(0)` של Dart, שמריץ teardown של
            // ה-VM — ו-P-2 מדד שזה מפיל את הבדיקה
            // "Isolate main is owned by os thread X, failed to schedule
            // from os thread Y" ב-~1% מהיציאות **כשמנוע אחר חי**. המסלול
            // הרגיל (`TerminateProcess`) חסין, כי הוא אינו מריץ teardown
            // בכלל.
            //
            // חלון סגור מוסתר ולא נהרס, ולכן `engines` יכול להיות 4 בעוד
            // `count` הוא 1 — ובלי המספר הזה בלוג אין דרך לדעת אם קריסת
            // יציאה שדווחה הייתה בתצורה המסוכנת.
            final live = await const MultiWindowService().windowCount().timeout(
              const Duration(seconds: 1),
              onTimeout: () => null,
            );
            final engines = live?.engines;
            _logForceTerminateFailure(
              'Job Object not ready in native runner — degraded close, '
              'WebView2 children may still orphan; '
              'live engines=${engines ?? 'unknown'} '
              'visible windows=${live?.count ?? 'unknown'}'
              '${engines != null && engines > 1 ? ' — exit() teardown is unsafe here' : ''}',
              null,
            );
            await Future<void>.delayed(const Duration(milliseconds: 500));
          }
          // Windows path מאז ומעולם — exit(0) במקום windowManager.destroy.
          // כשה-Job Object כן הוקם (המצב הרגיל), TerminateProcess כבר
          // הרג אותנו ולא נגיע לכאן.
          exit(0);
        }

        // ⚠️ `setPreventClose(true)` נקבע לפני `runApp`, ולכן
        // `window_manager` בולע את `WM_CLOSE` ומחזיר `-1` — כלומר מסלול
        // ה-hide אינו נגיש בחלון הראשי, וכל מסלולי הסגירה שלו (X, Alt+F4,
        // "סיים משימה") עוברים דרך Dart. זו הסיבה שהמעבר ל"מוסתר ולא
        // נהרס" לא השאיר את התהליך תלוי.
        await windowManager.setPreventClose(false);
        // סגירה רגילה דרך ה-WindowManager
        await _window.destroy();
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
    LastActiveWindow.markActive(windowId);
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
      // ⚠️ רשימת ה-listeners של `window_manager` היא פר-isolate, ולכן אין
      // כאן מה לרשום במקום מרכזי — חלון אינו יכול לרשום listener בחלון
      // אחר. מה שכן צריך תשומת לב: `dispose` **אינו נקרא** כשחלון נסגר,
      // כי הוא מוסתר ולא נהרס ועץ ה-widgets אינו מתפרק. ניקוי שחייב
      // לקרות בסגירת חלון תולים על המסלול שקורא ל-`closeSelf`.
      windowManager.removeListener(this);
    }
  }
}
