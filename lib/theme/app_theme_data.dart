import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:otzaria_context_menu/otzaria_context_menu.dart'
    show AppMenuMetrics;

import 'package:otzaria/theme/app_colors.dart';
import 'package:otzaria/theme/app_seed_colors.dart';
import 'package:otzaria/theme/app_tokens.dart';

export 'package:otzaria_context_menu/otzaria_context_menu.dart'
    show AppMenuMetrics;

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

  static Color _menuBackground(ColorScheme cs) {
    return cs.surfaceContainerHigh;
  }

  /// בונה [ColorScheme] מצבע seed ובהירות. צבע ניטרלי (אפור/לבן, רוויה
  /// נמוכה) מקבל וריאנט monochrome כדי שלא יקבל גוון צבעוני לא רצוי.
  /// מקור אמת יחיד לבניית הסכמה — נצרך גם ב-app.dart וגם בבניית ה-payload
  /// לתוספים, כדי שכולם יקבלו בדיוק אותם צבעים.
  static ColorScheme createColorScheme(Color seedColor, Brightness brightness) {
    final isNeutral = HSLColor.fromColor(seedColor).saturation < 0.1;
    final scheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: brightness,
      dynamicSchemeVariant: isNeutral
          ? DynamicSchemeVariant.monochrome
          : DynamicSchemeVariant.tonalSpot,
    );
    // ערכת "לבן": monochrome מחזיר לזרע לבן ולזרע אפור את אותו סולם נייטרלי,
    // ולכן גם ה-surface וגם סולם ה-surfaceContainer נדרסים — בלעדיו הסרגל,
    // חלונית הניווט ורקע הלוח נשארים אפורים כמו בערכת "אפור" (issue #1221).
    // "פרגמנט": tonalSpot שומר רק את גוון הזרע, והערכה יצאה זהה ל"חום".
    final surfaces = brightness == Brightness.light
        ? _lightSurfaces[AppThemeVariant.ofSeed(seedColor)]
        : null;
    if (surfaces != null) {
      return scheme.copyWith(
        surface: surfaces[0],
        surfaceContainerLowest: surfaces[1],
        surfaceContainerLow: surfaces[2],
        surfaceContainer: surfaces[3],
        surfaceContainerHigh: surfaces[4],
        surfaceContainerHighest: surfaces[5],
      );
    }
    return scheme;
  }

  static const Map<AppThemeVariant, List<Color>> _lightSurfaces = {
    AppThemeVariant.white: [
      Colors.white,
      Colors.white,
      Color(0xFFFAFAFA),
      Color(0xFFF6F6F6),
      Color(0xFFF1F1F1),
      Color(0xFFECECEC),
    ],
    AppThemeVariant.parchment: [
      Color(0xFFF5EDDC),
      Color(0xFFFAF5EA),
      Color(0xFFF2E8D5),
      Color(0xFFEEE3CD),
      Color(0xFFE9DDC5),
      Color(0xFFE3D6BC),
    ],
  };

  /// גופן הממשק הוא ברירת המחדל של הפלטפורמה (ThemeData בלי fontFamily),
  /// ואחריו רשימת fallback אחת. אין גופן ממשק כלול באפליקציה.
  static const List<String> uiFontFamilyFallback = [
    'Segoe UI',
    'SF Pro Text',
    '.AppleSystemUIFont',
    'Noto Sans Hebrew',
    'Arial',
  ];

  /// המשפחה ש־ThemeData בוחר כשאין fontFamily (Segoe UI ב־Windows), לסגנונות
  /// שנבנים מחוץ ל־textTheme.
  static String? get uiFontFamily => Typography.material2021(
    platform: defaultTargetPlatform,
  ).black.bodyMedium?.fontFamily;

  // ── Light Theme ──────────────────────────────────────────────────────────
  /// [variant] — הערכה של הזרע שממנו נבנתה [cs] ([AppThemeVariant.ofSeed]).
  static ThemeData light(
    ColorScheme cs, {
    required bool compactMenuMode,
    AppThemeVariant variant = AppThemeVariant.standard,
  }) {
    final compactMenus = _usesCompactMenus(compactMenuMode);
    final menuBackground = _menuBackground(cs);
    final menuMetrics = AppMenuMetrics.create(compactMenus: compactMenus);

    return ThemeData(
      useMaterial3: true,
      visualDensity: VisualDensity.adaptivePlatformDensity,
      fontFamilyFallback: uiFontFamilyFallback,
      colorScheme: cs,
      textTheme: const TextTheme(
        bodyMedium: TextStyle(fontSize: 18.0),
      ),
      cardTheme: const CardThemeData(shape: AppTokens.roundedShape),
      iconButtonTheme: IconButtonThemeData(
        style: _hoverButtonStyle(cs.primary),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: _hoverButtonStyle(cs.onPrimary),
      ),
      textButtonTheme: TextButtonThemeData(
        style: _hoverButtonStyle(cs.primary),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: _hoverButtonStyle(cs.primary),
      ),
      tabBarTheme: _tabBarTheme(cs),
      tooltipTheme: _tooltipTheme(cs),
      dropdownMenuTheme: _dropdownMenuTheme(cs, menuMetrics),
      menuButtonTheme: _menuButtonTheme(cs, menuMetrics),
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
      extensions: [menuMetrics, AppThemeVariantTheme(variant)],
    ).copyWith(
      dialogTheme: DialogThemeData(
        barrierColor: AppColors.dialogBarrier,
        backgroundColor: cs.surfaceContainerHigh,
        shape: AppTokens.roundedShape,
      ),
      datePickerTheme: const DatePickerThemeData(
        shape: AppTokens.roundedShape,
        rangePickerShape: AppTokens.roundedShape,
      ),
      // שדות טקסט: מסגרת מלאה בכל האפליקציה (בלי זה שדה ללא border מפורש
      // מצויר כקו תחתון), ובאותו רדיוס כמו שאר הרכיבים.
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: AppTokens.borderRadiusAll),
      ),
    );
  }

  // ── Dark Theme ── זהה לבהיר; ההבדל כולו ב-[cs].
  static ThemeData dark(
    ColorScheme cs, {
    required bool compactMenuMode,
    AppThemeVariant variant = AppThemeVariant.standard,
  }) => light(cs, compactMenuMode: compactMenuMode, variant: variant);

  static PopupMenuThemeData _popupMenuTheme(
    ColorScheme cs, {
    required Color backgroundColor,
    required AppMenuMetrics metrics,
  }) {
    return PopupMenuThemeData(
      color: backgroundColor,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.black.withValues(alpha: 0.22),
      elevation: AppTokens.elevation2,
      shape: AppTokens.roundedShape,
      menuPadding: metrics.menuPadding,
      textStyle: TextStyle(
        fontFamily: uiFontFamily,
        fontFamilyFallback: uiFontFamilyFallback,
        color: cs.onSurface,
        fontSize: metrics.fontSize,
        fontWeight: metrics.itemFontWeight,
      ),
    );
  }

  static TooltipThemeData _tooltipTheme(ColorScheme cs) {
    return TooltipThemeData(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: AppTokens.borderRadiusAll,
        border: Border.all(color: cs.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(
              alpha: 0.22,
            ), // כמו בשאר התפריטים בקובץ
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      textStyle: TextStyle(color: cs.onSurface),
    );
  }

  static MenuStyle _menuStyle(Color backgroundColor, AppMenuMetrics metrics) =>
      MenuStyle(
        backgroundColor: WidgetStatePropertyAll(backgroundColor),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        shadowColor: WidgetStatePropertyAll(
          Colors.black.withValues(alpha: 0.22),
        ),
        elevation: const WidgetStatePropertyAll(AppTokens.elevation2),
        shape: const WidgetStatePropertyAll(AppTokens.roundedShape),
        padding: WidgetStatePropertyAll(metrics.menuPadding),
        visualDensity: metrics.visualDensity,
      );

  static MenuThemeData _menuTheme(
    ColorScheme cs, {
    required Color backgroundColor,
    required AppMenuMetrics metrics,
  }) {
    return MenuThemeData(
      style: _menuStyle(backgroundColor, metrics),
    );
  }

  static DropdownMenuThemeData _dropdownMenuTheme(
    ColorScheme cs,
    AppMenuMetrics metrics,
  ) {
    return DropdownMenuThemeData(
      textStyle: TextStyle(
        fontFamily: uiFontFamily,
        fontFamilyFallback: uiFontFamilyFallback,
        fontSize: metrics.fontSize,
        fontWeight: FontWeight.w400,
        color: cs.onSurface,
      ),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: AppTokens.borderRadiusAll),
        isDense: true,
      ),
      menuStyle: _menuStyle(_menuBackground(cs), metrics),
    );
  }

  static MenuButtonThemeData _menuButtonTheme(
    ColorScheme cs,
    AppMenuMetrics metrics,
  ) {
    final overlayColor = cs.onSurface.withValues(alpha: 0.08);
    return MenuButtonThemeData(
      style: ButtonStyle(
        minimumSize: WidgetStatePropertyAll(Size(0, metrics.itemHeight)),
        padding: WidgetStatePropertyAll(metrics.itemPadding),
        visualDensity: metrics.visualDensity,
        textStyle: WidgetStatePropertyAll(
          TextStyle(
            fontFamily: uiFontFamily,
            fontFamilyFallback: uiFontFamilyFallback,
            fontSize: metrics.fontSize,
            fontWeight: metrics.itemFontWeight,
            color: cs.onSurface,
          ),
        ),
        foregroundColor: WidgetStatePropertyAll(cs.onSurface),
        iconColor: WidgetStatePropertyAll(cs.onSurface),
        shape: const WidgetStatePropertyAll(AppTokens.roundedShape),
        overlayColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.hovered) ||
              states.contains(WidgetState.focused)) {
            return overlayColor;
          }
          return null;
        }),
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

  static ButtonStyle _hoverButtonStyle(Color color) => ButtonStyle(
    shape: const WidgetStatePropertyAll(AppTokens.roundedShape),
    overlayColor: WidgetStateProperty.resolveWith((s) {
      if (s.contains(WidgetState.hovered)) return color.withValues(alpha: 0.08);
      if (s.contains(WidgetState.pressed) || s.contains(WidgetState.focused)) {
        return color.withValues(alpha: 0.12);
      }
      return null;
    }),
  );

  // ══════════════════════════════════════════════════════════════════════════
  //  TabBar Theme — secondaryContainer indicator + primary hover
  // ══════════════════════════════════════════════════════════════════════════

  static TabBarThemeData _tabBarTheme(ColorScheme cs) => TabBarThemeData(
    dividerColor: Colors.transparent,
    dividerHeight: 0,
    indicator: BoxDecoration(
      borderRadius: AppTokens.borderRadiusAll,
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

/// נושא את [AppThemeVariant] בתוך [ThemeData], כדי שמשטחים התלויים בערכה
/// לא יזהו אותה לפי ערכי צבע.
@immutable
class AppThemeVariantTheme extends ThemeExtension<AppThemeVariantTheme> {
  const AppThemeVariantTheme(this.variant);

  final AppThemeVariant variant;

  static AppThemeVariant of(ThemeData theme) =>
      theme.extension<AppThemeVariantTheme>()?.variant ??
      AppThemeVariant.standard;

  @override
  AppThemeVariantTheme copyWith({AppThemeVariant? variant}) =>
      AppThemeVariantTheme(variant ?? this.variant);

  @override
  AppThemeVariantTheme lerp(AppThemeVariantTheme? other, double t) =>
      other != null && t >= 0.5 ? other : this;
}
