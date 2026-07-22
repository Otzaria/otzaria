import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria/settings/tabs/about_settings_tab.dart';

void main() {
  group('AboutSettingsTab', () {
    testWidgets('מציגה את ההנצחה החדשה בתורמים', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AboutSettingsTab(),
          ),
        ),
      );

      expect(
        find.text(
          "לע\"נ ר' משה ב\"ר פרץ ובנו ר' יצחק ב\"ר משה, והאשה הכשרה מרת רחל יהודית בת אליעזר",
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          "ולהצלחת דוד ב\"ר יחזקאל ומשפחתו בתורה וביראת שמים\nתרומה גדולה ורבה לפיתוח התוכנה",
        ),
        findsOneWidget,
      );
      expect(find.byIcon(FluentIcons.fire_24_filled), findsNWidgets(2));
      expect(find.byIcon(FluentIcons.heart_24_filled), findsNothing);
      expect(find.byIcon(FluentIcons.heart_24_regular), findsOneWidget);
    });
  });
}
