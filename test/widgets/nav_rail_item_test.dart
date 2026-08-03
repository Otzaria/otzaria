import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria_icons/otzaria_icons.dart';
import 'package:otzaria/widgets/misc/rtl_icon.dart';
import 'package:otzaria/widgets/navigation/nav_rail_item.dart';

void main() {
  testWidgets('NavRailItem מצמיד tourTargetKey לכפתור עצמו', (tester) async {
    final buttonKey = GlobalKey();
    final itemKey = GlobalKey();

    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: NavRailItem(
            icon: FluentIcons.search_24_regular,
            label: 'איתור',
            isSelected: true,
            onTap: () {},
            tourTargetKey: buttonKey,
            tourItemKey: itemKey,
          ),
        ),
      ),
    );

    expect(buttonKey.currentWidget, isA<IconButton>());
    expect(itemKey.currentWidget, isA<SizedBox>());
  });

  group('NavRailItem — רוחב לפי מצב קומפקטי', () {
    Future<double> railWidth(
      WidgetTester tester, {
      required bool compact,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: NavRailItem(
              icon: FluentIcons.library_24_regular,
              label: 'ספרייה',
              isSelected: false,
              onTap: () {},
              compact: compact,
            ),
          ),
        ),
      );
      return tester.widget<SizedBox>(find.byType(SizedBox).first).width!;
    }

    testWidgets('רגיל משתמש ברוחב המלא', (tester) async {
      expect(await railWidth(tester, compact: false), NavRailItem.width);
    });

    testWidgets('קומפקטי מצר את הפריט', (tester) async {
      expect(await railWidth(tester, compact: true), NavRailItem.compactWidth);
      expect(NavRailItem.compactWidth, lessThan(NavRailItem.width));
    });

    Future<double> indicatorWidth(
      WidgetTester tester, {
      required bool compact,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: NavRailItem(
              icon: FluentIcons.library_24_regular,
              label: 'ספרייה',
              isSelected: true,
              onTap: () {},
              compact: compact,
            ),
          ),
        ),
      );
      final button = tester.widget<IconButton>(find.byType(IconButton));
      return button.style!.minimumSize!.resolve({})!.width;
    }

    testWidgets('אינדיקטור הבחירה מצטמצם במצב קומפקטי', (tester) async {
      final normal = await indicatorWidth(tester, compact: false);
      final compact = await indicatorWidth(tester, compact: true);
      expect(compact, lessThan(normal));
    });
  });

  group('NavRailItem imageAsset support', () {
    testWidgets(
      'renders ImageIcon when imageAsset is provided (instead of IconData)',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Directionality(
              textDirection: TextDirection.rtl,
              child: NavRailItem(
                imageAsset: 'assets/icon/שמור וזכור שחור ריק.png',
                label: 'שמור וזכור',
                isSelected: false,
                onTap: () {},
              ),
            ),
          ),
        );

        // ה-tree צריך להכיל ImageIcon, לא Icon רגיל עם IconData fallback.
        expect(find.byType(ImageIcon), findsOneWidget);
        expect(
          find.byWidgetPredicate(
            (w) => w is Icon && w.icon == FluentIcons.wrench_24_regular,
          ),
          findsNothing,
          reason:
              'P3 regression: image-based built-in tools must NOT fall back '
              'to a generic wrench icon in the nav rail',
        );
      },
    );

    testWidgets(
      'ImageIcon color reflects selection state (selected vs unselected)',
      (tester) async {
        Widget itemWith(bool selected) => MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: NavRailItem(
              imageAsset: 'assets/icon/שמור וזכור שחור ריק.png',
              label: 'שמור וזכור',
              isSelected: selected,
              onTap: () {},
            ),
          ),
        );

        await tester.pumpWidget(itemWith(false));
        final unselected = tester.widget<ImageIcon>(find.byType(ImageIcon));
        final unselectedColor = unselected.color;

        await tester.pumpWidget(itemWith(true));
        final selected = tester.widget<ImageIcon>(find.byType(ImageIcon));
        final selectedColor = selected.color;

        expect(unselectedColor, isNotNull);
        expect(selectedColor, isNotNull);
        expect(
          selectedColor,
          isNot(equals(unselectedColor)),
          reason:
              'selected and unselected states must use different colors '
              'so the user sees which item is active',
        );
      },
    );

    testWidgets(
      'when both icon and imageAsset are given, imageAsset wins',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Directionality(
              textDirection: TextDirection.rtl,
              child: NavRailItem(
                icon: FluentIcons.wrench_24_regular,
                imageAsset: 'assets/icon/שמור וזכור שחור ריק.png',
                label: 'שמור וזכור',
                isSelected: false,
                onTap: () {},
              ),
            ),
          ),
        );

        expect(find.byType(ImageIcon), findsOneWidget);
        // ה-Icon לא צריך להתרנדר — ImageIcon מחליף אותו לחלוטין
        expect(
          find.byWidgetPredicate(
            (w) => w is Icon && w.icon == FluentIcons.wrench_24_regular,
          ),
          findsNothing,
        );
      },
    );

    test(
      'asserts when both icon and imageAsset are null',
      () {
        expect(
          () => NavRailItem(
            label: 'broken',
            isSelected: false,
            onTap: () {},
          ),
          throwsAssertionError,
          reason:
              'a NavRailItem with no visual must fail loudly at '
              'construction, not silently render an empty space',
        );
      },
    );
  });

  group('NavRailItem — RTL icon rendering (regression: no mirrorIcon)', () {
    testWidgets('אייקון Otzaria מוצג ישירות ללא RtlIcon', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: NavRailItem(
              icon: OtzariaIcons.book_open_large_24_regular,
              label: 'עיון',
              isSelected: false,
              onTap: () {},
            ),
          ),
        ),
      );

      expect(find.byType(RtlIcon), findsNothing);
      expect(
        find.byIcon(OtzariaIcons.book_open_large_24_regular),
        findsOneWidget,
      );
    });

    testWidgets('משתמש ב-RtlIcon לניהול כיווניות', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: NavRailItem(
              icon: FluentIcons.arrow_left_24_regular,
              label: 'חזרה',
              isSelected: false,
              onTap: () {},
            ),
          ),
        ),
      );

      expect(
        find.byType(RtlIcon),
        findsOneWidget,
        reason: 'NavRailItem חייב להשתמש ב-RtlIcon ולא ב-Icon ישירות',
      );
    });

    testWidgets('arrow_left מוצג כ-arrow_right בהקשר RTL', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: NavRailItem(
              icon: FluentIcons.arrow_left_24_regular,
              label: 'חזרה',
              isSelected: false,
              onTap: () {},
            ),
          ),
        ),
      );

      final icon = tester.widget<Icon>(
        find.descendant(
          of: find.byType(RtlIcon),
          matching: find.byType(Icon),
        ),
      );
      expect(
        icon.icon,
        FluentIcons.arrow_right_24_regular,
        reason: 'חץ שמאל חייב להפוך לחץ ימין בממשק RTL',
      );
    });

    testWidgets('אייקון סימטרי (book) מוצג ללא שינוי כיוון ב-LTR', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: TextDirection.ltr,
            child: NavRailItem(
              icon: FluentIcons.book_24_regular,
              label: 'ספרייה',
              isSelected: false,
              onTap: () {},
            ),
          ),
        ),
      );

      // RtlIcon לא אמור לעטוף ב-Transform בהקשר LTR
      expect(
        find.descendant(
          of: find.byType(RtlIcon),
          matching: find.byType(Transform),
        ),
        findsNothing,
        reason: 'LTR — RtlIcon לא אמור להפוך אייקון',
      );
    });
  });
}
