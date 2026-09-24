import 'package:otzaria/external_catalog/responsa/text/responsa_names.dart';

/// צומת אחד בשרשרת מהשורש ועד הספר, כפי שהיא נדרשת לפירוק.
typedef ResponsaChainNode = ({int level, int param, String name});

/// פירוק שרשרת העץ לשם הספר, לקטגוריה ולהפניה.
///
/// **מקור האמת הוא `lParam` של הצומת, לא שמו.** ל-`TVITEM.lParam` של כל
/// צומת בעץ הקטלוג יש מילה גבוהה שבה הבייט הנמוך הוא **סוג הצומת**.
/// נמדד על העץ המלא — 1,251,889 צמתים, 8,523 ספרים:
///
/// | סוג | משמעות | דוגמה |
/// |---|---|---|
/// | 1, 2 | רמות הקטגוריה | `ספרות חז"ל`, `אחרונים על הבבלי` |
/// | 3 | שם מחבר או סדרה שמעל החיבור | `מהרש"א`, `ילקוט יוסף` |
/// | **4** | **החיבור עצמו** | `הון עשיר`, `שמירת הלשון` |
/// | 5 ומעלה | יחידות בתוך החיבור | `חלק א`, `בבא בתרא` |
///
/// 8,462 מתוך 8,523 הספרים (99.3%) הם צאצא של צומת סוג 4 **אחד בדיוק**.
/// 58 הנותרים אינם ספרים כלל אלא צמתי קטגוריה שהסיווג טעה בהם
/// (`שולחן ערוך`, `ילקוט יוסף`, `מפרשים על הרמב"ם`), ו-3 הם חיבור בתוך
/// חיבור (`סדר הגט` בתוך `שולחן ערוך אבן העזר`).
///
/// **מבנה ולא רשימת שמות.** רשימה של מסכתות, חומשים ומילות פתיחה
/// גנריות אינה יכולה להיות שלמה, והחוסר בה הוא שמציג את
/// `שו"ת תורת יקותיאל אישות` כ-`אישות`.
class ResponsaStructure {
  ResponsaStructure._();

  /// סוג הצומת: הבייט הנמוך של המילה הגבוהה ב-`lParam`.
  static int kindOf(int param) => (param >> 16) & 0xFF;

  /// סוג הצומת של חיבור.
  static const int workKind = 4;

  /// סוג הצומת של מחבר או סדרה שמעל החיבור. תמיד חלק מהשם.
  static const int collectionKind = 3;

  /// הסוגים שמתארים רמת קטגוריה.
  static const Set<int> categoryKinds = {1, 2, 3};

  /// מילות פתיחה של תווית מיון.
  ///
  /// הסיום `(?=[\s"'׳״]|$)` ולא `\b` — ב-Dart גבול המילה הוא ASCII ואות
  /// עברית אינה תו-מילה עבורו.
  static final RegExp _labelLead = RegExp(
    r'''^(ספרי|ספרות|מפרשי|מפרשים|ביאורים|פירושים|ראשונים|אחרונים'''
    r'''|מדרשי|דרשות|כתבי עת|אנציקלופד)(?=[\s"'׳״]|$)''',
  );

  /// צירופים שמופיעים רק בתוויות מיון.
  static final RegExp _labelPart = RegExp(
    r'(ונושאי כליו|ומפרשיו|ומפרשיהם|וחיבורים|מפתח| - ראשונים| - אחרונים)',
  );

  static const Set<String> _genericLabels = {
    'ערכים',
    'מפתחות',
    'שונות',
    'כללי',
    'נספחים',
  };

  /// האם הצומת הוא תווית מיון ולא רכיב בשם של חיבור.
  ///
  /// נדרש מפני שסוג 2 משמש לשני דברים: `אחרונים על הבבלי` הוא תווית מיון,
  /// ואילו `שולחן ערוך`, `משנה`, `תוספתא`, `תלמוד בבלי` ו-`טור` הם שמות
  /// חיבורים שהחלק שמתחתיהם הוא הספר. בלי ההבחנה `שולחן ערוך > חושן משפט`
  /// היה מוצג `חושן משפט` בלבד.
  ///
  /// הכלל נבדק מול **כל 101 צמתי הקטגוריה** שמעליהם יושב חיבור במהדורה
  /// המותקנת, ולא מול דוגמאות.
  static bool isCategoryLabel(String name, int level) {
    // שורש הוא תמיד קטגוריה. הוא תווית המיון העליונה ואינו שם של חיבור.
    if (level == 0) return true;
    final core = ResponsaNames.coreOf(name);
    if (core.isEmpty) return true;
    if (_genericLabels.contains(core)) return true;
    return _labelLead.hasMatch(core) || _labelPart.hasMatch(core);
  }

  /// פירוק של שרשרת אחת.
  ///
  /// `nameNodes` הם רכיבי השם — מהשם העליון ביותר שאינו תווית ומטה;
  /// `categoryNodes` הם רכיבי הקטגוריה שמעליהם. [workOffset] הוא מקומו
  /// של החיבור בתוך `nameNodes`, ומשם מתחילות חוליות הנסיגה.
  ///
  /// **רכיב שם שהוא תווית נשאר בקטגוריה.** `מהרש"א` ו-`ילקוט יוסף` הם
  /// שמות, והשם המלא `מהרש"א חידושי הלכות בבא בתרא` הוא בדיוק הכותרת
  /// שהתוכנה נותנת לחלון; לעומתם `ספרי החפץ חיים` הוא תווית אוסף,
  /// והתוכנה קוראת לאותו ספר `חפץ חיים - שמירת הלשון חלק א שער התורה`.
  /// נמדד חי: שלוש פתיחות תקינות נפסלו רק מפני שהתווית נכללה בשם המצופה.
  ///
  /// מחזיר `null` כששרשרת אינה מכילה חיבור כלל — כלומר הסיווג טעה וזיהה
  /// צומת קטגוריה כספר.
  static ({List<String> nameNodes, List<String> categoryNodes, int workOffset})?
  decompose(List<ResponsaChainNode> chain) {
    var work = -1;
    for (var i = 0; i < chain.length; i++) {
      if (kindOf(chain[i].param) == workKind) work = i;
    }
    if (work < 0) return null;

    var start = work;
    while (start > 0) {
      final parent = chain[start - 1];
      final kind = kindOf(parent.param);
      final isName =
          (kind == collectionKind || kind == 2) &&
          !isCategoryLabel(parent.name, parent.level);
      if (!isName) break;
      start--;
    }

    return (
      nameNodes: [for (final node in chain.sublist(start)) node.name],
      categoryNodes: [for (final node in chain.sublist(0, start)) node.name],
      workOffset: work - start,
    );
  }
}
