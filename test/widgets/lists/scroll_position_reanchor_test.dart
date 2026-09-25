import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/widgets/lists/scroll_position_reanchor.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

/// רשימה שגובה הפריטים בה תלוי ברוחב — מדמה שפיכה מחדש של טקסט שנשבר
/// לשורות נוספות כשהעמודה מצטמצמת.
Widget _buildList({
  required double width,
  required ItemScrollController controller,
  required ItemPositionsListener listener,
  required bool enabled,
  int? preferredIndex,
}) {
  return MaterialApp(
    home: Directionality(
      textDirection: TextDirection.rtl,
      child: Center(
        child: SizedBox(
          width: width,
          height: 400,
          child: ScrollPositionReanchor(
            enabled: enabled,
            preferredIndex: preferredIndex,
            scrollController: controller,
            positionsListener: listener,
            child: ScrollablePositionedList.builder(
              itemScrollController: controller,
              itemPositionsListener: listener,
              itemCount: 200,
              itemBuilder: (context, index) =>
                  SizedBox(height: 30 * (600 / width), child: Text('$index')),
            ),
          ),
        ),
      ),
    ),
  );
}

int _topIndex(ItemPositionsListener listener) =>
    reanchorTargetPosition(listener.itemPositions.value)!.index;

Future<int> _scrollAndResize(
  WidgetTester tester, {
  required bool enabled,
  double distance = 1500,
}) async {
  final controller = ItemScrollController();
  final listener = ItemPositionsListener.create();

  await tester.pumpWidget(
    _buildList(
      width: 600,
      controller: controller,
      listener: listener,
      enabled: enabled,
    ),
  );
  await tester.pumpAndSettle();
  await tester.drag(
    find.byType(ScrollablePositionedList),
    Offset(0, -distance),
  );
  await tester.pumpAndSettle();
  // הטיימר שממתין לרגיעת הגלילה אינו מתזמן פריימים, ולכן pumpAndSettle לבדו
  // לא מקדם אליו את השעון.
  await tester.pump(ScrollPositionReanchor.idleDelay);
  await tester.pumpAndSettle();

  final before = _topIndex(listener);
  expect(before, greaterThan(0), reason: 'הגלילה לא הזיזה');

  await tester.pumpWidget(
    _buildList(
      width: 300,
      controller: controller,
      listener: listener,
      enabled: enabled,
    ),
  );
  await tester.pumpAndSettle();

  return _topIndex(listener) - before;
}

void main() {
  group('ScrollPositionReanchor', () {
    testWidgets('המיקום נשמר כשרוחב התצוגה משתנה', (tester) async {
      expect(await _scrollAndResize(tester, enabled: true), 0);
    });

    testWidgets('בלי עיגון מחדש ההיסט בפיקסלים סוחף את המיקום', (tester) async {
      expect(await _scrollAndResize(tester, enabled: false), isNot(0));
    });

    // עיגון בונה מחדש את כל טווח המטמון, ועל נקישת גלגלת בודדת זה היה פי 38
    // בניות פריט. מתחת למסך שלם מהעוגן ההיסט עצמו קטן, ולכן גם הסחיפה.
    testWidgets('גלילה קצרה ממסך אינה מעגנת, והסחיפה נשארת קטנה', (
      tester,
    ) async {
      final anchored = await _scrollAndResize(
        tester,
        enabled: true,
        distance: 120,
      );
      final bare = await _scrollAndResize(
        tester,
        enabled: false,
        distance: 120,
      );
      expect(anchored.abs(), lessThan(bare.abs()));
      expect(anchored.abs(), lessThanOrEqualTo(2));
    });

    // כל עיגון בונה מחדש את טווח המטמון כולו. בלי הסף, נקישת גלגלת בודדת
    // שאחריה עצירה שילמה פי 38 בניות פריט על תזוזה של פריט או שניים.
    testWidgets('נקישת גלגלת בודדת אינה בונה את הפריטים מחדש', (tester) async {
      final controller = ItemScrollController();
      final listener = ItemPositionsListener.create();
      var builds = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            width: 600,
            height: 400,
            child: ScrollPositionReanchor(
              scrollController: controller,
              positionsListener: listener,
              child: ScrollablePositionedList.builder(
                itemScrollController: controller,
                itemPositionsListener: listener,
                itemCount: 2000,
                itemBuilder: (context, index) {
                  builds++;
                  return SizedBox(height: 30, child: Text('$index'));
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      builds = 0;
      await tester.drag(
        find.byType(ScrollablePositionedList),
        const Offset(0, -60),
      );
      await tester.pumpAndSettle();
      await tester.pump(ScrollPositionReanchor.idleDelay);
      await tester.pumpAndSettle();

      expect(builds, lessThan(10), reason: 'העיגון בנה מחדש את טווח המטמון');
    });

    testWidgets('קפיצה לאינדקס אחרי שינוי הרוחב מדויקת', (tester) async {
      final controller = ItemScrollController();
      final listener = ItemPositionsListener.create();
      await tester.pumpWidget(
        _buildList(
          width: 600,
          controller: controller,
          listener: listener,
          enabled: true,
        ),
      );
      await tester.pumpAndSettle();
      await tester.drag(
        find.byType(ScrollablePositionedList),
        const Offset(0, -1500),
      );
      await tester.pumpAndSettle();
      await tester.pump(ScrollPositionReanchor.idleDelay);
      await tester.pumpAndSettle();
      await tester.pumpWidget(
        _buildList(
          width: 300,
          controller: controller,
          listener: listener,
          enabled: true,
        ),
      );
      await tester.pumpAndSettle();

      controller.jumpTo(index: 120, alignment: 0);
      await tester.pumpAndSettle();

      expect(_topIndex(listener), 120);
    });
  });

  group('פסקה נבחרת כשהעמודה מצטמצמת (issue #1533)', () {
    Future<ItemPosition?> selectThenNarrow(
      WidgetTester tester, {
      required double distance,
    }) async {
      final controller = ItemScrollController();
      final listener = ItemPositionsListener.create();
      Widget list(double width, int? selected) => _buildList(
        width: width,
        controller: controller,
        listener: listener,
        enabled: true,
        preferredIndex: selected,
      );

      await tester.pumpWidget(list(600, null));
      await tester.pumpAndSettle();
      await tester.drag(
        find.byType(ScrollablePositionedList),
        Offset(0, -distance),
      );
      await tester.pumpAndSettle();
      await tester.pump(ScrollPositionReanchor.idleDelay);
      await tester.pumpAndSettle();

      // פסקה בערך בשלושה רבעים מגובה המסך, כמו בחירה לפני פתיחת החלונית.
      final selected = _topIndex(listener) + 10;
      await tester.pumpWidget(list(600, selected));
      await tester.pump(ScrollPositionReanchor.idleDelay);
      await tester.pumpAndSettle();
      await tester.pumpWidget(list(300, selected));
      await tester.pumpAndSettle();

      return listener.itemPositions.value
          .where((p) => p.index == selected)
          .firstOrNull;
    }

    testWidgets('הפסקה הנבחרת נשארת במסך', (tester) async {
      final position = await selectThenNarrow(tester, distance: 1500);
      expect(position, isNotNull, reason: 'הפסקה הנבחרת יצאה מהמסך');
      expect(position!.itemTrailingEdge, lessThanOrEqualTo(1));
    });

    testWidgets('גם אחרי גלילה קצרה ממסך', (tester) async {
      final position = await selectThenNarrow(tester, distance: 200);
      expect(position, isNotNull, reason: 'הפסקה הנבחרת יצאה מהמסך');
      expect(position!.itemTrailingEdge, lessThanOrEqualTo(1));
    });

    testWidgets('הפסקה חוזרת לאותו גובה, גם כשהבחירה והצמצום באותו פריים', (
      tester,
    ) async {
      final controller = ItemScrollController();
      final listener = ItemPositionsListener.create();
      Widget list(double width, int? selected) => _buildList(
        width: width,
        controller: controller,
        listener: listener,
        enabled: true,
        preferredIndex: selected,
      );

      await tester.pumpWidget(list(600, null));
      await tester.pumpAndSettle();
      await tester.drag(
        find.byType(ScrollablePositionedList),
        const Offset(0, -1500),
      );
      await tester.pumpAndSettle();
      await tester.pump(ScrollPositionReanchor.idleDelay);
      await tester.pumpAndSettle();

      final selected = _topIndex(listener) + 10;
      final edgeBefore = listener.itemPositions.value
          .firstWhere((p) => p.index == selected)
          .itemLeadingEdge;
      await tester.pumpWidget(list(300, selected));
      await tester.pumpAndSettle();

      final after = listener.itemPositions.value
          .where((p) => p.index == selected)
          .firstOrNull;
      expect(after, isNotNull, reason: 'הפסקה הנבחרת יצאה מהמסך');
      expect(
        after!.itemLeadingEdge,
        moreOrLessEquals(edgeBefore, epsilon: 0.01),
      );
    });

    testWidgets('צמצום מיד אחרי גלילה ארוכה, לפני שהגלילה נחה, אינו מפיל', (
      tester,
    ) async {
      final controller = ItemScrollController();
      final listener = ItemPositionsListener.create();
      Widget list(double width, int? selected) => _buildList(
        width: width,
        controller: controller,
        listener: listener,
        enabled: true,
        preferredIndex: selected,
      );

      await tester.pumpWidget(list(600, null));
      await tester.pumpAndSettle();
      await tester.drag(
        find.byType(ScrollablePositionedList),
        const Offset(0, -3000),
      );
      await tester.pumpAndSettle();

      await tester.pumpWidget(list(300, _topIndex(listener) + 10));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    // ניווט לתוצאה שעל המסך בוחר שורה וגולל אליה באותו רגע.
    testWidgets('בחירה בזמן גלילה אינה מבטלת את הגלילה', (tester) async {
      final controller = ItemScrollController();
      final listener = ItemPositionsListener.create();
      Widget list(int? selected) => _buildList(
        width: 600,
        controller: controller,
        listener: listener,
        enabled: true,
        preferredIndex: selected,
      );

      await tester.pumpWidget(list(null));
      await tester.pumpAndSettle();
      unawaited(
        controller.scrollTo(
          index: 8,
          duration: const Duration(milliseconds: 600),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pumpWidget(list(8));
      await tester.pumpAndSettle();
      await tester.pump(ScrollPositionReanchor.idleDelay);
      await tester.pumpAndSettle();

      expect(_topIndex(listener), 8);
    });
  });
}
