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
///
/// **מי מחליט היכן מתחיל השם** אינו כאן אלא ב-[ResponsaStructure], שקורא
/// את סוג הצומת מ-`lParam`. כאן נשארה רק העבודה על המחרוזת עצמה.
class ResponsaNames {
  ResponsaNames._();

  static final RegExp _hebrewLetter = RegExp('[א-ת]');

  // ------------------------------------------------ עטיפת הסוגריים

  /// מפרק שם מאוחסן לשם הליבה ולהסתייגות שבסוגריים.
  ///
  /// המבנה המאוחסן הוא `( PRE CORE ( POST`, כאשר `PRE` ריק ברוב
  /// המקרים ומכיל מספרים ב-110 מהם. ההסתייגות הקריאה מורכבת מ-`POST`
  /// ואחריו אסימוני `PRE` בסדר הפוך — כך `(108-126 'היכלות (עמ` חוזר
  /// להיות `היכלות` + `עמ' 108-126`.
  static ({String core, String? qualifier}) split(String raw) {
    var value = _moveLeadingMark(raw.trim());
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
      // שם שאין בו ליבה כלל — נשאר כפי שהוא. פירוק שמחזיר מחרוזת ריקה
      // גרוע מלא לפרק: הוא מוחק את הספר מהתצוגה ומההפניה כאחד.
      if (_trimMarks(core).isEmpty) return (core: value, qualifier: null);
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

  /// גרש או גרשיים בראש השם הם אותו היפוך חזותי של עטיפת הסוגריים,
  /// בסימן אחד: `'מלחמת ה` הוא `מלחמת ה'`, ו-`"ספרי בעל ה"חיי אדם` הוא
  /// `ספרי בעל ה"חיי אדם"`. הסימן חוזר לסופו של השם.
  ///
  /// אין כאן ניחוש: גרש לעולם אינו פותח שם עברי, והמאגר אינו מכיל שם
  /// שנפתח בו מלבד ההיפוך הזה. ההפניה `'מלחמת ה` נדחתה על ידי המנתח.
  static String _moveLeadingMark(String value) {
    if (value.isEmpty) return value;
    final first = value[0];
    if (first != "'" && first != '"' && first != '׳' && first != '״') {
      return value;
    }
    return '${value.substring(1).trimRight()}$first';
  }

  /// כוכבית מובילה מסמנת בעץ סימן שאינו במקומו הרגיל. היא אינה חלק מהשם
  /// ומנתח ההפניות אינו מקבל אותה.
  static String _trimMarks(String value) =>
      value.replaceAll(RegExp(r'^[*\s]+|[\s]+$'), '');

  /// השם בלי ההסתייגות — מה שנשלח למנתח ההפניות.
  static String coreOf(String raw) => split(raw).core;

  static final RegExp _parenthetical = RegExp(r'\([^)]*\)?|\)');

  /// מסיר כל קטע בסוגריים משם שכבר סודר.
  ///
  /// נחוץ בשני מקומות: בהפניה, כי המנתח אינו מקבל הסתייגות; ובאימות
  /// הכותרת שנפתחה, כי ההסתייגות היא מטא-דאטה של הקטלוג ולא חלק מהשם
  /// שהתוכנה מציגה — `היכלות (עמ' 108-126)` נפתח ככותרת
  /// `אוצר מדרשים (אייזנשטיין) היכלות`, ואימות מילולי היה פוסל פתיחה
  /// תקינה לחלוטין.
  static String withoutQualifier(String name) => name
      .replaceAll(_parenthetical, ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  /// השם הקריא, כולל ההסתייגות בסדר נכון.
  static String displayOf(String raw) {
    final parts = split(raw);
    if (parts.qualifier == null) return parts.core;
    return '${parts.core} (${parts.qualifier})';
  }

  // -------------------------------------------- חיבור רכיבים לשם אחד

  /// מחבר רכיבי נתיב לשם אחד, ומסיר חזרות בין רכיב לרכיב.
  ///
  /// במאגר יש צמתים שחוזרים על שם אביהם: `שמירת הלשון > חלק א >
  /// חלק א חתימת הספר`. חיבור נאיבי מייצר `שמירת הלשון חלק א חלק א
  /// חתימת הספר` — שם שהמשתמש רואה בו תקלה, ובצדק.
  ///
  /// ההשוואה לפי [ResponsaHebrew.spellingKey], כדי שכתיב מלא וחסר לא
  /// יחמקו מהניקוי, ורק על **גבול מילה** — `חלק א` מול `חלק אבן העזר`
  /// אינם חזרה.
  static String joinParts(Iterable<String> parts) {
    final kept = <String>[];
    for (final raw in parts) {
      final part = raw.trim();
      if (part.isEmpty) continue;
      final key = ResponsaHebrew.spellingKey(part);
      if (kept.isNotEmpty && key.isNotEmpty) {
        final previous = ResponsaHebrew.spellingKey(kept.last);
        if (previous.isNotEmpty) {
          // הרכיב הנוכחי בולע את הקודם — הקודם מיותר.
          if (key == previous || key.startsWith('$previous ')) {
            kept.removeLast();
          } else if (previous.startsWith('$key ')) {
            // הקודם כבר מכיל את הנוכחי — אין מה להוסיף.
            continue;
          }
        }
      }
      kept.add(part);
    }
    return kept.join(' ');
  }

  /// השם הקריא של רכיבי נתיב, מחובר ומנוקה מחזרות.
  static String titleOf(Iterable<String> parts) =>
      joinParts(parts.map(displayOf));

  /// אותם רכיבים בשמות הליבה — זו ההפניה שנשלחת למנתח ההפניות.
  ///
  /// חשוב ששתיהן ייגזרו מאותם רכיבים: הודעת שגיאה שמזכירה הפניה שאינה
  /// השם שהוצג היא הודעה חסרת תועלת.
  static String referenceOf(Iterable<String> parts) =>
      joinParts(parts.map(coreOf));
}
