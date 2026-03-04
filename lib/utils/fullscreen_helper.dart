import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:window_manager/window_manager.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';

/// Helper functions for fullscreen mode management
class FullscreenHelper {
  /// Toggle fullscreen mode with proper window manager handling
  static Future<void> toggleFullscreen(
    BuildContext context,
    bool isFullscreen,
  ) async {
    final settingsBloc = context.read<SettingsBloc>();
    if (settingsBloc.state.isFullscreen != isFullscreen) {
      settingsBloc.add(UpdateIsFullscreen(isFullscreen));
    }

    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      if (isFullscreen) {
        await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      } else {
        await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      }
      return;
    }

    if (!kIsWeb &&
        (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
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
}
