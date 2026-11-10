// Intentional use of window_manager 0.6's legacy facade during the
// staged nativeapi migration; remove after moving these callers to Window.
// ignore_for_file: deprecated_member_use

import 'dart:ffi';

import 'package:flutter/foundation.dart';
import 'package:otzaria/core/windowing/runner_window_channel.dart';
import 'package:window_manager/legacy.dart';
import 'package:window_manager/window_manager.dart' as native show Window;

/// מצמיד את `windowManager` ל-HWND האמיתי של החלון הראשי (Windows).
///
/// ⚠️ בלי זה window_manager 0.6 מאתר את החלון בעצמו: `GetActiveWindow`, ורק
/// כשאין כזה — חלון Flutter יחיד מוסתר. בעלייה הראשי מוסתר מאחורי ה-splash,
/// ולכן ההצמדה קודמת ל-`addListener` ול-`setPreventClose`: הם נקשרים לחלון
/// שנמצא ברגע הקריאה, וחלון אחר שהיה פעיל (ה-splash) היה מקבל אותם.
///
/// מחזיר את ה-HWND, או null כשה-runner לא החזיר אותו (אז נשאר האיתור הרגיל).
/// כשה-runner החזיר HWND, הוא מוחזר גם אם לא נוצר ממנו חלון nativeapi.
Future<int?> bindMainWindowHandle({
  Future<int?> Function()? mainWindowHandle,
  native.Window? Function(int hwnd)? createWindow,
  void Function(native.Window window)? bindWindow,
}) async {
  final int? hwnd;
  try {
    hwnd =
        await (mainWindowHandle ??
            const RunnerWindowChannel().mainWindowHandle)();
  } catch (e) {
    debugPrint('main window hwnd failed: $e');
    return null;
  }
  if (hwnd == null || hwnd == 0) return null;
  final window = (createWindow ?? _nativeWindow)(hwnd);
  if (window != null) (bindWindow ?? windowManager.bindWindow)(window);
  return hwnd;
}

native.Window? _nativeWindow(int hwnd) =>
    native.Window.createWithNativeWindow(Pointer<Void>.fromAddress(hwnd));
