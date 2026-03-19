import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:otzaria/navigation/main_window_screen.dart';
import 'package:otzaria/shortcuts/keyboard_shortcuts.dart';
import 'package:otzaria/settings/settings_exports.dart';
import 'package:window_manager/window_manager.dart';

class App extends StatelessWidget {
  const App({super.key});

  /// בדיקה אם הצבע ניטרלי (לבן/אפור) לפי רוויה
  bool _isNeutralColor(Color color) {
    final hslColor = HSLColor.fromColor(color);
    return hslColor.saturation < 0.1;
  }

  /// יצירת ColorScheme — מונוכרום לצבעים ניטרליים, רגיל לשאר
  ColorScheme _createColorScheme(Color seedColor, Brightness brightness) {
    if (_isNeutralColor(seedColor)) {
      return ColorScheme.fromSeed(
        seedColor: seedColor,
        brightness: brightness,
        dynamicSchemeVariant: DynamicSchemeVariant.monochrome,
      );
    }
    return ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: brightness,
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SettingsBloc, SettingsState>(
        builder: (context, settingsState) {
          final state = settingsState;
          final lightColorScheme =
              _createColorScheme(state.seedColor, Brightness.light);
          final useVirtualWindowFrame = !kIsWeb &&
              (Platform.isWindows || Platform.isLinux || Platform.isMacOS);
          return MaterialApp(
          navigatorKey: navigatorKey,
          localizationsDelegates: const [
            GlobalCupertinoLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          supportedLocales: const [Locale('he', 'IL')],
          locale: const Locale('he', 'IL'),
          title: 'אוצריא',
          theme: AppThemeData.light(
            lightColorScheme,
            compactMenuMode: state.compactMenuMode,
          ),
          darkTheme: AppThemeData.dark(
            state.darkSeedColor,
            compactMenuMode: state.compactMenuMode,
          ),
          themeMode: state.followSystemTheme
              ? ThemeMode.system
              : (state.isDarkMode ? ThemeMode.dark : ThemeMode.light),
          builder: (context, child) {
            final wrappedChild = KeyboardShortcuts(
              child: child ?? const SizedBox.shrink(),
            );

            if (!useVirtualWindowFrame) {
              return wrappedChild;
            }

            return VirtualWindowFrame(
              child: wrappedChild,
            );
          },
          home: const MainWindowScreen(),
        );
      },
    );
  }
}
