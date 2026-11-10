import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/text_book/utils/toc_unit_label.dart';

void main() {
  group('allUnitLabel', () {
    group('מילות מפתח מוכרות', () {
      test('פרק → כל הפרק', () {
        expect(allUnitLabel('פרק ראשון'), 'כל הפרק');
      });

      test('דף → כל הדף', () {
        expect(allUnitLabel('דף י:'), 'כל הדף');
      });
    });

    group('ברירת מחדל — כל הפיסקה', () {
      test('כותרת ספר ברירת מחדל', () {
        expect(allUnitLabel('ספר בראשית'), 'כל הפיסקה');
      });

      test('מחרוזת ריקה', () {
        expect(allUnitLabel(''), 'כל הפיסקה');
      });

      test('רווחים בלבד', () {
        expect(allUnitLabel('   '), 'כל הפיסקה');
      });
    });

    group('מילה ראשונה בלבד נבדקת', () {
      test('מילת מפתח שנייה לא מספיקה', () {
        // "ראשון פרק" — המילה הראשונה היא "ראשון", לא "פרק"
        expect(allUnitLabel('ראשון פרק'), 'כל הפיסקה');
      });

      test('ריווח מוביל מוסר לפני בדיקה', () {
        expect(allUnitLabel('  פרק א'), 'כל הפרק');
      });
    });
  });
}
