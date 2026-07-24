import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/widgets/misc/expanding_chevron.dart';
import 'package:otzaria/settings/widgets/expandable_settings_tile.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget buildHarness({
    required double width,
    required bool isExpanded,
    required VoidCallback onTap,
    bool hasContent = true,
    String title = 'הוסף תיקייה לאוצריא',
    String? subtitle = 'לחץ להוספת תיקיות אישיות',
    Widget? trailing,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: width,
            child: ExpandableSection(
              icon: FluentIcons.folder_add_24_regular,
              title: title,
              subtitle: subtitle,
              trailing: trailing,
              isExpanded: isExpanded,
              onTap: onTap,
              hasContent: hasContent,
              children: const [
                ListTile(title: Text('פריט בתוך הכרטיס')),
              ],
            ),
          ),
        ),
      ),
    );
  }

  group('ExpandableSection — לחיצה', () {
    testWidgets('לחיצה על הכותרת קוראת ל-onTap', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        buildHarness(width: 800, isExpanded: false, onTap: () => tapped = true),
      );
      await tester.pump();

      await tester.tap(find.text('הוסף תיקייה לאוצריא'));
      expect(tapped, isTrue);
    });

    testWidgets('לחיצה על הצ\'בֺרן עצמו קוראת ל-onTap', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        buildHarness(width: 800, isExpanded: false, onTap: () => tapped = true),
      );
      await tester.pump();

      await tester.tap(find.byType(ExpandingChevron));
      expect(tapped, isTrue);
    });

    testWidgets('כש-hasContent=false אין צ\'בֺרן והלחיצה לא קוראת ל-onTap', (
      tester,
    ) async {
      var tapped = false;
      await tester.pumpWidget(
        buildHarness(
          width: 800,
          isExpanded: false,
          onTap: () => tapped = true,
          hasContent: false,
        ),
      );
      await tester.pump();

      expect(find.byType(ExpandingChevron), findsNothing);

      await tester.tap(find.text('הוסף תיקייה לאוצריא'));
      expect(tapped, isFalse);
    });

    testWidgets('isExpanded=true מציג את children, isExpanded=false מסתיר', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildHarness(width: 800, isExpanded: false, onTap: () {}),
      );
      await tester.pump();
      expect(find.text('פריט בתוך הכרטיס'), findsNothing);

      await tester.pumpWidget(
        buildHarness(width: 800, isExpanded: true, onTap: () {}),
      );
      await tester.pumpAndSettle();
      expect(find.text('פריט בתוך הכרטיס'), findsOneWidget);
    });
  });

  group('ExpandableSection — הצ\'בֺרן תמיד לצד הטקסט', () {
    // trailing רחב שגורם ל-SettingsActionTile הפנימי ליפול ל-layout אנכי
    // (trailing מתחת לטקסט) — הצ'בֺרן לא אמור ליפול איתו, ותמיד יישאר
    // לצד הכותרת.
    Widget wideTrailing() => ElevatedButton(
      onPressed: () {},
      child: const Text('כפתור פעולה ארוך שתופס הרבה מקום'),
    );

    testWidgets('מסך רחב: הצ\'בֺרן וה-trailing על אותה שורה', (tester) async {
      await tester.pumpWidget(
        buildHarness(
          width: 800,
          isExpanded: false,
          onTap: () {},
          trailing: wideTrailing(),
        ),
      );
      await tester.pump();

      // במסך רחב ה-trailing נשאר ב-actions לצד הטקסט (בלי לגלוש) — הצ'בֺרן
      // אמור להיות על אותה שורה בדיוק כמוהו.
      final buttonRect = tester.getRect(find.byType(ElevatedButton));
      final chevronY = tester.getCenter(find.byType(ExpandingChevron)).dy;
      expect(chevronY, greaterThanOrEqualTo(buttonRect.top));
      expect(chevronY, lessThanOrEqualTo(buttonRect.bottom));
    });

    testWidgets('מסך צר: ה-trailing נופל מתחת לטקסט אך הצ\'בֺרן לא גולש איתו', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(400, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        buildHarness(
          width: 300,
          isExpanded: false,
          onTap: () {},
          trailing: wideTrailing(),
        ),
      );
      await tester.pump();

      // ה-trailing (הכפתור) נופל מתחת ל-subtitle בפריסה הצרה.
      final subtitleBottom = tester
          .getBottomLeft(find.text('לחץ להוספת תיקיות אישיות'))
          .dy;
      final buttonTop = tester.getTopLeft(find.byType(ElevatedButton)).dy;
      expect(buttonTop, greaterThanOrEqualTo(subtitleBottom));

      // הצ'בֺרן, לעומת זאת, לא גולש יחד עם ה-trailing — הוא נשאר מעל
      // הכפתור שגלש, ולא על אותה שורה כמוהו.
      final chevronY = tester.getCenter(find.byType(ExpandingChevron)).dy;
      expect(chevronY, lessThan(buttonTop));
    });
  });
}
