import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:otzaria/navigation/view/main_window_screen.dart';
import 'package:otzaria/settings/settings_exports.dart';
import 'package:window_manager/window_manager.dart';

// AppColors הועבר ל-lib/theme/app_colors.dart

class App extends StatelessWidget {
  const App({super.key});

  /// Check if a color is neutral (white/gray) based on its saturation
  bool _isNeutralColor(Color color) {
    final hslColor = HSLColor.fromColor(color);
    // If saturation is very low, it's a neutral color (white/gray/black)
    return hslColor.saturation < 0.1;
  }

  /// Create a ColorScheme that respects neutral colors
  ColorScheme _createColorScheme(Color seedColor, Brightness brightness) {
    if (_isNeutralColor(seedColor)) {
      // For neutral colors, use monochrome variant to avoid color tinting
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
      buildWhen: (previous, current) {
        return previous.seedColor != current.seedColor ||
            previous.darkSeedColor != current.darkSeedColor ||
            previous.compactMenuMode != current.compactMenuMode ||
            previous.followSystemTheme != current.followSystemTheme ||
            previous.isDarkMode != current.isDarkMode;
      },
      builder: (context, settingsState) {
        final state = settingsState;
        final lightColorScheme =
            _createColorScheme(state.seedColor, Brightness.light);
        final useVirtualWindowFrame = !kIsWeb &&
            (Platform.isWindows || Platform.isLinux || Platform.isMacOS);
        return MaterialApp(
          navigatorKey: navigatorKey,
          scaffoldMessengerKey: scaffoldMessengerKey,
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
          theme: AppThemeData.light(lightColorScheme,
              compactMenuMode: state.compactMenuMode),
          darkTheme: AppThemeData.dark(state.darkSeedColor,
              compactMenuMode: state.compactMenuMode),
          themeMode: state.followSystemTheme
              ? ThemeMode.system
              : (state.isDarkMode ? ThemeMode.dark : ThemeMode.light),
          builder: (context, child) {
            if (!useVirtualWindowFrame || child == null) {
              return child ?? const SizedBox.shrink();
            }

            return VirtualWindowFrame(
              child: child,
            );
          },
          home: MainWindowScreen(key: mainWindowScreenKey),
        );
      },
    );
  }
}
