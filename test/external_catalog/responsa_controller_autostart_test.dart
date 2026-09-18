import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/external_catalog/responsa/native/responsa_controller.dart';

/// הרשאת ההפעלה האוטומטית של בר אילן.
///
/// הבקר נוצר כשמסך ההגדרות שואל על מצב ההתקנה — כלומר **לפני** שהמשתמש
/// הדליק את ההגדרה. ערך שנלכד באותו רגע היה נשאר `false` עד להפעלה
/// מחדש של אוצריא, והפתיחה הייתה נכשלת ב"ההפעלה כבויה בהגדרות" בזמן
/// שהמשתמש רואה אותה דלוקה.
void main() {
  test('ההרשאה נקראת בכל פנייה, לא נלכדת בבנייה', () {
    var enabled = false;
    final controller = ResponsaController(allowAutoStart: () => enabled);

    expect(controller.autoStart, isFalse);

    enabled = true;

    expect(controller.autoStart, isTrue);
  });

  test('ברירת המחדל מתירה הפעלה', () {
    expect(ResponsaController().autoStart, isTrue);
  });
}
