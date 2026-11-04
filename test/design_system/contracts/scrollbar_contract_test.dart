import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/theme/app_tokens.dart';
import 'package:otzaria/widgets/feedback/app_scrollbar.dart';
import 'package:otzaria/widgets/feedback/edge_scrollbar_behavior.dart';

import 'contract_harness.dart';

/// חוזה פס הגלילה (DESIGN_SYSTEM.md, "פס גלילה"): פס אנכי בימין הפיזי בכל
/// כיוון, ברצועה משלו כשיש מה לגלול, כך שהאגודל לא עולה על התוכן.
void main() {
  const listWidth = 400.0;
  const rowKey = Key('row-0');

  /// רשימה ב-RTL עם ערכת הנושא וההתנהגות של האפליקציה, על פלטפורמת דסקטופ:
  /// ב-flutter_test ברירת המחדל היא אנדרואיד, ושם אין פס אוטומטי.
  Future<void> pumpList(
    WidgetTester tester, {
    int rows = 100,
    ScrollBehavior behavior = const EdgeScrollbarBehavior.right(),
    Widget Function(Widget list)? wrap,
    ScrollController? controller,
  }) async {
    Widget list = ListView.builder(
      controller: controller,
      itemCount: rows,
      itemBuilder: (context, i) => SizedBox(
        key: i == 0 ? rowKey : null,
        height: 40,
        child: Text('שורה $i'),
      ),
    );
    if (wrap != null) list = wrap(list);
    tester.view.physicalSize = const Size(listWidth, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(Brightness.light).copyWith(
          platform: TargetPlatform.windows,
        ),
        scrollBehavior: behavior,
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(body: list),
        ),
      ),
    );
    await tester.pump();
  }

  /// האזור שבו האגודל מצויר: [crossAxisMargin] מהקצה, ברוחב העובי.
  Rect thumbLane(WidgetTester tester, {bool right = true}) {
    final box = tester.getRect(find.byType(Scrollbar));
    const margin = AppTokens.scrollbarMargin;
    const thickness = AppTokens.scrollbarThickness;
    return right
        ? Rect.fromLTRB(
            box.right - margin - thickness,
            box.top,
            box.right - margin,
            box.bottom,
          )
        : Rect.fromLTRB(
            box.left + margin,
            box.top,
            box.left + margin + thickness,
            box.bottom,
          );
  }

  test('ה-MaterialApp של האפליקציה משתמש בהתנהגות הפס בימין', () {
    final source = File('lib/app.dart').readAsStringSync();
    expect(
      source,
      contains('scrollBehavior: const EdgeScrollbarBehavior.right()'),
      reason:
          'בלי ההתנהגות הזו כל פס אוטומטי חוזר לקצה ה-end, שמאל בעברית, ועולה '
          'על התוכן',
    );
  });

  testWidgets('ערכת הנושא: עובי מהטוקן גם בריחוף, ופינות בחצי העובי', (
    tester,
  ) async {
    final theme = appTheme(Brightness.light).scrollbarTheme;
    expect(
      theme.thickness?.resolve(const {WidgetState.hovered}),
      AppTokens.scrollbarThickness,
    );
    expect(
      theme.thickness?.resolve(const <WidgetState>{}),
      AppTokens.scrollbarThickness,
    );
    expect(
      theme.radius,
      const Radius.circular(AppTokens.scrollbarThickness / 2),
    );
    expect(theme.crossAxisMargin, AppTokens.scrollbarMargin);
    expect(
      AppTokens.scrollbarGutter,
      AppTokens.scrollbarMargin +
          AppTokens.scrollbarThickness +
          AppTokens.scrollbarContentGap,
    );
  });

  group('פס אוטומטי (ההתנהגות של האפליקציה)', () {
    testWidgets('ב-RTL הפס בימין הפיזי', (tester) async {
      await pumpList(tester);
      final bar = tester.widget<Scrollbar>(find.byType(Scrollbar));
      expect(bar.scrollbarOrientation, ScrollbarOrientation.right);
    });

    testWidgets('כשיש מה לגלול התוכן נעצר לפני האגודל', (tester) async {
      await pumpList(tester);
      final row = tester.getRect(find.byKey(rowKey));
      expect(row.right, listWidth - AppTokens.scrollbarGutter);
      expect(
        row.right,
        lessThan(thumbLane(tester).left),
        reason: 'האגודל עולה על התוכן',
      );
    });

    testWidgets('כשאין מה לגלול אין רצועה', (tester) async {
      await pumpList(tester, rows: 3);
      expect(tester.getRect(find.byKey(rowKey)).right, listWidth);
    });

    testWidgets('פס יחיד', (tester) async {
      await pumpList(tester);
      expect(find.byType(Scrollbar), findsOneWidget);
    });

    testWidgets('חריג מתועד: פס בשמאל, והרצועה בשמאל', (tester) async {
      await pumpList(
        tester,
        behavior: const EdgeScrollbarBehavior(ScrollbarOrientation.left),
      );
      final row = tester.getRect(find.byKey(rowKey));
      expect(row.left, AppTokens.scrollbarGutter);
      expect(row.right, listWidth);
      expect(row.left, greaterThan(thumbLane(tester, right: false).right));
    });

    testWidgets('reserveGutter: false — הפס בימין בלי רצועה', (tester) async {
      await pumpList(
        tester,
        behavior: const EdgeScrollbarBehavior.right(reserveGutter: false),
      );
      expect(tester.getRect(find.byKey(rowKey)).right, listWidth);
      expect(
        tester.widget<Scrollbar>(find.byType(Scrollbar)).scrollbarOrientation,
        ScrollbarOrientation.right,
      );
    });
  });

  group('תוכן שגובהו נגזר מרוחבו (R6-1)', () {
    /// רשת עם מספר עמודות קבוע ויחס קבוע: ברוחב מלא היא גולשת בקצת, ואחרי
    /// שהרצועה נלקחת האריחים קטנים והיא נכנסת. בלי טיפול הרצועה נפתחת ונסגרת
    /// בכל פריים.
    Future<void> pumpGrid(
      WidgetTester tester, {
      required ValueNotifier<int> tiles,
    }) async {
      tester.view.physicalSize = const Size(listWidth, 197);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(
            Brightness.light,
          ).copyWith(platform: TargetPlatform.windows),
          scrollBehavior: const EdgeScrollbarBehavior.right(),
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: ValueListenableBuilder<int>(
              valueListenable: tiles,
              builder: (context, count, _) => GridView.count(
                crossAxisCount: 4,
                children: [
                  for (var i = 0; i < count; i++)
                    ColoredBox(color: Colors.grey, child: Text('$i')),
                ],
              ),
            ),
          ),
        ),
      );
    }

    double gutterOf(WidgetTester tester) =>
        listWidth - tester.getSize(find.byType(Viewport)).width;

    testWidgets('הרצועה יציבה, ואין פריים נוסף אחרי שהיא נקבעה', (
      tester,
    ) async {
      final tiles = ValueNotifier(8);
      addTearDown(tiles.dispose);
      await pumpGrid(tester, tiles: tiles);

      final gutters = <double>[];
      for (var i = 0; i < 8; i++) {
        await tester.pump();
        gutters.add(gutterOf(tester));
      }
      expect(
        gutters.toSet(),
        hasLength(1),
        reason: 'הרצועה מהבהבת בין הפריימים: $gutters',
      );
      expect(
        tester.binding.hasScheduledFrame,
        isFalse,
        reason: 'הרשת נפרסת מחדש בכל פריים',
      );
      // ברוחב מלא יש מה לגלול, ולכן הרצועה נשמרת גם כשהרשת נכנסת לידה.
      expect(gutters.last, AppTokens.scrollbarGutter);
    });

    testWidgets('כשהתוכן מתכווץ ונכנס גם ברוחב מלא, הרצועה יורדת', (
      tester,
    ) async {
      final tiles = ValueNotifier(8);
      addTearDown(tiles.dispose);
      await pumpGrid(tester, tiles: tiles);
      await tester.pump();
      await tester.pump();

      tiles.value = 4;
      await tester.pump();
      await tester.pump();
      expect(gutterOf(tester), 0);
      expect(tester.binding.hasScheduledFrame, isFalse);

      tiles.value = 40;
      await tester.pump();
      await tester.pump();
      expect(gutterOf(tester), AppTokens.scrollbarGutter);
    });

    testWidgets('רשימה רגילה שהתקצרה מורידה את הרצועה', (tester) async {
      final rows = ValueNotifier(100);
      addTearDown(rows.dispose);
      await pumpList(
        tester,
        wrap: (_) => ValueListenableBuilder<int>(
          valueListenable: rows,
          builder: (context, count, _) => ListView.builder(
            itemCount: count,
            itemBuilder: (context, i) => SizedBox(
              key: i == 0 ? rowKey : null,
              height: 40,
              child: Text('שורה $i'),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(
        tester.getRect(find.byKey(rowKey)).right,
        listWidth - AppTokens.scrollbarGutter,
      );

      rows.value = 3;
      await tester.pump();
      await tester.pump();
      expect(tester.getRect(find.byKey(rowKey)).right, listWidth);
    });
  });

  group('מחוות גלילה ברצועה גוללות את הרשימה (R6-5)', () {
    // ברצועה, מחוץ לנתיב האגודל, כשהאגודל מוסתר.
    const inGutter = Offset(listWidth - AppTokens.scrollbarGutter + 2, 300);

    Future<ScrollController> pumpScrolling(WidgetTester tester) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await pumpList(tester, controller: controller);
      expect(controller.offset, 0);
      expect(
        tester.getRect(find.byKey(rowKey)).right,
        lessThanOrEqualTo(inGutter.dx),
        reason: 'הנקודה אינה ברצועה',
      );
      return controller;
    }

    testWidgets('משטח מגע (pan-zoom)', (tester) async {
      final controller = await pumpScrolling(tester);
      final pointer = TestPointer(1, PointerDeviceKind.trackpad);
      await tester.sendEventToBinding(pointer.panZoomStart(inGutter));
      for (var i = 1; i <= 10; i++) {
        await tester.sendEventToBinding(
          pointer.panZoomUpdate(inGutter, pan: Offset(0, -20.0 * i)),
        );
      }
      await tester.sendEventToBinding(pointer.panZoomEnd());
      await tester.pumpAndSettle();
      expect(controller.offset, greaterThan(0));
    });

    testWidgets('גרירת מגע', (tester) async {
      final controller = await pumpScrolling(tester);
      await tester.dragFrom(inGutter, const Offset(0, -200));
      await tester.pumpAndSettle();
      expect(controller.offset, greaterThan(0));
    });

    testWidgets('גלגלת עכבר', (tester) async {
      final controller = await pumpScrolling(tester);
      final pointer = TestPointer(1, PointerDeviceKind.mouse);
      pointer.hover(inGutter);
      await tester.sendEventToBinding(pointer.scroll(const Offset(0, 120)));
      await tester.pumpAndSettle();
      expect(controller.offset, greaterThan(0));
    });

    testWidgets('גרירת עכבר ברצועה אינה גוללת, כמו על התוכן', (tester) async {
      final controller = await pumpScrolling(tester);
      await tester.dragFrom(
        inGutter,
        const Offset(0, -200),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();
      expect(controller.offset, 0);
    });
  });

  testWidgets('שדה רב-שורות: בלי רצועה, הטקסט לא נשבר מחדש כשהוא גולש (R6-6)', (
    tester,
  ) async {
    final controller = TextEditingController(text: 'שורה');
    addTearDown(controller.dispose);
    tester.view.physicalSize = const Size(listWidth, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(
          Brightness.light,
        ).copyWith(platform: TargetPlatform.windows),
        scrollBehavior: const EdgeScrollbarBehavior.right(),
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: TextField(
              controller: controller,
              minLines: 3,
              maxLines: 6,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    double textWidth() =>
        tester.allRenderObjects.whereType<RenderEditable>().single.size.width;
    final before = textWidth();

    controller.text = List.filled(12, 'שורה').join('\n');
    await tester.pump();
    await tester.pump();
    expect(find.byType(Scrollbar), findsOneWidget, reason: 'אין פס בשדה');
    expect(textWidth(), before, reason: 'עמודת הטקסט הצטמצמה כשהטקסט גלש');
  });

  group('AppScrollbar (פס מפורש)', () {
    Future<void> pumpExplicit(WidgetTester tester, {double inset = 0}) {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      return pumpList(
        tester,
        controller: controller,
        wrap: (list) => AppScrollbar(
          controller: controller,
          thumbVisibility: true,
          contentInset: inset,
          child: list,
        ),
      );
    }

    testWidgets('פס יחיד בימין: הפס האוטומטי כבוי בתוכו', (tester) async {
      await pumpExplicit(tester);
      expect(find.byType(Scrollbar), findsOneWidget);
      final bar = tester.widget<Scrollbar>(find.byType(Scrollbar));
      expect(bar.scrollbarOrientation, ScrollbarOrientation.right);
      expect(bar.thumbVisibility, isTrue);
      expect(
        tester.getRect(find.byKey(rowKey)).right,
        listWidth - AppTokens.scrollbarGutter,
      );
    });

    testWidgets('contentInset מצמצם את הרצועה בריווח שכבר יש', (tester) async {
      await pumpExplicit(tester, inset: 8);
      expect(
        tester.getRect(find.byKey(rowKey)).right,
        listWidth - (AppTokens.scrollbarGutter - 8),
      );
    });

    testWidgets('ריווח רחב מהרצועה: אין רצועה נוספת', (tester) async {
      await pumpExplicit(tester, inset: 24);
      expect(tester.getRect(find.byKey(rowKey)).right, listWidth);
    });
  });
}
