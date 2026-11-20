import 'package:flutter/material.dart';
import 'package:otzaria/widgets/text/rtl_text_field.dart';

import '../golden_harness.dart';

/// ארבעת מצבי השדה בעמודה אחת: ריק עם רמז, מלא, שגיאה ומושבת.
Widget _states({String? longText}) => SizedBox(
  width: 320,
  child: Column(
    mainAxisSize: MainAxisSize.min,
    spacing: 16,
    children: [
      const RtlTextField(
        decoration: InputDecoration(
          labelText: 'שם הקבוצה',
          hintText: 'למשל: ספרי יסוד',
        ),
      ),
      RtlTextField(
        controller: TextEditingController(
          text: longText ?? 'ספרי יסוד בהלכה',
        ),
        decoration: const InputDecoration(labelText: 'שם הקבוצה'),
      ),
      RtlTextField(
        controller: TextEditingController(text: 'א'),
        decoration: const InputDecoration(
          labelText: 'שם הקבוצה',
          errorText: 'השם חייב להכיל לפחות שני תווים',
        ),
      ),
      const RtlTextField(
        enabled: false,
        decoration: InputDecoration(labelText: 'שם הקבוצה (מושבת)'),
      ),
    ],
  ),
);

void main() {
  for (final brightness in Brightness.values) {
    goldenTest('RtlTextField, מצבים, ${brightness.name}', (tester) async {
      await pumpGolden(
        tester,
        _states(),
        brightness: brightness,
        size: const Size(480, 420),
      );
      await expectGolden('rtl_text_field.${brightness.name}');
    });
  }

  goldenTest('RtlTextField, חלון צר וטקסט ארוך, light', (tester) async {
    await pumpGolden(
      tester,
      SizedBox(
        width: 200,
        child: RtlTextField(
          controller: TextEditingController(
            text:
                'שם ארוך מאוד של קבוצה שלא נכנס בשדה צר ונחתך בקצה, '
                'כולל מילים נוספות',
          ),
          decoration: const InputDecoration(
            labelText: 'שם הקבוצה כפי שיוצג ברשימה',
          ),
        ),
      ),
      size: const Size(280, 120),
    );
    await expectGolden('rtl_text_field_narrow_long.light');
  });

  goldenTest('RtlTextField, טקסט LTR בתוך שדה RTL, light', (tester) async {
    await pumpGolden(
      tester,
      _states(longText: 'https://otzaria.org/library'),
      size: const Size(480, 420),
    );
    await expectGolden('rtl_text_field_ltr_text.light');
  });
}
