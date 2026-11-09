import 'dart:ui';

import 'package:flutter/foundation.dart';

import 'package:otzaria/core/windowing/app_window_controller.dart';
import 'package:otzaria/core/windowing/app_window_id.dart';
import 'package:window_manager/legacy.dart';

/// המימוש של החלון הראשי: מאציל ל-singleton הגלובלי `windowManager`.
///
/// `windowManager` מתאר תמיד את החלון הראשי, ולכן ה-[id] הוא תיוג ולא
/// ניתוב. חלון Dart נוסף מקבל `HostWindowAppWindowController`.
final class WindowManagerAppWindowController
    implements AppWindowController, AppWindowGeometry {
  const WindowManagerAppWindowController({this.id = AppWindowId.primary});

  @override
  final AppWindowId id;

  @override
  Future<void> show() => windowManager.show();

  @override
  Future<void> focus() => windowManager.focus();

  @override
  Future<void> minimize() => windowManager.minimize();

  @override
  Future<void> maximize() => windowManager.maximize();

  @override
  Future<void> unmaximize() => windowManager.unmaximize();

  @override
  Future<void> center() => windowManager.center();

  @override
  Future<void> startDragging() => windowManager.startDragging();

  @override
  Future<void> close() => windowManager.close();

  @override
  Future<void> quitApplication() => windowManager.destroy();

  @override
  Future<bool> isVisible() => windowManager.isVisible();

  @override
  Future<bool> isMaximized() => windowManager.isMaximized();

  @override
  Future<bool> isMinimized() => windowManager.isMinimized();

  @override
  Future<bool> isFullScreen() => windowManager.isFullScreen();

  @override
  Listenable get stateChanges => _WindowManagerStateChanges.instance;

  @override
  Future<Rect> getBounds() => windowManager.getBounds();

  @override
  Future<void> setBounds(Rect bounds) => windowManager.setBounds(bounds);

  @override
  Future<void> setSize(Size size) => windowManager.setSize(size);

  @override
  Future<void> setMinimumSize(Size size) => windowManager.setMinimumSize(size);

  @override
  Future<void> setFullScreen(bool value) => windowManager.setFullScreen(value);

  @override
  Future<void> setTitleBarStyle(
    TitleBarStyle style, {
    required bool windowButtonVisibility,
  }) => windowManager.setTitleBarStyle(
    style,
    windowButtonVisibility: windowButtonVisibility,
  );

  @override
  Future<void> setProgressBar(double progress) =>
      windowManager.setProgressBar(progress);
}

/// מתרגם את אירועי ה-maximize של `windowManager` ל-[Listenable]; נרשם
/// ל-singleton רק כל עוד יש מאזינים.
final class _WindowManagerStateChanges extends ChangeNotifier
    with WindowListener {
  _WindowManagerStateChanges._();

  static final instance = _WindowManagerStateChanges._();

  @override
  void addListener(VoidCallback listener) {
    if (!hasListeners) windowManager.addListener(this);
    super.addListener(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    super.removeListener(listener);
    if (!hasListeners) windowManager.removeListener(this);
  }

  @override
  void onWindowMaximize() => notifyListeners();

  @override
  void onWindowUnmaximize() => notifyListeners();
}
