/// גופני הסת"ם של גוטמן — קנייניים, ולכן אינם מוטמעים בתוכנה. הם מותקנים
/// עם חבילת העברית של Office, ונטענים משם כשהם קיימים.
library;

import 'package:flutter/foundation.dart';
import 'package:otzaria/theme/app_fonts.dart';

/// שמות המשפחות כפי שהם בטבלת ה-name של הקבצים שמתקין Office.
const String kGuttmanStamFamily = 'Guttman Stam';
const String kGuttmanNikudFamily = 'Guttman Stam1';

/// החלופה לטור הסת"ם כשגוטמן אינו מותקן — Culmus המוטמע.
const String kTikkunFallbackFamily = 'AshkenaziStam';

/// גופני הסת"ם המוטמעים ממפים את 51 סימני הניקוד והטעמים לגליף, אך רק
/// לאחד מהם יש מִתאר — ולכן טור מנוקד בהם יוצא בלי ניקוד, במסך וב-PDF.
const Set<String> kTikkunUnpointedFamilies = {'AshkenaziStam', 'SefardiStam'};

/// החלופה לטור המנוקד — "כתר" המוטמע, שיש בו מִתאר לכל הסימנים. סימן ממופה
/// שאין לו מִתאר אינו מפעיל נפילת-גופן, ולכן חייבים לבחור אחר במקומו.
const String kTikkunNikudFallbackFamily = 'KeterYG';

/// קובצי הגופנים המוטמעים של הכלי, לפי שם המשפחה שב-pubspec — לייצוא ה-PDF.
const Map<String, String> kTikkunBundledFontAssets = {
  'AshkenaziStam': 'fonts/tikkun_korim/Ashkenazi-Stam.ttf',
  'SefardiStam': 'fonts/tikkun_korim/Sefardi-Stam.ttf',
};

/// זמינות גופני גוטמן במחשב, ובקשת טעינתם לזיכרון.
class TikkunStamFonts {
  TikkunStamFonts._();

  static bool _stamAvailable = false;
  static bool _nikudAvailable = false;
  static Future<void>? _preparing;

  static bool get stamAvailable => _stamAvailable;
  static bool get nikudAvailable => _nikudAvailable;

  /// טוען את גופני גוטמן מהמערכת אם הותקנו. ממוזכר — בטוח לקרוא בכל פתיחה
  /// של הכלי, וחייב להסתיים לפני מדידת מודל הרוחב.
  static Future<void> prepare() => _preparing ??= _prepare();

  static Future<void> _prepare() async {
    _stamAvailable = await _load(kGuttmanStamFamily);
    _nikudAvailable = await _load(kGuttmanNikudFamily);
  }

  static Future<bool> _load(String family) async {
    try {
      await AppFonts.ensureFontLoaded(family);
      return AppFonts.systemFamilyFaces(family) != null;
    } catch (_) {
      return false;
    }
  }

  /// גופן גוטמן שאינו מותקן אינו שמיש; כל שאר המשפחות מוטמעות ותמיד שמישות.
  static bool isUsable(String family) {
    if (family == kGuttmanStamFamily) return _stamAvailable;
    if (family == kGuttmanNikudFamily) return _nikudAvailable;
    return true;
  }

  @visibleForTesting
  static void debugSetAvailability({bool stam = false, bool nikud = false}) {
    _stamAvailable = stam;
    _nikudAvailable = nikud;
    _preparing = Future.value();
  }

  @visibleForTesting
  static void debugReset() {
    _stamAvailable = false;
    _nikudAvailable = false;
    _preparing = null;
  }
}
