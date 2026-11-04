import 'package:flutter/material.dart';
import 'package:material_color_utilities/material_color_utilities.dart';
import 'package:otzaria/theme/app_colors.dart';
import 'package:otzaria/theme/app_seed_colors.dart';

/// רקעי המשטחים של ערכת הנושא, מחושבים פעם אחת מתוך [ColorScheme].
///
/// נבנה ב-[AppThemeData] ונקרא דרך [AppSurfaceColors.of]. אפשר לדרוס אותו
/// לתת-עץ עם `Theme` שמחליף את ההרחבה.
@immutable
class AppSurfaceColors extends ThemeExtension<AppSurfaceColors> {
  const AppSurfaceColors({
    required this.readerBackground,
    required this.panelBackground,
    required this.topBarBackground,
    required this.navPanelBackground,
    required this.card,
    required this.panelSection,
    required this.panelSectionAccent,
    required this.panelSectionAccentBorder,
    required this.cardRowDivider,
    required this.paneCard,
    required this.paneGutter,
    required this.warning,
    required this.onWarning,
    required this.warningContainer,
    required this.onWarningContainer,
    this.regionBorder,
  });

  /// [variant] — הערכה של הזרע שממנו נבנתה [cs] ([AppThemeVariant.ofSeed]).
  factory AppSurfaceColors.fromScheme(
    ColorScheme cs, {
    AppThemeVariant variant = AppThemeVariant.standard,
  }) {
    final isDark = cs.brightness == Brightness.dark;
    // בכהה הקריאה נייטרלית ולא נגזרת מהזרע, והלוחות בסולם ה-surface שלו
    // (DD-05).
    final reader = isDark ? AppColors.darkScaffold : cs.surface;
    final panel = isDark
        ? cs.surfaceContainerLow
        : Color.alphaBlend(
            cs.surfaceContainerHighest.withValues(alpha: 0.475),
            cs.surface,
          );
    final topBar = cs.surfaceContainerHigh;
    // אזהרה: גוון קבוע שמתקרב לזרע (עד 15°), בטונים של M3 (DD-24).
    final warningTones = TonalPalette.of(
      Hct.fromInt(
        Blend.harmonize(
          AppColors.warningHue.toARGB32(),
          cs.primary.toARGB32(),
        ),
      ).hue,
      40,
    );
    Color tone(int light, int dark) =>
        Color(warningTones.get(isDark ? dark : light));
    return AppSurfaceColors(
      readerBackground: reader,
      panelBackground: panel,
      topBarBackground: topBar,
      navPanelBackground: topBar,
      card: isDark ? cs.surfaceContainer : cs.surface,
      panelSection: cs.surfaceContainerHighest.withValues(alpha: 0.5),
      panelSectionAccent: cs.primaryContainer.withValues(alpha: 0.3),
      panelSectionAccentBorder: cs.primary.withValues(alpha: 0.3),
      cardRowDivider: panel,
      paneCard: reader,
      paneGutter: Color.alphaBlend(
        (isDark ? cs.onSurface : cs.shadow).withValues(alpha: 0.07),
        reader,
      ),
      warning: tone(40, 80),
      onWarning: tone(100, 20),
      warningContainer: tone(90, 30),
      onWarningContainer: tone(10, 90),
      // "לבן" בבהיר: האזורים כמעט באותו לבן, ולכן קו כהה דק ביניהם, בסגנון
      // Windows הקלאסי (#1939, ‏#2850).
      regionBorder: variant == AppThemeVariant.white && !isDark
          ? cs.onSurface
          : null,
    );
  }

  /// המשטחים של ה-Theme הקרוב. Theme שלא נבנה ב-[AppThemeData] מקבל
  /// משטחים שמחושבים מה-[ColorScheme] שלו.
  static AppSurfaceColors of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<AppSurfaceColors>() ??
        AppSurfaceColors.fromScheme(theme.colorScheme);
  }

  /// רקע מסך העיון (טקסט, PDF, חיפוש).
  final Color readerBackground;

  /// רקע מסכי לוח: הגדרות, ספרייה, כלים וכל מסך משני.
  final Color panelBackground;

  /// רקע הסרגל העליון (AppTopBar).
  final Color topBarBackground;

  /// רקע חלונית הניווט. היום כצבע הסרגל, כדי שתיראה כהמשך רציף שלו.
  final Color navPanelBackground;

  /// רקע כרטיסי תוכן.
  final Color card;

  /// רקע קטע-משנה ניטרלי בתוך חלונית הגדרות.
  final Color panelSection;

  /// רקע קטע-משנה מודגש בתוך חלונית.
  final Color panelSectionAccent;

  /// גבול קטע-משנה מודגש בתוך חלונית.
  final Color panelSectionAccentBorder;

  /// מפריד פנימי בין שורות בתוך כרטיס תוכן.
  final Color cardRowDivider;

  /// רקע כרטיס החלונית בטאב מפוצל.
  final Color paneCard;

  /// הרווח שבין כרטיסי החלוניות: גוון אחד כהה/בהיר מרקע הקריאה.
  final Color paneGutter;

  /// אזהרה: אייקון, מסגרת וטקסט מודגש על המשטח.
  final Color warning;

  /// טקסט ואייקון על [warning].
  final Color onWarning;

  /// רקע באנר, הודעה או תגית של אזהרה.
  final Color warningContainer;

  /// טקסט ואייקון על [warningContainer].
  final Color onWarningContainer;

  /// הקו הדק (1) שמפריד בין אזורי החלון: שורת הכותרת ועמודת הכרטיסיות.
  /// קיים רק בערכת "לבן" בבהיר, שבה
  /// האזורים כמעט באותו צבע. `null` בכל ערכה אחרת: שם כל אזור שומר על
  /// ההפרדה שלו (גוון, צל או קו בהיר), ולכן קוראים כותבים `regionBorder ??`.
  final Color? regionBorder;

  @override
  AppSurfaceColors copyWith({
    Color? readerBackground,
    Color? panelBackground,
    Color? topBarBackground,
    Color? navPanelBackground,
    Color? card,
    Color? panelSection,
    Color? panelSectionAccent,
    Color? panelSectionAccentBorder,
    Color? cardRowDivider,
    Color? paneCard,
    Color? paneGutter,
    Color? warning,
    Color? onWarning,
    Color? warningContainer,
    Color? onWarningContainer,
    Color? regionBorder,
  }) => AppSurfaceColors(
    readerBackground: readerBackground ?? this.readerBackground,
    panelBackground: panelBackground ?? this.panelBackground,
    topBarBackground: topBarBackground ?? this.topBarBackground,
    navPanelBackground: navPanelBackground ?? this.navPanelBackground,
    card: card ?? this.card,
    panelSection: panelSection ?? this.panelSection,
    panelSectionAccent: panelSectionAccent ?? this.panelSectionAccent,
    panelSectionAccentBorder:
        panelSectionAccentBorder ?? this.panelSectionAccentBorder,
    cardRowDivider: cardRowDivider ?? this.cardRowDivider,
    paneCard: paneCard ?? this.paneCard,
    paneGutter: paneGutter ?? this.paneGutter,
    warning: warning ?? this.warning,
    onWarning: onWarning ?? this.onWarning,
    warningContainer: warningContainer ?? this.warningContainer,
    onWarningContainer: onWarningContainer ?? this.onWarningContainer,
    regionBorder: regionBorder ?? this.regionBorder,
  );

  @override
  AppSurfaceColors lerp(AppSurfaceColors? other, double t) {
    if (other == null) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppSurfaceColors(
      readerBackground: l(readerBackground, other.readerBackground),
      panelBackground: l(panelBackground, other.panelBackground),
      topBarBackground: l(topBarBackground, other.topBarBackground),
      navPanelBackground: l(navPanelBackground, other.navPanelBackground),
      card: l(card, other.card),
      panelSection: l(panelSection, other.panelSection),
      panelSectionAccent: l(panelSectionAccent, other.panelSectionAccent),
      panelSectionAccentBorder: l(
        panelSectionAccentBorder,
        other.panelSectionAccentBorder,
      ),
      cardRowDivider: l(cardRowDivider, other.cardRowDivider),
      paneCard: l(paneCard, other.paneCard),
      paneGutter: l(paneGutter, other.paneGutter),
      warning: l(warning, other.warning),
      onWarning: l(onWarning, other.onWarning),
      warningContainer: l(warningContainer, other.warningContainer),
      onWarningContainer: l(onWarningContainer, other.onWarningContainer),
      regionBorder: Color.lerp(regionBorder, other.regionBorder, t),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AppSurfaceColors &&
      other.readerBackground == readerBackground &&
      other.panelBackground == panelBackground &&
      other.topBarBackground == topBarBackground &&
      other.navPanelBackground == navPanelBackground &&
      other.card == card &&
      other.panelSection == panelSection &&
      other.panelSectionAccent == panelSectionAccent &&
      other.panelSectionAccentBorder == panelSectionAccentBorder &&
      other.cardRowDivider == cardRowDivider &&
      other.paneCard == paneCard &&
      other.paneGutter == paneGutter &&
      other.warning == warning &&
      other.onWarning == onWarning &&
      other.warningContainer == warningContainer &&
      other.onWarningContainer == onWarningContainer &&
      other.regionBorder == regionBorder;

  @override
  int get hashCode => Object.hash(
    readerBackground,
    panelBackground,
    topBarBackground,
    navPanelBackground,
    card,
    panelSection,
    panelSectionAccent,
    panelSectionAccentBorder,
    cardRowDivider,
    paneCard,
    paneGutter,
    warning,
    onWarning,
    warningContainer,
    onWarningContainer,
    regionBorder,
  );
}

/// אזור הקורא: כל Scaffold בתוכו (ספר טקסט, PDF, חיפוש) מקבל את רקע הקריאה
/// כרקע ברירת המחדל שלו.
class ReaderSurfaceScope extends StatelessWidget {
  const ReaderSurfaceScope({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Theme(
      data: theme.copyWith(
        scaffoldBackgroundColor: AppSurfaceColors.of(context).readerBackground,
      ),
      child: child,
    );
  }
}
