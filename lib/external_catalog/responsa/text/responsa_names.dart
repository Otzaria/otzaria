import 'package:otzaria/external_catalog/responsa/text/responsa_hebrew.dart';

/// שמות ספרים כפי שהם מאוחסנים בעץ הקטלוג של פרויקט השו"ת, ומה שצריך
/// לעשות בהם כדי שיהיו קריאים למשתמש ומובנים למנתח ההפניות.
///
/// שתי תופעות במאגר, שתיהן נמדדו על הקטלוג המלא (8,523 ספרים):
///
/// 1. **עטיפת סוגריים בסדר חזותי.** `"בבא בתרא (ליברמן)"` מאוחסן כרצף
///    התווים `(בבא בתרא (ליברמן` — סוגר פותח בתחילת המחרוזת, סוגר פותח
///    נוסף לפני ההסתייגות, ואף סוגר סוגר. ב-810 מתוך 8,523 השמות. ב-110
///    מהם גם המספרים הוזזו לראש: `"היכלות (עמ' 108-126)"` מאוחסן
///    כ-`(108-126 'היכלות (עמ`.
///
///    זו אינה בעיה קוסמטית: המחרוזת הזו נשלחה כהפניה אל מנתח ההפניות
///    והוא החזיר "לא נמצאה כל תוצאה", בעוד `היכלות` נפתח מיד.
///
/// 2. **שם הספר הוא שם היחידה בלבד.** הסיווג מזהה כספר את הצומת הגבוה
///    ביותר שתוכנו מקטעים, ובחיבור רב-כרכי זהו הכרך: `הון עשיר > אבות`
///    נשמר ככותרת `אבות`. שם החיבור — מה שהמשתמש מחפש — נעלם לנתיב.
class ResponsaNames {
  ResponsaNames._();

  /// מילים שפותחות שם של יחידה בתוך חיבור ולא של חיבור עצמאי.
  ///
  /// הסיום הוא `(?=\s|$|...)` ולא `\b`: ב-Dart גבול המילה הוא ASCII,
  /// ואות עברית אינה תו-מילה עבורו — `RegExp(r'כלל\b')` אינו מתאים
  /// ל-`כלל נא` ולא לשום דבר אחר.
  static final RegExp _genericLead = RegExp(
    r'''^["'׳״(\[*]*(כלל|נתיב|שנה|מערכת|ערך|שורש|לאוין|עשין|חלק|כרך'''
    r'|שער|מאמר|סימן|פרק|פרשת|פרשה|מסכת|הלכות|הלכה|דרוש|אות|תשובה'
    r'|מצוה|מהדורא|מהדורה|ליקוטים|תוספות|סדר|דף|עמוד|פסקה|דין'
    r'''|שמעתתא|קונטרס|סימנים)(?=[\s"'׳״]|$)''',
  );

  static final RegExp _hebrewLetter = RegExp('[א-ת]');

  /// שמות מסכתות. יחידה בתוך חיבור כמעט תמיד, חיבור עצמאי כמעט לעולם לא.
  static const List<String> _tractates = [
    'ברכות', 'פאה', 'דמאי', 'כלאים', 'שביעית', 'תרומות', 'מעשרות',
    'מעשר שני', 'חלה', 'ערלה', 'ביכורים', 'שבת', 'עירובין', 'פסחים',
    'שקלים', 'יומא', 'סוכה', 'ביצה', 'ראש השנה', 'תענית', 'מגילה',
    'מועד קטן', 'חגיגה', 'יבמות', 'כתובות', 'נדרים', 'נזיר', 'סוטה',
    'גיטין', 'קידושין', 'בבא קמא', 'בבא מציעא', 'בבא בתרא', 'סנהדרין',
    'מכות', 'שבועות', 'עדויות', 'עבודה זרה', 'אבות', 'הוריות', 'זבחים',
    'מנחות', 'חולין', 'בכורות', 'ערכין', 'תמורה', 'כריתות', 'מעילה',
    'תמיד', 'מידות', 'קינים', 'כלים', 'אהלות', 'נגעים', 'פרה', 'טהרות',
    'מקואות', 'נדה', 'מכשירין', 'זבים', 'טבול יום', 'ידים', 'עוקצים',
    'אבות דרבי נתן', 'שמחות', 'כלה', 'סופרים', 'דרך ארץ',
    // כתיב חלופי שמופיע במאגר לצד הראשי. קיפול הכתיב אינו מכסה אותו:
    // `עוקצים`/`עוקצין` נבדלים באות עצמה ולא בצורתה הסופית.
    'עוקצין', 'מקוואות', 'מקוואת', 'שקלים', 'כריתות', 'מכשירים',
  ];

  /// ספרי התנ"ך. בתוך חיבור על התנ"ך אלה כרכים, ולכן `חומת אנך > בראשית`
  /// זקוק לשם החיבור. תחת שורש התנ"ך עצמו אין תוספת — שורש אינו מצורף.
  static const List<String> _tanakh = [
    'בראשית',
    'שמות',
    'ויקרא',
    'במדבר',
    'דברים',
    'יהושע',
    'שופטים',
    'שמואל א',
    'שמואל ב',
    'מלכים א',
    'מלכים ב',
    'ישעיה',
    'ישעיהו',
    'ירמיה',
    'ירמיהו',
    'יחזקאל',
    'הושע',
    'יואל',
    'עמוס',
    'עובדיה',
    'יונה',
    'מיכה',
    'נחום',
    'חבקוק',
    'צפניה',
    'חגי',
    'זכריה',
    'מלאכי',
    'תהלים',
    'משלי',
    'איוב',
    'שיר השירים',
    'רות',
    'איכה',
    'קהלת',
    'אסתר',
    'דניאל',
    'עזרא',
    'נחמיה',
    'דברי הימים א',
    'דברי הימים ב',
    'תרי עשר',
    'תורה',
    'נביאים',
    'כתובים',
  ];

  /// חלקי השולחן ערוך וסדרי המשנה — גם הם שמות יחידה.
  static const List<String> _parts = [
    'אורח חיים',
    'יורה דעה',
    'אבן העזר',
    'חושן משפט',
    'זרעים',
    'מועד',
    'נשים',
    'נזיקין',
    'קדשים',
    'טהרות',
  ];

  static final Set<String> _unitKeys = {
    for (final name in [..._tractates, ..._tanakh, ..._parts])
      ResponsaHebrew.spellingKey(name),
  }..remove('');

  /// האם [name] הוא שם של יחידה בתוך חיבור ולא שם חיבור.
  ///
  /// ההשוואה לפי [ResponsaHebrew.spellingKey] ולא לפי מחרוזת: במאגר
  /// מופיעים `מקוואות` לצד `מקואות` ו-`עוקצין` לצד `עוקצים`, ובלי הקיפול
  /// שני ספרים מתוך כל מסכתות הש"ס היו נשארים בלי שם החיבור.
  static bool isUnitName(String? name) {
    final core = coreOf(name ?? '');
    if (core.isEmpty) return false;
    if (_genericLead.hasMatch(core)) return true;
    return _unitKeys.contains(ResponsaHebrew.spellingKey(core));
  }

  // ------------------------------------------------ עטיפת הסוגריים

  /// מפרק שם מאוחסן לשם הליבה ולהסתייגות שבסוגריים.
  ///
  /// המבנה המאוחסן הוא `( PRE CORE ( POST`, כאשר `PRE` ריק ברוב
  /// המקרים ומכיל מספרים ב-110 מהם. ההסתייגות הקריאה מורכבת מ-`POST`
  /// ואחריו אסימוני `PRE` בסדר הפוך — כך `(108-126 'היכלות (עמ` חוזר
  /// להיות `היכלות` + `עמ' 108-126`.
  static ({String core, String? qualifier}) split(String raw) {
    var value = raw.trim();
    if (value.isEmpty) return (core: '', qualifier: null);

    if (value.startsWith('(') && value.indexOf('(', 1) > 0) {
      final rest = value.substring(1);
      final cut = rest.indexOf('(');
      final head = rest.substring(0, cut);
      final post = rest.substring(cut + 1).trim();
      final firstLetter = _hebrewLetter.firstMatch(head);
      final pre = firstLetter == null
          ? ''
          : head.substring(0, firstLetter.start);
      final core = firstLetter == null
          ? head
          : head.substring(firstLetter.start);
      final pieces = [
        post,
        ...pre.split(' ').where((p) => p.isNotEmpty).toList().reversed,
      ].where((p) => p.isNotEmpty);
      final qualifier = pieces
          .join(' ')
          // גרש ומרכאות שייכים למילה שלפניהם: `עמ '` → `עמ'`.
          .replaceAll(" ' ", "' ")
          .replaceAll(' " ', '" ')
          .trim();
      return (
        core: _trimMarks(core),
        qualifier: qualifier.isEmpty ? null : qualifier,
      );
    }
    return (core: _trimMarks(value), qualifier: null);
  }

  /// כוכבית מובילה מסמנת בעץ סימן שאינו במקומו הרגיל. היא אינה חלק מהשם
  /// ומנתח ההפניות אינו מקבל אותה.
  static String _trimMarks(String value) =>
      value.replaceAll(RegExp(r'^[*\s]+|[\s]+$'), '');

  /// השם בלי ההסתייגות — מה שנשלח למנתח ההפניות.
  static String coreOf(String raw) => split(raw).core;

  /// השם הקריא, כולל ההסתייגות בסדר נכון.
  static String displayOf(String raw) {
    final parts = split(raw);
    if (parts.qualifier == null) return parts.core;
    return '${parts.core} (${parts.qualifier})';
  }

  // -------------------------------------------------- השם המלא של הספר

  /// השם המלא של הספר: שם החיבור ואחריו שם היחידה.
  ///
  /// מצרפים אב **כל עוד השם שבידינו הוא שם יחידה**, ולכל היותר
  /// [maxAncestors] אבות. שני סייגים:
  ///
  /// * **שורש הקטגוריה לעולם אינו מצורף.** `תנ"ך > בראשית` הוא
  ///   `בראשית`, לא `תנ"ך בראשית` — הקטגוריה מוצגת בשדה נפרד.
  /// * אב ששמו זהה לשם שכבר בידינו מדולג.
  ///
  /// [ancestors] הם רכיבי הנתיב כפי שהם בעץ, מהשורש ועד להורה הישיר.
  ///
  /// מחזיר גם את [coreParts] — אותם רכיבים בשמות הליבה שלהם. זו ההפניה
  /// שתישלח למנתח ההפניות, וחשוב ששתיהן ייגזרו מאותה החלטה: הודעת שגיאה
  /// שמזכירה הפניה שאינה השם שהוצג היא הודעה חסרת תועלת.
  /// [levels] הוא מספר **רמות** הנתיב שנצרכו, כולל אב שדולג. הבנייה
  /// משתמשת בו כדי להמשיך ולהעמיק את ההפניה מהמקום שבו השם נעצר.
  static ({String title, List<String> coreParts, int levels}) fullTitle({
    required String rawTitle,
    required List<String> ancestors,
    int maxAncestors = 2,
  }) {
    final names = <String>[displayOf(rawTitle)];
    final cores = <String>[coreOf(rawTitle)];
    var current = cores.first;
    var index = ancestors.length - 1;
    var added = 0;

    // `index >= 1`: עוצרים לפני השורש.
    while (isUnitName(current) && index >= 1 && added < maxAncestors) {
      final parentCore = coreOf(ancestors[index]);
      index--;
      if (parentCore.isEmpty) continue;
      if (ResponsaHebrew.spellingKey(parentCore) ==
          ResponsaHebrew.spellingKey(current)) {
        continue;
      }
      names.insert(0, displayOf(ancestors[index + 1]));
      cores.insert(0, parentCore);
      added++;
      current = parentCore;
    }
    return (
      title: names.join(' '),
      coreParts: cores,
      levels: ancestors.length - 1 - index,
    );
  }
}
