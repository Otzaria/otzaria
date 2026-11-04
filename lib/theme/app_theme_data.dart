import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:otzaria_context_menu/otzaria_context_menu.dart'
    show AppMenuMetrics;

import 'package:otzaria/theme/app_density.dart';
import 'package:otzaria/theme/app_focus_ring.dart';
import 'package:otzaria/theme/app_seed_colors.dart';
import 'package:otzaria/theme/app_shadows.dart';
import 'package:otzaria/theme/app_surface_colors.dart';
import 'package:otzaria/theme/app_surfaces.dart';
import 'package:otzaria/theme/app_tokens.dart';
import 'package:otzaria/theme/layout_tokens.dart';

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
    final variant = AppThemeVariant.ofSeed(seedColor);
    final surfaces = brightness == Brightness.light
        ? _lightSurfaces[variant]
        : null;
    if (surfaces != null) {
      return scheme.copyWith(
        surface: surfaces[0],
        surfaceContainerLowest: surfaces[1],
        surfaceContainerLow: surfaces[2],
        surfaceContainer: surfaces[3],
        surfaceContainerHigh: surfaces[4],
        surfaceContainerHighest: surfaces[5],
        secondaryContainer: variant == AppThemeVariant.white
            ? whiteSelectedFill
            : null,
      );
    }
    return scheme;
  }

  /// צבע הבחירה (secondaryContainer) של "לבן" בבהיר: E0 במקום D4 של
  /// monochrome, כדי שיתאים למשטחים הלבנים. באמצע בין D4 לריחוף (onSurface
  /// ‏8% מעל לבן, ED), כדי ש"נבחר" ו"בריחוף" לא יתמזגו, ובכל מקום שבו
  /// "נבחר" נשען רק על הצבע הוא מסומן גם בקו ([AppSurfaceColors.selectedBorder]).
  static const Color whiteSelectedFill = Color(0xFFE0E0E0);

  static const Map<AppThemeVariant, List<Color>> _lightSurfaces = {
    // "לבן" בסגנון Windows הקלאסי (#2850): הקריאה לבנה, והסרגלים, החלוניות
    // והדיאלוגים כמעט לבנים (FC, לוח FA) במקום אפור (F1, לוח F5). ההפרדה
    // בין האזורים היא קו כהה דק (AppSurfaceColors.regionBorder), לא הגוון.
    AppThemeVariant.white: [
      Colors.white,
      Colors.white,
      Color(0xFFFEFEFE),
      Color(0xFFFDFDFD),
      Color(0xFFFCFCFC),
      Color(0xFFF5F5F5),
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

  /// סולם הטקסט של הממשק (DD-02). משקל שלא צוין נשאר של M3; המשפחה, הצבע
  /// וגובה השורה באים מ-Typography של Flutter.
  static const TextTheme textTheme = TextTheme(
    headlineSmall: TextStyle(
      fontSize: AppTokens.font2XL,
      fontWeight: FontWeight.w600,
    ),
    titleLarge: TextStyle(
      fontSize: AppTokens.fontXL,
      fontWeight: FontWeight.w600,
    ),
    titleMedium: TextStyle(
      fontSize: AppTokens.fontLG,
      fontWeight: FontWeight.w700,
    ),
    titleSmall: TextStyle(
      fontSize: AppTokens.fontMD,
      fontWeight: FontWeight.w600,
    ),
    bodyLarge: TextStyle(fontSize: AppTokens.fontLG),
    bodyMedium: TextStyle(fontSize: AppTokens.fontMD),
    bodySmall: TextStyle(fontSize: AppTokens.fontSM),
    labelLarge: TextStyle(
      fontSize: AppTokens.fontMD,
      fontWeight: FontWeight.w500,
    ),
    labelMedium: TextStyle(fontSize: AppTokens.fontSM),
    labelSmall: TextStyle(fontSize: AppTokens.fontXS),
  );

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
    final surfaces = AppSurfaceColors.fromScheme(cs, variant: variant);
    final regionBorder = surfaces.regionBorder;

    final theme = ThemeData(
      useMaterial3: true,
      visualDensity: VisualDensity.adaptivePlatformDensity,
      fontFamilyFallback: uiFontFamilyFallback,
      colorScheme: cs,
      textTheme: textTheme,
      // סרגל הניווט התחתון בטלפון: 64 ולא 80, ותווית לכל יעד (q12 Q8, ss6).
      navigationBarTheme: const NavigationBarThemeData(
        height: LayoutConstraints.bottomNavigationBarHeight,
      ),
      // כרטיס: מסגרת ולא צל (DD-12).
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: AppTokens.borderRadiusAll,
          side: BorderSide(color: cs.outlineVariant),
        ),
      ),
      // כפתור אייקון בלבד עגול (DD-04, q9 שאלה 3). כפתור אייקון עם רקע גלוי
      // משלו (filled, filledTonal או backgroundColor) קובע roundedShape בעצמו
      // ונשאר 8 (q10 שאלה 22). components_contract_test בודק את שניהם.
      iconButtonTheme: IconButtonThemeData(
        style: _hoverButtonStyle(
          cs,
          cs.primary,
        ).copyWith(shape: const WidgetStatePropertyAll(CircleBorder())),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: _hoverButtonStyle(cs, cs.onPrimary),
      ),
      textButtonTheme: TextButtonThemeData(
        style: _hoverButtonStyle(cs, cs.primary),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: _hoverButtonStyle(cs, cs.primary),
      ),
      tabBarTheme: _tabBarTheme(cs),
      segmentedButtonTheme: _segmentedButtonTheme(cs, surfaces.selectedBorder),
      tooltipTheme: _tooltipTheme(cs, regionBorder: regionBorder),
      // פס גלילה: עובי קבוע גם בריחוף, כדי שהרצועה של AppScrollbar תכיל
      // אותו תמיד, ופינות בחצי העובי (q10 Q10).
      scrollbarTheme: const ScrollbarThemeData(
        thickness: WidgetStatePropertyAll(AppTokens.scrollbarThickness),
        radius: Radius.circular(AppTokens.scrollbarThickness / 2),
        crossAxisMargin: AppTokens.scrollbarMargin,
      ),
      dropdownMenuTheme: _dropdownMenuTheme(
        cs,
        menuMetrics,
        regionBorder: regionBorder,
      ),
      menuButtonTheme: _menuButtonTheme(cs, menuMetrics),
      popupMenuTheme: _popupMenuTheme(
        cs,
        backgroundColor: menuBackground,
        metrics: menuMetrics,
        regionBorder: regionBorder,
      ),
      menuTheme: _menuTheme(
        cs,
        backgroundColor: menuBackground,
        metrics: menuMetrics,
        regionBorder: regionBorder,
      ),
      extensions: [
        menuMetrics,
        AppThemeVariantTheme(variant),
        surfaces,
        AppDensity(isCompact: compactMenuMode),
      ],
    );
    return theme.copyWith(
      dialogTheme: DialogThemeData(
        barrierColor: AppSurfaces.scrim(cs),
        backgroundColor: cs.surfaceContainerHigh,
        // "לבן": מסגרת דקה סביב הדיאלוג (#2850).
        shape: raisedShape(regionBorder),
        // כותרת דיאלוג היא titleLarge, כמו ב-AppDialogHeader (M3: headlineSmall).
        // גובה השורה בא מה-geometry, ש-Theme.of ממזג רק לתוך textTheme.
        titleTextStyle: theme.typography.englishLike.titleLarge
            ?.merge(theme.textTheme.titleLarge)
            .copyWith(color: cs.onSurface),
      ),
      // צ'יפ בחירה (FilterChip / ChoiceChip / Chip): פינות 8 ותווית
      // labelMedium 12 (DD-13). הצבע כמו ברירת המחדל של M3.
      chipTheme: ChipThemeData(
        shape: AppTokens.roundedShape,
        labelStyle: theme.textTheme.labelMedium?.copyWith(
          color: WidgetStateColor.resolveWith(
            (states) => states.contains(WidgetState.disabled)
                ? cs.onSurface
                : states.contains(WidgetState.selected)
                ? cs.onSecondaryContainer
                : cs.onSurfaceVariant,
          ),
        ),
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

  /// צורת משטח מוגבה (דיאלוג, תפריט): פינות 8, וב"לבן" בבהיר מסגרת בקו
  /// האזורים ([AppSurfaceColors.regionBorder], ‏#2850). [regionBorder] null —
  /// בלי מסגרת, כמו שהיה.
  static RoundedRectangleBorder raisedShape(Color? regionBorder) =>
      regionBorder == null
      ? AppTokens.roundedShape
      : RoundedRectangleBorder(
          borderRadius: AppTokens.borderRadiusAll,
          side: BorderSide(color: regionBorder, width: AppTokens.borderThin),
        );

  /// בורר מקטעים. ב"לבן" בבהיר ([selectedBorder] לא null) המסגרת והמפרידים
  /// בהירים (outlineVariant, כמו מסגרת כרטיס), והמקטע הנבחר מוקף בקו
  /// [selectedBorder] כהה מהם (AppSegmentedControl). בשאר הערכות ברירת המחדל
  /// של M3 (outline).
  static SegmentedButtonThemeData _segmentedButtonTheme(
    ColorScheme cs,
    Color? selectedBorder,
  ) => selectedBorder == null
      ? const SegmentedButtonThemeData()
      : SegmentedButtonThemeData(
          style: ButtonStyle(
            side: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.disabled)
                  ? null
                  : BorderSide(
                      color: cs.outlineVariant,
                      width: AppTokens.borderThin,
                    ),
            ),
          ),
        );

  static PopupMenuThemeData _popupMenuTheme(
    ColorScheme cs, {
    required Color backgroundColor,
    required AppMenuMetrics metrics,
    required Color? regionBorder,
  }) {
    return PopupMenuThemeData(
      color: backgroundColor,
      surfaceTintColor: Colors.transparent,
      shadowColor: AppShadows.color(cs),
      elevation: AppTokens.elevation2,
      shape: raisedShape(regionBorder),
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

  static TooltipThemeData _tooltipTheme(
    ColorScheme cs, {
    required Color? regionBorder,
  }) {
    return TooltipThemeData(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: AppTokens.borderRadiusAll,
        // "לבן": המסגרת בקו האזורים (#2850).
        border: Border.all(
          color: regionBorder ?? cs.outlineVariant,
          width: AppTokens.borderThin,
        ),
        boxShadow: AppShadows.floating(cs),
      ),
      textStyle: TextStyle(color: cs.onSurface),
    );
  }

  static MenuStyle _menuStyle(
    ColorScheme cs,
    Color backgroundColor,
    AppMenuMetrics metrics, {
    required Color? regionBorder,
  }) => MenuStyle(
    backgroundColor: WidgetStatePropertyAll(backgroundColor),
    surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
    shadowColor: WidgetStatePropertyAll(AppShadows.color(cs)),
    elevation: const WidgetStatePropertyAll(AppTokens.elevation2),
    shape: WidgetStatePropertyAll(raisedShape(regionBorder)),
    padding: WidgetStatePropertyAll(metrics.menuPadding),
    visualDensity: metrics.visualDensity,
  );

  static MenuThemeData _menuTheme(
    ColorScheme cs, {
    required Color backgroundColor,
    required AppMenuMetrics metrics,
    required Color? regionBorder,
  }) {
    return MenuThemeData(
      style: _menuStyle(
        cs,
        backgroundColor,
        metrics,
        regionBorder: regionBorder,
      ),
    );
  }

  static DropdownMenuThemeData _dropdownMenuTheme(
    ColorScheme cs,
    AppMenuMetrics metrics, {
    required Color? regionBorder,
  }) {
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
      menuStyle: _menuStyle(
        cs,
        _menuBackground(cs),
        metrics,
        regionBorder: regionBorder,
      ),
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

  /// הריחוף והלחיצה של כל הכפתורים, וטבעת פוקוס המקלדת ([AppFocusRing]).
  static ButtonStyle _hoverButtonStyle(
    ColorScheme cs,
    Color color,
  ) => ButtonStyle(
    shape: const WidgetStatePropertyAll(AppTokens.roundedShape),
    side: AppFocusRing.buttonSide(cs),
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
