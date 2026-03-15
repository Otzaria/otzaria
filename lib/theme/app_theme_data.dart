import 'package:flutter/material.dart';
import 'package:otzaria/theme/app_tokens.dart';
import 'package:otzaria/theme/app_colors.dart';

// ════════════════════════════════════════════════════════════════════════════
//  app_theme_data.dart — lib/theme/app_theme_data.dart
// ════════════════════════════════════════════════════════════════════════════
//
//  שינויים:
//  • Hover גלובלי M3 — צבע primary (לא אפור) להתאמה לצבעי האפליקציה
//  • TabBarTheme אחיד — secondaryContainer, padding מתאים, ללא קו תחתון
//  • IconButton hover = primary (לא onSurfaceVariant)

class AppThemeData {
  AppThemeData._();

  // ── Light Theme ──────────────────────────────────────────────────────────
  static ThemeData light(ColorScheme colorScheme) {
    return ThemeData(
      visualDensity: VisualDensity.adaptivePlatformDensity,
      fontFamily: 'Roboto',
      colorScheme: colorScheme,
      textTheme: const TextTheme(
        bodyMedium: TextStyle(fontSize: 18.0, fontFamily: 'candara'),
      ),
      iconButtonTheme: _iconButtonTheme(colorScheme),
      filledButtonTheme: _filledButtonTheme(colorScheme),
      textButtonTheme: _textButtonTheme(colorScheme),
      outlinedButtonTheme: _outlinedButtonTheme(colorScheme),
      tabBarTheme: _tabBarTheme(colorScheme),
    ).copyWith(
      dialogTheme: DialogThemeData(
        barrierColor: AppColors.dialogBarrier,
        backgroundColor: colorScheme.surface,
      ),
    );
  }

  // ── Dark Theme ───────────────────────────────────────────────────────────
  static ThemeData dark(Color darkSeedColor) {
    final cs = ColorScheme.dark(
      surface: AppColors.darkScaffold,
      surfaceContainer: AppColors.darkCard,
      onSurface: AppColors.darkOnSurface,
      primary: darkSeedColor,
      onPrimary: Colors.white,
      secondary: darkSeedColor.withValues(alpha: 0.7),
      onSecondary: Colors.white,
      outline: AppColors.darkOutline,
    );
    return ThemeData.dark(useMaterial3: true).copyWith(
      scaffoldBackgroundColor: AppColors.darkScaffold,
      canvasColor: AppColors.darkScaffold,
      cardColor: AppColors.darkCard,
      colorScheme: cs,
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
          side: const BorderSide(color: AppColors.darkOutline, width: 1),
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
      iconButtonTheme: _iconButtonTheme(cs),
      filledButtonTheme: _filledButtonTheme(cs),
      textButtonTheme: _textButtonTheme(cs),
      outlinedButtonTheme: _outlinedButtonTheme(cs),
      tabBarTheme: _tabBarTheme(cs),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  Button Themes — Hover בצבע primary
  // ══════════════════════════════════════════════════════════════════════════
  //
  //  M3: hover = 8% overlay, pressed/focused = 12%
  //  צבע: primary (לא אפור) — מתאים לפלטת הצבעים החמה של האפליקציה
  // ──────────────────────────────────────────────────────────────────────────

  static IconButtonThemeData _iconButtonTheme(ColorScheme cs) =>
      IconButtonThemeData(
        style: ButtonStyle(
          // צורה עגולה — M3 standard
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppTokens.radiusXL),
            ),
          ),
          // ✅ primary (לא אפור) — hover תואם את צבעי האפליקציה
          overlayColor: WidgetStateProperty.resolveWith((s) {
            if (s.contains(WidgetState.hovered)) {
              return cs.primary.withValues(alpha: 0.08);
            }
            if (s.contains(WidgetState.pressed) ||
                s.contains(WidgetState.focused)) {
              return cs.primary.withValues(alpha: 0.12);
            }
            return null;
          }),
        ),
      );

  static FilledButtonThemeData _filledButtonTheme(ColorScheme cs) =>
      FilledButtonThemeData(
        style: ButtonStyle(
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppTokens.radiusMD),
            ),
          ),
          overlayColor: WidgetStateProperty.resolveWith((s) {
            if (s.contains(WidgetState.hovered)) {
              return cs.onPrimary.withValues(alpha: 0.08);
            }
            if (s.contains(WidgetState.pressed) ||
                s.contains(WidgetState.focused)) {
              return cs.onPrimary.withValues(alpha: 0.12);
            }
            return null;
          }),
        ),
      );

  static TextButtonThemeData _textButtonTheme(ColorScheme cs) =>
      TextButtonThemeData(
        style: ButtonStyle(
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppTokens.radiusMD),
            ),
          ),
          overlayColor: WidgetStateProperty.resolveWith((s) {
            if (s.contains(WidgetState.hovered)) {
              return cs.primary.withValues(alpha: 0.08);
            }
            if (s.contains(WidgetState.pressed) ||
                s.contains(WidgetState.focused)) {
              return cs.primary.withValues(alpha: 0.12);
            }
            return null;
          }),
        ),
      );

  static OutlinedButtonThemeData _outlinedButtonTheme(ColorScheme cs) =>
      OutlinedButtonThemeData(
        style: ButtonStyle(
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppTokens.radiusMD),
            ),
          ),
          overlayColor: WidgetStateProperty.resolveWith((s) {
            if (s.contains(WidgetState.hovered)) {
              return cs.primary.withValues(alpha: 0.08);
            }
            if (s.contains(WidgetState.pressed) ||
                s.contains(WidgetState.focused)) {
              return cs.primary.withValues(alpha: 0.12);
            }
            return null;
          }),
        ),
      );

  // ══════════════════════════════════════════════════════════════════════════
  //  TabBar Theme — secondaryContainer indicator + primary hover
  // ══════════════════════════════════════════════════════════════════════════

  static TabBarThemeData _tabBarTheme(ColorScheme cs) => TabBarThemeData(
        dividerColor: Colors.transparent,
        dividerHeight: 0,
        indicator: BoxDecoration(
          borderRadius: BorderRadius.circular(AppTokens.radiusMD),
          color: cs.secondaryContainer,
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        labelColor: cs.onSurface,
        unselectedLabelColor: cs.onSurfaceVariant,
        labelStyle: const TextStyle(
          fontSize: AppTokens.fontMD,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelStyle: const TextStyle(
          fontSize: AppTokens.fontMD,
          fontWeight: FontWeight.w400,
        ),
        // ✅ primary (לא אפור) — hover תואם את צבעי האפליקציה
        overlayColor: WidgetStateProperty.resolveWith((s) {
          if (s.contains(WidgetState.hovered)) {
            return cs.primary.withValues(alpha: 0.08);
          }
          if (s.contains(WidgetState.pressed)) {
            return cs.primary.withValues(alpha: 0.12);
          }
          return null;
        }),
      );
}
