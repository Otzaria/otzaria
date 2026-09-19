/// גופני הסת"ם והמנוקד של הכלי: "אוצריא אשורית" מחבילת `otzaria_ashurit`,
/// וגופני Culmus המוטמעים כחלופה.
library;

import 'package:otzaria/theme/app_fonts.dart';

/// החלופה לטור הסת"ם כשנבחר גופן אחר — Culmus המוטמע.
const String kTikkunFallbackFamily = 'AshkenaziStam';

/// גופני הסת"ם של Culmus ממפים את 51 סימני הניקוד והטעמים לגליף, אך רק
/// לאחד מהם יש מִתאר — ולכן טור מנוקד בהם יוצא בלי ניקוד, במסך וב-PDF.
const Set<String> kTikkunUnpointedFamilies = {'AshkenaziStam', 'SefardiStam'};

/// החלופה לטור המנוקד — "כתר" המוטמע, שיש בו מִתאר לכל הסימנים. סימן ממופה
/// שאין לו מִתאר אינו מפעיל נפילת-גופן, ולכן חייבים לבחור אחר במקומו.
const String kTikkunNikudFallbackFamily = 'KeterYG';

/// קובצי הגופנים שנארזים באפליקציה, לפי שם המשפחה — לייצוא ה-PDF, שמטמיע
/// את הקובץ עצמו.
const Map<String, String> kTikkunBundledFontAssets = {
  'AshkenaziStam': 'fonts/tikkun_korim/Ashkenazi-Stam.ttf',
  'SefardiStam': 'fonts/tikkun_korim/Sefardi-Stam.ttf',
  AppFonts.ashuritFont: 'packages/otzaria_ashurit/OtzariaAshurit-Regular.otf',
  AppFonts.ashuritNikudFont:
      'packages/otzaria_ashurit/OtzariaAshuritNikud-Regular.otf',
};

/// משפחות שיש בהן גליף לנו"ן מנוזרת (U+05C6). בשאר מהפכים נו"ן רגילה.
bool tikkunFamilyHasNunHafukha(String? family) =>
    family == AppFonts.ashuritFont || family == AppFonts.ashuritNikudFont;
