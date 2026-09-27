import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/external_catalog/responsa/native/responsa_instance.dart';

/// מופע חונה מחוץ למסך אינו נבחר לעולם: הוא עונה לפקודות ופותח ספרים, כך
/// שהפתיחה "מצליחה" והמשתמש אינו רואה דבר.
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
      // מיון לפי מספר החלונות לבדו בוחר תמיד בחונה, כי הוא מרוקן את
      // חלונותיו בסגירה ונשאר עם אפס.
      expect(ResponsaInstance.pickIndex([parked, usable(9)]), 1);
    });

    test('כל המופעים חונים — אין בחירה, ולא נסיגה לחונה', () {
      expect(ResponsaInstance.pickIndex(const [parked, parked]), isNull);
    });
  });
}
