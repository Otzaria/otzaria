import 'package:flutter/material.dart';
import 'package:otzaria/theme/app_tokens.dart';
import 'package:otzaria/theme/app_colors.dart';

// ════════════════════════════════════════════════════════════════════════════
//  app_theme_data.dart — lib/theme/app_theme_data.dart
// ════════════════════════════════════════════════════════════════════════════
//  הגדרות ThemeData של אוצריא — light ו-dark.
//
//  שינויים:
//  • Hover גלובלי לכל כפתורי האפליקציה — M3 (8% hover / 12% press)
//  • TabBarTheme אחיד — secondaryContainer indicator, ללא קו תחתון
//    (MoreScreen ו-SettingsScreen כבר לא יצטרכו להגדיר זאת ידנית)
//
//  שימוש ב-app.dart:
//  theme:     AppThemeData.light(lightColorScheme),
//  darkTheme: AppThemeData.dark(state.darkSeedColor),
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
      // ── Hover גלובלי ────────────────────────────────────────────────────
      iconButtonTheme: _iconButtonTheme(colorScheme),
      filledButtonTheme: _filledButtonTheme(colorScheme),
      textButtonTheme: _textButtonTheme(colorScheme),
      outlinedButtonTheme: _outlinedButtonTheme(colorScheme),
      // ── TabBar אחיד ───────────────────────────────────────────────────
      tabBarTheme: _tabBarTheme(colorScheme),
    ).copyWith(
      dialogTheme: DialogThemeData(
        barrierColor: AppColors.dialogBarrier,
        backgroundColor: colorScheme.surface,
      ),
    );
  }

  // ── Dark Theme ─────────────────────────────────────────────────────────────

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
      // ── Hover גלובלי ──────────────────────────────────────────────────
      iconButtonTheme: _iconButtonTheme(cs),
      filledButtonTheme: _filledButtonTheme(cs),
      textButtonTheme: _textButtonTheme(cs),
      outlinedButtonTheme: _outlinedButtonTheme(cs),
      // ── TabBar אחיד ───────────────────────────────────────────────────
      tabBarTheme: _tabBarTheme(cs),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  Button Themes — Hover גלובלי M3
  // ══════════════════════════════════════════════════════════════════════════
  //
  //  עיקרון M3:
  //    hover   = 8%  overlay מעל foreground-color
  //    pressed = 12% overlay
  //    focused = 12% overlay
  //
  //  הגדרה ברמת ThemeData → כל הכפתורים בכל האפליקציה יתנהגו אחיד,
  //  ללא צורך לחזור על overlayColor בכל widget בנפרד.
  //
  //  מקור: https://m3.material.io/foundations/interaction/states/overview
  // ──────────────────────────────────────────────────────────────────────────

  static IconButtonThemeData _iconButtonTheme(ColorScheme cs) {
    return IconButtonThemeData(
      style: ButtonStyle(
        // Hover בגודל הכפתור — צורה עגולה לפי M3
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTokens.radiusXL),
          ),
        ),
        overlayColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.hovered)) {
            return cs.onSurfaceVariant.withValues(alpha: 0.08);
          }
          if (states.contains(WidgetState.pressed) ||
              states.contains(WidgetState.focused)) {
            return cs.onSurfaceVariant.withValues(alpha: 0.12);
          }
          return null;
        }),
      ),
    );
  }

  static FilledButtonThemeData _filledButtonTheme(ColorScheme cs) {
    return FilledButtonThemeData(
      style: ButtonStyle(
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTokens.radiusMD),
          ),
        ),
        overlayColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.hovered)) {
            return cs.onPrimary.withValues(alpha: 0.08);
          }
          if (states.contains(WidgetState.pressed) ||
              states.contains(WidgetState.focused)) {
            return cs.onPrimary.withValues(alpha: 0.12);
          }
          return null;
        }),
      ),
    );
  }

  static TextButtonThemeData _textButtonTheme(ColorScheme cs) {
    return TextButtonThemeData(
      style: ButtonStyle(
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTokens.radiusMD),
          ),
        ),
        overlayColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.hovered)) {
            return cs.primary.withValues(alpha: 0.08);
          }
          if (states.contains(WidgetState.pressed) ||
              states.contains(WidgetState.focused)) {
            return cs.primary.withValues(alpha: 0.12);
          }
          return null;
        }),
      ),
    );
  }

  static OutlinedButtonThemeData _outlinedButtonTheme(ColorScheme cs) {
    return OutlinedButtonThemeData(
      style: ButtonStyle(
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTokens.radiusMD),
          ),
        ),
        overlayColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.hovered)) {
            return cs.primary.withValues(alpha: 0.08);
          }
          if (states.contains(WidgetState.pressed) ||
              states.contains(WidgetState.focused)) {
            return cs.primary.withValues(alpha: 0.12);
          }
          return null;
        }),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  TabBar Theme — אחיד לכל האפליקציה
  // ══════════════════════════════════════════════════════════════════════════
  //
  //  M3 Secondary TabBar:
  //  • indicator = BoxDecoration עם secondaryContainer + border-radius
  //  • dividerColor = transparent (ללא קו מפריד תחתון)
  //  • labelColor / unselectedLabelColor = onSurface / onSurfaceVariant
  //
  //  לאחר הגדרה זו:
  //  MoreScreen ו-SettingsScreen אינם צריכים להגדיר TabBar styles ידנית.
  //  רק indicatorPadding ו-isScrollable משתנים לפי צורך ספציפי.
  // ──────────────────────────────────────────────────────────────────────────

  static TabBarThemeData _tabBarTheme(ColorScheme cs) {
    return TabBarThemeData(
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
      overlayColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.hovered)) {
          return cs.onSurface.withValues(alpha: 0.08);
        }
        if (states.contains(WidgetState.pressed)) {
          return cs.onSurface.withValues(alpha: 0.12);
        }
        return null;
      }),
    );
  }
}
