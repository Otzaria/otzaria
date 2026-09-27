import 'package:otzaria/external_catalog/responsa/text/responsa_names.dart';

/// צומת אחד בשרשרת מהשורש ועד הספר, כפי שהיא נדרשת לפירוק.
typedef ResponsaChainNode = ({int level, int param, String name});

/// מקור האמת הוא סוג הצומת ב-`lParam` ולא שמו: 1-2 קטגוריה, 3 מחבר/סדרה,
/// 4 החיבור, 5+ יחידות. רשימת שמות לעולם אינה שלמה.
class ResponsaStructure {
  ResponsaStructure._();

  /// סוג הצומת: הבייט הנמוך של המילה הגבוהה ב-`lParam`.
  static int kindOf(int param) => (param >> 16) & 0xFF;

  /// סוג הצומת של חיבור.
  static const int workKind = 4;

  /// סוג הצומת של מחבר או סדרה שמעל החיבור. תמיד חלק מהשם.
  static const int collectionKind = 3;

  /// הסיום `(?=[\s"'׳״]|$)` ולא `\b` - ב-Dart גבול המילה הוא ASCII ואות
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

  /// סוג 2 משמש גם לתווית מיון וגם לשם חיבור (`שולחן ערוך`); בלי ההבחנה
  /// `שולחן ערוך > חושן משפט` מוצג כ-`חושן משפט` בלבד.
  static bool isCategoryLabel(String name, int level) {
    // שורש הוא תמיד קטגוריה. הוא תווית המיון העליונה ואינו שם של חיבור.
    if (level == 0) return true;
    final core = ResponsaNames.coreOf(name);
    if (core.isEmpty) return true;
    if (_genericLabels.contains(core)) return true;
    return _labelLead.hasMatch(core) || _labelPart.hasMatch(core);
  }

  /// תווית מעל החיבור נשארת בקטגוריה, אחרת היא נכללת בשם המצופה ופוסלת פתיחה
  /// תקינה. `null` כשאין חיבור - צומת קטגוריה שסווג כספר.
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
