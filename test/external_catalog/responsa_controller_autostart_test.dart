import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/external_catalog/responsa/native/responsa_controller.dart';

/// הבקר נוצר לפני שהמשתמש מדליק את ההפעלה האוטומטית: ערך שנלכד בבנייה נשאר
/// `false` עד להפעלה מחדש של אוצריא, והפתיחה נכשלת בזמן שההגדרה דלוקה.
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
