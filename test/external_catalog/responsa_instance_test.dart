import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/external_catalog/responsa/native/responsa_instance.dart';

/// מדיניות בחירת המופע.
///
/// הכלל היחיד שחשוב כאן: **מופע חונה מחוץ למסך אינו נבחר לעולם**, גם
/// כשהוא המופע הפנוי ביותר וגם כשהוא היחיד. נמדד שמופע כזה עונה
/// לפקודות ופותח ספרים — כלומר הפתיחה "מצליחה" והמשתמש אינו רואה דבר.
void main() {
  ({bool usable, int windows}) usable(int windows) =>
      (usable: true, windows: windows);
  const parked = (usable: false, windows: 0);

  group('בחירת מופע', () {
    test('אין מופעים — אין בחירה', () {
      expect(ResponsaInstance.pickIndex(const []), isNull);
    });

    test('מופע שימושי יחיד נבחר', () {
      expect(ResponsaInstance.pickIndex([usable(3)]), 0);
    });

    test('הפנוי ביותר מבין השימושיים', () {
      expect(ResponsaInstance.pickIndex([usable(7), usable(2), usable(5)]), 1);
    });

    test('בשוויון נשאר הראשון', () {
      expect(ResponsaInstance.pickIndex([usable(4), usable(4)]), 0);
    });

    test('מופע חונה אינו נבחר אף שהוא הפנוי ביותר', () {
      // זה הכשל עצמו: המיון לפי מספר החלונות בסדר עולה בחר תמיד במופע
      // החונה, כי הוא מרוקן את חלונותיו בסגירה ונשאר עם אפס.
      expect(ResponsaInstance.pickIndex([parked, usable(9)]), 1);
    });

    test('כל המופעים חונים — אין בחירה, ולא נסיגה לחונה', () {
      expect(ResponsaInstance.pickIndex(const [parked, parked]), isNull);
    });
  });
}
