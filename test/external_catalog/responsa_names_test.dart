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

    test('שם שאין בו ליבה נשאר כפי שהוא', () {
      // פירוק שמחזיר מחרוזת ריקה מוחק את הספר מהתצוגה ומההפניה כאחד.
      expect(ResponsaNames.coreOf('(('), '((');
      expect(ResponsaNames.displayOf('((123'), '((123');
      expect(ResponsaNames.coreOf(''), '');
    });

    test('שם תקין אינו משתנה', () {
      expect(ResponsaNames.displayOf('שולחן ערוך'), 'שולחן ערוך');
      expect(
        ResponsaNames.displayOf('הלכות קטנות לרי"ף (מנחות) - הלכות ציצית'),
        'הלכות קטנות לרי"ף (מנחות) - הלכות ציצית',
      );
    });
  });

  group('גרש מוביל', () {
    test('גרש בראש השם חוזר לסופו', () {
      // נמדד: ההפניה `'מלחמת ה` נדחתה על ידי המנתח.
      expect(ResponsaNames.displayOf("'מלחמת ה"), "מלחמת ה'");
      expect(ResponsaNames.coreOf("'מלחמת ה"), "מלחמת ה'");
    });

    test('גרשיים מובילים כשיש עוד אחד בפנים', () {
      expect(
        ResponsaNames.displayOf('"ספרי בעל ה"חיי אדם'),
        'ספרי בעל ה"חיי אדם"',
      );
    });

    test('שם שאינו מתחיל בסימן אינו משתנה', () {
      expect(ResponsaNames.displayOf('שאגת אריה'), 'שאגת אריה');
      expect(ResponsaNames.displayOf('רשב"א'), 'רשב"א');
    });
  });

  group('חיבור רכיבים לשם אחד', () {
    test('רכיב שחוזר על אביו אינו נכפל', () {
      // נצפה במאגר: `שמירת הלשון > חלק א > חלק א חתימת הספר`.
      expect(
        ResponsaNames.titleOf(['שמירת הלשון', 'חלק א', 'חלק א חתימת הספר']),
        'שמירת הלשון חלק א חתימת הספר',
      );
    });

    test('רכיב זהה לאביו מדולג', () {
      expect(
        ResponsaNames.titleOf(['בכורי יוסף', 'בכורי יוסף']),
        'בכורי יוסף',
      );
    });

    test('הניקוי הוא על גבול מילה בלבד', () {
      // `חלק א` אינו תחילית של `חלק אבן העזר` — הן שתי מילים שונות.
      expect(
        ResponsaNames.titleOf(['ישועות מלכו', 'חלק אבן העזר']),
        'ישועות מלכו חלק אבן העזר',
      );
    });

    test('ההסתייגות נשמרת בשם ונעלמת מההפניה', () {
      expect(
        ResponsaNames.titleOf(['תוספתא', '(בבא בתרא (ליברמן']),
        'תוספתא בבא בתרא (ליברמן)',
      );
      expect(
        ResponsaNames.referenceOf(['תוספתא', '(בבא בתרא (ליברמן']),
        'תוספתא בבא בתרא',
      );
    });

    test('כתיב מלא וחסר נחשבים חזרה', () {
      expect(
        ResponsaNames.titleOf(['חידושי הריטב"א', 'חדושי הריטבא שבת']),
        'חדושי הריטבא שבת',
      );
    });
  });
}
