import 'dart:ui' show lerpDouble;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:otzaria/theme/app_colors.dart';
import 'package:otzaria/theme/app_tokens.dart';

// ════════════════════════════════════════════════════════════════════════════
//  app_theme_data.dart — lib/theme/app_theme_data.dart
// ════════════════════════════════════════════════════════════════════════════
//
//  שינויים:
//  • Hover גלובלי M3 — צבע primary (לא אפור) להתאמה לצבעי האפליקציה
//  • TabBarTheme אחיד — secondaryContainer, padding מתאים, ללא קו תחתון
//  • IconButton hover = primary (לא onSurfaceVariant)
//  • Menus בסגנון Chrome — רקע ניטרלי, רדיוס קטן, elevation עדין

class AppThemeData {
  AppThemeData._();

  static bool _isDesktopPlatform(TargetPlatform platform) {
    return switch (platform) {
      TargetPlatform.android || TargetPlatform.iOS => false,
      _ => true,
    };
  }

  static bool _usesCompactMenus(bool compactMenuMode) {
    return _isDesktopPlatform(defaultTargetPlatform) && compactMenuMode;
  }

  static Color _menuBackground(Brightness brightness) {
    return brightness == Brightness.dark
        ? AppColors.menuDarkBackground
        : AppColors.menuLightBackground;
  }

  static BorderSide _menuBorder(ColorScheme cs) {
    return BorderSide(
      color: cs.outlineVariant.withValues(alpha: 0.55),
      width: 1,
    );
  }

  // ── Light Theme ──────────────────────────────────────────────────────────
  static ThemeData light(
    ColorScheme colorScheme, {
    required bool compactMenuMode,
  }) {
    final compactMenus = _usesCompactMenus(compactMenuMode);
    final menuBackground = _menuBackground(Brightness.light);
    final menuMetrics = AppMenuMetrics.create(compactMenus: compactMenus);

    return ThemeData(
      useMaterial3: true,
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
      popupMenuTheme: _popupMenuTheme(
        colorScheme,
        backgroundColor: menuBackground,
        metrics: menuMetrics,
      ),
      menuTheme: _menuTheme(
        colorScheme,
        backgroundColor: menuBackground,
        metrics: menuMetrics,
      ),
      extensions: [menuMetrics],
    ).copyWith(
      dialogTheme: DialogThemeData(
        barrierColor: AppColors.dialogBarrier,
        backgroundColor: colorScheme.surfaceContainerHigh,
      ),
    );
  }

  // ── Dark Theme ───────────────────────────────────────────────────────────
  static ThemeData dark(
    Color darkSeedColor, {
    required bool compactMenuMode,
  }) {
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
    final compactMenus = _usesCompactMenus(compactMenuMode);
    final menuBackground = _menuBackground(Brightness.dark);
    final menuMetrics = AppMenuMetrics.create(compactMenus: compactMenus);

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
      dialogTheme: DialogThemeData(
        barrierColor: AppColors.dialogBarrier,
        backgroundColor: cs.surfaceContainerHigh,
      ),
      iconButtonTheme: _iconButtonTheme(cs),
      filledButtonTheme: _filledButtonTheme(cs),
      textButtonTheme: _textButtonTheme(cs),
      outlinedButtonTheme: _outlinedButtonTheme(cs),
      tabBarTheme: _tabBarTheme(cs),
      popupMenuTheme: _popupMenuTheme(
        cs,
        backgroundColor: menuBackground,
        metrics: menuMetrics,
      ),
      menuTheme: _menuTheme(
        cs,
        backgroundColor: menuBackground,
        metrics: menuMetrics,
      ),
      extensions: [menuMetrics],
    );
  }

  static PopupMenuThemeData _popupMenuTheme(
    ColorScheme cs, {
    required Color backgroundColor,
    required AppMenuMetrics metrics,
  }) {
    return PopupMenuThemeData(
      color: backgroundColor,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.black.withValues(alpha: 0.22),
      elevation: AppTokens.elevation1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTokens.radiusSM),
        side: _menuBorder(cs),
      ),
      menuPadding: metrics.menuPadding,
      textStyle: TextStyle(
        color: cs.onSurface,
        fontSize: AppTokens.fontMD,
      ),
    );
  }

  static MenuThemeData _menuTheme(
    ColorScheme cs, {
    required Color backgroundColor,
    required AppMenuMetrics metrics,
  }) {
    return MenuThemeData(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(backgroundColor),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        shadowColor:
            WidgetStatePropertyAll(Colors.black.withValues(alpha: 0.22)),
        elevation: const WidgetStatePropertyAll(AppTokens.elevation1),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTokens.radiusSM),
            side: _menuBorder(cs),
          ),
        ),
        padding: WidgetStatePropertyAll(metrics.menuPadding),
        visualDensity: metrics.visualDensity,
      ),
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
          // primary (לא אפור) — hover תואם את צבעי האפליקציה
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
        // primary (לא אפור) — hover תואם את צבעי האפליקציה
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

/// עזרי דחיסות ותזוזות עבור תפריטים
class AppMenuMetrics extends ThemeExtension<AppMenuMetrics> {
  final bool compactMenus;
  final double itemHeight;
  final EdgeInsets itemPadding;
  final EdgeInsets menuPadding;
  final VisualDensity visualDensity;
  final double dividerHeight;

  const AppMenuMetrics({
    required this.compactMenus,
    required this.itemHeight,
    required this.itemPadding,
    required this.menuPadding,
    required this.visualDensity,
    required this.dividerHeight,
  });

  factory AppMenuMetrics.create({required bool compactMenus}) {
    final isDesktop = AppThemeData._isDesktopPlatform(defaultTargetPlatform);
    final effectiveCompact = isDesktop && compactMenus;

    return AppMenuMetrics(
      compactMenus: effectiveCompact,
      itemHeight: isDesktop ? (effectiveCompact ? 32 : 40) : 48,
      itemPadding: EdgeInsets.symmetric(
        horizontal: AppTokens.spaceMD,
        vertical: isDesktop ? (effectiveCompact ? 4 : 8) : 8,
      ),
      menuPadding: EdgeInsets.symmetric(
        vertical: isDesktop ? (effectiveCompact ? 4 : 8) : 8,
      ),
      visualDensity: isDesktop
          ? (effectiveCompact ? VisualDensity.compact : VisualDensity.standard)
          : VisualDensity.standard,
      dividerHeight: isDesktop ? (effectiveCompact ? 6 : 8) : 8,
    );
  }

  @override
  AppMenuMetrics copyWith({
    bool? compactMenus,
    double? itemHeight,
    EdgeInsets? itemPadding,
    EdgeInsets? menuPadding,
    VisualDensity? visualDensity,
    double? dividerHeight,
  }) {
    return AppMenuMetrics(
      compactMenus: compactMenus ?? this.compactMenus,
      itemHeight: itemHeight ?? this.itemHeight,
      itemPadding: itemPadding ?? this.itemPadding,
      menuPadding: menuPadding ?? this.menuPadding,
      visualDensity: visualDensity ?? this.visualDensity,
      dividerHeight: dividerHeight ?? this.dividerHeight,
    );
  }

  @override
  AppMenuMetrics lerp(ThemeExtension<AppMenuMetrics>? other, double t) {
    if (other is! AppMenuMetrics) return this;

    return AppMenuMetrics(
      compactMenus: t < 0.5 ? compactMenus : other.compactMenus,
      itemHeight: lerpDouble(itemHeight, other.itemHeight, t) ?? itemHeight,
      itemPadding:
          EdgeInsets.lerp(itemPadding, other.itemPadding, t) ?? itemPadding,
      menuPadding:
          EdgeInsets.lerp(menuPadding, other.menuPadding, t) ?? menuPadding,
      visualDensity: t < 0.5 ? visualDensity : other.visualDensity,
      dividerHeight:
          lerpDouble(dividerHeight, other.dividerHeight, t) ?? dividerHeight,
    );
  }
}
