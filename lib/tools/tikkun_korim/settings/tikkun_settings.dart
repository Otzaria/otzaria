/// ההגדרות של "תיקון קוראים" — מודל, ברירות מחדל ושמירה ב-Settings.
library;

import 'dart:convert';

import 'package:equatable/equatable.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/tools/tikkun_korim/models/tikkun_models.dart';
import 'package:otzaria/tools/tikkun_korim/repository/tikkun_contracts.dart';
import 'package:otzaria/tools/tikkun_korim/settings/tikkun_stam_fonts.dart';

/// מפתחות השמירה. הערכים זהים לברירות המחדל של התוסף המקורי.
abstract class TikkunSettingsKeys {
  static const stamFont = 'key-tikkun-stam-font';
  static const nikudFont = 'key-tikkun-nikud-font';
  static const lineSpacing = 'key-tikkun-line-spacing';
  static const hideStam = 'key-tikkun-hide-stam';
  static const hideNikud = 'key-tikkun-hide-nikud';
  static const swapColumns = 'key-tikkun-swap-columns';
  static const hideRowBorders = 'key-tikkun-hide-row-borders';
  static const hideDivineName = 'key-tikkun-hide-divine-name';
  static const centerSingleColumn = 'key-tikkun-center-single-column';
  static const startupMode = 'key-tikkun-startup-mode';
  static const nusach = 'key-tikkun-nusach';
  static const decalogueTaam = 'key-tikkun-decalogue-taam';
  static const nusachLand = 'key-tikkun-nusach-land';
  static const navState = 'key-tikkun-nav-state';
}

/// גופני הסת"ם: הערך השמור → משפחת הגופן. "קלאסי" ו"סטנדרטי" הם גופני
/// גוטמן שנטענים מהמערכת — ראו [TikkunStamFonts].
const Map<String, String> kTikkunStamFontFamilies = {
  'Klasi': kGuttmanStamFamily,
  'Ashkenazi': 'AshkenaziStam',
  'Sefardi': 'SefardiStam',
};

/// גופני הסת"ם אינם כאן — אין בהם מִתאר לניקוד ולטעמים, וערך שמור שלהם
/// נפתר ל-[kTikkunNikudFallbackFamily].
const Map<String, String> kTikkunNikudFontFamilies = {
  'Standard': kGuttmanNikudFamily,
};

/// גופן מערכת נשמר כ-`System:<משפחה>` — בדיוק כמו בתוסף.
const String kTikkunSystemFontPrefix = 'System:';

/// ה-line-height בפועל של מרווח 1.0 — המחוון מציג גורם יחסי סביבו.
const double kTikkunBaseLineSpacing = 1.2;

class TikkunSettings extends Equatable {
  final String stamFont;
  final String nikudFont;
  final double lineSpacing;
  final bool hideStam;
  final bool hideNikud;
  final bool swapColumns;
  final bool hideRowBorders;
  final bool hideDivineName;
  final bool centerSingleColumn;

  /// 'parasha' — פרשת השבוע; 'lastPosition' — המיקום האחרון.
  final String startupMode;

  /// 'ashkenaz' | 'sephard'
  final String nusach;

  /// 'israel' | 'diaspora'
  final String nusachLand;

  /// מערכת הטעמים של עשרת הדברות.
  final TikkunDecalogueTaam decalogueTaam;

  const TikkunSettings({
    this.stamFont = 'Klasi',
    this.nikudFont = 'Standard',
    this.lineSpacing = 1.0,
    this.hideStam = false,
    this.hideNikud = false,
    this.swapColumns = false,
    this.hideRowBorders = false,
    this.hideDivineName = false,
    this.centerSingleColumn = false,
    this.startupMode = 'parasha',
    this.nusach = 'ashkenaz',
    this.nusachLand = 'israel',
    this.decalogueTaam = TikkunDecalogueTaam.merged,
  });

  /// ה-line-height בפועל: הגורם המוצג למשתמש כפול במרווח הבסיס.
  double get resolvedLineSpacing => lineSpacing * kTikkunBaseLineSpacing;

  /// בדיוק אחד מהטורים מוסתר — רק אז ההחלפה המהירה והמירכוז רלוונטיים.
  bool get isSingleColumn => hideStam != hideNikud;

  /// טור יחיד ממורכז — הטור תופס את רוחב העמוד במקום להישאר במקומו.
  bool get showsSingleCenteredColumn => centerSingleColumn && isSingleColumn;

  String get stamFontFamily => _resolveFamily(
    stamFont,
    kTikkunStamFontFamilies,
    kTikkunFallbackFamily,
  );

  /// גופן שאין בו מִתאר לסימנים אינו יכול לשמש את הטור המנוקד — גם כשהוא
  /// נבחר במפורש.
  String get nikudFontFamily {
    final family = _resolveFamily(
      nikudFont,
      kTikkunNikudFontFamilies,
      kTikkunNikudFallbackFamily,
    );
    return kTikkunUnpointedFamilies.contains(family)
        ? kTikkunNikudFallbackFamily
        : family;
  }

  static String _resolveFamily(
    String value,
    Map<String, String> builtIn,
    String fallback,
  ) {
    final family = value.startsWith(kTikkunSystemFontPrefix)
        ? value.substring(kTikkunSystemFontPrefix.length)
        : builtIn[value] ?? builtIn.values.first;
    return TikkunStamFonts.isUsable(family) ? family : fallback;
  }

  TikkunSettings copyWith({
    String? stamFont,
    String? nikudFont,
    double? lineSpacing,
    bool? hideStam,
    bool? hideNikud,
    bool? swapColumns,
    bool? hideRowBorders,
    bool? hideDivineName,
    bool? centerSingleColumn,
    String? startupMode,
    String? nusach,
    String? nusachLand,
    TikkunDecalogueTaam? decalogueTaam,
  }) => TikkunSettings(
    stamFont: stamFont ?? this.stamFont,
    nikudFont: nikudFont ?? this.nikudFont,
    lineSpacing: lineSpacing ?? this.lineSpacing,
    hideStam: hideStam ?? this.hideStam,
    hideNikud: hideNikud ?? this.hideNikud,
    swapColumns: swapColumns ?? this.swapColumns,
    hideRowBorders: hideRowBorders ?? this.hideRowBorders,
    hideDivineName: hideDivineName ?? this.hideDivineName,
    centerSingleColumn: centerSingleColumn ?? this.centerSingleColumn,
    startupMode: startupMode ?? this.startupMode,
    nusach: nusach ?? this.nusach,
    nusachLand: nusachLand ?? this.nusachLand,
    decalogueTaam: decalogueTaam ?? this.decalogueTaam,
  );

  @override
  List<Object?> get props => [
    stamFont,
    nikudFont,
    lineSpacing,
    hideStam,
    hideNikud,
    swapColumns,
    hideRowBorders,
    hideDivineName,
    centerSingleColumn,
    startupMode,
    nusach,
    nusachLand,
    decalogueTaam,
  ];
}

/// קריאה וכתיבה של ההגדרות ומצב הניווט דרך `Settings` של אוצריא.
class TikkunSettingsStore {
  const TikkunSettingsStore();

  TikkunSettings load() {
    const d = TikkunSettings();
    return TikkunSettings(
      stamFont:
          Settings.getValue<String>(TikkunSettingsKeys.stamFont) ?? d.stamFont,
      nikudFont:
          Settings.getValue<String>(TikkunSettingsKeys.nikudFont) ??
          d.nikudFont,
      lineSpacing:
          Settings.getValue<double>(TikkunSettingsKeys.lineSpacing) ??
          d.lineSpacing,
      hideStam:
          Settings.getValue<bool>(TikkunSettingsKeys.hideStam) ?? d.hideStam,
      hideNikud:
          Settings.getValue<bool>(TikkunSettingsKeys.hideNikud) ?? d.hideNikud,
      swapColumns:
          Settings.getValue<bool>(TikkunSettingsKeys.swapColumns) ??
          d.swapColumns,
      hideRowBorders:
          Settings.getValue<bool>(TikkunSettingsKeys.hideRowBorders) ??
          d.hideRowBorders,
      hideDivineName:
          Settings.getValue<bool>(TikkunSettingsKeys.hideDivineName) ??
          d.hideDivineName,
      centerSingleColumn:
          Settings.getValue<bool>(TikkunSettingsKeys.centerSingleColumn) ??
          d.centerSingleColumn,
      startupMode:
          Settings.getValue<String>(TikkunSettingsKeys.startupMode) ??
          d.startupMode,
      nusach: Settings.getValue<String>(TikkunSettingsKeys.nusach) ?? d.nusach,
      nusachLand:
          Settings.getValue<String>(TikkunSettingsKeys.nusachLand) ??
          d.nusachLand,
      decalogueTaam: TikkunDecalogueTaam.byId(
        Settings.getValue<String>(TikkunSettingsKeys.decalogueTaam),
      ),
    );
  }

  Future<void> save(TikkunSettings s) async {
    await Settings.setValue<String>(TikkunSettingsKeys.stamFont, s.stamFont);
    await Settings.setValue<String>(TikkunSettingsKeys.nikudFont, s.nikudFont);
    await Settings.setValue<double>(
      TikkunSettingsKeys.lineSpacing,
      s.lineSpacing,
    );
    await Settings.setValue<bool>(TikkunSettingsKeys.hideStam, s.hideStam);
    await Settings.setValue<bool>(TikkunSettingsKeys.hideNikud, s.hideNikud);
    await Settings.setValue<bool>(
      TikkunSettingsKeys.swapColumns,
      s.swapColumns,
    );
    await Settings.setValue<bool>(
      TikkunSettingsKeys.hideRowBorders,
      s.hideRowBorders,
    );
    await Settings.setValue<bool>(
      TikkunSettingsKeys.hideDivineName,
      s.hideDivineName,
    );
    await Settings.setValue<bool>(
      TikkunSettingsKeys.centerSingleColumn,
      s.centerSingleColumn,
    );
    await Settings.setValue<String>(
      TikkunSettingsKeys.startupMode,
      s.startupMode,
    );
    await Settings.setValue<String>(TikkunSettingsKeys.nusach, s.nusach);
    await Settings.setValue<String>(
      TikkunSettingsKeys.nusachLand,
      s.nusachLand,
    );
    await Settings.setValue<String>(
      TikkunSettingsKeys.decalogueTaam,
      s.decalogueTaam.id,
    );
  }

  TikkunNavState loadNavState() {
    final raw = Settings.getValue<String>(TikkunSettingsKeys.navState);
    if (raw == null || raw.isEmpty) return const TikkunNavState();
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const TikkunNavState();
      return TikkunNavState.fromJson(Map<String, dynamic>.from(decoded));
    } on FormatException {
      return const TikkunNavState();
    }
  }

  Future<void> saveNavState(TikkunNavState state) => Settings.setValue<String>(
    TikkunSettingsKeys.navState,
    jsonEncode(state.toJson()),
  );
}
