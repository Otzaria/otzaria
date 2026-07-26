import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:window_manager/window_manager.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_state.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/settings/settings_exports.dart';

/// Helper functions for fullscreen mode management
class FullscreenHelper {
  /// מסך מלא זמין רק בעת קריאת ספר (טאב פתוח בעיון) או בכלים/תוספים.
  static bool isContextAllowed(Screen screen, bool hasOpenTabs) {
    if (screen == Screen.reading) return hasOpenTabs;
    if (screen == Screen.more) return true;
    return false;
  }

  /// בודקת אם ההקשר הנוכחי (המסך והטאבים הפתוחים) מתיר מסך מלא.
  static bool isAllowedInContext(BuildContext context) {
    return isContextAllowed(
      context.read<NavigationBloc>().state.currentScreen,
      context.read<TabsBloc>().state.hasOpenTabs,
    );
  }

  /// האם מסך מלא צריך להסתיר את כרום האפליקציה.
  ///
  /// ב-macOS מסך מלא הוא מצב חלון נייטיבי, ולכן הטאבים וסרגל הניווט נשארים
  /// גלויים גם כשהחלון תופס את כל ה-Space.
  static bool shouldUseImmersiveLayout({
    required TargetPlatform platform,
    required bool isFullscreen,
    required Screen screen,
    required bool hasOpenTabs,
  }) {
    if (platform == TargetPlatform.macOS) return false;
    return isFullscreen && isContextAllowed(screen, hasOpenTabs);
  }

  /// האם ניווט למסך אחר צריך לצאת ממסך מלא.
  static bool shouldExitFullscreenOnNavigation({
    required TargetPlatform platform,
    required bool isFullscreen,
    required Screen screen,
    required bool hasOpenTabs,
  }) {
    if (platform == TargetPlatform.macOS) return false;
    return isFullscreen && !isContextAllowed(screen, hasOpenTabs);
  }

  /// מצב ה-System UI המתאים: מסתיר את שורת המצב במסך מלא, ומשיב אותה כשיוצאים.
  static SystemUiMode systemUiModeForFullscreen(bool isFullscreen) {
    return isFullscreen
        ? SystemUiMode.immersiveSticky
        : SystemUiMode.edgeToEdge;
  }

  /// מעדכן את מצב המסך המלא ואת ממשק המערכת בפלטפורמה הנוכחית.
  static Future<void> toggleFullscreen(
    BuildContext context,
    bool isFullscreen,
  ) async {
    // עדכון ה-state ב-Bloc
    final settingsBloc = context.read<SettingsBloc>();
    if (settingsBloc.state.isFullscreen != isFullscreen) {
      settingsBloc.add(UpdateIsFullscreen(isFullscreen));
    }

    final isMobilePlatform =
        !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS);
    if (isMobilePlatform) {
      // בנייד אין title bar/window manager - שורת המצב נשלטת ישירות דרך SystemChrome.
      await SystemChrome.setEnabledSystemUIMode(
        systemUiModeForFullscreen(isFullscreen),
      );
      return;
    }

    // פעולות על מנהל החלונות
    // חשוב: להסתיר את ה-title bar לפני המעבר למסך מלא כדי למנוע הבהוב
    if (isFullscreen) {
      await windowManager.setTitleBarStyle(
        TitleBarStyle.hidden,
        windowButtonVisibility: false,
      );
      await windowManager.setFullScreen(true);
    } else {
      await windowManager.setFullScreen(false);
      // אנחנו משתמשים ב-CustomTitleBar ולכן תמיד רוצים להסתיר את הכותרת המקורית
      await windowManager.setTitleBarStyle(
        TitleBarStyle.hidden,
        windowButtonVisibility: false,
      );
    }
  }
}
