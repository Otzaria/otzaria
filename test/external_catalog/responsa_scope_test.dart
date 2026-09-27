import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/external_catalog/responsa/text/responsa_names.dart';

/// יש צמתי חיבור ששמם כולל את תחום התוכן, והמנתח מכיר רק את שם החיבור:
/// `תרגום יונתן נביאים יהושע` נדחה, `תרגום יונתן יהושע` נפתח.
void main() {
  group('הסרת תחום משם החיבור', () {
    test('סעיף אחרי מקף', () {
      expect(ResponsaNames.withoutScope('תרגום המיוחס ליונתן - תורה'), [
        'תרגום המיוחס ליונתן',
        // המילה האחרונה, כצורה מבנית שנייה.
        'תרגום המיוחס ליונתן -',
      ]);
    });

    test('המילה האחרונה כשאין מקף', () {
      expect(ResponsaNames.withoutScope('תרגום יונתן נביאים'), [
        'תרגום יונתן',
      ]);
    });

    test('שם בן שתי מילים אינו מקוצר', () {
      // `חידושי הגר"ח` היה הופך ל-`חידושי` — מילה גנרית ששייכת למאות
      // חיבורים, ובדיוק כזו שפותחת ספר אחר.
      expect(ResponsaNames.withoutScope('חידושי הגר"ח'), isEmpty);
    });

    test('שם בן מילה אחת אינו מקוצר', () {
      expect(ResponsaNames.withoutScope('רמב"ם'), isEmpty);
    });

    test('ריק', () {
      expect(ResponsaNames.withoutScope(''), isEmpty);
      expect(ResponsaNames.withoutScope('   '), isEmpty);
    });

    test('מקף בלי סעיף אחריו רק נושר', () {
      // הסעיף שאחרי המקף הוא מה שמוסר, ומקף יחיד בסוף אינו סעיף.
      // מה שנשאר הוא השם עצמו — הפניה תקינה, לא קיצור.
      expect(ResponsaNames.withoutScope('אור זרוע -'), ['אור זרוע']);
    });
  });
}
