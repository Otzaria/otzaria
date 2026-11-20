import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/utils/platform_brightness_listener.dart';

/// theme.changed כשהמערכת מחליפה בהיר/כהה ("עקוב אחרי המערכת"): ה-MaterialApp
/// מתחלף, אבל לתוספים צריך להישלח אירוע. ההאזנה ל-platformBrightness היא
/// ההתחלה של זה (השליחה עצמה ב-MainWindowScreen).
void main() {
  testWidgets('קורא ל-onChanged כשבהירות המערכת מתחלפת, פעם אחת לכל החלפה', (
    tester,
  ) async {
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    final calls = <Brightness>[];

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.rtl,
        child: PlatformBrightnessListener(
          onChanged: calls.add,
          child: const SizedBox(),
        ),
      ),
    );
    expect(calls, isEmpty, reason: 'בבנייה הראשונה אין קריאה');

    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    await tester.pump();
    expect(calls, [Brightness.dark]);

    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    await tester.pump();
    expect(calls, [Brightness.dark, Brightness.light]);
  });

  testWidgets('אחרי הסרת הווידג׳ט אין עוד קריאות', (tester) async {
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    final calls = <Brightness>[];

    await tester.pumpWidget(
      PlatformBrightnessListener(
        onChanged: calls.add,
        child: const SizedBox(),
      ),
    );
    await tester.pumpWidget(const SizedBox());

    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    await tester.pump();
    expect(calls, isEmpty);
  });
}
