import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/core/directory_writability.dart';
import 'package:otzaria/plugins/services/plugin_asset_scheme.dart';
import 'package:otzaria/plugins/services/plugin_webview_failure_log.dart';

/// מחזיק סביבת WebView2 עם תיקיית נתונים הניתנת לכתיבה ב-APPDATA,
/// כדי שהתקנה ב-Program Files לא תנסה לכתוב לצד ה-EXE.
class WebViewEnvironmentHolder {
  static WebViewEnvironment? _environment;
  // Coalesces concurrent init calls (background host vs. plugin tab): two
  // callers racing past the null guard would spawn two Edge process trees.
  static Future<void>? _initializeFuture;
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
      return version != null && version.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// override לבדיקות בלבד: כשמוגדר, [checkDataFolderWritable] מחזיר את ערכו
  /// במקום לגעת בדיסק.
  static String? _unwritableDataFolderOverride;
  static bool _hasUnwritableDataFolderOverride = false;

  /// מגדיר ערך קבוע ל-[checkDataFolderWritable]. העבר `null` לנתיב חסום
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
  /// [dataFolderChecked] חוסך בדיקה חוזרת כשהקורא כבר בדק כתיבה מיד לפני הקריאה.
  static Future<void> initialize({bool dataFolderChecked = false}) {
    if (_initializeOverride != null) return _initializeOverride!();
    if (!Platform.isWindows) return Future<void>.value();
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
      _environment = await WebViewEnvironment.create(
        settings: _environmentSettings(webviewDataFolder),
      );
    } catch (error, stackTrace) {
      // כשל כאן = כל התוספים יעלו ריקים; בלי הרישום אין לזה שום עקבות.
      logPluginWebViewFailure(
        'WebView2 environment init failed',
        error,
        stackTrace: stackTrace,
        details: {'UserDataFolder': webviewDataFolder},
      );
      rethrow;
    } finally {
      // בהצלחה: _environment מוגדר, ה-guard בכניסה ל-initialize יחזיר
      // מיידית. בכישלון: _environment עדיין null וקריאה הבאה לא תיתפס
      // ע"י future ישן עם שגיאה ישנה — היא תתחיל ניסיון אתחול חדש.
      _initializeFuture = null;
    }
  }

  @visibleForTesting
  static WebViewEnvironmentSettings debugEnvironmentSettings(
    String userDataFolder,
  ) => _environmentSettings(userDataFolder);

  static WebViewEnvironmentSettings _environmentSettings(
    String userDataFolder,
  ) => WebViewEnvironmentSettings(
    userDataFolder: userDataFolder,
    // בלעדיות מכשילה תהליך נוסף על התיקייה: 0x8007139F/0x8000FFFF (#2458).
    exclusiveUserDataFolderAccess: false,
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
    if (!Platform.isWindows) return;

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
