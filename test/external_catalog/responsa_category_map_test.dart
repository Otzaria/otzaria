import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/external_catalog/responsa/responsa_category_map.dart';
import 'otzaria_categories_fixture.dart';

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
      expect(target('ספרי שאלות ותשובות (שו"ת) > מדף שאינו בטבלה'), ['שו״ת']);
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

  test('כל יעד קיים בעץ הקטגוריות של אוצריא', () {
    // בלי הבדיקה הזו אפשר לכתוב יעד שנראה סביר ואינו קיים — ואז הספרים
    // פשוט אינם מופיעים בשום מקום, בלי שגיאה ובלי סימן.
    for (final path in ResponsaCategoryMap.allTargets) {
      expect(
        otzariaCategories,
        contains(path.join('/')),
        reason: 'היעד ${path.join(' › ')} אינו קיים בעץ של אוצריא',
      );
    }
  });

  test('כל מדף שנמדד בקטלוג משויך', () {
    // 43 נתיבי הסיווג שנמדדו בקטלוג של מהדורה 25. מדף שאינו משויך
    // שולח את ספריו לתיקייה עליונה נפרדת במקום לקטגוריה של אוצריא.
    for (final path in measuredResponsaShelves) {
      expect(
        ResponsaCategoryMap.otzariaPathFor(path),
        isNotNull,
        reason: 'המדף "$path" אינו משויך לשום קטגוריה באוצריא',
      );
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
        'שו״ת › אחרונים',
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
