import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/external_catalog/responsa/text/responsa_hebrew.dart';

/// השוואת הכותרת שביקשנו לכותרת החלון שנפתח בפועל.
///
/// זו הבדיקה שמונעת פתיחת ספר שגוי, ולכן כל הרפיה בה מסוכנת. כל אחד
/// מהמקרים כאן נצפה בפתיחה חיה מול ההתקנה שעל המחשב.
void main() {
  ResponsaMatchLevel level(String want, String got) =>
      ResponsaHebrew.matchLevel(want, got);

  group('התוכנה מרחיבה את ההפניה', () {
    test('כותרת שהתוכנה הוסיפה לה מיקום', () {
      expect(
        level('הון עשיר אבות', 'הון עשיר מסכת אבות הקדמה'),
        isNot(ResponsaMatchLevel.none),
      );
      expect(
        level('רש"י זכריה', 'רש"י זכריה פרק א'),
        isNot(ResponsaMatchLevel.none),
      );
    });

    test('ספר אחר לגמרי נדחה', () {
      expect(
        level('ספר אחר לגמרי', 'הון עשיר מסכת אבות'),
        ResponsaMatchLevel.none,
      );
      expect(level('שאגת אריה', 'אוצר מדרשים היכלות'), ResponsaMatchLevel.none);
    });
  });

  group('ראשי תיבות', () {
    test("`ר'` מתאים ל-`רבי`", () {
      // נצפה חי: ההפניה נכונה, הספר שנפתח נכון, והאימות פסל אותו —
      // כי `ר` ו-`רב` הם שני אסימונים שונים אחרי קיפול הכתיב.
      expect(
        level(
          "ר' אברהם מן ההר יבמות",
          "רבי אברהם מן ההר (מהד' בלוי) מסכת יבמות הקדמה",
        ),
        isNot(ResponsaMatchLevel.none),
      );
      expect(
        level(
          "ר' אברהם מן ההר הוספות",
          "רבי אברהם מן ההר (מהד' בלוי) הוספות קטעים לשאר מסכתות",
        ),
        isNot(ResponsaMatchLevel.none),
      );
    });

    test('ההרפיה חלה רק על מילה שסומנה בגרש', () {
      // בלי הגרש `ר` נשאר אסימון שלם, ואינו מתאים ל-`רבי`.
      expect(
        level('ר אברהם מן ההר יבמות', 'רבי אברהם מן ההר מסכת יבמות'),
        ResponsaMatchLevel.none,
      );
    });

    test('גרש בסוף מילה אינו מרשה התאמה לכל דבר', () {
      expect(level("ר' אברהם", 'הון עשיר מסכת אבות'), ResponsaMatchLevel.none);
    });
  });

  group('קיפול כתיב', () {
    test('כתיב מלא וחסר מתאימים', () {
      expect(
        level('חדושי אגדות תמורה', 'מהרש"א חידושי אגדות מסכת תמורה'),
        isNot(ResponsaMatchLevel.none),
      );
    });

    test('גרשיים בתוך מילה אינם שוברים את ההשוואה', () {
      expect(
        level('רשב"א', 'חידושי הרשב"א מסכת מנחות'),
        isNot(ResponsaMatchLevel.none),
      );
    });
  });

  group('מקף בתוך מילה', () {
    test('כותרת זהה תו-בתו מתקבלת', () {
      // `spellingKey` מחליף מקף ברווח, ולכן `כו-כז` הופך למפתח שיש בו
      // רווח. בלי פיצול שני, האסימון הזה לעולם אינו שווה לאף אסימון
      // מהצד השני — וכל שם שיש בו מקף נפסל, גם כשהכותרת זהה בדיוק.
      const title = 'חיי אדם חלק ב-ג (הלכות שבת ומועדים) כלל כו-כז';
      expect(ResponsaHebrew.coversTitle(title, title), isTrue);
    });

    test('המקף אינו מבטל את ההבחנה', () {
      expect(
        ResponsaHebrew.coversTitle(
          'חיי אדם חלק ב-ג כלל כו-כז',
          'חיי אדם חלק א כלל א',
        ),
        isFalse,
      );
    });

    test('אסימוני המקף מופיעים בנפרד', () {
      expect(
        ResponsaHebrew.markedTokens('כו-כז').map((t) => t.key).toList(),
        ['כ', 'כז'],
      );
    });
  });

  group('מדף שנדבק לשם', () {
    test('ראש השם חסר בכותרת — אסימון אחד מותר', () {
      // `מדרש רבה (תורה) > שמות רבה (וילנא)` הוא מדף וחיבור, והתוכנה
      // מכנה את החלון בשם החיבור בלבד.
      expect(
        ResponsaHebrew.coversTitle(
          'מדרש רבה שמות רבה',
          'שמות רבה (וילנא) פרשת שמות פרשה א',
        ),
        isTrue,
      );
    });

    test('ויתור על שני אסימונים אינו מותר', () {
      // `בית הבחירה למאירי על הש"ס ברכות` נפתח בטעות כ-`שרידי אש על
      // הש"ס ברכות`. הדרישה ל-`בית` או `הבחירה` היא מה שפוסל אותו.
      expect(
        ResponsaHebrew.coversTitle(
          'בית הבחירה למאירי על הש"ס ברכות',
          'שרידי אש על הש"ס ברכות',
        ),
        isFalse,
      );
    });

    test('סוף השם נדרש תמיד', () {
      expect(
        ResponsaHebrew.coversTitle('מהרש"א בבא בתרא', 'מהרש"א פסחים'),
        isFalse,
      );
    });
  });

  group('מהדורות סותרות', () {
    test('שתי הסתייגויות שונות הן סתירה', () {
      expect(
        ResponsaHebrew.editionsConflict(
          'שמות רבה (שנאן)',
          'שמות רבה (וילנא) פרשת שמות פרשה א',
        ),
        isTrue,
      );
    });

    test('אותה הסתייגות אינה סתירה', () {
      expect(
        ResponsaHebrew.editionsConflict(
          'שמות רבה (וילנא)',
          'שמות רבה (וילנא) פרשת שמות פרשה א',
        ),
        isFalse,
      );
    });

    test('צד אחד בלי הסתייגות אינו סתירה', () {
      // `היכלות (עמ' 108-126)` נפתח ככותרת `אוצר מדרשים (אייזנשטיין)
      // היכלות`; שתי ההסתייגויות מתארות דברים שונים לגמרי, ולכן
      // הבדיקה פועלת רק כששתיהן קיימות — וכאן היא אינה פוסלת.
      expect(
        ResponsaHebrew.editionsConflict('היכלות', 'היכלות פרק א'),
        isFalse,
      );
      expect(
        ResponsaHebrew.editionsConflict('שמות רבה', 'שמות רבה (וילנא)'),
        isFalse,
      );
    });

    test('הסתייגות עם ספרה היא מיקום ולא מהדורה', () {
      // `(עמ' 108-126)` מתאר טווח עמודים ב-110 שמות במאגר. הוא אינו
      // סותר את `(אייזנשטיין)`, שהוא מהדורה — והספר נכון.
      expect(
        ResponsaHebrew.editionsConflict(
          "היכלות (עמ' 108-126)",
          'אוצר מדרשים (אייזנשטיין) היכלות',
        ),
        isFalse,
      );
    });

    test('שתי הסתייגויות שאחת מהן משותפת אינה סתירה', () {
      expect(
        ResponsaHebrew.editionsConflict(
          'בראשית רבה (תיאודור-אלבק) (כי"ו)',
          'בראשית רבה (תיאודור-אלבק)',
        ),
        isFalse,
      );
    });
  });
}
