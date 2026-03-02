import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:window_manager/window_manager.dart';
import 'package:otzaria/settings/settings_exports.dart';

/// Helper functions for fullscreen mode management
class FullscreenHelper {
  /// Toggle fullscreen mode with proper window manager handling
  static Future<void> toggleFullscreen(
    BuildContext context,
    bool isFullscreen,
  ) async {
    // עדכון ה-state ב-Bloc
    final settingsBloc = context.read<SettingsBloc>();
    if (settingsBloc.state.isFullscreen != isFullscreen) {
      settingsBloc.add(UpdateIsFullscreen(isFullscreen));
    }

    // פעולות על מנהל החלונות
    // חשוב: להסתיר את ה-title bar לפני המעבר למסך מלא כדי למנוע הבהוב
    if (isFullscreen) {
      await windowManager.setTitleBarStyle(TitleBarStyle.hidden);
      await windowManager.setFullScreen(true);
    } else {
      await windowManager.setFullScreen(false);
      // אנחנו משתמשים ב-CustomTitleBar ולכן תמיד רוצים להסתיר את הכותרת המקורית
      await windowManager.setTitleBarStyle(TitleBarStyle.hidden);
    }
  }
}
