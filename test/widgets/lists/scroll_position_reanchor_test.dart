import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/widgets/lists/scroll_position_reanchor.dart';
import 'package:otzaria/widgets/misc/smooth_wheel_scroll.dart';
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

/// רשימה חיצונית שבה הפריט [nestedIndex] הוא [nested] — כמו כרטיס המפרשים
/// שמתחת לפסקה. גובה שאר הפריטים תלוי ברוחב, כמו טקסט שנשפך מחדש.
Widget _buildNestedHost({
  required ItemScrollController controller,
  required ItemPositionsListener listener,
  required Widget nested,
  double width = 600,
  int nestedIndex = 1,
  int? preferredIndex,
  bool smoothWheel = false,
}) {
  Widget list = ScrollPositionReanchor(
    preferredIndex: preferredIndex,
    scrollController: controller,
    positionsListener: listener,
    child: ScrollablePositionedList.builder(
      itemScrollController: controller,
      itemPositionsListener: listener,
      itemCount: 50,
      itemBuilder: (context, index) => index == nestedIndex
          ? nested
          : SizedBox(height: 100 * (600 / width), child: Text('$index')),
    ),
  );
  if (smoothWheel) list = SmoothWheelScroll(child: list);
  return MaterialApp(
    home: Align(
      alignment: Alignment.topCenter,
      child: SizedBox(width: width, height: 400, child: list),
    ),
  );
}

Future<void> _idle(WidgetTester tester) async {
  await tester.pump(ScrollPositionReanchor.idleDelay);
  await tester.pumpAndSettle();
}

/// מזיז את הרשימה החיצונית מעט, כך שהעוגן שלה (0) שונה מהפריט הראשון
/// שתחילתו במסך (1) — אחרת עיגון היה קפיצה לאותו מקום, שאינה הורסת דבר.
Future<void> _nudgeOuter(WidgetTester tester) async {
  await tester.dragFrom(
    tester.getTopLeft(find.text('0')) + const Offset(5, 5),
    const Offset(0, -50),
  );
  await tester.pumpAndSettle();
  await _idle(tester);
}

ScrollableState _scrollableIn(WidgetTester tester, Key key) =>
    tester.state<ScrollableState>(
      find
          .descendant(
            of: find.byKey(key, skipOffstage: false),
            matching: find.byType(Scrollable, skipOffstage: false),
          )
          .first,
    );

void _wheel(WidgetTester tester, Offset position, {double dy = 100}) {
  tester.binding.handlePointerEvent(
    PointerScrollEvent(
      position: position,
      scrollDelta: Offset(0, dy),
      kind: PointerDeviceKind.mouse,
    ),
  );
}

/// מתג פשוט בתוך פריט — כמו מפרש שהמשתמש כיווץ בכרטיס.
class _Toggle extends StatefulWidget {
  const _Toggle({super.key});

  @override
  State<_Toggle> createState() => _ToggleState();
}

class _ToggleState extends State<_Toggle> {
  bool on = false;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: () => setState(() => on = !on),
    child: SizedBox(height: 50, child: Text(on ? 'פתוח' : 'סגור')),
  );
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

    testWidgets('מחליף את positionsListener יחד עם הווידג’ט', (tester) async {
      final controller = ItemScrollController();
      final oldListener = ItemPositionsListener.create();
      final newListener = ItemPositionsListener.create();
      Widget list(double width, ItemPositionsListener listener) => _buildList(
        width: width,
        controller: controller,
        listener: listener,
        enabled: true,
      );

      await tester.pumpWidget(list(600, oldListener));
      await tester.pumpAndSettle();
      await tester.drag(
        find.byType(ScrollablePositionedList),
        const Offset(0, -1500),
      );
      await tester.pumpAndSettle();
      await tester.pump(ScrollPositionReanchor.idleDelay);
      await tester.pumpAndSettle();

      await tester.pumpWidget(list(600, newListener));
      await tester.pumpAndSettle();
      final index = _topIndex(newListener) + 8;
      await tester.pumpWidget(
        _buildList(
          width: 600,
          controller: controller,
          listener: newListener,
          enabled: true,
          preferredIndex: index,
        ),
      );
      await tester.pumpAndSettle();
      await tester.drag(
        find.byType(ScrollablePositionedList),
        const Offset(0, -90),
      );
      await tester.pumpAndSettle();
      await tester.pump(ScrollPositionReanchor.idleDelay);
      await tester.pumpAndSettle();

      final edgeBefore = newListener.itemPositions.value
          .firstWhere((p) => p.index == index)
          .itemLeadingEdge;
      await tester.pumpWidget(
        _buildList(
          width: 300,
          controller: controller,
          listener: newListener,
          enabled: true,
          preferredIndex: index,
        ),
      );
      await tester.pumpAndSettle();

      final after = newListener.itemPositions.value.firstWhere(
        (p) => p.index == index,
      );
      expect(
        after.itemLeadingEdge,
        moreOrLessEquals(edgeBefore, epsilon: 0.01),
      );
      expect(oldListener.itemPositions.value, isNotEmpty);
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

  // issue #1768: כרטיס המפרשים גולל רשימה משלו, והעיגון קפץ ברשימה החיצונית
  // על גלילה פנימית — הקפיצה זרקה את הפריט, ואיתו את כל המצב שבתוכו.
  group('רשימה מקוננת בתוך פריט (issue #1768)', () {
    late ItemScrollController controller;
    late ItemPositionsListener listener;

    setUp(() {
      controller = ItemScrollController();
      listener = ItemPositionsListener.create();
    });

    testWidgets('גלגלת על רשימה מקוננת, מתחת להחלקת הגלגלת, אינה מעגנת', (
      tester,
    ) async {
      final innerController = ScrollController();
      addTearDown(innerController.dispose);
      const inner = Key('inner');

      await tester.pumpWidget(
        _buildNestedHost(
          controller: controller,
          listener: listener,
          smoothWheel: true,
          nested: SizedBox(
            height: 250,
            child: ListView.builder(
              key: inner,
              controller: innerController,
              itemCount: 60,
              itemBuilder: (context, i) =>
                  SizedBox(height: 40, child: Text('פנימי $i')),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _nudgeOuter(tester);

      final stateBefore = _scrollableIn(tester, inner);
      for (var i = 0; i < 6; i++) {
        _wheel(tester, tester.getCenter(find.byKey(inner)));
        await tester.pumpAndSettle();
      }
      expect(innerController.offset, 600, reason: 'הגלגלת לא הגיעה לפנימית');

      await _idle(tester);

      expect(_scrollableIn(tester, inner), same(stateBefore));
      expect(innerController.offset, 600);
    });

    // כמו CommentaryListBase: רשימה ממוקמת עם החלקת גלגלת משלה.
    testWidgets('רשימה ממוקמת מקוננת עם החלקה משלה שומרת את מקומה', (
      tester,
    ) async {
      final innerPositions = ItemPositionsListener.create();
      const inner = Key('inner');
      int innerTop() => innerPositions.itemPositions.value
          .where((p) => p.itemLeadingEdge <= 0 && p.itemTrailingEdge > 0)
          .first
          .index;

      await tester.pumpWidget(
        _buildNestedHost(
          controller: controller,
          listener: listener,
          smoothWheel: true,
          nested: SizedBox(
            height: 250,
            child: SmoothWheelScroll(
              child: ScrollablePositionedList.builder(
                key: inner,
                itemPositionsListener: innerPositions,
                itemCount: 60,
                itemBuilder: (context, i) =>
                    SizedBox(height: 40, child: Text('פנימי $i')),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _nudgeOuter(tester);

      final stateBefore = _scrollableIn(tester, inner);
      for (var i = 0; i < 8; i++) {
        _wheel(tester, tester.getCenter(find.byKey(inner)));
      }
      await tester.pumpAndSettle();
      final topBefore = innerTop();
      expect(topBefore, 20, reason: 'הגלגלת לא גללה את הרשימה הפנימית');

      await _idle(tester);

      expect(_scrollableIn(tester, inner), same(stateBefore));
      expect(innerTop(), topBefore);
    });

    testWidgets('גלילה בעומק שתיים אינה מעגנת', (tester) async {
      final deepController = ScrollController();
      addTearDown(deepController.dispose);
      const middle = Key('middle');
      const deep = Key('deep');

      await tester.pumpWidget(
        _buildNestedHost(
          controller: controller,
          listener: listener,
          nested: SizedBox(
            height: 250,
            child: ListView(
              key: middle,
              children: [
                SizedBox(
                  height: 200,
                  child: ListView.builder(
                    key: deep,
                    controller: deepController,
                    itemCount: 60,
                    itemBuilder: (context, i) =>
                        SizedBox(height: 40, child: Text('עמוק $i')),
                  ),
                ),
                const SizedBox(height: 600),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _nudgeOuter(tester);

      await tester.drag(find.byKey(deep), const Offset(0, -600));
      await tester.pumpAndSettle();
      final middleBefore = _scrollableIn(tester, middle);
      final deepBefore = _scrollableIn(tester, deep);
      final offset = deepController.offset;
      expect(offset, greaterThan(200), reason: 'הגלילה העמוקה לא זזה');

      await _idle(tester);

      expect(_scrollableIn(tester, middle), same(middleBefore));
      expect(_scrollableIn(tester, deep), same(deepBefore));
      expect(deepController.offset, offset);
    });

    testWidgets('מצב של ווידג׳ט אחר בפריט שורד גלילה מקוננת', (tester) async {
      const toggle = Key('toggle');
      const inner = Key('inner');

      await tester.pumpWidget(
        _buildNestedHost(
          controller: controller,
          listener: listener,
          nested: SizedBox(
            height: 250,
            child: Column(
              children: [
                const _Toggle(key: toggle),
                Expanded(
                  child: ListView.builder(
                    key: inner,
                    itemCount: 60,
                    itemBuilder: (context, i) =>
                        SizedBox(height: 40, child: Text('פנימי $i')),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _nudgeOuter(tester);
      await tester.tap(find.byKey(toggle));
      await tester.pump();
      expect(find.text('פתוח'), findsOneWidget);

      await tester.drag(find.byKey(inner), const Offset(0, -600));
      await tester.pumpAndSettle();
      await _idle(tester);

      expect(find.text('פתוח'), findsOneWidget, reason: 'הפריט נבנה מחדש');
    });

    // SmoothWheelScroll ו-MiddleClickAutoscroll שמעל העיגון מזהים רשימות
    // מקוננות לפי ההודעות שלהן, ולכן הסינון אסור שיעצור אותן.
    testWidgets('הודעות הגלילה המקוננת ממשיכות לעלות מעל העיגון', (
      tester,
    ) async {
      final depths = <int>{};
      const inner = Key('inner');

      await tester.pumpWidget(
        NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            depths.add(notification.depth);
            return false;
          },
          child: _buildNestedHost(
            controller: controller,
            listener: listener,
            nested: SizedBox(
              height: 250,
              child: ListView.builder(
                key: inner,
                itemCount: 60,
                itemBuilder: (context, i) =>
                    SizedBox(height: 40, child: Text('פנימי $i')),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.drag(find.byKey(inner), const Offset(0, -100));
      await tester.pumpAndSettle();

      expect(depths, contains(1));
    });

    // העיגון שתוזמן בגלילה החיצונית היה קופץ באמצע הגלילה הפנימית שאחריה.
    testWidgets(
      'גלגלת שממשיכה מהרשימה אל הפריט המקונן אינה מאפסת אותו',
      (tester) async {
        final innerController = ScrollController();
        addTearDown(innerController.dispose);
        const inner = Key('inner');

        await tester.pumpWidget(
          _buildNestedHost(
            controller: controller,
            listener: listener,
            nestedIndex: 8,
            smoothWheel: true,
            nested: SizedBox(
              height: 250,
              child: ListView.builder(
                key: inner,
                controller: innerController,
                itemCount: 60,
                itemBuilder: (context, i) =>
                    SizedBox(height: 40, child: Text('פנימי $i')),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // הסמן נשאר במקומו, והרשימה מביאה את הפריט המקונן אל מתחתיו.
        final pointer = tester.getCenter(find.text('1'));
        for (var i = 0; i < 8; i++) {
          _wheel(tester, pointer);
        }
        await tester.pumpAndSettle();
        expect(
          tester.getRect(find.byKey(inner)).contains(pointer),
          isTrue,
          reason: 'הפריט המקונן לא הגיע אל מתחת לסמן',
        );

        final stateBefore = _scrollableIn(tester, inner);
        _wheel(tester, pointer);
        await tester.pump();
        expect(innerController.offset, 100, reason: 'הגלגלת לא עברה לפנימית');
        for (var i = 0; i < 5; i++) {
          await tester.pump(const Duration(milliseconds: 100));
          _wheel(tester, pointer);
        }
        await _idle(tester);

        expect(_scrollableIn(tester, inner), same(stateBefore));
        expect(innerController.offset, 600);

        // ההיסט מהעוגן עדיין גדול: נקישה על הטקסט שמתחת לכרטיס, שנשאר במסך,
        // אסור שתתזמן מחדש את העיגון שבוטל.
        _wheel(
          tester,
          tester.getRect(find.byKey(inner)).bottomCenter + const Offset(0, 50),
          dy: -50,
        );
        await tester.pumpAndSettle();
        await _idle(tester);

        expect(find.byKey(inner), findsOneWidget);
        expect(_scrollableIn(tester, inner), same(stateBefore));
        expect(innerController.offset, 600);
      },
    );

    // שינוי רוחב בתוך זמן הרגיעה נדחה כדי לא לקפוץ באמצע גלילה. גלילה
    // פנימית אסור שתפעיל את ההשהיה הזו, אחרת הפסקה הנבחרת נדחפת ממקומה.
    testWidgets('צמצום מיד אחרי גלילה מקוננת מחזיר את הפסקה הנבחרת לגובהה', (
      tester,
    ) async {
      final innerController = ScrollController();
      addTearDown(innerController.dispose);
      const selected = 2;
      Widget host(double width) => _buildNestedHost(
        width: width,
        controller: controller,
        listener: listener,
        preferredIndex: selected,
        nested: SizedBox(
          height: 250,
          child: ListView.builder(
            controller: innerController,
            itemCount: 60,
            itemBuilder: (context, i) =>
                SizedBox(height: 40, child: Text('פנימי $i')),
          ),
        ),
      );

      await tester.pumpWidget(host(600));
      await tester.pumpAndSettle();
      await _nudgeOuter(tester);
      final edgeBefore = listener.itemPositions.value
          .firstWhere((p) => p.index == selected)
          .itemLeadingEdge;

      innerController.jumpTo(600);
      await tester.pump();
      await tester.pumpWidget(host(300));
      await tester.pumpAndSettle();

      final after = listener.itemPositions.value
          .where((p) => p.index == selected)
          .firstOrNull;
      expect(after, isNotNull, reason: 'הפסקה הנבחרת יצאה מהמסך');
      expect(
        after!.itemLeadingEdge,
        moreOrLessEquals(edgeBefore, epsilon: 0.01),
      );
      await _idle(tester);
    });

    // פסקה ארוכה וכרטיס תחתיה: תחילת הפסקה מעל המסך, ואין לה גובה לשחזר.
    // העיגון שהגלילה המקוננת ביטלה חייב להתבצע בשינוי הרוחב.
    testWidgets('צמצום אחרי גלילה מקוננת שביטלה עיגון אינו סוחף את הטקסט', (
      tester,
    ) async {
      final innerController = ScrollController();
      addTearDown(innerController.dispose);
      const selected = 6;
      const inner = Key('inner');
      Widget host(double width) => _buildNestedHost(
        width: width,
        controller: controller,
        listener: listener,
        nestedIndex: selected,
        preferredIndex: selected,
        nested: Column(
          children: [
            SizedBox(height: 100 * (600 / width), child: const Text('פסקה')),
            SizedBox(
              height: 250,
              child: ListView.builder(
                key: inner,
                controller: innerController,
                itemCount: 60,
                itemBuilder: (context, i) =>
                    SizedBox(height: 40, child: Text('פנימי $i')),
              ),
            ),
          ],
        ),
      );
      ItemPosition? positionOf(int index) => listener.itemPositions.value
          .where((p) => p.index == index)
          .firstOrNull;

      await tester.pumpWidget(host(600));
      await tester.pumpAndSettle();
      // גלילה של פחות משני מסכים, כדי שרק שינוי הרוחב יסגור את החוב, ומיד
      // אחריה גלילה בכרטיס — לפני שהעיגון רץ.
      await tester.dragFrom(const Offset(400, 390), const Offset(0, -660));
      await tester.pump();
      await tester.drag(find.byKey(inner), const Offset(0, -200));
      await tester.pump();
      await _idle(tester);
      expect(
        innerController.offset,
        greaterThan(100),
        reason: 'הכרטיס לא נגלל',
      );
      expect(
        positionOf(selected)!.itemLeadingEdge,
        lessThan(0),
        reason: 'תחילת הפסקה הנבחרת צריכה להיות מעל המסך',
      );
      final next = positionOf(selected + 1)!.itemLeadingEdge;

      await tester.pumpWidget(host(300));
      await tester.pumpAndSettle();

      final after = positionOf(selected + 1);
      expect(after, isNotNull, reason: 'הטקסט נסחף מהמסך');
      expect(after!.itemLeadingEdge, moreOrLessEquals(next, epsilon: 0.01));

      // החוב שולם: גלילה בכרטיס, גלילה חיצונית קצרה ממסך ושינוי רוחב נוסף
      // אינם בונים אותו מחדש. הגלילה הקצרה מעבירה את ראש התצוגה לפריט אחר.
      await _idle(tester);
      await tester.drag(find.byKey(inner), const Offset(0, -200));
      await tester.pumpAndSettle();
      final stateBefore = _scrollableIn(tester, inner);
      final offset = innerController.offset;
      expect(offset, greaterThan(100), reason: 'הכרטיס לא נגלל');
      final topBefore = _topIndex(listener);
      await tester.dragFrom(const Offset(400, 390), const Offset(0, -330));
      await tester.pumpAndSettle();
      await _idle(tester);
      expect(_topIndex(listener), isNot(topBefore));

      await tester.pumpWidget(host(310));
      await tester.pumpAndSettle();
      await _idle(tester);

      expect(_scrollableIn(tester, inner), same(stateBefore));
      expect(innerController.offset, offset);
    });

    // שינוי רוחב בזמן הרגיעה נדחה בלי לקפוץ, ולכן החוב נשאר והעיגון ברגיעה
    // שאחריו עדיין אסור — הכרטיס במסך.
    testWidgets('שינוי רוחב שנדחה אינו מבטל את החוב', (tester) async {
      final innerController = ScrollController();
      addTearDown(innerController.dispose);
      const inner = Key('inner');
      Widget host(double width) => _buildNestedHost(
        width: width,
        controller: controller,
        listener: listener,
        nestedIndex: 4,
        nested: SizedBox(
          height: 250,
          child: ListView.builder(
            key: inner,
            controller: innerController,
            itemCount: 60,
            itemBuilder: (context, i) =>
                SizedBox(height: 40, child: Text('פנימי $i')),
          ),
        ),
      );

      await tester.pumpWidget(host(600));
      await tester.pumpAndSettle();
      await tester.dragFrom(const Offset(400, 390), const Offset(0, -450));
      await tester.pump();
      await tester.drag(find.byKey(inner), const Offset(0, -200));
      await tester.pump();
      await _idle(tester);
      final stateBefore = _scrollableIn(tester, inner);
      final offset = innerController.offset;
      expect(offset, greaterThan(100), reason: 'הכרטיס לא נגלל');

      await tester.dragFrom(const Offset(400, 300), const Offset(0, -50));
      await tester.pump();
      await tester.pumpWidget(host(300));
      await tester.pumpAndSettle();
      await _idle(tester);

      expect(find.byKey(inner), findsOneWidget, reason: 'הכרטיס יצא מהמסך');
      expect(_scrollableIn(tester, inner), same(stateBefore));
      expect(innerController.offset, offset);
    });

    // כרטיס בגובה כמעט מסך עדיין נראה אחרי יותר ממסך אחד של גלילה.
    testWidgets('גלילה חיצונית של פחות משני מסכים אינה מאפסת כרטיס שנגלל', (
      tester,
    ) async {
      final innerController = ScrollController();
      addTearDown(innerController.dispose);
      const inner = Key('inner');

      await tester.pumpWidget(
        _buildNestedHost(
          controller: controller,
          listener: listener,
          nestedIndex: 8,
          nested: SizedBox(
            height: 350,
            child: ListView.builder(
              key: inner,
              controller: innerController,
              itemCount: 60,
              itemBuilder: (context, i) =>
                  SizedBox(height: 40, child: Text('פנימי $i')),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.dragFrom(const Offset(400, 390), const Offset(0, -500));
      await tester.pump();
      await tester.dragFrom(const Offset(400, 350), const Offset(0, -100));
      await tester.pump();
      await _idle(tester);
      final stateBefore = _scrollableIn(tester, inner);
      final offset = innerController.offset;
      expect(offset, greaterThan(50), reason: 'הכרטיס לא נגלל');

      await tester.dragFrom(const Offset(400, 50), const Offset(0, -450));
      await tester.pumpAndSettle();
      await _idle(tester);

      expect(find.byKey(inner), findsOneWidget, reason: 'הכרטיס יצא מהמסך');
      expect(_scrollableIn(tester, inner), same(stateBefore));
      expect(innerController.offset, offset);
    });

    // סגירת כרטיס שמעל המסך: בלי עיגון ברגיעה הטקסט שבמסך קופץ בגובהו.
    testWidgets('שני מסכים אחרי כרטיס שנגלל העיגון ברגיעה חוזר', (
      tester,
    ) async {
      final innerController = ScrollController();
      addTearDown(innerController.dispose);
      const inner = Key('inner');
      Widget host({required bool card}) => _buildNestedHost(
        controller: controller,
        listener: listener,
        nestedIndex: 8,
        nested: card
            ? SizedBox(
                height: 250,
                child: ListView.builder(
                  key: inner,
                  controller: innerController,
                  itemCount: 60,
                  itemBuilder: (context, i) =>
                      SizedBox(height: 40, child: Text('פנימי $i')),
                ),
              )
            : const SizedBox(height: 100),
      );

      await tester.pumpWidget(host(card: true));
      await tester.pumpAndSettle();
      await tester.dragFrom(const Offset(400, 390), const Offset(0, -860));
      await tester.pump();
      await tester.drag(find.byKey(inner), const Offset(0, -200));
      await tester.pump();
      await _idle(tester);
      expect(innerController.offset, greaterThan(100), reason: 'הכרטיס אופס');

      for (var i = 0; i < 3; i++) {
        await tester.dragFrom(const Offset(400, 390), const Offset(0, -300));
        await tester.pumpAndSettle();
      }
      await _idle(tester);
      final top = reanchorTargetPosition(listener.itemPositions.value)!;

      await tester.pumpWidget(host(card: false));
      await tester.pumpAndSettle();

      final after = listener.itemPositions.value
          .where((p) => p.index == top.index)
          .firstOrNull;
      expect(after, isNotNull, reason: 'הטקסט קפץ מהמסך');
      expect(
        after!.itemLeadingEdge,
        moreOrLessEquals(top.itemLeadingEdge, epsilon: 0.01),
      );
    });

    // הגלילה המקוננת ביטלה את הטיימר, ולכן שינוי רוחב מיידי אינו נדחה.
    testWidgets(
      'גלילה חיצונית שלא נחה ואחריה מקוננת — הצמצום מחזיר את הנבחרת',
      (
        tester,
      ) async {
        const selected = 20;
        const inner = Key('inner');
        Widget host(double width) => _buildNestedHost(
          width: width,
          controller: controller,
          listener: listener,
          nestedIndex: selected,
          preferredIndex: selected,
          nested: Column(
            children: [
              SizedBox(height: 40 * (600 / width), child: const Text('פסקה')),
              SizedBox(
                height: 250,
                child: ListView.builder(
                  key: inner,
                  itemCount: 60,
                  itemBuilder: (context, i) =>
                      SizedBox(height: 40, child: Text('פנימי $i')),
                ),
              ),
            ],
          ),
        );
        double? edgeOf(int index) => listener.itemPositions.value
            .where((p) => p.index == index)
            .firstOrNull
            ?.itemLeadingEdge;

        await tester.pumpWidget(host(600));
        await tester.pumpAndSettle();
        await tester.dragFrom(const Offset(400, 390), const Offset(0, -1950));
        await tester.pump();
        await tester.drag(find.byKey(inner), const Offset(0, -200));
        await tester.pump();
        final edgeBefore = edgeOf(selected);
        expect(edgeBefore, isNotNull);
        expect(edgeBefore, inInclusiveRange(0, 1));

        await tester.pumpWidget(host(300));
        await tester.pumpAndSettle();

        expect(edgeOf(selected), isNotNull, reason: 'הפסקה הנבחרת יצאה מהמסך');
        expect(edgeOf(selected), moreOrLessEquals(edgeBefore!, epsilon: 0.01));
        await _idle(tester);
      },
    );

    // הסינון לפי עומק אסור שיבלע את גלילת הרשימה עצמה כשיש בה פריט מקונן.
    Future<int> scrollOuterAndNarrow(
      WidgetTester tester,
      Future<void> Function() scroll,
    ) async {
      Widget host(double width) => _buildNestedHost(
        width: width,
        controller: controller,
        listener: listener,
        nestedIndex: 15,
        smoothWheel: true,
        nested: SizedBox(
          height: 250,
          child: ListView.builder(
            itemCount: 60,
            itemBuilder: (context, i) =>
                SizedBox(height: 40, child: Text('פנימי $i')),
          ),
        ),
      );
      await tester.pumpWidget(host(600));
      await tester.pumpAndSettle();
      await scroll();
      await tester.pumpAndSettle();
      await _idle(tester);
      final before = _topIndex(listener);
      expect(before, greaterThan(10), reason: 'הגלילה החיצונית לא זזה');
      expect(
        find.text('פנימי 0'),
        findsOneWidget,
        reason: 'הפריט המקונן צריך להיות במסך',
      );

      await tester.pumpWidget(host(300));
      await tester.pumpAndSettle();
      return _topIndex(listener) - before;
    }

    testWidgets('גרירה חיצונית עדיין מעגנת כשיש פריט מקונן', (tester) async {
      final drift = await scrollOuterAndNarrow(
        tester,
        () => tester.drag(
          find.byType(ScrollablePositionedList),
          const Offset(0, -1500),
        ),
      );
      expect(drift, 0);
    });

    testWidgets('גלגלת חיצונית (החלקה) עדיין מעגנת כשיש פריט מקונן', (
      tester,
    ) async {
      final drift = await scrollOuterAndNarrow(tester, () async {
        // כל הנקישות באותו פריים, לפני שהפריט המקונן מגיע אל מתחת לסמן.
        final position = tester.getCenter(find.text('3'));
        for (var i = 0; i < 15; i++) {
          _wheel(tester, position);
        }
      });
      expect(drift, 0);
    });
  });
}
