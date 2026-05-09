import 'package:flutter/material.dart';

class AppTokens {
  // ── Spacing ————————————————————————————————
  static const double spaceXS = 4;
  static const double spaceSM = 8;
  static const double spaceMD = 16;
  static const double spaceLG = 24;
  static const double spaceXL = 32;

  // ── Border Radius ——————————————————————————
  static const double radiusSM = 8;
  static const double radiusMD = 12;
  static const double radiusLG = 16;
  static const double radiusXL = 20; // SettingsCard
  static const double radiusPanel = 18;

  // ── Typography Scale ——————————————————————
  static const double fontSM = 12;
  static const double fontMD = 14;
  static const double fontLG = 16; // רוב ה-ListTile titles
  static const double fontXL = 18;

  // ── Elevation ——————————————————————————————
  static const double elevation0 = 0;
  static const double elevation1 = 1;
  static const double elevation2 = 3;

  // ── Animation Durations ————————————————————
  static const Duration animFast = Duration(milliseconds: 150);
  static const Duration animNormal = Duration(milliseconds: 250);
  static const Duration animPanelOpacity = Duration(milliseconds: 200);
  static const Duration animPanelSlide = Duration(milliseconds: 300);
  static const Duration animSlow = Duration(milliseconds: 400);

  // ── Drag Handle ——————————————————————————————
  static const double dragHandleCompactHitSize = 18;
  static const double dragHandleRegularHitSize = 24;
}

/// סגנונות טקסט מובנים לשימוש עקבי בכל האפליקציה
class AppTextStyles {
  AppTextStyles._();

  /// כותרת שורת הגדרה (16sp) — לשימוש ב-ListTile title בכל מסכי ההגדרות
  static const TextStyle settingTitle = TextStyle(fontSize: AppTokens.fontLG);

  /// תת-כותרת שורת הגדרה (13sp) — לשימוש ב-ListTile subtitle
  static const TextStyle settingSubtitle = TextStyle(fontSize: 13);
}
