import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_inappwebview_windows/flutter_inappwebview_windows.dart'
    show WindowsWebViewHwndFallbacks;
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/core/startup_timeline.dart';
import 'package:otzaria/core/directory_writability.dart';
import 'package:otzaria/plugins/services/plugin_asset_scheme.dart';
import 'package:otzaria/plugins/services/plugin_webview_failure_log.dart';
import 'package:otzaria/plugins/services/webview2_creation_diagnostics.dart';

/// מתאם חימום WebView וב-Windows מחזיק סביבת WebView2 עם תיקיית נתונים
/// הניתנת לכתיבה ב-APPDATA, כדי שלא לכתוב לצד ה-EXE ב-Program Files.
class WebViewEnvironmentHolder {
  static WebViewEnvironment? _environment;
  // Coalesces concurrent init calls (background host vs. plugin tab): two
  // callers racing past the null guard would spawn two Edge process trees.
  static Future<void>? _initializeFuture;
  static StreamSubscription<void>? _hwndFallbackSubscription;
  static const MethodChannel _nativeShutdownChannel = MethodChannel(
    'com.pichillilorenzo/flutter_inappwebview_manager',
  );

  /// מחזיר את ה-WebViewEnvironment שנוצר באתחול, או null בפלטפורמות שאינן Windows.
  static WebViewEnvironment? get environment => _environment;

  /// override לבדיקות בלבד: כשמוגדר, [isRuntimeAvailable] מחזיר את ערכו
  /// במקום לפנות ל-platform channel (שאינו זמין בטסטים).
  static bool? _runtimeAvailableOverride;

  /// מגדיר ערך קבוע ל-[isRuntimeAvailable] בבדיקות. העבר `null` לאיפוס.
  @visibleForTesting
  static void debugOverrideRuntimeAvailable(bool? value) {
    _runtimeAvailableOverride = value;
  }

  /// override לבדיקות בלבד: מחליף את גוף [initialize]. בלעדיו הבדיקה יוצרת
  /// סביבת WebView2 אמיתית — נתקעת ב-flutter_tester שאין בו platform channel.
  static Future<void> Function()? _initializeOverride;

  /// מחליף את מימוש [initialize] בבדיקות. העבר `null` לאיפוס.
  @visibleForTesting
  static void debugOverrideInitialize(Future<void> Function()? override) {
    _initializeOverride = override;
  }

  /// בודק אם WebView2 Runtime מותקן במחשב (Windows בלבד).
  ///
  /// מחזיר `true` בכל פלטפורמה שאינה Windows — שם הבדיקה אינה רלוונטית.
  /// ב-Windows מחזיר `false` כאשר לא נמצא WebView2 Runtime מותקן, מצב שבו
  /// יצירת [WebViewEnvironment]/[InAppWebView] נכשלת. הבדיקה מאפשרת להציג
  /// למשתמש מסך הכוונה להתקנת ה-Runtime במקום שגיאה טכנית גולמית.
  ///
  /// מסתמך על [WebViewEnvironment.getAvailableVersion] שמחזיר `null` כשאין
  /// התקנה זמינה. כל חריגה נחשבת אף היא כ"חסר", כי משמעותה שלא ניתן לוודא
  /// קיום Runtime תקין.
  static Future<bool> isRuntimeAvailable() async {
    if (_runtimeAvailableOverride != null) return _runtimeAvailableOverride!;
    if (!Platform.isWindows) return true;
    try {
      final version = await WebViewEnvironment.getAvailableVersion();
      WebView2CreationDiagnostics.runtimeVersion = version;
      return version != null && version.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// override לבדיקות בלבד: כשמוגדר, [checkDataFolderWritable] מחזיר את ערכו
  /// במקום לגעת בדיסק.
  static String? _unwritableDataFolderOverride;
  static bool _hasUnwritableDataFolderOverride = false;

  /// מגדיר ערך קבוע ל-[checkDataFolderWritable] בבדיקות. העבר `null` לנתיב חסום
  /// מדומה; קרא ל-[debugClearUnwritableDataFolder] לאיפוס.
  @visibleForTesting
  static void debugOverrideUnwritableDataFolder(String? path) {
    _unwritableDataFolderOverride = path;
    _hasUnwritableDataFolderOverride = true;
    _unwritableDataFolder = path;
  }

  @visibleForTesting
  static void debugClearUnwritableDataFolder() {
    _hasUnwritableDataFolderOverride = false;
    _unwritableDataFolderOverride = null;
    _unwritableDataFolder = null;
  }

  static String? _unwritableDataFolder;

  /// הנתיב שנמצא חסום-לכתיבה בבדיקה האחרונה, או `null` כשהכל תקין.
  static String? get unwritableDataFolder => _unwritableDataFolder;

  /// בודק שתיקיית הנתונים של WebView2 ניתנת לכתיבה, ומחזיר את הנתיב החסום
  /// (או `null` כשהכל תקין). תת-תיקיית EBWebView נבדקת בנפרד — ACL של מנהל
  /// עליה חוסם רק אותה.
  ///
  /// בלי הבדיקה הכשל מתגלה רק בתוך WebView2, שמציג דיאלוג מערכת של Edge
  /// במקום הסבר (issue #1031).
  static Future<String?> checkDataFolderWritable() async {
    if (_hasUnwritableDataFolderOverride) return _unwritableDataFolderOverride;
    if (!Platform.isWindows) return _unwritableDataFolder = null;

    final root = p.join(await AppPaths.getDataRootPath(), 'webview2');
    if (!await isDirectoryWritable(root)) return _unwritableDataFolder = root;

    // EBWebView נוצרת ע"י WebView2 עצמו — כשאינה קיימת היא תירש את הרשאות
    // תיקיית האם, שכבר נבדקו.
    final profile = p.join(root, 'EBWebView');
    if (await FileSystemEntity.type(profile) != FileSystemEntityType.notFound &&
        !await isDirectoryWritable(profile)) {
      return _unwritableDataFolder = profile;
    }
    return _unwritableDataFolder = null;
  }

  /// מאתחל לפני יצירת WebView; קוראים מקבילים חולקים Future שניתן לנסות שוב בכשל.
  /// ב-Android רק ממתין לחימום שכבר התחיל, בלי ליצור WebView2 environment.
  /// יש לקרוא לפני כל API של Android שעשוי לאתחל WebView, כולל debugging.
  /// [dataFolderChecked] חוסך בדיקה חוזרת כשהקורא כבר בדק כתיבה מיד לפני הקריאה.
  static Future<void> initialize({bool dataFolderChecked = false}) {
    if (_initializeOverride != null) return _initializeOverride!();
    if (!_isWindows) {
      return _isAndroid ? _awaitPrewarm() : Future<void>.value();
    }
    if (_environment != null) return Future<void>.value();
    return _initializeFuture ??= _runInitialize(
      checkDataFolder: !dataFolderChecked,
    );
  }

  static Future<void> _runInitialize({required bool checkDataFolder}) async {
    String? webviewDataFolder;
    try {
      final dataRoot = await AppPaths.getDataRootPath();
      webviewDataFolder = p.join(dataRoot, 'webview2');
      await Directory(webviewDataFolder).create(recursive: true);
      final blocked = checkDataFolder ? await checkDataFolderWritable() : null;
      if (blocked != null) {
        // WebView2 היה מגיב לזה בדיאלוג מערכת של Edge; עצירה כאן משאירה
        // את ההסבר בידי PluginDataFolderUnwritableView.
        throw FileSystemException(
          'WebView2 data folder is not writable',
          blocked,
        );
      }
      // ארגומנטים שעוקפים את גלילת Chromium גורמים לפריימים תקועים בטאצ׳פד.
      // מדידה: integration_test/webview_scroll_smoothness_probe_test.dart.
      // מונע ממופע אחר לשתף את תהליך הדפדפן שמחזיק בתיקייה; במקרה של
      // התנגשות WebView2 דוחה את יצירת ה-controller והכשל נרשם בדיאגנוסטיקה.
      await _awaitPrewarm();
      final environment = await WebViewEnvironment.create(
        settings: _environmentSettings(webviewDataFolder),
      );
      environment.onBrowserProcessExited = _logAbnormalBrowserExit;
      _environment = environment;
      // כל WebView שעולה מכאן, טאב או מופע רקע, נרשם אם נסוג למצב HWND.
      _hwndFallbackSubscription ??= WindowsWebViewHwndFallbacks.stream.listen(
        logPluginWebViewHwndFallback,
      );
    } catch (error, stackTrace) {
      // כשל כאן = כל התוספים יעלו ריקים; בלי הרישום אין לזה שום עקבות.
      logPluginWebViewFailure(
        'WebView2 environment init failed',
        error,
        stackTrace: stackTrace,
        details: {
          'UserDataFolder': webviewDataFolder,
          'Prewarm': WebView2CreationDiagnostics.prewarmOutcome,
        },
        creationFailure: true,
      );
      rethrow;
    } finally {
      // בהצלחה: _environment מוגדר, ה-guard בכניסה ל-initialize יחזיר
      // מיידית. בכישלון: _environment עדיין null וקריאה הבאה לא תיתפס
      // ע"י future ישן עם שגיאה ישנה — היא תתחיל ניסיון אתחול חדש.
      _initializeFuture = null;
    }
  }

  static Future<WebViewEnvironmentPrewarmResult?> Function(
    WebViewEnvironmentSettings settings,
  )?
  _prewarmOverride;

  /// מחליף את הקריאה הנייטיבית של [prewarm] בבדיקות. העבר `null` לאיפוס.
  @visibleForTesting
  static void debugOverridePrewarm(
    Future<WebViewEnvironmentPrewarmResult?> Function(
      WebViewEnvironmentSettings settings,
    )?
    override,
  ) {
    _prewarmOverride = override;
  }

  @visibleForTesting
  static bool? debugIsWindowsOverride;

  static bool get _isWindows => debugIsWindowsOverride ?? Platform.isWindows;

  static bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// הפורק מממש חימום רקע ב-Windows וב-Android בלבד.
  static bool get supportsPrewarm => !kIsWeb && (_isWindows || _isAndroid);

  static Future<void>? _prewarmInFlight;
  static Future<void>? _waitedPrewarm;
  static Future<void>? _prewarmWait;
  @visibleForTesting
  static Duration prewarmWaitLimit = const Duration(seconds: 30);

  /// מחמם את המנוע ברקע בלי ליצור WebView. נקרא במסלול האתחול הדחוי,
  /// אחרי הצגת האפליקציה. מחזיר false כשדולג או בפלטפורמה שאינה תומכת.
  static Future<bool> prewarm({
    required Future<bool> Function() hasEnabledPlugin,
  }) async {
    if (!supportsPrewarm) {
      _recordPrewarm('unsupported');
      return false;
    }
    if (_environment != null || _initializeFuture != null) {
      _recordPrewarm('skipped: environment exists');
      return false;
    }
    // Publish the gate before eligibility awaits: Android creation must
    // not slip through while the enabled-plugin lookup is still pending.
    if (_prewarmInFlight != null) return false;
    final done = Completer<void>();
    _prewarmInFlight = done.future;
    try {
      if (!await hasEnabledPlugin()) {
        _recordPrewarm('skipped: no enabled plugin');
        return false;
      }
      // Creation may have timed out and proceeded. Never start a late
      // native prewarm after this operation lost its gate.
      if (!identical(_prewarmInFlight, done.future)) return false;
      if (_environment != null || _initializeFuture != null) {
        _recordPrewarm('skipped: environment exists');
        return false;
      }
      // Android מנהל את הפרופיל בעצמו. אין גישה ל-AppPaths או להגדרות
      // UDF/custom schemes של WebView2 במסלול הזה.
      final settings = _isWindows
          ? _environmentSettings(
              p.join(await AppPaths.getDataRootPath(), 'webview2'),
            )
          : WebViewEnvironmentSettings();
      if (!identical(_prewarmInFlight, done.future)) return false;
      final result =
          await (_prewarmOverride ??
              (settings) =>
                  WebViewEnvironment.prewarm(settings: settings))(settings);
      _recordPrewarm(result?.toString() ?? 'unsupported');
      return true;
    } catch (error) {
      _recordPrewarm('error: $error');
      rethrow;
    } finally {
      if (identical(_prewarmInFlight, done.future)) _prewarmInFlight = null;
      done.complete();
    }
  }

  // יצירה ב-thread ה-UI בזמן שהחימום עוד טוען הייתה נחסמת בטעינת ה-DLL;
  // ההמתנה כאן אסינכרונית ומוגבלת.
  static Future<void> _awaitPrewarm() {
    final prewarm = _prewarmInFlight;
    if (prewarm == null) return Future<void>.value();
    // Every consumer of this operation shares the same bounded wait.
    // A later consumer must not keep waiting after the first timeout.
    if (identical(_waitedPrewarm, prewarm)) return _prewarmWait!;
    _waitedPrewarm = prewarm;
    return _prewarmWait = _waitForPrewarm(prewarm);
  }

  static Future<void> _waitForPrewarm(Future<void> prewarm) async {
    final waited = Stopwatch()..start();
    await prewarm.timeout(
      prewarmWaitLimit,
      // תשובה נייטיבית שלא הגיעה לא תעכב שוב כל ניסיון אתחול.
      onTimeout: () {
        if (identical(_prewarmInFlight, prewarm)) _prewarmInFlight = null;
      },
    );
    WebView2CreationDiagnostics.prewarmOutcome =
        '${WebView2CreationDiagnostics.prewarmOutcome ?? 'pending'}; '
        'initialize waited ${waited.elapsedMilliseconds}ms';
  }

  static void _recordPrewarm(String outcome) {
    final launchedAt = StartupTimeline.instance.startedAt;
    final at = launchedAt == null
        ? ''
        : ', ended +${DateTime.now().difference(launchedAt).inMilliseconds}ms '
              'after launch';
    WebView2CreationDiagnostics.prewarmOutcome = '$outcome$at';
  }

  static int _browserExitsLogged = 0;
  static const int _maxBrowserExitsLogged = 3;

  // יציאה תקינה (סגירת כל ה-WebViews או של התוכנה) אינה נרשמת.
  static void _logAbnormalBrowserExit(BrowserProcessExitedDetail detail) {
    if (detail.kind.toValue() == BrowserProcessExitKind.NORMAL.toValue()) {
      return;
    }
    if (_browserExitsLogged >= _maxBrowserExitsLogged) return;
    _browserExitsLogged++;
    logPluginWebViewFailure(
      'WebView2 browser process exited',
      detail.kind.name(),
      details: {'ProcessId': detail.processId?.toString()},
    );
  }

  @visibleForTesting
  static void debugBrowserProcessExited(BrowserProcessExitedDetail detail) =>
      _logAbnormalBrowserExit(detail);

  @visibleForTesting
  static void debugResetBrowserExitCount() => _browserExitsLogged = 0;

  @visibleForTesting
  static WebViewEnvironmentSettings debugEnvironmentSettings(
    String userDataFolder,
  ) => _environmentSettings(userDataFolder);

  static WebViewEnvironmentSettings _environmentSettings(
    String userDataFolder,
  ) => WebViewEnvironmentSettings(
    userDataFolder: userDataFolder,
    exclusiveUserDataFolderAccess: true,
    // בלי רישום ה-scheme אינו נטען כלל, ועם treatAsSecure מודולים ו-fetch עובדים בו.
    customSchemeRegistrations: [
      CustomSchemeRegistration(
        scheme: pluginAssetScheme,
        treatAsSecure: true,
        hasAuthorityComponent: true,
      ),
    ],
  );

  /// Disposes the current Windows WebView environment after the old widget
  /// tree has been torn down during an in-process app restart.
  static Future<void> disposeForAppRestart() async {
    if (!_isWindows) return;

    final environment = _environment;
    _environment = null;
    if (environment == null) return;

    environment.onNewBrowserVersionAvailable = null;
    environment.onBrowserProcessExited = null;
    environment.onProcessInfosChanged = null;

    try {
      await environment.dispose();
    } catch (_) {}
  }

  /// Best-effort teardown for process exit on Windows.
  static Future<void> shutdownForAppExit() async {
    if (!Platform.isWindows) return;

    final environment = _environment;
    _environment = null;

    if (environment != null) {
      environment.onNewBrowserVersionAvailable = null;
      environment.onBrowserProcessExited = null;
      environment.onProcessInfosChanged = null;

      try {
        await environment.dispose();
      } catch (_) {}
    }

    await Future<void>.delayed(Duration.zero);

    try {
      if (kDebugMode) {
        debugPrint(
          'WebViewEnvironmentHolder: requesting native shutdown preparation',
        );
      }
      await _nativeShutdownChannel.invokeMethod('prepareForEngineShutdown');
    } catch (_) {}
  }
}
