import 'package:flutter/material.dart';
import 'package:otzaria/theme/app_surface_colors.dart';
import 'package:otzaria/theme/app_seed_colors.dart';
import 'package:otzaria/theme/app_theme_data.dart';
import 'package:otzaria/theme/app_tokens.dart';

AppSurfaceColors _s(BuildContext context) => AppSurfaceColors.of(context);

extension on ColorScheme {
  bool get isDark => brightness == Brightness.dark;
}

/// רקעי מסך לסביבות שימוש שונות באפליקציה.
///
/// הפונקציות שמקבלות [BuildContext] קוראות את [AppSurfaceColors] מה-Theme;
/// הן נשארות עטיפה עד שהקוראים יעברו ל-`AppSurfaceColors.of(context)`.
class AppSurfaces {
  AppSurfaces._();

  /// רקע מסך העיון (טקסט, PDF, חיפוש).
  static Color readerBackground(BuildContext context) =>
      _s(context).readerBackground;

  /// צבע קישורי ספר; בסכמה נייטרלית מובחן מהטקסט בלי לשנות את צבעי הממשק.
  static Color readerLink(ColorScheme cs) =>
      HSLColor.fromColor(cs.primary).saturation < 0.1
      ? (cs.isDark ? const Color(0xFFA0A0A0) : const Color(0xFF5E5E5E))
      : cs.primary;

  /// רקע מסכי לוח — הגדרות, ספריה, כלים וכל מסך משני
  static Color panelBackground(BuildContext context) =>
      _s(context).panelBackground;

  /// רקע סרגל עליון (AppTopBar).
  static Color topBarBackground(BuildContext context) =>
      _s(context).topBarBackground;

  /// רקע חלונית הניווט.
  static Color navPanelBackground(BuildContext context) =>
      _s(context).navPanelBackground;

  /// צבע ברירת המחדל לכרטיסי תוכן באפליקציה.
  static Color card(BuildContext context) => _s(context).card;

  /// רקע קטע-משנה ניטרלי בתוך חלונית הגדרות.
  static Color panelSection(BuildContext context) => _s(context).panelSection;

  /// רקע קטע-משנה מודגש בתוך חלונית (הגדרות, עורך הערה אישית).
  static Color panelSectionAccent(BuildContext context) =>
      _s(context).panelSectionAccent;

  /// גבול קטע-משנה מודגש בתוך חלונית הגדרות.
  static Color panelSectionAccentBorder(BuildContext context) =>
      _s(context).panelSectionAccentBorder;

  /// צבע מפריד פנימי בין שורות בתוך כרטיס תוכן.
  static Color cardRowDivider(BuildContext context) =>
      _s(context).cardRowDivider;

  /// רקע כפתור סרגל במצב נבחר (BarButton, BarSplitButton).
  static Color barButtonSelected(ColorScheme cs) =>
      cs.onSurface.withValues(alpha: 0.12);

  // ── מצבי שורה (DD-06): מקור אחד ל"נבחר", "בפוקוס", "בריחוף" ו"בחירה מרובה".

  /// רקע שורה נבחרת: רשימה, עץ, כרטיס, צ'יפ וכרטיסייה ברשימה. "נבחר"
  /// מסומן גם במשקל הגופן או באייקון, לא רק בצבע.
  static Color selectedRow(ColorScheme cs) => cs.secondaryContainer;

  /// טקסט ואייקון על [selectedRow].
  static Color onSelectedRow(ColorScheme cs) => cs.onSecondaryContainer;

  /// מילוי שורה בפוקוס מקלדת (8% primary), יחד עם [focusRingDecoration].
  static Color focusedRow(ColorScheme cs) => cs.primary.withValues(alpha: 0.08);

  /// טבעת הפוקוס של שורה, לציור מעל התוכן (foregroundDecoration).
  static BoxDecoration focusRingDecoration(ColorScheme cs) => BoxDecoration(
    border: Border.all(color: cs.primary, width: AppTokens.focusRingWidth),
    borderRadius: AppTokens.borderRadiusAll,
  );

  /// רקע שורה בריחוף: שכבת ה-hover של M3 (8% onSurface).
  static Color hoverRow(ColorScheme cs) => cs.onSurface.withValues(alpha: 0.08);

  /// כרטיסייה בבחירה מרובה, עם מסגרת [multiSelectedBorder].
  static Color multiSelected(ColorScheme cs) => cs.primaryContainer;

  /// מסגרת כרטיסייה בבחירה מרובה ([AppTokens.multiSelectedBorderWidth]).
  static Color multiSelectedBorder(ColorScheme cs) => cs.primary;

  /// רקע הפסקה הנבחרת במסך העיון — השורה הפעילה בספר.
  ///
  /// ברירת מחדל: 8% primary — רמז עדין של הצבע הראשי. בערכת "לבן" במצב
  /// בהיר הרקע בהיר יותר — F8FAFC — כדי שהבחירה תהיה עדינה וקרובה ללבן.
  static Color paragraphSelectionBackground(ThemeData theme) =>
      theme.brightness == Brightness.light &&
          AppThemeVariantTheme.of(theme) == AppThemeVariant.white
      ? const Color(0xFFF8FAFC)
      : theme.colorScheme.primary.withValues(alpha: 0.08);

  /// פס בצד תחילת השורה לפסקה שתוקנה מקומית בסשן תיקון של תוסף.
  static Color correctedParagraphMarker(ColorScheme cs) => cs.tertiary;

  /// רקע זמני לשורת ספר שהודגשה (מעבר מקישור/חיפוש/תוכן עניינים).
  static Color highlightedLineBackground(ColorScheme cs) =>
      cs.secondaryContainer.withValues(alpha: 0.4);

  /// רקע הדגשה לשורה שמעליה מרחפים בגרירה (drag target).
  ///
  /// 8% primary — רמז עדין למקום השחרור מבלי להסתיר את תוכן השורה.
  static Color dragTargetHighlight(ColorScheme cs) =>
      cs.primary.withValues(alpha: 0.08);

  /// רקע הקטע שהחיפוש החכם סימן לפי עניין: גוון הדגשת המילים בתוצאות,
  /// שקוף מספיק כדי שלא יתחרה בהתאמה מילולית.
  static Color semanticPassageHighlight(ColorScheme cs) =>
      cs.error.withValues(alpha: 0.12);

  /// מילוי חיווי ההפלה של חלונית קריאה — המלבן שמסמן היכן תיפול החלונית.
  ///
  /// 16% primary — קריא מעל תוכן ספר, ועדיין שקוף מספיק כדי לראות
  /// לאיזה חלק מהתצוגה החלונית תיכנס.
  static Color paneDropPreview(ColorScheme cs) =>
      cs.primary.withValues(alpha: 0.16);

  /// מסגרת חיווי ההפלה של חלונית קריאה.
  static Color paneDropPreviewBorder(ColorScheme cs) =>
      cs.primary.withValues(alpha: 0.7);

  /// רקע כרטיס החלונית בטאב מפוצל — אותו רקע קריאה, בתוך מסגרת מעוגלת.
  static Color paneCard(BuildContext context) => _s(context).paneCard;

  /// הרווח שבין כרטיסי החלוניות. גוון אחד כהה/בהיר מרקע הקריאה, כדי
  /// שההפרדה תיראה בלי קו מפריד — ובלי להתנגש בצבע הקריאה שהמשתמש בחר.
  static Color paneGutter(BuildContext context) => _s(context).paneGutter;

  /// מסגרת כרטיס החלונית. החלונית הפעילה מסומנת בקו דק בצבע הראשי, והשאר
  /// נשענות על הרווח שביניהן בלבד.
  static Color paneCardBorder(ColorScheme cs, {required bool isActive}) =>
      isActive
      ? cs.primary.withValues(alpha: 0.55)
      : cs.outlineVariant.withValues(alpha: 0.35);

  /// ידית המפריד בין חלוניות — נראית רק בהצבעה, בגרירה או בפוקוס.
  /// ההיעלמות היא באלפא של אותו גוון, כדי שהדהייה תהיה שקיפות בלבד.
  static Color paneDividerHandle(ColorScheme cs, {required bool isActive}) =>
      isActive ? cs.primary : cs.primary.withValues(alpha: 0);

  /// רקע רצועת [PanelOpenHandle] — מתפוגג מעט במצב רגיל, אטום יותר ב-hover.
  static Color panelOpenHandle(ColorScheme cs, {required bool isHovering}) =>
      cs.surfaceContainerHighest.withValues(alpha: isHovering ? 0.95 : 0.8);

  /// אגודל הסקרולבר המותאם — בולט בזמן גרירה, מעומעם במנוחה.
  static Color scrollbarThumb(ColorScheme cs, {required bool isDragging}) =>
      isDragging
      ? cs.primary.withValues(alpha: 0.8)
      : cs.onSurfaceVariant.withValues(alpha: 0.4);

  /// רקע מתג קומפקטי בסגנון גלולה (מתגי דיאלוג החיפוש) — מודגש כשדלוק.
  static Color togglePill(ColorScheme cs, {required bool active}) => active
      ? cs.primaryContainer.withValues(alpha: 0.6)
      : cs.surfaceContainerHighest.withValues(alpha: 0.5);

  /// הדגשת קישור בתוך עמוד PDF בריחוף — 20% primary, קריא מעל עמוד סרוק.
  static Color pdfLinkHover(ColorScheme cs) =>
      cs.primary.withValues(alpha: 0.2);
}
