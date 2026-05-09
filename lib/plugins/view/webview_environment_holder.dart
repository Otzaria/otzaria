import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:otzaria/core/app_paths.dart';

/// מחזיק את ה-WebViewEnvironment הסינגלטוני עם userDataFolder הניתן לכתיבה.
///
/// בהתקנה מערכתית (Program Files), WebView2 מנסה כברירת מחדל לכתוב לצד
/// קובץ ה-EXE — תיקייה read-only למשתמש רגיל — ונכשל עם
/// "Cannot create the InAppWebView instance!".
/// הגדרת נתיב מפורש תחת APPDATA פותרת זאת.
class WebViewEnvironmentHolder {
  static WebViewEnvironment? _environment;
  // Private native shutdown hook.
  // Keep the channel/method name in sync with
  // flutter_inappwebview_windows/windows/in_app_webview/in_app_webview_manager.h
  // and its prepareForEngineShutdown handler.
  static const MethodChannel _nativeShutdownChannel = MethodChannel(
    'com.pichillilorenzo/flutter_inappwebview_manager',
  );

  /// מחזיר את ה-WebViewEnvironment שנוצר באתחול, או null בפלטפורמות שאינן Windows.
  static WebViewEnvironment? get environment => _environment;

  /// מאתחל את סביבת WebView2 עם תיקיית נתונים הניתנת לכתיבה.
  /// חייב להיקרא לפני יצירת כל InAppWebView.
  static Future<void> initialize() async {
    if (!Platform.isWindows) return;
    if (_environment != null) return;

    final dataRoot = await AppPaths.getDataRootPath();
    final webviewDataFolder = p.join(dataRoot, 'webview2');

    await Directory(webviewDataFolder).create(recursive: true);

    _environment = await WebViewEnvironment.create(
      settings: WebViewEnvironmentSettings(userDataFolder: webviewDataFolder),
    );
  }

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

  /// Tears down the current Windows WebView environment before process exit.
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

    // Yield once so widget disposal triggered by the close flow can progress
    // before the native layer starts draining the shared dispatcher queue.
    await Future<void>.delayed(Duration.zero);

    if (kDebugMode) {
      debugPrint(
        'WebViewEnvironmentHolder: requesting native prepareForEngineShutdown',
      );
    }
    await _nativeShutdownChannel.invokeMethod('prepareForEngineShutdown');
    if (kDebugMode) {
      debugPrint(
        'WebViewEnvironmentHolder: native prepareForEngineShutdown completed',
      );
    }
  }
}
