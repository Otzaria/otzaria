import 'package:flutter/material.dart';

class AppTokens {
  // ── Spacing ————————————————————————————————
  // ערך שמחוץ לסולם עולה לערך הבא: 6→8, 10→12, 14→16.
  static const double space2XS = 2;
  static const double spaceXS = 4;
  static const double spaceSM = 8;
  static const double spaceSMD = 12;
  static const double spaceMD = 16;
  static const double spaceLG = 24;
  static const double spaceXL = 32;

  // ── Semantic Spacing ———————————————————————
  static const EdgeInsets cardPadding = EdgeInsets.all(spaceSMD);
  static const double listItemGap = spaceSM;

  /// ריפוד התוכן של דיאלוג עם פס כותרת.
  static const EdgeInsets dialogPadding = EdgeInsets.symmetric(
    horizontal: spaceLG,
    vertical: spaceMD,
  );

  // ── Icon Sizes ———————————————————————————————
  static const double iconXS = 14;
  static const double iconSM = 16;
  static const double iconMD = 20;
  static const double iconLG = 24;
  static const double iconXL = 48;

  // ── Border Radius — מקור אמת יחיד: כל הפינות 8 ——————————————
  static const double radius = 8;
  static const BorderRadius borderRadiusAll = BorderRadius.all(
    Radius.circular(radius),
  );
  static const RoundedRectangleBorder roundedShape = RoundedRectangleBorder(
    borderRadius: borderRadiusAll,
  );

  // ── Typography Scale — מקור ה-textTheme ב-AppThemeData (DD-02) ——————
  static const double fontXS = 11;
  static const double fontSM = 12;
  static const double fontMD = 14;
  static const double fontLG = 16;
  static const double fontXL = 18;
  static const double font2XL = 22;

  // ── State Borders (DD-06) ————————————————————
  /// טבעת הפוקוס של שורה.
  static const double focusRingWidth = 2;

  /// מסגרת כרטיסייה בבחירה מרובה.
  static const double multiSelectedBorderWidth = 1.5;

  /// קו דק: מסגרת ומפריד, וקו האזורים של "לבן" (`AppSurfaceColors.regionBorder`).
  static const double borderThin = 1;

  // ── Scrollbar — פס אנכי בימין הפיזי, ברצועה משלו (AppScrollbar) ——————
  /// עובי האגודל. הפינות חצי ממנו (q10 Q10).
  static const double scrollbarThickness = 8;

  /// המרחק בין האגודל לקצה של אזור הגלילה.
  static const double scrollbarMargin = 2;

  /// המרווח בין האגודל לתוכן.
  static const double scrollbarContentGap = 2;

  /// הרצועה שהפס שומר לעצמו כשיש מה לגלול.
  static const double scrollbarGutter =
      scrollbarMargin + scrollbarThickness + scrollbarContentGap;

  // ── Elevation (DD-12): 0 / 1 / 3 בלבד, הצל מ-AppShadows ——————————
  // כרטיס ומשטח רגיל: 0, עם מסגרת outlineVariant.
  /// סרגל עליון וחלונית מוצמדת.
  static const double elevation1 = 1;

  /// תפריט, tooltip, חלונית צפה ומשוב גרירה.
  static const double elevation2 = 3;

  // ── Animation Durations ————————————————————
  static const Duration animFast = Duration(milliseconds: 150);
  static const Duration animNormal = Duration(milliseconds: 250);
  static const Duration animPanelOpacity = Duration(milliseconds: 200);
  static const Duration animPanelSlide = Duration(milliseconds: 300);

  /// השהיה לפני תצוגה מקדימה ברפרוף (לא תנועה, ולכן לא עוברת דרך AppMotion).
  static const Duration hoverPreviewDelay = Duration(milliseconds: 280);

  // ── Drag Handle ——————————————————————————————
  static const double dragHandleCompactHitSize = 18;
  static const double dragHandleRegularHitSize = 24;

  // ── Panel Tab ————————————————————————————————
  static const double panelTabHeight = 44;
  static const double panelTabIconSize = 16;
  static const double panelTabFontSize = 11;
  static const EdgeInsets panelTabIconMargin = EdgeInsets.only(bottom: 1);
}

/// סגנונות טקסט מובנים לשימוש עקבי בכל האפליקציה
class AppTextStyles {
  AppTextStyles._();

  /// כותרת שורת הגדרה (16sp) — לשימוש ב-ListTile title בכל מסכי ההגדרות
  static const TextStyle settingTitle = TextStyle(fontSize: AppTokens.fontLG);

  /// תת-כותרת שורת הגדרה (13sp) — לשימוש ב-ListTile subtitle
  static const TextStyle settingSubtitle = TextStyle(fontSize: 13);

  /// משפחת המונוספייס של המערכת (נתיב, גרסה, פרטים טכניים). רק המשפחה: הגודל
  /// בא מה־slot של הטקסט (DESIGN_SYSTEM §2.4.1, `AppTextStyles.mono` יעד).
  static const String monospaceFamily = 'monospace';
}
