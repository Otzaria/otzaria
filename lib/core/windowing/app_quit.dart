import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:otzaria/core/windowing/app_window_controller.dart';
import 'package:otzaria/widgets/misc/restart_widget.dart';

/// מדוע כל החלונות נסגרים; לרישום בלבד.
enum AppQuitReason { update, user }

/// נקודת הכניסה היחידה ליציאה מכל החלונות ולבנייתם מחדש. סגירת הראשי לבדה
/// רק מסתירה אותו כשחלונות Dart פתוחים, ולכן היציאה עוברת במסלול משלה.
abstract final class AppQuit {
  static Future<void> Function()? _quitProcess;

  /// מסלול היציאה המלא של התהליך: שאלות, שטיפה, הריסת החלונות וסיום.
  /// נקבע ב-main.
  static void install(Future<void> Function() quitProcess) =>
      _quitProcess = quitProcess;

  @visibleForTesting
  static void resetForTest() => _quitProcess = null;

  /// יציאה מכל החלונות: הסשנים של כולם נשמרים להפעלה הבאה והתהליך מסתיים.
  /// חזרה מהקריאה פירושה ביטול (שינויים שלא נשמרו).
  static Future<void> quitAll(
    AppQuitReason reason, {
    required AppWindowController window,
  }) async {
    final quitProcess = _quitProcess;
    if (quitProcess != null) {
      debugPrint('AppQuit.quitAll(${reason.name})');
      await quitProcess();
      return;
    }
    // ⚠️ סגירה מנומסת ולא `quitApplication()`: האחרון הוא `PostQuitMessage`
    // ומפיל את המנוע תחת Dart רץ. ראו התיעוד ב-`AppWindowController`.
    await window.close();
  }

  /// בונה מחדש את כל החלונות בלי לצאת מהתהליך: `RestartWidget` עוטף גם את
  /// חלונות ה-Dart.
  static void restartAll(
    BuildContext context, {
    bool? pluginSafeMode,
    FutureOr<void> Function()? afterRestart,
  }) {
    RestartWidget.restartApp(context, afterRestart: afterRestart);
  }
}
