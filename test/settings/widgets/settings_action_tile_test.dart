import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/settings/widgets/settings_action_tile.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // נתיב ארוך שמדמה את הבעיה — בלי הפריסה הרספונסיבית הוא היה קורס
  // לתו-לשורה במסך צר.
  const longPath = r'C:\Users\user\AppData\Roaming\otzaria\library';

  Widget buildHarness({
    required double width,
    String? buttonText,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: width,
            child: SettingsActionTile.text(
              icon: FluentIcons.folder_24_regular,
              title: 'מיקום ספריית אוצריא',
              subtitle: longPath,
              actions: [
                ElevatedButton(
                  onPressed: () {},
                  child: Text(buttonText ?? 'שנה מיקום'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  group('SettingsActionTile — פריסה רספונסיבית', () {
    testWidgets('מסך רחב: הכפתורים ב-trailing של ListTile', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1024, 768));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(buildHarness(width: 800));
      await tester.pump();

      // ListTile קיים — זו הפריסה הרחבה.
      expect(find.byType(ListTile), findsOneWidget);

      // הכפתור נמצא בתוך ה-ListTile (כצאצא של trailing).
      expect(
        find.descendant(
          of: find.byType(ListTile),
          matching: find.widgetWithText(ElevatedButton, 'שנה מיקום'),
        ),
        findsOneWidget,
      );

      // הכפתור לימין הכותרת (אותו ציר אנכי, x שונה).
      final titleY = tester.getTopLeft(find.text('מיקום ספריית אוצריא')).dy;
      final buttonY = tester.getTopLeft(find.byType(ElevatedButton)).dy;
      expect((titleY - buttonY).abs(), lessThan(40),
          reason: 'במסך רחב הכפתור באותה שורה כללית כמו הכותרת');
    });

    testWidgets('מסך צר: הכפתורים תחת ה-subtitle ולא בתוך ListTile.trailing',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(buildHarness(width: 360));
      await tester.pump();

      // בפריסה הצרה משתמשים ב-Column ולא ב-ListTile.
      expect(find.byType(ListTile), findsNothing);

      // הכפתור מתחת לטקסט הנתיב (subtitle).
      final subtitleBottom = tester.getBottomLeft(find.text(longPath)).dy;
      final buttonTop = tester.getTopLeft(find.byType(ElevatedButton)).dy;
      expect(buttonTop, greaterThanOrEqualTo(subtitleBottom),
          reason: 'הכפתור צריך להופיע מתחת לטקסט הנתיב במסך צר');
    });

    testWidgets('מסך צר: טקסט הנתיב תופס רוחב סביר ולא קורס לתו-לשורה',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(buildHarness(width: 360));
      await tester.pump();

      final pathWidth = tester.getSize(find.text(longPath)).width;
      expect(pathWidth, greaterThan(200),
          reason:
              'במסך צר ל-subtitle (הנתיב) צריך להיות רוחב סביר ולא להתקפל לתו-לשורה');
    });

    testWidgets('מספר כפתורים מוצגים יחדיו', (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 360,
              child: SettingsActionTile.text(
                icon: FluentIcons.folder_24_regular,
                title: 'כותרת',
                subtitle: 'תת-כותרת',
                actions: [
                  ElevatedButton(
                      onPressed: () {}, child: const Text('כפתור א')),
                  ElevatedButton(
                      onPressed: () {}, child: const Text('כפתור ב')),
                ],
              ),
            ),
          ),
        ),
      ));
      await tester.pump();

      expect(find.text('כפתור א'), findsOneWidget);
      expect(find.text('כפתור ב'), findsOneWidget);
    });
  });
}
