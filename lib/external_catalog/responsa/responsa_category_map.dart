import 'package:otzaria/external_catalog/responsa/text/responsa_hebrew.dart';

/// שיוך קטגוריות בר אילן לקטגוריות אוצריא.
///
/// שני עצי הסיווג נבנו בנפרד ואינם חופפים: לבר אילן 20 קטגוריות שורש
/// שנבנו סביב **סוג החיבור** (`ספרי שאלות ותשובות (שו"ת)`,
/// `מפרשים ופוסקים על הבבלי והירושלמי`), ולאוצריא 18 שנבנו סביב
/// **הספרות הנדונה** (`שו״ת`, `תלמוד בבלי`). בלי שיוך מפורש, ספר
/// מבר אילן אינו מופיע בשום מקום בעיון בספרייה.
///
/// **השיוך מפורש ולא לפי דמיון מחרוזות.** `שו"ת` ו-`שו״ת` נבדלים בתו
/// הגרשיים (U+0022 מול U+05F4), `ספרי חסידות` מול `חסידות` בתחילית,
/// ו-`ספרות חז"ל` מתפצל לחמש קטגוריות שונות באוצריא. התאמה מקורבת
/// הייתה משייכת ספרים לקטגוריה שגויה ושותקת על מה שלא שויך.
///
/// המפתח הוא **נתיב הקטגוריה בבר אילן**, מנורמל, ורמה אחת או שתיים.
/// הרמה העמוקה נבדקת ראשונה.
class ResponsaCategoryMap {
  ResponsaCategoryMap._();

  /// מפריד רכיבים בנתיב הקטגוריה כפי שהקטלוג שומר אותו.
  static const String pathSeparator = ' > ';

  /// `ספרות חז"ל` מתפצל — הרמה השנייה היא שקובעת.
  static const Map<String, List<String>> _twoLevel = {
    'ספרות חז"ל > משנה': ['משנה'],
    'ספרות חז"ל > תוספתא': ['תוספתא'],
    'ספרות חז"ל > תלמוד בבלי': ['תלמוד בבלי'],
    'ספרות חז"ל > תלמוד ירושלמי (וילנא)': ['תלמוד ירושלמי'],
    'ספרות חז"ל > תלמוד ירושלמי (ונציה)': ['תלמוד ירושלמי'],
    'ספרות חז"ל > מסכתות קטנות': ['תלמוד בבלי', 'מסכתות קטנות'],
    'ספרות חז"ל > מדרשי הלכה': ['מדרש', 'הלכה'],
    'ספרות חז"ל > מדרשי אגדה': ['מדרש', 'אגדה'],
  };

  static const Map<String, List<String>> _oneLevel = {
    'תנ"ך (החומש מחולק לפרקים)': ['תנ״ך'],
    'מפרשי תנ"ך (החומש מחולק לפרקים)': ['תנ״ך'],
    'ספרות חז"ל': ['תלמוד בבלי'],
    'זוהר': ['קבלה', 'זהר'],
    'גאונים': ['הלכה', 'ראשונים'],
    'מפרשי המשנה ומדרשי הלכה': ['משנה'],
    'מפרשים ופוסקים על הבבלי והירושלמי': ['תלמוד בבלי'],
    'ספרי הלכה ומנהג': ['הלכה'],
    'ספרי מצוות ומפרשיהם': ['הלכה', 'ספרי מצוות'],
    'ספרי מחשבה ומוסר': ['מחשבת ישראל'],
    'רמב"ם ומפרשיו': ['הלכה', 'משנה תורה'],
    'טור, שולחן ערוך, מפרשים וחיבורים': ['הלכה'],
    'ספרי מערכות ועניינים': ['הלכה', 'מערכות ועניינים'],
    'ספרי שאלות ותשובות (שו"ת)': ['שו״ת'],
    'דרשות ודרושים': ['תנ״ך', 'דרשות ודרושים'],
    'ספרי חסידות': ['חסידות'],
    'ספרי כללים וסדר הדורות': ['ספרות עזר'],
    'אנציקלופדיה תלמודית': ['ספרות עזר'],
    'אנציקלופדיות שונות': ['ספרות עזר'],
    'כתבי עת': ['ספרות עזר'],
  };

  static Map<String, List<String>>? _normalizedTwo;
  static Map<String, List<String>>? _normalizedOne;

  static String _key(Iterable<String> parts) => parts
      .map(ResponsaHebrew.spellingKey)
      .where((part) => part.isNotEmpty)
      .join('|');

  static Map<String, List<String>> _normalize(Map<String, List<String>> raw) =>
      {
        for (final entry in raw.entries)
          _key(entry.key.split(pathSeparator)): entry.value,
      };

  /// נתיב הקטגוריה באוצריא עבור [categoryPath] של בר אילן, או `null`
  /// כשאין שיוך — אז הספרים מוצגים תחת קטגוריה משלהם ולא נעלמים.
  ///
  /// ההשוואה לפי [ResponsaHebrew.spellingKey] ולא לפי מחרוזת, כדי
  /// שהבדלי כתיב וגרשיים בין מהדורות לא ינתקו את השיוך.
  static List<String>? otzariaPathFor(String? categoryPath) =>
      resolve(categoryPath)?.target;

  /// השיוך יחד עם מספר רכיבי נתיב בר אילן שהוא **צרך**.
  ///
  /// המספר נחוץ לבניית התיקיות: מה שנצרך מיוצג כבר על ידי קטגוריית
  /// היעד, ומה שמתחתיו נשאר כתיקייה בתוכה.
  static ({List<String> target, int levels})? resolve(String? categoryPath) {
    if (categoryPath == null || categoryPath.trim().isEmpty) return null;
    _normalizedTwo ??= _normalize(_twoLevel);
    _normalizedOne ??= _normalize(_oneLevel);

    final parts = categoryPath
        .split(pathSeparator)
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) return null;

    if (parts.length >= 2) {
      final match = _normalizedTwo![_key(parts.take(2))];
      if (match != null) return (target: match, levels: 2);
    }
    final single = _normalizedOne![_key(parts.take(1))];
    return single == null ? null : (target: single, levels: 1);
  }

  /// שם הקטגוריה **להצגה** — בשמות של אוצריא.
  ///
  /// השם שבמאגר הוא שם של מדף בתוכנה אחרת: `ספרי שאלות ותשובות (שו"ת)
  /// › ספרי שאלות ותשובות - אחרונים › תורת יקותיאל`. הוא ארוך, הוא חוזר
  /// על עצמו, והוא אינו השם שהמשתמש מכיר. מה שמוצג הוא הקטגוריה
  /// באוצריא — `שו״ת` — כי שם הוא ימצא את הספר בעיון.
  ///
  /// כשאין שיוך מוצג שורש הקטגוריה של בר אילן, ולא מחרוזת ריקה.
  static String? displayNameFor(String? categoryPath) {
    final match = resolve(categoryPath);
    if (match != null) return match.target.join(' › ');
    final root = categoryPath
        ?.split(pathSeparator)
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .firstOrNull;
    return (root == null || root.isEmpty) ? null : root;
  }

  /// כל נתיבי היעד באוצריא. משמש לבדיקה שכל יעד קיים באמת בספרייה.
  static Iterable<List<String>> get allTargets => [
    ..._twoLevel.values,
    ..._oneLevel.values,
  ];
}
