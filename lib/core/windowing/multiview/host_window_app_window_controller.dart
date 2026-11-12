import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart' show Listenable;
import 'package:otzaria/core/windowing/app_window_controller.dart';
import 'package:otzaria/core/windowing/app_window_id.dart';
import 'package:otzaria/core/windowing/multiview/cocoa_view_window_native.dart';
import 'package:otzaria/core/windowing/multiview/multiview_flag.dart';
import 'package:otzaria/core/windowing/multiview/view_window_native.dart';
import 'package:window_manager/legacy.dart' show ResizeEdge, TitleBarStyle;

/// החלון של חלון Dart: המצב מהבקר של המסגרת, המיקום דרך [ViewWindowNative].
/// הגבולות לוגיים: macOS בנקודות מסך, ובשאר פיזי חלקי DPR, כמו window_manager.
final class HostWindowAppWindowController
    implements AppWindowController, AppWindowGeometry, AppWindowResizing {
  HostWindowAppWindowController({
    required this.id,
    required this._handle,
    required this._onClose,
    ViewWindowNative? native,
  }) : _native = native ?? ViewWindowNative.platform();

  @override
  final AppWindowId id;

  final ViewWindowHandle _handle;
  final Future<void> Function() _onClose;
  final ViewWindowNative _native;

  double get _dpr {
    if (_native is CocoaViewWindowNative) return 1;
    final dpr = _handle.view.devicePixelRatio;
    return dpr > 0 ? dpr : 1.0;
  }

  Future<void> _withHwnd(FutureOr<void> Function(int hwnd) body) async {
    final hwnd = _handle.nativeHandle;
    if (hwnd != null) await body(hwnd);
  }

  @override
  Future<void> show() => _withHwnd(_native.show);

  @override
  Future<void> focus() async {
    // `activate` של המסגרת הוא SW_RESTORE, שמבטל גם maximize.
    if (_handle.isMinimized) _handle.setMinimized(false);
    await _withHwnd(_native.focus);
  }

  @override
  Future<void> minimize() async => _handle.setMinimized(true);

  @override
  Future<void> maximize() async => _handle.setMaximized(true);

  @override
  Future<void> unmaximize() async => _handle.setMaximized(false);

  @override
  Future<void> center() => _withHwnd((hwnd) async {
    final rect = await _native.windowRect(hwnd);
    final area = await _native.workArea(hwnd);
    if (rect == null || area == null) return;
    await _native.setWindowRect(
      hwnd,
      Rect.fromCenter(
        center: area.center,
        width: rect.width,
        height: rect.height,
      ),
    );
  });

  @override
  Future<void> startDragging() => _withHwnd(_native.startDragging);

  @override
  Future<void> startResizing(ResizeEdge edge) =>
      _withHwnd((hwnd) => _native.startResizing(hwnd, edge));

  @override
  Future<void> maximizeVertically() => _withHwnd(_native.maximizeVertically);

  /// עובר במסלול הסגירה של החלון, כמו לחיצה על X.
  @override
  Future<void> close() => _onClose();

  @override
  Future<void> quitApplication() =>
      throw UnsupportedError('חלון Dart אינו מסיים את התוכנה');

  @override
  Future<bool> isVisible() async {
    final hwnd = _handle.nativeHandle;
    return hwnd != null && await _native.isVisible(hwnd);
  }

  @override
  Future<bool> isMaximized() async => _handle.isMaximized;

  @override
  Future<bool> isMinimized() async => _handle.isMinimized;

  @override
  Future<bool> isFullScreen() async => _handle.isFullscreen;

  @override
  Listenable get stateChanges => _handle.changes;

  @override
  Future<Rect> getBounds() async {
    final hwnd = _handle.nativeHandle;
    final rect = hwnd == null ? null : await _native.windowRect(hwnd);
    if (rect == null) return Rect.zero;
    return _scale(rect, 1 / _dpr);
  }

  @override
  Future<void> setBounds(Rect bounds) =>
      _withHwnd((hwnd) => _native.setWindowRect(hwnd, _scale(bounds, _dpr)));

  @override
  Future<void> setSize(Size size) => _withHwnd((hwnd) async {
    final rect = await _native.windowRect(hwnd);
    if (rect == null) return;
    await _native.setWindowRect(hwnd, rect.topLeft & size * _dpr);
  });

  @override
  Future<void> setMinimumSize(Size size) async => _handle.setMinimumSize(size);

  @override
  Future<void> setFullScreen(bool value) async => _handle.setFullscreen(value);

  /// הכותרת הוסרה פעם אחת בפתיחה (`makeFrameless`); מסך מלא של המסגרת
  /// מחזיר את הסגנון בסיומו, ולכן אין מה לעשות כאן.
  @override
  Future<void> setTitleBarStyle(
    TitleBarStyle style, {
    required bool windowButtonVisibility,
  }) async {}

  /// החיווי בשורת המשימות שייך לחלון הראשי (`DockProgressListener`).
  @override
  Future<void> setProgressBar(double progress) async {}

  static Rect _scale(Rect rect, double factor) => Rect.fromLTWH(
    rect.left * factor,
    rect.top * factor,
    rect.width * factor,
    rect.height * factor,
  );
}
