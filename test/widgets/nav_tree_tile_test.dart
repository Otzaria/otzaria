import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria_icons/otzaria_icons.dart';
import 'package:otzaria/widgets/lists/nav_tree_tile.dart';
import 'package:otzaria/widgets/widgets_exports.dart';

void main() {
  Future<void> pump(WidgetTester tester, Widget child) {
    return tester.pumpWidget(
      MaterialApp(home: Scaffold(body: child)),
    );
  }

  group('NavTreeTile', () {
    testWidgets('קטגוריה מציגה כותרת, מונה וחץ; החץ מפעיל onToggleExpand', (
      tester,
    ) async {
      var toggled = false;
      await pump(
        tester,
        NavTreeTile.category(
          title: 'תנ"ך',
          level: 0,
          count: 7,
          hasChildren: true,
          onToggleExpand: () => toggled = true,
        ),
      );

      expect(find.text('תנ"ך'), findsOneWidget);
      expect(find.text('(7)'), findsOneWidget);

      await tester.tap(find.byType(IconButton));
      await tester.pump();
      expect(toggled, isTrue);
    });

    testWidgets('onClearFilter מציג "נקה סינון" והלחיצה מפעילה אותו', (
      tester,
    ) async {
      var cleared = false;
      await pump(
        tester,
        NavTreeTile.category(
          title: 'תנ"ך',
          level: 0,
          count: 3,
          onClearFilter: () => cleared = true,
        ),
      );

      expect(find.text('נקה סינון'), findsOneWidget);
      // המונה מוחלף בכפתור הניקוי.
      expect(find.text('(3)'), findsNothing);

      await tester.tap(find.text('נקה סינון'));
      await tester.pump();
      expect(cleared, isTrue);
    });

    testWidgets('לחיצה על השורה מפעילה onTap', (tester) async {
      var tapped = false;
      await pump(
        tester,
        NavTreeTile.category(
          title: 'תנ"ך',
          level: 0,
          onTap: () => tapped = true,
        ),
      );

      await tester.tap(find.text('תנ"ך'));
      await tester.pump();
      expect(tapped, isTrue);
    });

    testWidgets(
      'NavTreeTile.heading: טקסט בלבד ללא אייקון, והזחה זהה עם ובלי ילדים',
      (tester) async {
        var toggled = false;
        await pump(
          tester,
          Column(
            children: [
              NavTreeTile.heading(
                title: 'כותרת עם ילדים',
                level: 0,
                hasChildren: true,
                onToggleExpand: () => toggled = true,
              ),
              NavTreeTile.heading(
                title: 'כותרת בלי ילדים',
                level: 0,
                hasChildren: false,
              ),
              NavTreeTile.heading(
                title: 'כותרת משנה',
                level: 1,
                hasChildren: false,
              ),
            ],
          ),
        );

        // שורות תוכן עניינים הן טקסט בלבד — אין קופסת אייקון (issue #1226).
        expect(find.byIcon(FluentIcons.folder_24_regular), findsNothing);
        expect(find.byIcon(FluentIcons.folder_open_24_regular), findsNothing);
        expect(
          find.byIcon(OtzariaIcons.text_bullet_list_24_regular),
          findsNothing,
        );

        // וידוא שהזחת start שווה בדיוק בין שתי כותרות רמה 0
        final paddingContainers = tester
            .widgetList<Container>(find.byType(Container))
            .where((c) => c.padding is EdgeInsetsDirectional)
            .toList();
        final padding0WithChildren =
            paddingContainers[0].padding as EdgeInsetsDirectional;
        final padding0WithoutChildren =
            paddingContainers[1].padding as EdgeInsetsDirectional;
        final padding1 = paddingContainers[2].padding as EdgeInsetsDirectional;

        expect(padding0WithChildren.start, equals(12.0));
        expect(padding0WithoutChildren.start, equals(12.0));
        expect(padding1.start, equals(24.0)); // 12 + 1 * 12

        // בדיקת לחיצה על צ'ברון הרחבה
        await tester.tap(find.byType(IconButton));
        await tester.pump();
        expect(toggled, isTrue);
      },
    );
  });

  group('NavTreeHeader', () {
    for (final width in [220.0, 235.0, 600.0]) {
      for (final direction in TextDirection.values) {
        for (final scale in [1.0, 1.3]) {
          testWidgets(
            'פעולות נשארות גלויות ולחיצות ברוחב $width ${direction.name} ×$scale',
            (tester) async {
              await (FontLoader('Roboto')..addFont(
                    rootBundle.load('fonts/Rubik-VariableFont_wght.ttf'),
                  ))
                  .load();
              final activated = <int>[];
              await pump(
                tester,
                Directionality(
                  textDirection: direction,
                  child: MediaQuery(
                    data: MediaQueryData(
                      textScaler: TextScaler.linear(scale),
                    ),
                    child: SizedBox(
                      width: width,
                      child: NavTreeHeader(
                        title: 'ספריית אוצריא',
                        onClearFilter: () => activated.add(0),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (var i = 1; i <= 3; i++)
                              AppIconButton(
                                size: AppIconButtonSize.small,
                                icon: const Icon(Icons.search),
                                tooltip: 'פעולה $i',
                                onPressed: () => activated.add(i),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
              expect(tester.takeException(), isNull);
              final header = tester.getRect(find.byType(NavTreeHeader));
              final clear = find.text('נקה סינון');
              await tester.tap(clear);
              for (var i = 1; i <= 3; i++) {
                final action = find.byType(AppIconButton).at(i - 1);
                final bounds = tester.getRect(action);
                expect(bounds.left, greaterThanOrEqualTo(header.left));
                expect(bounds.right, lessThanOrEqualTo(header.right));
                expect(bounds.width, greaterThanOrEqualTo(48));
                expect(bounds.height, greaterThanOrEqualTo(48));
                await tester.tapAt(bounds.topLeft + const Offset(1, 1));
              }
              expect(activated, [0, 1, 2, 3]);
              if (width == 600) {
                expect(
                  tester.getCenter(find.text('ספריית אוצריא')).dy,
                  closeTo(tester.getCenter(find.byTooltip('פעולה 1')).dy, 0.01),
                );
              }
              expect(tester.takeException(), isNull);
            },
          );
        }
      }
    }

    testWidgets('ללא סינון: מציג כותרת ומונה, בלי "נקה סינון"', (tester) async {
      await pump(
        tester,
        const NavTreeHeader(title: 'ספריית אוצריא', count: 12),
      );

      expect(find.text('ספריית אוצריא'), findsOneWidget);
      expect(find.text('(12)'), findsOneWidget);
      expect(find.text('נקה סינון'), findsNothing);
    });

    testWidgets('עם onClearFilter: מציג "נקה סינון" והלחיצה מפעילה אותו', (
      tester,
    ) async {
      var cleared = false;
      await pump(
        tester,
        NavTreeHeader(
          title: 'חז"ל',
          onClearFilter: () => cleared = true,
        ),
      );

      expect(find.text('חז"ל'), findsOneWidget);
      expect(find.text('נקה סינון'), findsOneWidget);

      await tester.tap(find.text('נקה סינון'));
      await tester.pump();
      expect(cleared, isTrue);
    });
  });

  group('NavTreeGroupCard', () {
    testWidgets('מפריד מוצג רק כשאין isGroupStart', (tester) async {
      await pump(
        tester,
        const Column(
          children: [
            NavTreeGroupCard(
              isGroupStart: true,
              isGroupEnd: false,
              child: Text('ראשון'),
            ),
            NavTreeGroupCard(
              isGroupStart: false,
              isGroupEnd: true,
              child: Text('שני'),
            ),
          ],
        ),
      );

      expect(find.text('ראשון'), findsOneWidget);
      expect(find.text('שני'), findsOneWidget);
      // שורה שאינה תחילת קבוצה נושאת מפריד לפניה; תחילת קבוצה לא.
      expect(find.byType(Divider), findsOneWidget);
    });
  });

  group('NavTreeFocusGroup', () {
    testWidgets('Tab מהשדה שמעל הרשימה מתמקד בשורה המסומנת ולא בראשונה', (
      tester,
    ) async {
      final fieldFocus = FocusNode(debugLabel: 'field');
      addTearDown(fieldFocus.dispose);

      await pump(
        tester,
        Column(
          children: [
            TextField(focusNode: fieldFocus),
            Expanded(
              child: NavTreeFocusGroup(
                child: ListView(
                  children: [
                    for (var i = 0; i < 4; i++)
                      NavTreeGroupCard(
                        isGroupStart: i == 0,
                        isGroupEnd: i == 3,
                        child: NavTreeTile.category(
                          title: 'שורה $i',
                          level: 0,
                          isSelected: i == 2,
                          onTap: () {},
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );

      fieldFocus.requestFocus();
      await tester.pump();

      expect(
        tester.binding.focusManager.primaryFocus,
        fieldFocus,
        reason: 'נקודת הפתיחה: הפוקוס בשדה שמעל הרשימה',
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();

      // הפוקוס נכנס לרשימה — ועל השורה המסומנת (2), לא על הראשונה.
      final focusedTile = find.ancestor(
        of: find.text('שורה 2'),
        matching: find.byType(InkWell),
      );
      expect(focusedTile, findsWidgets);
      expect(
        tester.binding.focusManager.primaryFocus!.context!
            .findAncestorWidgetOfExactType<FocusTraversalOrder>(),
        isNotNull,
        reason: 'השורה שקיבלה פוקוס היא זו שסומנה בעדיפות מעבר',
      );
      expect(
        find.descendant(
          of: find.byWidget(
            tester.binding.focusManager.primaryFocus!.context!
                .findAncestorWidgetOfExactType<FocusTraversalOrder>()!,
          ),
          matching: find.text('שורה 2'),
        ),
        findsOneWidget,
      );
    });
  });

  group('OverflowTooltipText וטולטיפ בריחוף בעץ הניווט (issue #1103)', () {
    testWidgets('כותרת קצרה ב-NavTreeTile אינה מציגה Tooltip', (tester) async {
      await pump(
        tester,
        SizedBox(
          width: 300,
          child: NavTreeTile.category(
            title: 'קצר',
            level: 0,
          ),
        ),
      );

      expect(find.text('קצר'), findsOneWidget);
      expect(find.byTooltip('קצר'), findsNothing);
    });

    testWidgets(
      'כותרת ארוכה שנקטעת ב-NavTreeTile מציגה Tooltip עם הטקסט המלא',
      (
        tester,
      ) async {
        const longTitle =
            'חזון איש יורה דעה הלכות שחיטה וטרפות סימן קכ"ג סעיף קטן ד';
        await pump(
          tester,
          SizedBox(
            width: 120,
            child: NavTreeTile.category(
              title: longTitle,
              level: 2,
            ),
          ),
        );

        expect(find.text(longTitle), findsOneWidget);
        expect(find.byTooltip(longTitle), findsOneWidget);
      },
    );

    testWidgets(
      'כותרת ארוכה שנקטעת ב-NavTreeHeader מציגה Tooltip עם הטקסט המלא',
      (
        tester,
      ) async {
        const longTitle =
            'שולחן ערוך חלק יורה דעה הלכות ריבית והיתר עסקה עם פירוש מקיף';
        await pump(
          tester,
          SizedBox(
            width: 100,
            child: const NavTreeHeader(title: longTitle),
          ),
        );

        expect(find.text(longTitle), findsOneWidget);
        expect(find.byTooltip(longTitle), findsOneWidget);
      },
    );

    testWidgets('OverflowTooltipText ישיר: מציג Tooltip אך ורק כשיש חריגה', (
      tester,
    ) async {
      const text = 'טקסט לבדיקת חריגה';

      // רוחב רחב מאוד - אין חריגה
      await pump(
        tester,
        const SizedBox(
          width: 400,
          child: OverflowTooltipText(text: text),
        ),
      );
      expect(find.byTooltip(text), findsNothing);

      // רוחב צר מאוד - יש חריגה
      await pump(
        tester,
        const SizedBox(
          width: 30,
          child: OverflowTooltipText(text: text),
        ),
      );
      expect(find.byTooltip(text), findsOneWidget);
    });
  });
}
