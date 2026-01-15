import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/core/scaffold_messenger.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:otzaria/settings/settings_bloc.dart';
import 'package:otzaria/settings/settings_state.dart';
import 'package:otzaria/navigation/main_window_screen.dart';

/// קבועי צבעים לעיצוב האפליקציה
class AppColors {
  static const Color darkScaffold = Color(0xFF242424);
  static const Color darkCard = Color(0xFF333333);
  static const Color darkAppBar = Color(0xFF2A2A2A);
  static const Color darkOnSurface = Color(0xFFE0E0E0);
  static const Color darkOutline = Color(0xFF4A4A4A);
  static const Color dialogBarrier = Color(0x22000000);
}

class App extends StatelessWidget {
  final String? initialUrl;
  
  const App({super.key, this.initialUrl});

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
    } else {
      // For colored seeds, use default behavior
      return ColorScheme.fromSeed(
        seedColor: seedColor,
        brightness: brightness,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SettingsBloc, SettingsState>(
      builder: (context, settingsState) {
        final state = settingsState;
        return MaterialApp(
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
          theme: state.isDarkMode
              ? ThemeData.dark(useMaterial3: true).copyWith(
                  scaffoldBackgroundColor: AppColors.darkScaffold,
                  canvasColor: AppColors.darkScaffold,
                  cardColor: AppColors.darkCard,
                  colorScheme: ColorScheme.dark(
                    surface: AppColors.darkScaffold,
                    surfaceContainer: AppColors.darkCard,
                    onSurface: AppColors.darkOnSurface,
                    primary: state.darkSeedColor,
                    onPrimary: Colors.white,
                    secondary: state.darkSeedColor.withValues(alpha: 0.7),
                    onSecondary: Colors.white,
                    outline: AppColors.darkOutline,
                  ),
                  textTheme: ThemeData.dark()
                      .textTheme
                      .apply(
                        fontFamily: 'Roboto',
                        bodyColor: AppColors.darkOnSurface,
                        displayColor: AppColors.darkOnSurface,
                      )
                      .copyWith(
                        bodyMedium: const TextStyle(
                          fontSize: 18.0,
                          fontFamily: 'candara',
                          color: AppColors.darkOnSurface,
                        ),
                      ),
                  cardTheme: CardThemeData(
                    color: AppColors.darkCard,
                    elevation: 3,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: const BorderSide(
                        color: AppColors.darkOutline,
                        width: 1,
                      ),
                    ),
                  ),
                  appBarTheme: const AppBarTheme(
                    backgroundColor: AppColors.darkAppBar,
                    foregroundColor: AppColors.darkOnSurface,
                  ),
                  dialogTheme: const DialogThemeData(
                    barrierColor: AppColors.dialogBarrier,
                    backgroundColor: AppColors.darkAppBar,
                  ),
                )
              : ThemeData(
                  visualDensity: VisualDensity.adaptivePlatformDensity,
                  fontFamily: 'Roboto',
                  colorScheme:
                      _createColorScheme(state.seedColor, Brightness.light),
                  textTheme: const TextTheme(
                    bodyMedium:
                        TextStyle(fontSize: 18.0, fontFamily: 'candara'),
                  ),
                ).copyWith(
                  dialogTheme: DialogThemeData(
                    barrierColor: AppColors.dialogBarrier,
                    backgroundColor: ThemeData(
                      colorScheme:
                          _createColorScheme(state.seedColor, Brightness.light),
                    ).scaffoldBackgroundColor,
                  ),
                ),
          home: MainWindowScreen(initialUrl: initialUrl),
        );
      },
    );
  }
}
