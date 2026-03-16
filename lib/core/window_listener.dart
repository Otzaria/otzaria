import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';
import '../migration/dao/daos/database.dart';
import 'package:otzaria/core/window_persistence.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

/// Callback type for fullscreen state changes
typedef FullscreenCallback = void Function(bool isFullscreen);

/// Window listener that handles window events properly to prevent crashes
class AppWindowListener extends WindowListener {
  FullscreenCallback? onFullscreenChanged;

  @override
  void onWindowEnterFullScreen() {
    if (kDebugMode) {
      print('Window entered fullscreen');
    }
    onFullscreenChanged?.call(true);
  }

  @override
  void onWindowLeaveFullScreen() {
    if (kDebugMode) {
      print('Window left fullscreen');
    }
    onFullscreenChanged?.call(false);
  }

  @override
  void onWindowClose() async {
    if (kDebugMode) {
      print('Window close requested');
    }

    try {
      // ביצוע פעולות הניקוי
      MyDatabase().close();
      SqliteDataProvider.instance.dispose();
      await Sentry.close();

      if (!kIsWeb &&
          (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
        // שמירת מצב החלון
        await WindowPersistence.saveNow();
        // סגירה רגילה דרך ה-WindowManager
        await windowManager.destroy();
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error during window close: $e');
      }
      // נשמור על exit(0) רק למקרה חירום של קריסה בתהליך הסגירה
      exit(0);
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
      print('Window minimized');
    }
  }

  @override
  void onWindowRestore() {
    if (kDebugMode) {
      print('Window restored');
    }
  }

  @override
  void onWindowResize() {
    if (kDebugMode) {
      print('Window resized');
    }

    WindowPersistence.scheduleSave();
  }

  @override
  void onWindowMove() {
    if (kDebugMode) {
      print('Window moved');
    }

    WindowPersistence.scheduleSave();
  }

  @override
  void onWindowMaximize() {
    if (kDebugMode) {
      print('Window maximized');
    }
    WindowPersistence.scheduleSave();
  }

  @override
  void onWindowUnmaximize() {
    if (kDebugMode) {
      print('Window unmaximized');
    }
    WindowPersistence.scheduleSave();
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
