import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/external_catalog/responsa/responsa_category_map.dart';

/// שיוך קטגוריות בר אילן לקטגוריות אוצריא.
void main() {
  List<String>? target(String path) => ResponsaCategoryMap.otzariaPathFor(path);

  group('שיוך ברמה אחת', () {
    test('שו"ת', () {
      // התלונה המקורית: ספרי שו"ת מבר אילן לא הופיעו תחת `שו״ת`.
      expect(target('ספרי שאלות ותשובות (שו"ת)'), ['שו״ת']);
    });

    test('חסידות', () {
      expect(target('ספרי חסידות'), ['חסידות']);
    });

    test('קטגוריה עם תת-נתיב שאינו בטבלה נופלת לרמה אחת', () {
      expect(
        target('ספרי שאלות ותשובות (שו"ת) > ספרי שאלות ותשובות - אחרונים'),
        ['שו״ת'],
      );
    });
  });

  group('שיוך ברמה שתיים', () {
    test('ספרות חז"ל מתפצלת', () {
      expect(target('ספרות חז"ל > משנה'), ['משנה']);
      expect(target('ספרות חז"ל > תוספתא'), ['תוספתא']);
      expect(target('ספרות חז"ל > תלמוד בבלי'), ['תלמוד בבלי']);
      expect(target('ספרות חז"ל > מדרשי אגדה'), ['מדרש', 'אגדה']);
      expect(target('ספרות חז"ל > מדרשי הלכה'), ['מדרש', 'הלכה']);
    });

    test('שתי מהדורות הירושלמי לאותו יעד', () {
      expect(target('ספרות חז"ל > תלמוד ירושלמי (וילנא)'), ['תלמוד ירושלמי']);
      expect(target('ספרות חז"ל > תלמוד ירושלמי (ונציה)'), ['תלמוד ירושלמי']);
    });

    test('הרמה שנצרכה מדווחת', () {
      expect(ResponsaCategoryMap.resolve('ספרות חז"ל > משנה')?.levels, 2);
      expect(ResponsaCategoryMap.resolve('ספרי חסידות')?.levels, 1);
    });
  });

  group('נרמול', () {
    test('גרשיים שונים אינם מנתקים את השיוך', () {
      // `שו"ת` במאגר ו-`שו״ת` באוצריא נבדלים בתו הגרשיים.
      expect(target('ספרי שאלות ותשובות (שו״ת)'), ['שו״ת']);
    });

    test('כתיב מלא וחסר', () {
      expect(target('ספרי חסידות'), target('ספרי חסידות'));
      expect(target('רמב"ם ומפרשיו'), ['הלכה', 'משנה תורה']);
    });

    test('רווחים מיותרים', () {
      expect(target('  ספרי חסידות  '), ['חסידות']);
    });
  });

  group('אין שיוך', () {
    test('קטגוריה שאינה בטבלה', () {
      expect(target('קטגוריה שלא קיימת'), isNull);
    });

    test('ריק', () {
      expect(target(''), isNull);
      expect(target('   '), isNull);
      expect(ResponsaCategoryMap.otzariaPathFor(null), isNull);
    });
  });

  test('כל יעד הוא נתיב לא ריק', () {
    for (final path in ResponsaCategoryMap.allTargets) {
      expect(path, isNotEmpty);
      for (final part in path) {
        expect(part.trim(), isNotEmpty);
      }
    }
  });

  group('שם להצגה', () {
    test('הקטגוריה מוצגת בשמות של אוצריא', () {
      // התלונה: "כותרות שסתם מופיעות באריכות ולא בשם המקובל, למשל
      // ספרי שאלות ותשובות במקום שו"ת".
      expect(
        ResponsaCategoryMap.displayNameFor(
          'ספרי שאלות ותשובות (שו"ת) > ספרי שאלות ותשובות - אחרונים',
        ),
        'שו״ת',
      );
      expect(ResponsaCategoryMap.displayNameFor('ספרי חסידות'), 'חסידות');
    });

    test('נתיב בן שני רכיבים מוצג במלואו', () {
      expect(
        ResponsaCategoryMap.displayNameFor('ספרות חז"ל > מדרשי אגדה'),
        'מדרש › אגדה',
      );
    });

    test('בלי שיוך מוצג שורש בר אילן ולא כלום', () {
      expect(
        ResponsaCategoryMap.displayNameFor('קטגוריה חדשה > תת-קטגוריה'),
        'קטגוריה חדשה',
      );
    });

    test('ריק מחזיר null', () {
      expect(ResponsaCategoryMap.displayNameFor(''), isNull);
      expect(ResponsaCategoryMap.displayNameFor(null), isNull);
    });
  });
}
