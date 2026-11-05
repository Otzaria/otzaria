import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/core/startup_timeline.dart';
import 'package:otzaria/core/diagnostics/app_context_snapshot.dart';
import 'package:otzaria/core/diagnostics/developer_diagnostics.dart';
import 'package:otzaria/core/diagnostics/frame_stats_overlay.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/plugins/bloc/plugin_system_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/core/windowing/app_virtual_window_frame.dart';
import 'package:otzaria/core/windowing/app_window_keys.dart';
import 'package:otzaria/core/windowing/app_window_scope.dart';
import 'package:otzaria/core/windowing/mac_menu_bar.dart';
import 'package:otzaria/core/windowing/window_caption_hit_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:otzaria/navigation/view/main_window_screen.dart';
import 'package:otzaria/settings/settings_exports.dart';
import 'package:otzaria/widgets/feedback/edge_scrollbar_behavior.dart';
import 'package:otzaria/widgets/misc/middle_click_autoscroll.dart';
import 'package:window_manager/window_manager.dart';

// AppColors הועבר ל-lib/theme/app_colors.dart

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SettingsBloc, SettingsState>(
      buildWhen: (previous, current) {
        return previous.seedColor != current.seedColor ||
            previous.darkSeedColor != current.darkSeedColor ||
            previous.compactMenuMode != current.compactMenuMode ||
            previous.compactMenuModeIsSet != current.compactMenuModeIsSet ||
            previous.followSystemTheme != current.followSystemTheme ||
            previous.isDarkMode != current.isDarkMode;
      },
      builder: (context, settingsState) {
        StartupTimeline.instance.markOnce('appBuild');
        final state = settingsState;
        final lightColorScheme = AppThemeData.createColorScheme(
          state.seedColor,
          Brightness.light,
        );
        final darkColorScheme = AppThemeData.createColorScheme(
          state.darkSeedColor,
          Brightness.dark,
        );
        final useVirtualWindowFrame =
            !kIsWeb &&
            (Platform.isWindows || Platform.isLinux || Platform.isMacOS);
        // `VirtualWindowFrame` מאזין לחלון הראשי; לחלון Dart מסגרת משלו.
        final isViewWindow = AppWindowScope.roleOf(context).isViewWindow;
        // "צפיפות ממשק" שלא נבחרה מצומצמת בחלון קטן; ערכת הנושא נבנית מחדש
        // רק כשהחלון עובר את הסף.
        return SmallWindowBuilder(
          builder: (isSmallWindow) {
            final compact = state.compactMenuModeFor(
              isSmallWindow: isSmallWindow,
            );
            return ValueListenableBuilder<bool>(
              valueListenable: DeveloperDiagnostics.instance.performanceOverlay,
              builder: (context, showPerformanceOverlay, _) => MaterialApp(
                showPerformanceOverlay: showPerformanceOverlay,
                navigatorKey: AppWindowKeys.of(context).navigator,
                localizationsDelegates: const [
                  GlobalCupertinoLocalizations.delegate,
                  GlobalMaterialLocalizations.delegate,
                  GlobalWidgetsLocalizations.delegate,
                ],
                supportedLocales: const [
                  Locale("he", "IL"),
                ],
                locale: const Locale("he", "IL"),
                title: 'אוצריא',
                // פס הגלילה בימין הפיזי, ברצועה משלו, בכל האפליקציה (AppScrollbar).
                scrollBehavior: const EdgeScrollbarBehavior.right(),
                theme: AppThemeData.light(
                  lightColorScheme,
                  compactMenuMode: compact,
                  variant: AppThemeVariant.ofSeed(state.seedColor),
                ),
                darkTheme: AppThemeData.dark(
                  darkColorScheme,
                  compactMenuMode: compact,
                  variant: AppThemeVariant.ofSeed(state.darkSeedColor),
                ),
                themeMode: state.followSystemTheme
                    ? ThemeMode.system
                    : (state.isDarkMode ? ThemeMode.dark : ThemeMode.light),
                builder: (context, child) {
                  // שפת הממשק זמינה לכל האפליקציה, גם לדיאלוגים שמעל ה-Navigator.
                  // הכיווניות נשארת RTL; כרום הממשק (DESIGN_SYSTEM.md, DD-20) עובר
                  // ל-LTR ב-ChromeDirectionality ובמסך ההגדרות.
                  Widget navigator = child ?? const SizedBox.shrink();
                  // בדסקטופ כפתורי החלון ואזורי הגרירה נשארים פעילים מעל שכבת
                  // ההחשכה של דיאלוג (DD-16).
                  if (useVirtualWindowFrame) {
                    navigator = WindowCaptionHitTestScope(child: navigator);
                  }
                  Widget content =
                      BlocSelector<SettingsBloc, SettingsState, String>(
                        selector: (state) => state.settingsLanguageCode,
                        builder: (context, languageCode) => SettingsTextScope(
                          language: resolveSettingsLanguage(languageCode),
                          child: navigator,
                        ),
                      );

                  // קביעת צבע אייקוני פס הסטטוס לפי התמה הפעילה.
                  // האפליקציה אינה משתמשת ב-AppBar רגיל, ולכן systemOverlayStyle
                  // לא נקבע אוטומטית — מגדירים אותו כאן כדי שהשעה והאייקונים
                  // יישארו נראים תמיד (בעיקר באנדרואיד במצב edge-to-edge).
                  if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
                    final isDark =
                        Theme.of(context).brightness == Brightness.dark;
                    final overlayStyle = SystemUiOverlayStyle(
                      statusBarColor: Colors.transparent,
                      statusBarIconBrightness: isDark
                          ? Brightness.light
                          : Brightness.dark,
                      statusBarBrightness: isDark
                          ? Brightness.dark
                          : Brightness.light,
                    );
                    content = AnnotatedRegion<SystemUiOverlayStyle>(
                      value: overlayStyle,
                      child: content,
                    );
                  }

                  // גלילה אוטומטית בלחיצת גלגל העכבר — עטיפה אחת לכל האפליקציה,
                  // מתחת למסגרת החלון כדי שכפתורי המסגרת יישארו לחיצים.
                  content = MiddleClickAutoScroll(child: content);

                  content = MacMenuBar(child: content);
                  content = FrameStatsOverlay(
                    contextProvider: () => _diagnosticsContext(context),
                    child: content,
                  );

                  if (!useVirtualWindowFrame) {
                    return content;
                  }

                  if (isViewWindow) {
                    return AppVirtualWindowFrame(child: content);
                  }

                  return VirtualWindowFrame(
                    child: content,
                  );
                },
                home: MainWindowScreen(
                  key: AppWindowKeys.of(context).mainWindowScreen,
                ),
              ),
            );
          },
        );
      },
    );
  }
}

Map<String, Object?> _diagnosticsContext(BuildContext context) =>
    describeAppContext(
      screen: context.read<NavigationBloc>().state.currentScreen,
      tabs: context.read<TabsBloc>().state,
      pluginState: context.read<PluginSystemBloc>().state,
    );
