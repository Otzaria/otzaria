import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:win32/win32.dart';

/// שורה גולמית אחת כפי ש-GDI מוסר אותה — קריאת callback אחת.
typedef FontRow = ({
  String name,
  int charset,
  int pitchAndFamily,
  int fontType,
});

/// מזהי ה-scripts. נגזרים מ-charset של GDI, לא מטבלאות ה-name של ה-TTF.
const Map<int, String> _charsetScripts = {
  HEBREW_CHARSET: 'hebrew', // 177
  ARABIC_CHARSET: 'arabic', // 178
  RUSSIAN_CHARSET: 'cyrillic', // 204
  GREEK_CHARSET: 'greek', // 161
  SHIFTJIS_CHARSET: 'cjk', // 128
  HANGEUL_CHARSET: 'cjk', // 129
  GB2312_CHARSET: 'cjk', // 134
  CHINESEBIG5_CHARSET: 'cjk', // 136
  JOHAB_CHARSET: 'cjk', // 130
  THAI_CHARSET: 'thai', // 222
  SYMBOL_CHARSET: 'symbol', // 2
};

/// `lfPitchAndFamily & 0x03` — שני הביטים התחתונים הם ה-pitch.
const int _pitchMask = 0x03;
const int _fixedPitch = 1;

/// RASTER_FONTTYPE. גופני `.fon` ישנים אינם נפתרים ב-CSS, ולכן שמם אינו
/// עומד בחוזה. אסור לסנן לפי TRUETYPE_FONTTYPE במקום: גופני OpenType/CFF
/// מדווחים DEVICE_FONTTYPE, וסינון כזה היה משמיט אותם.
const int _rasterFontType = 0x0001;

/// רשימת משפחות הגופנים המותקנות במכונה, למתודה `fonts.listInstalled`.
///
/// תוסף שמרנדר מסמך צריך לדעת מה באמת קיים כאן לפני שהוא בוחר תחליף. בלי זה
/// הוא יכול רק לנחש, או לבקש בייטים של כל משפחה דרך `fonts.resolveFamilies`
/// כדי לגלות אילו מהן נפתרות — יקר בהרבה מרשימת שמות.
class InstalledFonts {
  static Map<String, dynamic>? _cache;

  /// override לבדיקות בלבד. העבר `null` לאיפוס.
  @visibleForTesting
  static void debugOverrideResult(Map<String, dynamic>? value) {
    _cache = value;
  }

  /// המשפחות המותקנות, ממוינות לפי שם. מנייה אחת לכל ריצת אפליקציה.
  ///
  /// פלטפורמה שאין בה מימוש מחזירה `families: []` — היעדר רשימה אינו שגיאה,
  /// והקורא נופל בחזרה למדיניות התחליפים שלו.
  static Map<String, dynamic> list() {
    final cached = _cache;
    if (cached != null) return cached;

    final result = Platform.isWindows
        ? _enumerateWindows()
        : buildResult(const [], platform: Platform.operatingSystem);

    // כשל חולף — מיצוי GDI handles, תחנת חלונות לא-אינטראקטיבית — מחזיר
    // רשימה ריקה. שמירתה הייתה נועלת כל תוסף על "אין גופנים" עד סוף הריצה.
    if (!Platform.isWindows || (result['families'] as List).isNotEmpty) {
      _cache = result;
    }
    return result;
  }

  /// בונה את התשובה משורות גולמיות. הלוגיקה כולה כאן ולא ב-callback, כדי
  /// שתהיה ניתנת לבדיקה בלי GDI חי — כלומר גם ב-CI שאינו Windows.
  @visibleForTesting
  static Map<String, dynamic> buildResult(
    Iterable<FontRow> rows, {
    required String platform,
  }) {
    // ה-callback יורה פעם לכל צירוף (משפחה, charset): משפחה עם עברית ולטינית
    // מגיעה פעמיים, ולכן הצבירה היא לקבוצה לפי שם ולא לרשימה שטוחה.
    final scripts = <String, Set<String>>{};
    final monospace = <String>{};

    for (final row in rows) {
      if (!_isUsable(row.name, row.fontType)) continue;
      scripts
          .putIfAbsent(row.name, () => <String>{})
          .add(_charsetScripts[row.charset] ?? 'latin');
      if (row.pitchAndFamily & _pitchMask == _fixedPitch) {
        monospace.add(row.name);
      }
    }

    final names = scripts.keys.toList()..sort();
    return {
      'families': [
        for (final name in names)
          {
            'name': name,
            'scripts': scripts[name]!.toList()..sort(),
            'monospace': monospace.contains(name),
          },
      ],
      'platform': platform,
    };
  }

  /// שם ריק, וריאנט אנכי של CJK (`@`) או גופן raster — אף אחד מהם אינו שם
  /// שאפשר למסור ל-CSS `font-family`.
  static bool _isUsable(String name, int fontType) =>
      name.isNotEmpty &&
      !name.startsWith('@') &&
      fontType & _rasterFontType == 0;

  static Map<String, dynamic> _enumerateWindows() {
    _rows.clear();
    try {
      final hdc = GetDC(null);
      try {
        final logfont = calloc<LOGFONT>();
        try {
          // DEFAULT_CHARSET + שם ריק = כל המשפחות בכל ה-charsets.
          logfont.ref.lfCharSet = DEFAULT_CHARSET;
          logfont.ref.lfFaceName = '';
          EnumFontFamiliesEx(
            hdc,
            logfont,
            ffi.Pointer.fromFunction<FONTENUMPROC>(_onFont, 1),
            const LPARAM(0),
            0,
          );
        } finally {
          calloc.free(logfont);
        }
      } finally {
        if (hdc.address != 0) ReleaseDC(null, hdc);
      }
      return buildResult(_rows, platform: Platform.operatingSystem);
    } catch (e) {
      debugPrint('InstalledFonts: enumeration failed: $e');
      return buildResult(const [], platform: Platform.operatingSystem);
    } finally {
      _rows.clear();
    }
  }
}

/// צבירה בין קריאות ה-callback. ה-callback חייב להיות טופ-לבל כדי לעבור
/// ל-[ffi.Pointer.fromFunction], והמנייה סינכרונית — אין כאן מרוץ.
final List<FontRow> _rows = [];

int _onFont(
  ffi.Pointer<LOGFONT> logfont,
  ffi.Pointer<TEXTMETRIC> metric,
  int fontType,
  int lParam,
) {
  // כל מסלול חייב להחזיר 1 — החזרת 0 עוצרת את המנייה כולה.
  try {
    _rows.add((
      name: logfont.ref.lfFaceName,
      charset: logfont.ref.lfCharSet,
      pitchAndFamily: logfont.ref.lfPitchAndFamily,
      fontType: fontType,
    ));
  } catch (_) {
    // כשל בשורה אחת אינו מצדיק לאבד את שאר הרשימה.
  }
  return 1;
}
