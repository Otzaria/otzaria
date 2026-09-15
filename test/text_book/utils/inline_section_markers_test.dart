import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/text_book/utils/inline_section_markers.dart';

void main() {
  group('prependSectionMarker', () {
    test('מקדים אות מודגשת בסוגריים מרובעים לפני התוכן', () {
      expect(
        prependSectionMarker('רַבִּי הוֹשַׁעְיָה רַבָּה פָּתַח', 'א'),
        '<b>[א]</b> רַבִּי הוֹשַׁעְיָה רַבָּה פָּתַח',
      );
    });

    test('תווית רב-אותית (יא, סעיף ג) נשמרת כלשונה', () {
      expect(
        prependSectionMarker('טקסט', 'סעיף ג'),
        '<b>[סעיף ג]</b> טקסט',
      );
    });

    test('שורה עם תגי HTML — הסמן נכנס לפני התג הראשון', () {
      expect(
        prependSectionMarker('<big>בְּ</big>רֵאשִׁית', 'ב'),
        '<b>[ב]</b> <big>בְּ</big>רֵאשִׁית',
      );
    });

    test('label null — השורה חוזרת כמות שהיא', () {
      expect(prependSectionMarker('טקסט', null), 'טקסט');
    });

    test('label ריק — השורה חוזרת כמות שהיא', () {
      expect(prependSectionMarker('טקסט', ''), 'טקסט');
    });

    test('שורה ריקה — נשארת ריקה גם עם label', () {
      expect(prependSectionMarker('', 'א'), '');
    });
  });

  group('prependSectionHeadings', () {
    test('כל כותרת נכנסת כבלוק h3 עם מחלקת העיצוב, לפי הסדר', () {
      expect(
        prependSectionHeadings('טקסט', ['הלכות תפילין', 'דיני הנחה']),
        '<h3 class="$kSectionHeadingClass">הלכות תפילין</h3>'
        '<h3 class="$kSectionHeadingClass">דיני הנחה</h3>טקסט',
      );
    });

    test('בלי כותרות — השורה חוזרת כמות שהיא', () {
      expect(prependSectionHeadings('טקסט', null), 'טקסט');
      expect(prependSectionHeadings('טקסט', const []), 'טקסט');
    });
  });

  group('cleanSectionHeadingLabel', () {
    test('מסיר קידומת בסוגריים (קיצור שולחן ערוך) ורווח/שורה חדשה', () {
      expect(
        cleanSectionHeadingLabel('[סימן א] דיני השכמת הבקר\n'),
        'דיני השכמת הבקר',
      );
    });

    test('מסיר BOM', () {
      expect(cleanSectionHeadingLabel('﻿סיפורים חדשים'), 'סיפורים חדשים');
    });
  });

  group('sectionHeadingLinesAbove', () {
    test('עולה מעל כותרת הסימן הצמודה (שולחן ערוך: סימן ח)', () {
      expect(sectionHeadingLinesAbove(['<h2>סימן ח</h2>', '(ד) טקסט']), 1);
    });

    test('עולה מעל רצף כותרות (בית יוסף: סימן + סעיף קטן)', () {
      expect(
        sectionHeadingLinesAbove(['<h4>סעיף קטן א</h4>', '<h3>סימן א</h3>']),
        2,
      );
    });

    test('לא עולה מעל כותרת הספר (h1) או מעל שורת טקסט', () {
      expect(sectionHeadingLinesAbove(['<h1>טור</h1>', null]), 0);
      expect(sectionHeadingLinesAbove(['טקסט', '<h2>סימן א</h2>']), 0);
      expect(sectionHeadingLinesAbove([null, null]), 0);
    });
  });

  group('isSectionHeadingVisible', () {
    test('כותרת מנוקדת בכתיב מלא בראש השורה — גלויה (מסילת ישרים)', () {
      expect(
        isSectionHeadingVisible('בביאור מדת הזהירות', [
          '<b>בְּבֵאוּר מִדַּת הַזְּהִירוּת</b> הִנֵּה עִנְיַן',
          '<h2>פרק ב</h2>',
          null,
        ]),
        isTrue,
      );
    });

    test('מספור "(א)" לפני הכותרת אינו מסתיר אותה', () {
      expect(
        isSectionHeadingVisible('הלכות ציצית', [
          '(א) <b>הלכות ציצית ועטיפתו. ובו יז סעיפים:</b>',
          '<h2>סימן ח</h2>',
          null,
        ]),
        isTrue,
      );
    });

    test('כותרת מקוצרת שתי שורות לפני — גלויה (טור)', () {
      expect(
        isSectionHeadingVisible('הלכות ברכות השחר ושאר ברכות', [
          'טקסט הסימן',
          '<h3>סימן מז</h3>',
          '<b>הלכות ברכות השחר </b> <i data-commentator="Bach"></i>',
        ]),
        isTrue,
      );
    });

    test('הכותרת לא כתובה בסביבה — חסרה (שולחן ערוך)', () {
      expect(
        isSectionHeadingVisible('הלכות הנהגת האדם בבוקר', [
          '(א) <b>דין השכמת הבוקר. ובו ט סעיפים:</b>',
          '<h2>סימן א</h2>',
          'יוסף קארו',
        ]),
        isFalse,
      );
    });

    test('אזכור באמצע השורה אינו נחשב כותרת גלויה', () {
      expect(
        isSectionHeadingVisible('הלכות תפילין', [
          '(א) כדי שלא יעבור על המצות, כמבואר לעיל הלכות תפילין',
          null,
          null,
        ]),
        isFalse,
      );
    });
  });
}
