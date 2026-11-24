import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:otzaria/core/windowing/multiview/cocoa_view_window_native.dart';
import 'package:otzaria/core/windowing/multiview/gtk_view_window_native.dart';
import 'package:win32/win32.dart';
import 'package:window_manager/window_manager.dart' show ResizeEdge;

/// מה שחלון Dart צריך מהמערכת ואין לו בבקר של המסגרת. ב-Windows/Linux בפיקסלים פיזיים; ב-macOS בנקודות מסך.
/// `hwnd` הוא `ViewWindowHandle.nativeHandle`: HWND ב-Windows, `GtkWindow*` ב-Linux,
/// `NSWindow*` ב-macOS. FutureOr: ב-macOS הכול עובר בערוץ, ובשאר סינכרוני.
abstract interface class ViewWindowNative {
  /// המימוש של הפלטפורמה הנוכחית.
  factory ViewWindowNative.platform() => Platform.isLinux
      ? const GtkViewWindowNative()
      : Platform.isMacOS
      ? const CocoaViewWindowNative()
      : const Win32ViewWindowNative();

  /// מלבן החלון כולו (כולל המסגרת); null כשאינו זמין.
  FutureOr<Rect?> windowRect(int hwnd);
  FutureOr<void> setWindowRect(int hwnd, Rect rect);
  FutureOr<bool> isVisible(int hwnd);
  FutureOr<void> show(int hwnd);
  FutureOr<void> hide(int hwnd);

  /// מביא לחזית בלי לשנות את מצב ה-maximize.
  FutureOr<void> focus(int hwnd);
  FutureOr<void> startDragging(int hwnd);

  /// לולאת שינוי הגודל של המערכת מ-[edge], כמו `windowManager.startResizing`.
  FutureOr<void> startResizing(int hwnd, ResizeEdge edge);

  /// הגדלה לגובה המסך, כמו לחיצה כפולה על הקצה העליון.
  FutureOr<void> maximizeVertically(int hwnd);

  /// אזור העבודה של המסך שהחלון עליו.
  FutureOr<Rect?> workArea(int hwnd);

  /// החלון שבחזית; null כשאין.
  FutureOr<int?> foregroundWindow();

  /// המסגרת הרגילה (גם כשהחלון ממוקסם), המיקסום וה-DPI; null כשאינם זמינים.
  FutureOr<({Rect normal, bool maximized, int dpi})?> placement(int hwnd);

  /// תיקוני הקלט של ה-runner (#1441, #1645) לתצוגה של החלון.
  Future<void> installViewHooks(int hwnd);

  /// מסיר את כותרת המערכת, כמו `TitleBarStyle.hidden` בחלון הראשי.
  Future<void> makeFrameless(int hwnd);

  /// אחרי הפריים הראשון: GTK מציג ו-macOS מסיר את ההסתרה של ה-runner.
  Future<void> reveal(int hwnd);
}

/// המימוש האמיתי: win32 ישירות, והערוץ של ה-runner להתקנת התיקונים.
class Win32ViewWindowNative implements ViewWindowNative {
  const Win32ViewWindowNative();

  static const MethodChannel _channel = MethodChannel('otzaria/multiwindow');

  static HWND _h(int hwnd) => HWND(Pointer.fromAddress(hwnd));

  static Rect _rect(RECT r) => Rect.fromLTRB(
    r.left.toDouble(),
    r.top.toDouble(),
    r.right.toDouble(),
    r.bottom.toDouble(),
  );

  @override
  Rect? windowRect(int hwnd) {
    final rect = calloc<RECT>();
    try {
      if (!GetWindowRect(_h(hwnd), rect).value) return null;
      return _rect(rect.ref);
    } finally {
      calloc.free(rect);
    }
  }

  @override
  void setWindowRect(int hwnd, Rect rect) {
    SetWindowPos(
      _h(hwnd),
      null,
      rect.left.round(),
      rect.top.round(),
      rect.width.round(),
      rect.height.round(),
      SET_WINDOW_POS_FLAGS(SWP_NOZORDER | SWP_NOACTIVATE),
    );
  }

  @override
  bool isVisible(int hwnd) => IsWindowVisible(_h(hwnd));

  @override
  void show(int hwnd) => ShowWindow(_h(hwnd), SW_SHOW);

  @override
  void hide(int hwnd) => ShowWindow(_h(hwnd), SW_HIDE);

  @override
  void focus(int hwnd) => SetForegroundWindow(_h(hwnd));

  /// הפקודה ש-`windowManager.startDragging` שולח לחלון הראשי.
  @visibleForTesting
  static const int dragCommand = SC_MOVE | HTCAPTION;

  @override
  void startDragging(int hwnd) {
    // כמו window_manager: SC_MOVE ישר ללולאה, בלי זיהוי הלחיצה של WM_NCLBUTTONDOWN.
    // ב-Post ולא ב-Send: לולאה מודאלית בתוך קריאת FFI הייתה חוסמת את ה-isolate.
    ReleaseCapture();
    PostMessage(
      _h(hwnd),
      WM_SYSCOMMAND,
      const WPARAM(dragCommand),
      const LPARAM(0),
    );
  }

  static const Map<ResizeEdge, int> _hitTest = {
    ResizeEdge.top: HTTOP,
    ResizeEdge.topLeft: HTTOPLEFT,
    ResizeEdge.topRight: HTTOPRIGHT,
    ResizeEdge.left: HTLEFT,
    ResizeEdge.right: HTRIGHT,
    ResizeEdge.bottom: HTBOTTOM,
    ResizeEdge.bottomLeft: HTBOTTOMLEFT,
    ResizeEdge.bottomRight: HTBOTTOMRIGHT,
  };

  // הודעת WM_NC* (מחוץ לאזור הלקוח) במיקום הסמן, כמו ב-window_manager.
  static void _postAtCursor(int hwnd, int message, int hitTest) {
    final point = calloc<POINT>();
    try {
      GetCursorPos(point);
      final x = point.ref.x & 0xFFFF;
      final y = point.ref.y & 0xFFFF;
      PostMessage(_h(hwnd), message, WPARAM(hitTest), LPARAM(x | (y << 16)));
    } finally {
      calloc.free(point);
    }
  }

  @override
  void startResizing(int hwnd, ResizeEdge edge) {
    ReleaseCapture();
    _postAtCursor(hwnd, WM_NCLBUTTONDOWN, _hitTest[edge]!);
  }

  @override
  void maximizeVertically(int hwnd) =>
      _postAtCursor(hwnd, WM_NCLBUTTONDBLCLK, HTTOP);

  @override
  Rect? workArea(int hwnd) {
    final monitor = MonitorFromWindow(_h(hwnd), MONITOR_DEFAULTTONEAREST);
    final info = calloc<MONITORINFO>()..ref.cbSize = sizeOf<MONITORINFO>();
    try {
      if (!GetMonitorInfo(monitor, info)) return null;
      return _rect(info.ref.rcWork);
    } finally {
      calloc.free(info);
    }
  }

  @override
  int? foregroundWindow() {
    final hwnd = GetForegroundWindow().address;
    return hwnd == 0 ? null : hwnd;
  }

  @override
  ({Rect normal, bool maximized, int dpi})? placement(int hwnd) {
    final h = _h(hwnd);
    final placement = calloc<WINDOWPLACEMENT>()
      ..ref.length = sizeOf<WINDOWPLACEMENT>();
    final info = calloc<MONITORINFO>()..ref.cbSize = sizeOf<MONITORINFO>();
    try {
      if (!GetWindowPlacement(h, placement).value) return null;
      final maximized = IsZoomed(h);
      var normal = windowRect(hwnd);
      if (maximized || IsIconic(h)) {
        // כמו ב-runner: rcNormalPosition יחסית לאזור העבודה, לא למסך.
        normal = _rect(placement.ref.rcNormalPosition);
        final style = GetWindowLongPtr(h, GWL_EXSTYLE).value;
        final monitor = MonitorFromWindow(h, MONITOR_DEFAULTTONEAREST);
        if (style & WS_EX_TOOLWINDOW == 0 && GetMonitorInfo(monitor, info)) {
          normal = normal.translate(
            (info.ref.rcWork.left - info.ref.rcMonitor.left).toDouble(),
            (info.ref.rcWork.top - info.ref.rcMonitor.top).toDouble(),
          );
        }
      }
      if (normal == null) return null;
      final dpi = GetDpiForWindow(h);
      return (normal: normal, maximized: maximized, dpi: dpi > 0 ? dpi : 96);
    } finally {
      calloc.free(placement);
      calloc.free(info);
    }
  }

  @override
  Future<void> installViewHooks(int hwnd) async {
    if (!Platform.isWindows) return;
    try {
      final installed = await _channel.invokeMethod<bool>(
        'installViewHooks',
        {'hwnd': hwnd},
      );
      if (installed != true) debugPrint('installViewHooks: not installed');
    } catch (e) {
      // החלון עובד גם בלי התיקונים; רק מגע ו-Shift תקוע חוזרים.
      debugPrint('installViewHooks failed: $e');
    }
  }

  @override
  Future<void> makeFrameless(int hwnd) async {
    if (!Platform.isWindows) return;
    try {
      final done = await _channel.invokeMethod<bool>('makeFrameless', {
        'hwnd': hwnd,
      });
      if (done != true) debugPrint('makeFrameless: not applied');
    } catch (e) {
      // בלי זה החלון נשאר עם מסגרת מערכת וכפתורים כפולים, אבל עובד.
      debugPrint('makeFrameless failed: $e');
    }
  }

  @override
  Future<void> reveal(int hwnd) async {}
}
