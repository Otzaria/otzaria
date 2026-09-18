import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/external_catalog/responsa/text/responsa_names.dart';

/// כל המחרוזות כאן הן ציטוט מילולי מהקטלוג שנבנה מהתקנת CD25 — 8,523
/// ספרים. הן נראות שבורות מפני שכך הן מאוחסנות.
void main() {
  group('עטיפת הסוגריים', () {
    test('הסתייגות פשוטה חוזרת למקומה', () {
      // במאגר: סוגר פותח בתחילת המחרוזת, סוגר פותח נוסף, ואין סוגר סוגר.
      const raw = '(בבא בתרא (ליברמן';
      expect(ResponsaNames.coreOf(raw), 'בבא בתרא');
      expect(ResponsaNames.displayOf(raw), 'בבא בתרא (ליברמן)');
    });

    test('טווח עמודים — המספרים חוזרים לסוף והשם לראש', () {
      // זה הספר שממנו התגלה הפגם: `היכלות` נפתח, המחרוזת המלאה אינה
      // נפתחת כלל ומחזירה "לא נמצאה כל תוצאה".
      const raw = "(108-126 'היכלות (עמ";
      expect(ResponsaNames.coreOf(raw), 'היכלות');
      expect(ResponsaNames.displayOf(raw), "היכלות (עמ' 108-126)");
    });

    test('שתי הסתייגויות — הראשונה נחתכת והשאר נשמר', () {
      const raw = '(ביצה (יום טוב) (ליברמן';
      expect(ResponsaNames.coreOf(raw), 'ביצה');
    });

    test('שם קטגוריה ארוך', () {
      const raw = '(תנ"ך (החומש מחולק לפרקים';
      expect(ResponsaNames.coreOf(raw), 'תנ"ך');
      expect(ResponsaNames.displayOf(raw), 'תנ"ך (החומש מחולק לפרקים)');
    });

    test('כוכבית מובילה אינה חלק מהשם', () {
      expect(ResponsaNames.coreOf('*סימן רצז'), 'סימן רצז');
    });

    test('שם תקין אינו משתנה', () {
      expect(ResponsaNames.displayOf('שולחן ערוך'), 'שולחן ערוך');
      expect(
        ResponsaNames.displayOf('הלכות קטנות לרי"ף (מנחות) - הלכות ציצית'),
        'הלכות קטנות לרי"ף (מנחות) - הלכות ציצית',
      );
    });
  });

  group('זיהוי שם יחידה', () {
    test('מסכת', () {
      expect(ResponsaNames.isUnitName('בבא קמא'), isTrue);
      expect(ResponsaNames.isUnitName('אבות'), isTrue);
    });

    test('כתיב חלופי במאגר', () {
      // במאגר מופיעים זה לצד זה, ובלי קיפול הכתיב שני ספרים מכל מסכתות
      // הש"ס היו נשארים בלי שם החיבור.
      expect(ResponsaNames.isUnitName('מקוואות'), isTrue);
      expect(ResponsaNames.isUnitName('עוקצין'), isTrue);
    });

    test('ספר תנ"ך וחלק שולחן ערוך', () {
      expect(ResponsaNames.isUnitName('בראשית'), isTrue);
      expect(ResponsaNames.isUnitName('יורה דעה'), isTrue);
    });

    test('מילה פותחת גנרית', () {
      expect(ResponsaNames.isUnitName('כלל נא'), isTrue);
      expect(ResponsaNames.isUnitName('פרשת תצוה'), isTrue);
      expect(ResponsaNames.isUnitName('חלק ב'), isTrue);
    });

    test('שם חיבור אינו שם יחידה', () {
      expect(ResponsaNames.isUnitName('הון עשיר'), isFalse);
      expect(ResponsaNames.isUnitName('נודע ביהודה'), isFalse);
      expect(ResponsaNames.isUnitName('היכלות'), isFalse);
    });
  });

  group('השם המלא', () {
    ({String title, List<String> coreParts, int levels}) full(
      String title,
      List<String> ancestors,
    ) => ResponsaNames.fullTitle(rawTitle: title, ancestors: ancestors);

    test('כרך של חיבור מקבל את שם החיבור', () {
      // הדוגמה שהמשתמש דיווח עליה: ברשימה הופיע `אבות` ושם החיבור
      // הופיע רק בנתיב הקטן שמתחת.
      final result = full('אבות', [
        'מפרשי המשנה ומדרשי הלכה',
        'הון עשיר',
      ]);
      expect(result.title, 'הון עשיר אבות');
      expect(result.coreParts, ['הון עשיר', 'אבות']);
      expect(result.levels, 1);
    });

    test('שורש הקטגוריה לעולם אינו מצורף', () {
      // `בראשית` תחת שורש התנ"ך הוא שם הספר. `תנ"ך בראשית` הוא גם שם
      // גרוע להצגה וגם הפניה שהמנתח דוחה.
      final result = full('בראשית', ['(תנ"ך (החומש מחולק לפרקים']);
      expect(result.title, 'בראשית');
      expect(result.levels, 0);
    });

    test('שרשור של שתי רמות', () {
      final result = full('פרשת בראשית', [
        'פרשנות על התורה',
        'חומת אנך',
        'בראשית',
      ]);
      expect(result.title, 'חומת אנך בראשית פרשת בראשית');
      expect(result.coreParts, ['חומת אנך', 'בראשית', 'פרשת בראשית']);
      expect(result.levels, 2);
    });

    test('אב שאינו מוסיף מידע מדולג, והרמה עדיין נספרת', () {
      final result = full('אבות', ['קטגוריה', 'הון עשיר', 'אבות']);
      expect(result.title, 'הון עשיר אבות');
      expect(result.levels, 2);
    });

    test('ההסתייגות נשמרת בשם המלא', () {
      final result = full('(בבא בתרא (ליברמן', ['ספרות חז"ל', 'תוספתא']);
      expect(result.title, 'תוספתא בבא בתרא (ליברמן)');
      // ההפניה נשלחת בלי ההסתייגות — המנתח אינו מקבל אותה.
      expect(result.coreParts, ['תוספתא', 'בבא בתרא']);
    });

    test('שם חיבור עצמאי נשאר כפי שהוא', () {
      final result = full('היכלות', ['ספרות חז"ל', 'מדרשי אגדה', 'אוצר']);
      expect(result.title, 'היכלות');
      expect(result.levels, 0);
    });
  });
}
