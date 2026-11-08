import 'package:flutter/widgets.dart';

/// שפת כרום הממשק (הרשימה הסגורה ב-DESIGN_SYSTEM.md, DD-20) וטופסי הדיווח.
/// כוללת כותרת, ניווט, הגדרות, סיור ותוויות ברירת המחדל של הדיאלוגים.
///
/// אינה משנה את `MaterialApp.locale` ואינה מתרגמת תוכן ספרים ודיווחים.
/// כיווניות תוכן הדיווחים נקבעת לפי התוכן; יתר תוכן המסכים נשאר ללא שינוי.
///
/// להוספת שפה: ערך חדש כאן + קובץ `settings_<code>.arb` באותה תיקייה.
/// שאר המערכת — הבורר, השמירה והזיהוי האוטומטי — מתעדכנת מאליה.
enum SettingsLanguage {
  hebrew('he', 'עברית', TextDirection.rtl),
  english('en', 'English', TextDirection.ltr);

  const SettingsLanguage(this.code, this.label, this.textDirection);

  /// מזהה לשמירה בהגדרות ולשם קובץ הקטלוג. אסור לשנות — ערכים שמורים
  /// תלויים בו.
  final String code;

  /// השם שמוצג בבורר השפה, תמיד בשפה עצמה.
  final String label;

  /// כיוון הכתיבה של כרום הממשק וטופסי הדיווח בשפה זו.
  final TextDirection textDirection;

  /// שפת המקור: הטקסטים בקוד כתובים בה והיא משמשת כמפתח, ולכן אין לה קטלוג.
  static const SettingsLanguage source = SettingsLanguage.hebrew;

  /// ממיר קוד שמור לשפה; ערך לא מוכר או חסר מחזיר null.
  static SettingsLanguage? fromCode(String? code) {
    for (final language in SettingsLanguage.values) {
      if (language.code == code) return language;
    }
    return null;
  }
}

/// ייצוג השפה הפעילה עבור ממשק התוספים (plugin.boot / app.getLocale).
/// [code] — הערך השמור בהגדרות (או null לזיהוי אוטומטי). 'locale' נשאר
/// he-IL עבור עברית לתאימות עם תוספים קיימים.
/// [systemLocale] נמסר במפורש בבדיקות (כמו ב-[resolveSettingsLanguage]).
Map<String, String> pluginLocalePayload({String? code, Locale? systemLocale}) {
  final resolved = resolveSettingsLanguage(code, systemLocale: systemLocale);
  return {
    'locale': resolved == SettingsLanguage.hebrew ? 'he-IL' : resolved.code,
    'language': resolved.code,
    'textDirection': resolved.textDirection == TextDirection.rtl
        ? 'rtl'
        : 'ltr',
  };
}

/// הקוד שנשמר ונבחר כשהשפה מותאמת אוטומטית לשפת המערכת.
const String kSettingsLanguageSystemCode = 'system';

/// ברירת המחדל: התאמה אוטומטית לשפת מערכת ההפעלה.
const String kDefaultSettingsLanguageCode = kSettingsLanguageSystemCode;

/// שפת המערכת כפי שדווחה למנוע — לא דרך `Localizations`, שכן ה-locale של
/// האפליקציה קבוע ל-he_IL ולכן תמיד יחזיר עברית.
Locale currentSystemLocale() =>
    WidgetsBinding.instance.platformDispatcher.locale;

/// מכריע באיזו שפה להציג את ההגדרות בפועל.
///
/// [code] הוא בחירת המשתמש: קוד שפה, או `system` להתאמה אוטומטית. קוד לא
/// מוכר — למשל שפה שהוסרה מגרסה קודמת — נופל להתאמה אוטומטית.
/// [systemLocale] נמסר במפורש כדי שהלוגיקה תהיה ניתנת לבדיקה.
SettingsLanguage resolveSettingsLanguage(
  String? code, {
  Locale? systemLocale,
}) =>
    SettingsLanguage.fromCode(code) ??
    _languageForLocale(systemLocale ?? currentSystemLocale());

/// מתאים שפת מערכת לשפה נתמכת. `iw` הוא קוד ISO ישן לעברית שעדיין מדווח
/// בחלק מהמערכות. שפה שאינה נתמכת נופלת לאנגלית.
SettingsLanguage _languageForLocale(Locale locale) {
  final code = locale.languageCode.toLowerCase();
  if (code == 'iw') return SettingsLanguage.hebrew;
  return SettingsLanguage.fromCode(code) ?? SettingsLanguage.english;
}
