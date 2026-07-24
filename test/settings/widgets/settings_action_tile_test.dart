import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/settings/widgets/settings_card.dart';

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
      expect(
        (titleY - buttonY).abs(),
        lessThan(40),
        reason: 'במסך רחב הכפתור באותה שורה כללית כמו הכותרת',
      );
    });

    testWidgets('מסך צר: הכפתורים תחת ה-subtitle ולא בתוך ListTile.trailing', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(400, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(buildHarness(width: 360));
      await tester.pump();

      // בפריסה הצרה משתמשים ב-Column ולא ב-ListTile.
      expect(find.byType(ListTile), findsNothing);

      // הכפתור מתחת לטקסט הנתיב (subtitle).
      final subtitleBottom = tester.getBottomLeft(find.text(longPath)).dy;
      final buttonTop = tester.getTopLeft(find.byType(ElevatedButton)).dy;
      expect(
        buttonTop,
        greaterThanOrEqualTo(subtitleBottom),
        reason: 'הכפתור צריך להופיע מתחת לטקסט הנתיב במסך צר',
      );
    });

    testWidgets('מסך צר: טקסט הנתיב תופס רוחב סביר ולא קורס לתו-לשורה', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(400, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(buildHarness(width: 360));
      await tester.pump();

      final pathWidth = tester.getSize(find.text(longPath)).width;
      expect(
        pathWidth,
        greaterThan(200),
        reason:
            'במסך צר ל-subtitle (הנתיב) צריך להיות רוחב סביר ולא להתקפל לתו-לשורה',
      );
    });

    testWidgets('title מוגבל לשורה אחת עם ellipsis', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 800,
              child: SettingsActionTile.text(
                title: 'כותרת ארוכה מאוד שאמורה לגלוש לשורה שנייה אבל לא תוכל',
                actions: [
                  ElevatedButton(onPressed: () {}, child: const Text('כפתור')),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final titleWidget = tester.widget<Text>(
        find.text('כותרת ארוכה מאוד שאמורה לגלוש לשורה שנייה אבל לא תוכל'),
      );
      expect(titleWidget.maxLines, 1);
      expect(titleWidget.overflow, TextOverflow.ellipsis);
    });

    testWidgets(
      'כשהכותרת לא מסתדרת עם ה-action — action עובר מתחת ל-subtitle',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(350, 800));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 300,
                child: SettingsActionTile.text(
                  title: 'כותרת הגדרה',
                  subtitle: 'תיאור ההגדרה',
                  actions: [
                    ElevatedButton(
                      onPressed: () {},
                      child: const Text('כפתור'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        // כשהaction לא מסתדר עם הtitle, עוברים ל-Column — אין ListTile
        expect(find.byType(ListTile), findsNothing);

        // הכפתור מתחת לtitle ולsubtitle
        final subtitleBottom = tester
            .getBottomLeft(find.text('תיאור ההגדרה'))
            .dy;
        final buttonTop = tester.getTopLeft(find.byType(ElevatedButton)).dy;
        expect(
          buttonTop,
          greaterThanOrEqualTo(subtitleBottom),
          reason: 'ה-action צריך להיות מתחת ל-subtitle כשאין מקום בשורה',
        );
      },
    );

    testWidgets(
      'מסך צר: onTap עדיין נקרא כשה-layout נופל ל-Column (בלי ListTile)',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(350, 800));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        var tapped = false;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 300,
                child: SettingsActionTile.text(
                  title: 'כותרת הגדרה',
                  subtitle: 'תיאור ההגדרה',
                  onTap: () => tapped = true,
                  actions: [
                    ElevatedButton(
                      onPressed: () {},
                      child: const Text('כפתור'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        // ודא שאכן נפלנו ל-layout האנכי (בלי ListTile) — אחרת הבדיקה לא רלוונטית.
        expect(find.byType(ListTile), findsNothing);

        await tester.tap(find.text('כותרת הגדרה'));
        expect(
          tapped,
          isTrue,
          reason:
              'לפני התיקון, onTap לא היה מחובר כלל ב-layout האנכי (_buildColumnLayout)',
        );
      },
    );

    testWidgets('מסך צר: onTap לא נקרא כש-enabled=false ב-layout אנכי', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(350, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      var tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 300,
              child: SettingsActionTile.text(
                title: 'כותרת הגדרה',
                subtitle: 'תיאור ההגדרה',
                enabled: false,
                onTap: () => tapped = true,
                actions: [
                  ElevatedButton(onPressed: () {}, child: const Text('כפתור')),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(ListTile), findsNothing);

      await tester.tap(find.text('כותרת הגדרה'));
      expect(tapped, isFalse);
    });

    testWidgets('מספר כפתורים מוצגים יחדיו', (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
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
                      onPressed: () {},
                      child: const Text('כפתור א'),
                    ),
                    ElevatedButton(
                      onPressed: () {},
                      child: const Text('כפתור ב'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('כפתור א'), findsOneWidget);
      expect(find.text('כפתור ב'), findsOneWidget);
    });
  });

  group('SettingsActionTile.path — עיצוב נתיב', () {
    Widget buildPath({String? path}) => MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 800,
          child: SettingsActionTile.path(
            icon: FluentIcons.folder_24_regular,
            title: 'מיקום',
            path: path,
            placeholder: 'בחר מיקום',
            actions: [
              ElevatedButton(onPressed: () {}, child: const Text('שנה')),
            ],
          ),
        ),
      ),
    );

    testWidgets('כשאין נתיב מוצג ה-placeholder', (tester) async {
      await tester.pumpWidget(buildPath());
      expect(find.text('בחר מיקום'), findsOneWidget);
    });

    testWidgets('כשיש נתיב הוא מוצג עם סימני LTR אחרי המפרידים', (
      tester,
    ) async {
      await tester.pumpWidget(buildPath(path: r'C:\Users\test'));
      // הטקסט המוצג מכיל את הנתיב — מציאת ה-Text widget לפי סוג
      final texts = tester.widgetList<Text>(find.byType(Text));
      final subtitleText = texts.firstWhere(
        (t) => t.data?.contains('Users') ?? false,
      );
      // בודק שיש סימן LTR (\u200E) אחרי כל \
      expect(subtitleText.data, contains('\u200E'));
    });

    testWidgets('כשיש נתיב עם / הסימן נוסף גם אחריו', (tester) async {
      await tester.pumpWidget(buildPath(path: '/home/user/docs'));
      final texts = tester.widgetList<Text>(find.byType(Text));
      final subtitleText = texts.firstWhere(
        (t) => t.data?.contains('home') ?? false,
      );
      expect(subtitleText.data, contains('\u200E'));
    });

    testWidgets('נתיב מוצג ב-LTR', (tester) async {
      await tester.pumpWidget(buildPath(path: r'C:\Users\test'));
      final texts = tester.widgetList<Text>(find.byType(Text));
      final subtitle = texts.firstWhere(
        (t) => t.data?.contains('Users') ?? false,
      );
      expect(subtitle.textDirection, TextDirection.ltr);
    });
  });
}
