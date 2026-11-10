import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria_icons/otzaria_icons.dart';
import 'package:otzaria/widgets/controls/action_buttons.dart';
import 'package:otzaria/widgets/feedback/otzaria_empty_state.dart';

void main() {
  group('OtzariaEmptyState', () {
    testWidgets('מציג סמל, כותרת, תיאור וכפתור פעולה יחיד', (tester) async {
      var actionTapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OtzariaEmptyState(
              icon: FluentIcons.search_24_regular,
              title: 'לא נמצאו תוצאות',
              message: 'נסה לחפש מילים אחרות',
              action: ActionButton.recommended(
                text: 'נקה חיפוש',
                onPressed: () => actionTapped = true,
              ),
            ),
          ),
        ),
      );

      expect(find.byIcon(FluentIcons.search_24_regular), findsOneWidget);
      expect(find.text('לא נמצאו תוצאות'), findsOneWidget);
      expect(find.text('נסה לחפש מילים אחרות'), findsOneWidget);
      expect(find.text('נקה חיפוש'), findsOneWidget);

      await tester.tap(find.text('נקה חיפוש'));
      expect(actionTapped, isTrue);
    });

    testWidgets('מציג רשימת פעולות מרובות (actions)', (tester) async {
      var firstTapped = false;
      var secondTapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OtzariaEmptyState(
              title: 'פעולות מרובות',
              actions: [
                ActionButton.recommended(
                  text: 'פעולה ראשית',
                  onPressed: () => firstTapped = true,
                ),
                ActionButton.neutral(
                  text: 'פעולה משנית',
                  onPressed: () => secondTapped = true,
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.text('פעולה ראשית'), findsOneWidget);
      expect(find.text('פעולה משנית'), findsOneWidget);

      await tester.tap(find.text('פעולה ראשית'));
      expect(firstTapped, isTrue);

      await tester.tap(find.text('פעולה משנית'));
      expect(secondTapped, isTrue);
    });

    testWidgets('מצב קומפקטי (isCompact: true) מציג סמלים וטקסטים מותאמים', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: OtzariaEmptyState(
              isCompact: true,
              icon: OtzariaIcons.links_24_regular,
              title: 'אין קישורים',
              message: 'הסבר קצר',
            ),
          ),
        ),
      );

      expect(find.byIcon(OtzariaIcons.links_24_regular), findsOneWidget);
      expect(find.text('אין קישורים'), findsOneWidget);
      expect(find.text('הסבר קצר'), findsOneWidget);
    });

    testWidgets('מציג customIcon אם סופק במקום icon', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: OtzariaEmptyState(
              customIcon: FlutterLogo(),
              title: 'מותאם אישית',
            ),
          ),
        ),
      );

      expect(find.byType(FlutterLogo), findsOneWidget);
      expect(find.text('מותאם אישית'), findsOneWidget);
    });

    testWidgets(
      'חלון נמוך/קצר לא גורם לגלישה (overflow) בזכות הגלילה המרכזית',
      (
        tester,
      ) async {
        tester.view.physicalSize = const Size(800, 200);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: OtzariaEmptyState(
                icon: FluentIcons.info_24_regular,
                title: 'כותרת ארוכה לבדיקת חוסר גלישה במסכים קטנים מאוד',
                message: 'תיאור מפורט שעלול היה לגרום לגלישת פיקסלים',
                actions: [
                  ActionButton.recommended(text: 'כפתור 1', onPressed: () {}),
                  ActionButton.neutral(text: 'כפתור 2', onPressed: () {}),
                ],
              ),
            ),
          ),
        );

        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'scrollable: false אינו עוטף ב-Scrollable ועובד ב-SliverFillRemaining',
      (
        tester,
      ) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: CustomScrollView(
                slivers: [
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: OtzariaEmptyState(
                      scrollable: false,
                      icon: FluentIcons.info_24_regular,
                      title: 'בדיקת סליבר',
                      message: 'ללא עטיפת גלילה פנימית',
                    ),
                  ),
                ],
              ),
            ),
          ),
        );

        expect(tester.takeException(), isNull);
        expect(find.text('בדיקת סליבר'), findsOneWidget);
        // מוודא שאין SingleChildScrollView פנימי שנבנה בתוך ה-empty state
        expect(
          find.descendant(
            of: find.byType(OtzariaEmptyState),
            matching: find.byType(SingleChildScrollView),
          ),
          findsNothing,
        );
      },
    );
  });
}
