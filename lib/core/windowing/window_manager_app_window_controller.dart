import 'dart:ui';

import 'package:otzaria/core/windowing/app_window_controller.dart';
import 'package:otzaria/core/windowing/app_window_id.dart';
import 'package:window_manager/window_manager.dart';

/// המימוש היחיד היום: מאציל ל-singleton הגלובלי `windowManager`.
///
/// `windowManager` מתאר תמיד את החלון היחיד של התהליך, ולכן כל המופעים
/// של המחלקה הזו מפנים בפועל לאותו חלון — ה-[id] הוא תיוג, לא ניתוב.
/// כשתהיה תשתית ריבוי חלונות, המימוש הזה יישאר עבור החלון הראשי ויתווסף
/// לצדו מימוש שמנתב לפי [id].
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
}
