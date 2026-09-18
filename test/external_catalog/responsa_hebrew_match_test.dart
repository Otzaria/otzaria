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
}
