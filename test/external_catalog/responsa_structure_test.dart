import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/external_catalog/responsa/text/responsa_names.dart';
import 'package:otzaria/external_catalog/responsa/text/responsa_structure.dart';

/// פירוק שרשרת העץ לפי סוג הצומת.
///
/// כל שרשרת כאן הועתקה מהעץ האמיתי של המהדורה המותקנת, כולל ערכי
/// `lParam`, ולכן הבדיקות מתארות את המאגר ולא השערה עליו.
void main() {
  /// בונה צומת עם סוג [kind] ומזהה [id] במילה הנמוכה, כמו במאגר.
  ResponsaChainNode node(int level, int kind, String name, [int id = 1]) =>
      (level: level, param: (kind << 16) | id, name: name);

  group('סוג הצומת', () {
    test('נקרא מהבייט הנמוך של המילה הגבוהה', () {
      expect(ResponsaStructure.kindOf(0x00040000 | 49156), 4);
      expect(ResponsaStructure.kindOf(0x00030000 | 10), 3);
      expect(ResponsaStructure.kindOf(0x130b0000), 11);
    });
  });

  group('תווית מיון מול שם חיבור', () {
    test('שורש הוא תמיד קטגוריה', () {
      expect(ResponsaStructure.isCategoryLabel('שולחן ערוך', 0), isTrue);
    });

    test('תוויות מיון של המאגר', () {
      for (final label in [
        'ספרי שאלות ותשובות - אחרונים',
        'מפרשים על הרמב"ם',
        'ראשונים ופוסקים על הבבלי',
        'אחרונים על הבבלי',
        'רי"ף ונושאי כליו',
        'רש"י ומפרשיו',
        'מדרשי אגדה',
        'ביאורים וליקוטים על הבבלי והירושלמי',
        'מפרשים וחיבורים סביב שולחן ערוך',
        'מפתח נושאים בשו"ת',
        'ערכים',
      ]) {
        expect(
          ResponsaStructure.isCategoryLabel(label, 1),
          isTrue,
          reason: label,
        );
      }
    });

    test('שמות חיבורים שיושבים ברמת קטגוריה', () {
      for (final name in [
        'שולחן ערוך',
        'טור',
        'משנה',
        'תוספתא',
        'תלמוד בבלי',
        '(תלמוד ירושלמי (וילנא',
        '(משנה תורה לרמב"ם (עם ראב"ד',
      ]) {
        expect(
          ResponsaStructure.isCategoryLabel(name, 1),
          isFalse,
          reason: name,
        );
      }
    });
  });

  group('פירוק שרשרת', () {
    test('חיבור פשוט תחת קטגוריה', () {
      // מפרשי המשנה ומדרשי הלכה > הון עשיר(4) > אבות
      final parts = ResponsaStructure.decompose([
        node(0, 2, 'מפרשי המשנה ומדרשי הלכה'),
        node(1, 4, 'הון עשיר', 49156),
        node(2, 6, 'אבות'),
      ])!;
      expect(ResponsaNames.titleOf(parts.nameNodes), 'הון עשיר אבות');
      expect(parts.categoryNodes, ['מפרשי המשנה ומדרשי הלכה']);
      expect(parts.workOffset, 0);
    });

    test('שם המחבר שמעל החיבור נכנס לשם ולא לקטגוריה', () {
      // זה מה שהחזיר את `מהרש"א` לכותרת: הוא הופיע ב-78 נתיבים ובאפס
      // כותרות, ולכן חיפוש לפי שמו לא החזיר דבר.
      final parts = ResponsaStructure.decompose([
        node(0, 1, 'מפרשים ופוסקים על הבבלי והירושלמי'),
        node(1, 2, 'אחרונים על הבבלי'),
        node(2, 3, 'מהרש"א'),
        node(3, 4, 'חידושי הלכות', 23557),
        node(4, 6, 'בבא בתרא'),
      ])!;
      expect(
        ResponsaNames.titleOf(parts.nameNodes),
        'מהרש"א חידושי הלכות בבא בתרא',
      );
      // ההפניה מתחילה מהחיבור: `מהרש"א` אינו חלק ממה שהמנתח מצפה לו.
      expect(parts.workOffset, 1);
      expect(
        ResponsaNames.referenceOf(parts.nameNodes.sublist(parts.workOffset)),
        'חידושי הלכות בבא בתרא',
      );
    });

    test('שם חיבור ברמת קטגוריה נכנס לשם', () {
      final parts = ResponsaStructure.decompose([
        node(0, 1, 'טור, שולחן ערוך, מפרשים וחיבורים'),
        node(1, 2, 'שולחן ערוך'),
        node(2, 4, 'חושן משפט', 30000),
      ])!;
      expect(ResponsaNames.titleOf(parts.nameNodes), 'שולחן ערוך חושן משפט');
      expect(parts.categoryNodes, ['טור, שולחן ערוך, מפרשים וחיבורים']);
    });

    test('תווית מיון נשארת בקטגוריה', () {
      final parts = ResponsaStructure.decompose([
        node(0, 1, '(ספרי שאלות ותשובות (שו"ת'),
        node(1, 2, 'ספרי שאלות ותשובות - אחרונים'),
        node(2, 4, 'תורת יקותיאל', 23832),
        node(3, 6, 'אישות'),
      ])!;
      // הדוגמה שהמשתמש דיווח עליה: הוצג `אישות` בלבד ולכן לא נפתח.
      expect(ResponsaNames.titleOf(parts.nameNodes), 'תורת יקותיאל אישות');
      expect(parts.categoryNodes.length, 2);
      expect(parts.workOffset, 0);
    });

    test('תווית אוסף נשארת בקטגוריה ואינה נכנסת לשם', () {
      // נמדד חי: `ספרי החפץ חיים שמירת הלשון חלק א שער התורה` נפתח
      // ככותרת `חפץ חיים - שמירת הלשון חלק א שער התורה פרק א`, ונפסל
      // רק בגלל התווית. שלוש פתיחות תקינות נפסלו כך.
      final parts = ResponsaStructure.decompose([
        node(0, 2, 'ספרי מחשבה ומוסר'),
        node(1, 3, 'ספרי החפץ חיים', 3),
        node(2, 4, 'שמירת הלשון', 30472),
        node(3, 5, 'חלק א'),
        node(4, 6, 'חלק א שער התורה'),
      ])!;
      expect(
        ResponsaNames.titleOf(parts.nameNodes),
        'שמירת הלשון חלק א שער התורה',
      );
      expect(parts.categoryNodes, ['ספרי מחשבה ומוסר', 'ספרי החפץ חיים']);
      expect(parts.workOffset, 0);
    });

    test('שרשרת בלי חיבור אינה ספר', () {
      // `ילקוט יוסף` הוא צומת אוסף. הסיווג זיהה אותו כספר מפני שיש לו
      // ילד ששמו נראה כמקטע, והוא הופיע בחיפוש בלי שאפשר לפתוח אותו.
      expect(
        ResponsaStructure.decompose([
          node(0, 1, 'ספרי הלכה ומנהג'),
          node(1, 2, 'ספרי הלכה ומנהג - אחרונים'),
          node(2, 3, 'ילקוט יוסף', 10),
        ]),
        isNull,
      );
    });

    test('חיבור בתוך חיבור — העמוק שבהם קובע', () {
      final parts = ResponsaStructure.decompose([
        node(0, 1, 'טור, שולחן ערוך, מפרשים וחיבורים'),
        node(1, 2, 'שולחן ערוך'),
        node(2, 4, 'אבן העזר', 100),
        node(3, 6, '(הלכות גיטין (קיט - קנד'),
        node(4, 4, 'סדר הגט', 200),
      ])!;
      expect(parts.nameNodes.last, 'סדר הגט');
      expect(parts.workOffset, parts.nameNodes.length - 1);
    });
  });
}
