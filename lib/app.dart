import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/core/startup_timeline.dart';
import 'package:otzaria/core/diagnostics/developer_diagnostics.dart';
import 'package:otzaria/core/diagnostics/frame_stats_overlay.dart';
import 'package:otzaria/core/diagnostics/freeze_context_reporter.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/core/windowing/dock_progress_listener.dart';
import 'package:otzaria/core/windowing/mac_menu_bar.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:otzaria/navigation/view/main_window_screen.dart';
import 'package:otzaria/settings/settings_exports.dart';
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
        return ValueListenableBuilder<bool>(
          valueListenable: DeveloperDiagnostics.instance.performanceOverlay,
          builder: (context, showPerformanceOverlay, _) => MaterialApp(
            showPerformanceOverlay: showPerformanceOverlay,
            navigatorKey: navigatorKey,
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
            theme: AppThemeData.light(
              lightColorScheme,
              compactMenuMode: state.compactMenuMode,
            ),
            darkTheme: AppThemeData.dark(
              darkColorScheme,
              compactMenuMode: state.compactMenuMode,
            ),
            themeMode: state.followSystemTheme
                ? ThemeMode.system
                : (state.isDarkMode ? ThemeMode.dark : ThemeMode.light),
            builder: (context, child) {
              // שפת ההגדרות זמינה לכל האפליקציה כדי שגם סרגל הניווט ופס
              // הכותרת יתורגמו. הכיווניות נשארת RTL — רק מסך ההגדרות עובר
              // ל-LTR מקומית.
              Widget content =
                  BlocSelector<SettingsBloc, SettingsState, String>(
                    selector: (state) => state.settingsLanguageCode,
                    builder: (context, languageCode) => SettingsTextScope(
                      language: resolveSettingsLanguage(languageCode),
                      child: child ?? const SizedBox.shrink(),
                    ),
                  );

              // קביעת צבע אייקוני פס הסטטוס לפי התמה הפעילה.
              // האפליקציה אינה משתמשת ב-AppBar רגיל, ולכן systemOverlayStyle
              // לא נקבע אוטומטית — מגדירים אותו כאן כדי שהשעה והאייקונים
              // יישארו נראים תמיד (בעיקר באנדרואיד במצב edge-to-edge).
              if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
                final isDark = Theme.of(context).brightness == Brightness.dark;
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

              content = DockProgressListener(child: content);
              content = MacMenuBar(child: content);
              content = FreezeContextReporter(
                describe: () => _diagnosticsContext(context),
                child: content,
              );
              content = FrameStatsOverlay(
                contextProvider: () => _diagnosticsContext(context),
                child: content,
              );

              if (!useVirtualWindowFrame) {
                return content;
              }

              return VirtualWindowFrame(
                child: content,
              );
            },
            home: MainWindowScreen(key: mainWindowScreenKey),
          ),
        );
      },
    );
  }
}

Map<String, Object?> _diagnosticsContext(BuildContext context) {
  final tabs = context.read<TabsBloc>().state;
  final current = tabs.currentTab;
  return {
    'screen': context.read<NavigationBloc>().state.currentScreen.name,
    'tabs': tabs.tabs.length,
    'currentTab': current?.runtimeType.toString(),
    'currentTitle': current?.title,
  };
}
