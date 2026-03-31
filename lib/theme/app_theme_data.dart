import 'package:flutter/material.dart';
import 'package:otzaria/theme/app_tokens.dart';
import 'package:otzaria/theme/app_colors.dart';

// ════════════════════════════════════════════════════════════════════════════
//  app_theme_data.dart
//  lib/theme/app_theme_data.dart
// ════════════════════════════════════════════════════════════════════════════
//  הגדרות ThemeData של אוצריא — light ו-dark.
//
//  שימוש ב-app.dart:
//  ```dart
//  theme:     AppThemeData.light(lightColorScheme),
//  darkTheme: AppThemeData.dark(state.darkSeedColor),
//  ```
// ════════════════════════════════════════════════════════════════════════════

class AppThemeData {
  AppThemeData._();

  // ── Light Theme ────────────────────────────────────────────────────────────

  static ThemeData light(ColorScheme colorScheme) {
    return ThemeData(
      visualDensity: VisualDensity.adaptivePlatformDensity,
      fontFamily: 'Roboto',
      colorScheme: colorScheme,
      textTheme: const TextTheme(
        bodyMedium: TextStyle(fontSize: 18.0, fontFamily: 'candara'),
      ),
    ).copyWith(
      dialogTheme: DialogThemeData(
        barrierColor: AppColors.dialogBarrier,
        backgroundColor: colorScheme.surface,
      ),
    );
  }

  // ── Dark Theme ─────────────────────────────────────────────────────────────

  static ThemeData dark(Color darkSeedColor) {
    return ThemeData.dark(useMaterial3: true).copyWith(
      scaffoldBackgroundColor: AppColors.darkScaffold,
      canvasColor: AppColors.darkScaffold,
      cardColor: AppColors.darkCard,
      colorScheme: ColorScheme.dark(
        surface: AppColors.darkScaffold,
        surfaceContainer: AppColors.darkCard,
        onSurface: AppColors.darkOnSurface,
        primary: darkSeedColor,
        onPrimary: Colors.white,
        secondary: darkSeedColor.withValues(alpha: 0.7),
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
        elevation: AppTokens.elevation2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusMD),
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
    );
  }
}
