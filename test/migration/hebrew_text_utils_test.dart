import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/migration/generator/hebrew_text_utils.dart';

void main() {
  // בראשית עם ניקוד מלא
  const withNikud = 'בְּרֵאשִׁית';
  // בראשית עם ניקוד וטעמים (טיפחא U+0596 על השי"ן)
  const withNikudAndTeamim = 'בְּרֵאשִׁ֖ית';
  // מילה עם מתג (U+05BD)
  const withMeteg = 'הָֽאָרֶץ';

  group('removeNikud', () {
    test('מסיר ניקוד מטקסט', () {
      expect(removeNikud(withNikud), 'בראשית');
    });

    test('מסיר מתג כברירת מחדל', () {
      expect(removeNikud(withMeteg), 'הארץ');
    });

    test('משאיר מתג כאשר includeMeteg=false', () {
      expect(removeNikud(withMeteg, includeMeteg: false), 'הֽארץ');
    });

    test('לא מסיר טעמים', () {
      expect(removeNikud(withNikudAndTeamim), 'בראש֖ית');
    });

    test('קלט null או ריק מחזיר מחרוזת ריקה', () {
      expect(removeNikud(null), '');
      expect(removeNikud(''), '');
    });

    test('טקסט ללא ניקוד מוחזר כמו שהוא', () {
      expect(removeNikud('בראשית'), 'בראשית');
    });
  });
}
