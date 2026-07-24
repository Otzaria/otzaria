import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/personal_notes/utils/note_text_utils.dart';

void main() {
  group('splitBookContentIntoLines', () {
    test('מפצל לפי שורות ומנרמל \\r\\n', () {
      expect(
        splitBookContentIntoLines('שורה א\r\nשורה ב\nשורה ג'),
        ['שורה א', 'שורה ב', 'שורה ג'],
      );
    });

    test('מסיר שורה ריקה בסוף התוכן', () {
      expect(splitBookContentIntoLines('שורה א\nשורה ב\n'), [
        'שורה א',
        'שורה ב',
      ]);
    });

    test('שורות ריקות באמצע נשמרות', () {
      expect(splitBookContentIntoLines('א\n\nב'), ['א', '', 'ב']);
    });
  });

  group('extractReferenceWordsFromLine', () {
    test('מחלץ מילים עד למגבלה', () {
      final words = extractReferenceWordsFromLine(
        'אחת שתיים שלוש ארבע חמש',
        limit: 3,
      );
      expect(words, ['אחת', 'שתיים', 'שלוש']);
    });

    test('מסיר תגי HTML לפני חילוץ', () {
      final words = extractReferenceWordsFromLine(
        '<b>מילה</b> <span>נוספת</span>',
      );
      expect(words, ['מילה', 'נוספת']);
    });

    test('מדלג על מילים מכותרת הספר', () {
      final words = extractReferenceWordsFromLine(
        'בראשית ברא אלהים',
        excludeBookTitle: 'בראשית',
      );
      expect(words, ['ברא', 'אלהים']);
    });

    test('שורה ריקה מחזירה רשימה ריקה', () {
      expect(extractReferenceWordsFromLine(''), isEmpty);
    });
  });

  group('extractReferenceWordsFromLines', () {
    final lines = ['שורה ראשונה', 'שורה שניה'];

    test('מספור שורות הוא 1-based', () {
      expect(extractReferenceWordsFromLines(lines, 1), ['שורה', 'ראשונה']);
      expect(extractReferenceWordsFromLines(lines, 2), ['שורה', 'שניה']);
    });

    test('מספר שורה מחוץ לטווח מחזיר רשימה ריקה', () {
      expect(extractReferenceWordsFromLines(lines, 0), isEmpty);
      expect(extractReferenceWordsFromLines(lines, 3), isEmpty);
    });
  });

  group('extractDisplayTextFromLine', () {
    test('מסיר ניקוד ותגי HTML', () {
      final text = extractDisplayTextFromLine('<b>בְּרֵאשִׁית בָּרָא</b>');
      expect(text, 'בראשית ברא');
    });

    test('מגביל את מספר המילים', () {
      final text = extractDisplayTextFromLine(
        'אחת שתיים שלוש ארבע חמש שש',
        maxWords: 2,
      );
      expect(text, 'אחת שתיים');
    });

    test('מדלג על מילות כותרת הספר', () {
      final text = extractDisplayTextFromLine(
        'בראשית ברא אלהים',
        excludeBookTitle: 'בראשית',
      );
      expect(text, 'ברא אלהים');
    });

    test('קוצץ תוצאה ארוכה מ-100 תווים', () {
      final longLine = List.filled(5, 'א' * 30).join(' ');
      final text = extractDisplayTextFromLine(longLine, maxWords: 5);
      expect(text.length, lessThanOrEqualTo(100));
    });

    test('שורה ריקה מחזירה מחרוזת ריקה', () {
      expect(extractDisplayTextFromLine(''), '');
      expect(extractDisplayTextFromLine('<br/>'), '');
    });
  });

  group('removeHebrewDiacritics', () {
    test('מסיר ניקוד וטעמים', () {
      expect(removeHebrewDiacritics('בְּרֵאשִׁ֖ית'), 'בראשית');
    });

    test('מחליף מקף עברי ברווח', () {
      expect(removeHebrewDiacritics('על־כן'), 'על כן');
    });
  });

  group('normalizeWord', () {
    test('מסיר סימני פיסוק ומשאיר אותיות וספרות', () {
      expect(normalizeWord('"שלום,'), 'שלום');
      expect(normalizeWord('123!'), '123');
    });

    test('מילה שכולה פיסוק מוחזרת לאחר trim', () {
      expect(normalizeWord(' ?! '), '?!');
    });
  });

  group('computeWordOverlapRatio', () {
    test('רשימה שמורה ריקה מחזירה 1.0', () {
      expect(computeWordOverlapRatio([], ['א']), 1.0);
    });

    test('רשימה בפועל ריקה מחזירה 0.0', () {
      expect(computeWordOverlapRatio(['א'], []), 0.0);
    });

    test('חפיפה מלאה מחזירה 1.0', () {
      expect(computeWordOverlapRatio(['א', 'ב'], ['ב', 'א']), 1.0);
    });

    test('חפיפה חלקית מחזירה את היחס הנכון', () {
      expect(computeWordOverlapRatio(['א', 'ב', 'ג', 'ד'], ['א', 'ב']), 0.5);
    });

    test('הנרמול מתעלם מסימני פיסוק בהשוואה', () {
      expect(computeWordOverlapRatio(['שלום,'], ['"שלום']), 1.0);
    });
  });
}
