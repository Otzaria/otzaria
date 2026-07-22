import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/widgets/lists/nav_tree_tile.dart';

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

    testWidgets('filterMode מציג אייקון סינון והלחיצה עליו מפעילה onFilter', (
      tester,
    ) async {
      var filtered = false;
      await pump(
        tester,
        NavTreeTile.category(
          title: 'תנ"ך',
          level: 0,
          filterMode: true,
          onFilter: () => filtered = true,
        ),
      );

      final filterIcon = find.byTooltip('סנן לפריט זה');
      expect(filterIcon, findsOneWidget);

      await tester.tap(filterIcon);
      await tester.pump();
      expect(filtered, isTrue);
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
  });

  group('NavTreeHeader', () {
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
}
