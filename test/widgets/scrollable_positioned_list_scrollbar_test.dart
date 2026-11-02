import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/widgets/feedback/scrollable_positioned_list_scrollbar.dart';
import 'package:otzaria/widgets/layout/adaptive_side_pane.dart';
import 'package:otzaria/widgets/layout/resizable_drag_handle.dart';
import 'package:positioned_sliver_list/positioned_list.dart';

class _ListFixture {
  _ListFixture(this.heights);

  final List<double> heights;
  final item = ItemScrollController();
  final pixels = ScrollController(keepScrollOffset: false);

  Widget app({
    TextDirection direction = TextDirection.ltr,
    bool reverse = false,
    bool accurateEstimates = true,
    EdgeInsets? padding,
    String Function(int)? label,
    VoidCallback? onNavigationStart,
    IndexedWidgetBuilder? itemBuilder,
  }) => MaterialApp(
    home: Directionality(
      textDirection: direction,
      child: Scaffold(
        body: ScrollablePositionedListScrollbar(
          scrollController: item,
          itemCount: heights.length,
          labelForIndex: label,
          onNavigationStart: onNavigationStart,
          child: ScrollablePositionedList.builder(
            key: ValueKey(this),
            itemScrollController: item,
            scrollController: pixels,
            itemCount: heights.length,
            reverse: reverse,
            padding: padding,
            estimateExtent: accurateEstimates
                ? (index, width) => heights[index]
                : null,
            itemBuilder:
                itemBuilder ??
                (_, index) => SizedBox(
                  height: heights[index],
                  child: Text('שורה $index'),
                ),
          ),
        ),
      ),
    ),
  );
}

final _track = find.byKey(ScrollablePositionedListScrollbar.trackKey);
final _thumb = find.byKey(ScrollablePositionedListScrollbar.thumbKey);

Future<_ListFixture> _pumpList(
  WidgetTester tester, {
  List<double>? heights,
  TextDirection direction = TextDirection.ltr,
  bool reverse = false,
  bool accurateEstimates = true,
  EdgeInsets? padding,
  String Function(int)? label,
  VoidCallback? onNavigationStart,
  IndexedWidgetBuilder? itemBuilder,
}) async {
  tester.view.physicalSize = const Size(800, 600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final fixture = _ListFixture(heights ?? List.filled(100, 100));
  addTearDown(fixture.pixels.dispose);
  await tester.pumpWidget(
    fixture.app(
      direction: direction,
      reverse: reverse,
      accurateEstimates: accurateEstimates,
      padding: padding,
      label: label,
      onNavigationStart: onNavigationStart,
      itemBuilder: itemBuilder,
    ),
  );
  await tester.pumpAndSettle();
  return fixture;
}

void _expectPhysicalThumb(WidgetTester tester, _ListFixture fixture) {
  final position = fixture.pixels.position;
  final range = position.maxScrollExtent - position.minScrollExtent;
  if (range <= 0 || fixture.heights.isEmpty) {
    expect(_thumb, findsNothing);
    return;
  }
  final track = tester.getRect(_track);
  final thumb = tester.getRect(_thumb);
  final height =
      (position.viewportDimension / (range + position.viewportDimension)).clamp(
        0.05,
        1.0,
      );
  var fraction = ((position.pixels - position.minScrollExtent) / range).clamp(
    0.0,
    1.0,
  );
  if (position.axisDirection == AxisDirection.up) fraction = 1 - fraction;
  expect(thumb.height, closeTo(track.height * height, 0.01));
  expect(
    thumb.top - track.top,
    closeTo(track.height * (1 - height) * fraction, 0.01),
  );
}

double _targetAt(WidgetTester tester, _ListFixture fixture, double dy) {
  final track = tester.getRect(_track);
  final height = tester.getRect(_thumb).height / track.height;
  var fraction = ((dy / track.height - height / 2) / (1 - height)).clamp(
    0.0,
    1.0,
  );
  final position = fixture.pixels.position;
  if (position.axisDirection == AxisDirection.up) fraction = 1 - fraction;
  return position.minScrollExtent +
      fraction * (position.maxScrollExtent - position.minScrollExtent);
}

Future<TestGesture> _hover(WidgetTester tester, Offset position) async {
  final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await gesture.addPointer(location: const Offset(400, 300));
  await gesture.moveTo(position);
  await tester.pump();
  addTearDown(gesture.removePointer);
  return gesture;
}

void main() {
  testWidgets('האגודל משקף אורך תוכן גם כשפריט אחרון ארוך מאוד', (
    tester,
  ) async {
    final fixture = await _pumpList(
      tester,
      heights: [...List.filled(9, 50.0), 1500],
    );
    fixture.pixels.jumpTo(250);
    await tester.pumpAndSettle();
    expect(fixture.pixels.position.maxScrollExtent, 1350);
    _expectPhysicalThumb(tester, fixture);
    final track = tester.getRect(_track);
    final thumb = tester.getRect(_thumb);
    expect(
      (thumb.top - track.top) / (track.height - thumb.height),
      closeTo(250 / 1350, 0.001),
    );
  });

  testWidgets('גרירת מסילה מגיעה לסוף בתוך פסקה הגבוהה ממסך', (tester) async {
    final fixture = await _pumpList(tester, heights: [3000]);
    await tester.tapAt(
      tester.getRect(_track).bottomCenter - const Offset(0, 1),
    );
    await tester.pumpAndSettle();
    expect(fixture.pixels.offset, closeTo(2400, 0.01));
    _expectPhysicalThumb(tester, fixture);
    expect(
      tester.getRect(_thumb).bottom,
      closeTo(tester.getRect(_track).bottom, 0.01),
    );
  });

  for (final itemCount in [1, 3]) {
    testWidgets(
      'גרירת אגודל עוברת בתוך פריטים גבוהים עד סוף האחרון: count=$itemCount',
      (tester) async {
        final fixture = await _pumpList(
          tester,
          heights: List.filled(itemCount, 4000),
        );
        final gesture = await tester.startGesture(
          tester.getRect(_thumb).center,
        );
        await gesture.moveBy(const Offset(0, 700));
        await gesture.up();
        await tester.pumpAndSettle();
        expect(
          fixture.pixels.offset,
          closeTo(fixture.pixels.position.maxScrollExtent, 0.01),
        );
        final last = fixture.item.listController!
            .computeItemPositions()!
            .singleWhere((position) => position.index == itemCount - 1);
        expect(last.itemTrailingEdge, closeTo(1, 0.01));
        _expectPhysicalThumb(tester, fixture);
      },
    );
  }

  testWidgets('לחיצה באמצע המסילה ממפה לפיקסלים גם בגבהים משתנים', (
    tester,
  ) async {
    final fixture = await _pumpList(
      tester,
      heights: [...List.filled(9, 50.0), 1500],
    );
    final target = _targetAt(tester, fixture, 300);
    await tester.tapAt(tester.getRect(_track).topCenter + const Offset(0, 300));
    await tester.pumpAndSettle();
    expect(fixture.pixels.offset, closeTo(target, 0.01));
    _expectPhysicalThumb(tester, fixture);
  });

  testWidgets('אגודל מינימלי שומר את מיפוי הטווח ואת ההגעה לתחתית', (
    tester,
  ) async {
    final fixture = await _pumpList(tester, heights: List.filled(10000, 100));
    expect(tester.getRect(_thumb).height, closeTo(30, 0.01));
    await tester.tapAt(
      tester.getRect(_track).bottomCenter - const Offset(0, 1),
    );
    await tester.pumpAndSettle();
    expect(fixture.pixels.offset, fixture.pixels.position.maxScrollExtent);
    _expectPhysicalThumb(tester, fixture);
  });

  for (final reverse in [false, true]) {
    testWidgets('מיקום וגרירה תואמים לכיוון הרשימה reverse=$reverse', (
      tester,
    ) async {
      final fixture = await _pumpList(tester, reverse: reverse);
      _expectPhysicalThumb(tester, fixture);
      final target = _targetAt(tester, fixture, 180);
      await tester.tapAt(
        tester.getRect(_track).topCenter + const Offset(0, 180),
      );
      await tester.pumpAndSettle();
      expect(fixture.pixels.offset, closeTo(target, 0.01));
      _expectPhysicalThumb(tester, fixture);
    });
  }

  testWidgets('לחיצה על האגודל אינה מקפיצה ואינה רושמת ניווט', (tester) async {
    var navigations = 0;
    final fixture = await _pumpList(
      tester,
      onNavigationStart: () => navigations++,
    );
    await tester.tapAt(tester.getRect(_thumb).center);
    await tester.pumpAndSettle();
    expect(fixture.pixels.offset, 0);
    expect(navigations, 0);
  });

  testWidgets('גרירה נותנת משוב ראשון מיידי ורושמת ניווט פעם אחת', (
    tester,
  ) async {
    final starts = <double>[];
    late _ListFixture fixture;
    fixture = await _pumpList(
      tester,
      onNavigationStart: () => starts.add(fixture.pixels.offset),
    );
    final gesture = await tester.startGesture(tester.getRect(_thumb).center);
    await gesture.moveBy(const Offset(0, 40));
    expect(fixture.pixels.offset, greaterThan(0));
    for (var i = 0; i < 10; i++) {
      await gesture.moveBy(const Offset(0, 3));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pumpAndSettle();
    expect(starts, [0]);
    _expectPhysicalThumb(tester, fixture);
  });

  testWidgets('עדכונים באותו פריים מתאחדים והשחרור נוחת ביעד האחרון', (
    tester,
  ) async {
    final fixture = await _pumpList(tester);
    var updates = 0;
    fixture.pixels.addListener(() => updates++);
    final gesture = await tester.startGesture(tester.getRect(_thumb).center);
    await gesture.moveBy(const Offset(0, 40));
    final first = fixture.pixels.offset;
    final firstUpdates = updates;
    final movementRange =
        tester.getRect(_track).height - tester.getRect(_thumb).height;
    for (var i = 0; i < 20; i++) {
      await gesture.moveBy(const Offset(0, 2));
    }
    expect(updates, firstUpdates);
    expect(fixture.pixels.offset, first);
    await gesture.up();
    expect(
      fixture.pixels.offset,
      closeTo(
        first + 40 / movementRange * fixture.pixels.position.maxScrollExtent,
        0.01,
      ),
    );
    expect(updates, firstUpdates + 1);
    await tester.pumpAndSettle();
    _expectPhysicalThumb(tester, fixture);
  });

  testWidgets('חזרה ליעד הקיים מבטלת יעד ממתין באותו פריים', (tester) async {
    final fixture = await _pumpList(tester);
    final gesture = await tester.startGesture(tester.getRect(_thumb).center);
    await gesture.moveBy(const Offset(0, 80));
    final first = fixture.pixels.offset;
    await gesture.moveBy(const Offset(0, 40));
    await gesture.moveBy(const Offset(0, -40));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(fixture.pixels.offset, closeTo(first, 0.01));
  });

  testWidgets('ביטול גרירה אינו מבצע יעד ממתין', (tester) async {
    final fixture = await _pumpList(tester, label: (index) => 'יעד $index');
    final gesture = await tester.startGesture(tester.getRect(_thumb).center);
    await gesture.moveBy(const Offset(0, 40));
    final first = fixture.pixels.offset;
    await gesture.moveBy(const Offset(0, 100));
    await gesture.cancel();
    await tester.pumpAndSettle();
    expect(fixture.pixels.offset, closeTo(first, 0.01));
    expect(find.textContaining('יעד '), findsNothing);
  });

  testWidgets('לחיצה שהתפתחה לגרירת מסילה רושמת נקודת מוצא אחת', (
    tester,
  ) async {
    final starts = <double>[];
    late _ListFixture fixture;
    fixture = await _pumpList(
      tester,
      onNavigationStart: () => starts.add(fixture.pixels.offset),
    );
    final gesture = await tester.startGesture(
      tester.getRect(_track).topCenter + const Offset(0, 250),
    );
    await tester.pump(const Duration(milliseconds: 150));
    await gesture.moveBy(const Offset(0, 50));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(starts, [0]);
    await tester.tapAt(
      tester.getRect(_track).bottomCenter - const Offset(0, 1),
    );
    await tester.pumpAndSettle();
    expect(starts.length, 2);
  });

  for (final onThumb in [false, true]) {
    testWidgets(
      'גלילה בשתי אצבעות בלוח מגע ${onThumb ? 'על האגודל' : 'על המסילה'} '
      'אינה מזיזה את הספר כגרירת פס (issue #2680)',
      (tester) async {
        var navigations = 0;
        final fixture = await _pumpList(
          tester,
          heights: List.filled(2000, 100),
          onNavigationStart: () => navigations++,
        );
        fixture.pixels.jumpTo(5000);
        await tester.pump();
        final at = onThumb
            ? tester.getRect(_thumb).center
            : tester.getRect(_track).center;
        final gesture = await tester.createGesture(
          kind: PointerDeviceKind.trackpad,
        );
        await gesture.panZoomStart(at);
        for (var i = 1; i <= 3; i++) {
          await gesture.panZoomUpdate(at, pan: Offset(0, 10.0 * i));
          await tester.pump(const Duration(milliseconds: 16));
        }
        await gesture.panZoomEnd();
        await tester.pumpAndSettle();
        expect(
          (fixture.pixels.offset - 5000).abs(),
          lessThanOrEqualTo(30),
          reason: 'תנועה של 30px בלוח המגע הזיזה את הספר כמו גרירת האגודל',
        );
        expect(navigations, 0);
      },
    );
  }

  testWidgets('גרירת פס מבטלת יעד של אנימציה קודמת', (tester) async {
    final fixture = await _pumpList(tester);
    final animation = fixture.item.scrollTo(
      index: 90,
      duration: const Duration(seconds: 2),
    );
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 16));
    final gesture = await tester.startGesture(tester.getRect(_thumb).center);
    await gesture.moveBy(const Offset(0, -60));
    await gesture.up();
    await tester.pumpAndSettle();
    await animation;
    final landed = fixture.pixels.offset;
    await tester.pump(const Duration(seconds: 3));
    expect(fixture.pixels.offset, landed);
    _expectPhysicalThumb(tester, fixture);
  });

  testWidgets('התווית מתייחסת לפריט ביעד הפיזי ומחשבת רק בעת שינוי אינדקס', (
    tester,
  ) async {
    final calls = <int>[];
    final fixture = await _pumpList(
      tester,
      heights: [...List.filled(9, 50.0), 1500],
      label: (index) {
        calls.add(index);
        return 'יעד $index';
      },
    );
    final track = tester.getRect(_track);
    final expected = fixture.item.indexForScrollOffset(
      _targetAt(tester, fixture, 300),
    );
    final gesture = await _hover(
      tester,
      track.topCenter + const Offset(0, 300),
    );
    expect(find.text('יעד $expected'), findsOneWidget);
    expect(calls, [expected]);
    await gesture.moveBy(const Offset(0, 0.1));
    await tester.pump();
    expect(calls, [expected]);
    await gesture.moveTo(const Offset(400, 300));
    await tester.pump();
    expect(find.textContaining('יעד '), findsNothing);
  });

  testWidgets('ריפוד לפני פריט אפס מציג את כתובתו בתווית', (tester) async {
    await _pumpList(
      tester,
      padding: const EdgeInsets.only(top: 30),
      label: (index) => 'יעד $index',
    );
    await _hover(tester, tester.getRect(_track).topCenter + const Offset(0, 1));
    expect(find.text('יעד 0'), findsOneWidget);
  });

  testWidgets('לחיצה בודדת במגע אינה משאירה תווית יתומה', (tester) async {
    await _pumpList(tester, label: (index) => 'יעד $index');
    await tester.tapAt(tester.getRect(_track).center);
    await tester.pumpAndSettle();
    expect(find.textContaining('יעד '), findsNothing);
  });

  testWidgets('ללא תוויות ריחוף וגרירה אינם זורקים', (tester) async {
    await _pumpList(tester);
    await _hover(tester, tester.getRect(_track).center);
    await tester.dragFrom(tester.getRect(_thumb).center, const Offset(0, 100));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('תוכן שגדל בפריט קיים מחזיר את המסילה', (tester) async {
    final height = ValueNotifier(40.0);
    addTearDown(height.dispose);
    final fixture = await _pumpList(
      tester,
      heights: [40],
      itemBuilder: (_, index) => ValueListenableBuilder<double>(
        valueListenable: height,
        builder: (_, value, child) => SizedBox(height: value),
      ),
    );
    expect(_track, findsNothing);
    height.value = 900;
    await tester.pumpAndSettle();
    expect(_track, findsOneWidget);
    _expectPhysicalThumb(tester, fixture);
  });

  testWidgets('תוכן שהתכווץ מסתיר גם את התווית תחת הסמן', (tester) async {
    final height = ValueNotifier(900.0);
    addTearDown(height.dispose);
    await _pumpList(
      tester,
      heights: [900],
      label: (index) => 'יעד $index',
      itemBuilder: (_, index) => ValueListenableBuilder<double>(
        valueListenable: height,
        builder: (_, value, child) => SizedBox(height: value),
      ),
    );
    await _hover(tester, tester.getRect(_track).center);
    expect(find.text('יעד 0'), findsOneWidget);
    height.value = 40;
    await tester.pumpAndSettle();
    expect(_track, findsNothing);
    expect(find.text('יעד 0'), findsNothing);
  });

  for (final heights in [
    <double>[],
    [40.0],
    [100.0, 200.0],
  ]) {
    testWidgets('אין רצועה כשכל התוכן נכנס במסך: $heights', (tester) async {
      final fixture = await _pumpList(tester, heights: heights);
      expect(_track, findsNothing);
      expect(tester.getRect(find.byType(ScrollablePositionedList)).left, 0);
      if (heights.isNotEmpty) {
        expect(tester.getTopLeft(find.text('שורה 0')).dy, 0);
      }
      _expectPhysicalThumb(tester, fixture);
    });
  }

  for (final direction in TextDirection.values) {
    testWidgets('רצועת 12px ואגודל בדופן ההתחלה: $direction', (tester) async {
      await _pumpList(tester, direction: direction);
      final track = tester.getRect(_track);
      final thumb = tester.getRect(_thumb);
      final content = tester.getRect(find.byType(ScrollablePositionedList));
      expect(track.width, 12);
      if (direction == TextDirection.rtl) {
        expect(track.right, 800);
        expect(track.right - thumb.right, 2);
        expect(content.right, 788);
      } else {
        expect(track.left, 0);
        expect(thumb.left - track.left, 2);
        expect(content.left, 12);
      }
    });
  }

  for (final paneOnRight in [false, true]) {
    testWidgets('ידית חלונית צד אינה מכסה את האגודל: right=$paneOnRight', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(500, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final fixture = _ListFixture(List.filled(100, 80));
      addTearDown(fixture.pixels.dispose);
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('he', 'IL'),
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          supportedLocales: const [Locale('he', 'IL')],
          home: Scaffold(
            body: AdaptiveSidePane(
              isOpen: true,
              alignment: paneOnRight
                  ? AlignmentDirectional.centerEnd
                  : AlignmentDirectional.centerStart,
              isResizable: true,
              onPaneWidthChanged: (_) {},
              onClose: () {},
              mainContent: const SizedBox.expand(),
              paneContent: ScrollablePositionedListScrollbar(
                scrollController: fixture.item,
                itemCount: 100,
                child: ScrollablePositionedList.builder(
                  itemScrollController: fixture.item,
                  scrollController: fixture.pixels,
                  itemCount: 100,
                  estimateExtent: (_, width) => 80,
                  itemBuilder: (_, index) =>
                      SizedBox(height: 80, child: Text('שורה $index')),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final pane = tester.getRect(
        find.byType(ScrollablePositionedListScrollbar),
      );
      final thumb = tester.getRect(_thumb);
      final handle = tester.getRect(find.byType(ResizableDragHandle));
      expect(handle.contains(thumb.center), isFalse);
      expect(thumb.center.dx, greaterThan(pane.center.dx));
      final grip = tester.getRect(
        find.descendant(
          of: find.byType(ResizableDragHandle),
          matching: find.byType(AnimatedContainer),
        ),
      );
      expect(
        grip.center.dx,
        closeTo(paneOnRight ? pane.left : pane.right, 0.5),
      );
    });
  }

  testWidgets('מיקום בסוף רשימה נשאר פיזי והמסילה נשארת גלויה', (tester) async {
    final fixture = await _pumpList(
      tester,
      heights: List.generate(40, (index) => index.isEven ? 80 : 350),
    );
    fixture.pixels.jumpTo(fixture.pixels.position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(_track, findsOneWidget);
    _expectPhysicalThumb(tester, fixture);
    expect(tester.getRect(_thumb).bottom, closeTo(600, 0.01));
  });

  testWidgets('אומדנים טובים מונעים נסיגה ונשימה בגבהים משתנים', (
    tester,
  ) async {
    final fixture = await _pumpList(
      tester,
      heights: List.generate(
        200,
        (index) => const [40.0, 90.0, 240.0, 60.0, 150.0, 320.0][index % 6],
      ),
    );
    final height = tester.getRect(_thumb).height;
    var top = tester.getRect(_thumb).top;
    for (var i = 0; i < 100; i++) {
      fixture.pixels.jumpTo(
        math.min(
          fixture.pixels.offset + 30,
          fixture.pixels.position.maxScrollExtent,
        ),
      );
      await tester.pumpAndSettle();
      _expectPhysicalThumb(tester, fixture);
      expect(tester.getRect(_thumb).top, greaterThanOrEqualTo(top - 0.01));
      expect(tester.getRect(_thumb).height, closeTo(height, 0.01));
      top = tester.getRect(_thumb).top;
    }
  });

  testWidgets('גם אומדנים שמשתנים מקבלים יחס ממטריקות הפיקסלים הנוכחיות', (
    tester,
  ) async {
    final fixture = await _pumpList(
      tester,
      accurateEstimates: false,
      heights: List.generate(200, (index) => index.isEven ? 40 : 700),
    );
    for (var i = 0; i < 30; i++) {
      fixture.pixels.jumpTo(
        math.min(
          fixture.pixels.offset + 100,
          fixture.pixels.position.maxScrollExtent,
        ),
      );
      await tester.pumpAndSettle();
      _expectPhysicalThumb(tester, fixture);
    }
  });

  for (final reverse in [false, true]) {
    for (final estimatedHeight in [50.0, 200.0]) {
      for (final flushOnRelease in [false, true]) {
        testWidgets(
          'גרירה נשארת יחסית אחרי שינוי אומדנים: '
          'height=$estimatedHeight reverse=$reverse release=$flushOnRelease',
          (tester) async {
            final fixture = await _pumpList(
              tester,
              heights: List.filled(1000, 100.0),
              reverse: reverse,
            );
            final position = fixture.pixels.position;
            fixture.pixels.jumpTo(position.maxScrollExtent / 2);
            await tester.pumpAndSettle();
            final gesture = await tester.startGesture(
              tester.getRect(_thumb).center,
              kind: PointerDeviceKind.mouse,
            );
            await gesture.moveBy(const Offset(0, 40));
            await tester.pump(const Duration(milliseconds: 16));

            final listController = fixture.item.listController!;
            final beforeUpdate = position.pixels;
            final anchor = listController.anchor!;
            final oldRange =
                position.maxScrollExtent - position.minScrollExtent;
            final update = listController.updateEstimatedExtents({
              for (var index = 600; index < 1000; index++)
                index: estimatedHeight,
            });
            await tester.pump(const Duration(milliseconds: 16));
            await update;
            expect(position.pixels, closeTo(beforeUpdate, 0.01));
            expect(listController.anchor!.index, anchor.index);
            expect(
              listController.anchor!.offsetInItem,
              closeTo(anchor.offsetInItem, 0.01),
            );
            final newRange =
                position.maxScrollExtent - position.minScrollExtent;
            expect(
              newRange,
              closeTo(oldRange + 400 * (estimatedHeight - 100), 0.01),
            );

            final movementRange =
                tester.getRect(_track).height - tester.getRect(_thumb).height;
            final pixelsPerDragPixel =
                (reverse ? -1 : 1) * newRange / movementRange;
            await gesture.moveBy(const Offset(0, 1));
            final firstTarget = beforeUpdate + pixelsPerDragPixel;
            expect(position.pixels, closeTo(firstTarget, 0.01));
            for (var i = 0; i < 10; i++) {
              await gesture.moveBy(const Offset(0, 0.25));
            }
            expect(position.pixels, closeTo(firstTarget, 0.01));
            final lastTarget = beforeUpdate + 3.5 * pixelsPerDragPixel;
            if (flushOnRelease) {
              await gesture.up();
              expect(position.pixels, closeTo(lastTarget, 0.01));
            } else {
              await tester.pump(const Duration(milliseconds: 16));
              expect(position.pixels, closeTo(lastTarget, 0.01));
              await gesture.up();
            }
            await tester.pumpAndSettle();
            expect(position.pixels, closeTo(lastTarget, 0.01));
            _expectPhysicalThumb(tester, fixture);
          },
        );
      }
    }
  }

  for (final reverse in [false, true]) {
    testWidgets(
      'יעד גרירה ממתין שומר מקור אחרי שינוי אומדנים לפניו: reverse=$reverse',
      (tester) async {
        final fixture = await _pumpList(
          tester,
          heights: List.filled(1000, 100.0),
          reverse: reverse,
        );
        final position = fixture.pixels.position;
        fixture.pixels.jumpTo(position.maxScrollExtent / 2);
        await tester.pumpAndSettle();
        final gesture = await tester.startGesture(
          tester.getRect(_thumb).center,
          kind: PointerDeviceKind.mouse,
        );
        await gesture.moveBy(const Offset(0, 40));
        await tester.pump(const Duration(milliseconds: 16));

        final listController = fixture.item.listController!;
        final source = find.text('שורה ${listController.anchor!.index + 3}');
        final sourceTop = tester.getTopLeft(source).dy;
        expect(sourceTop, inExclusiveRange(0, position.viewportDimension));
        final beforeDrag = position.pixels;
        final range = position.maxScrollExtent - position.minScrollExtent;
        final movementRange =
            tester.getRect(_track).height - tester.getRect(_thumb).height;
        final distance = 0.75 * range / movementRange;
        expect(sourceTop - distance, greaterThanOrEqualTo(0));
        await gesture.moveBy(const Offset(0, 0.5));
        final immediateTarget = position.pixels;
        for (var i = 0; i < 10; i++) {
          await gesture.moveBy(const Offset(0, 0.025));
        }
        expect(position.pixels, immediateTarget);
        final update = listController.updateEstimatedExtents({
          for (var index = 0; index < 200; index++) index: 150,
        });
        await tester.pump(const Duration(milliseconds: 16));
        await update;
        expect(
          position.pixels,
          closeTo(beforeDrag + (reverse ? -distance : distance) + 10000, 0.01),
        );
        expect(
          tester.getTopLeft(source).dy,
          closeTo(sourceTop - distance, 0.01),
        );
        await gesture.up();
        await tester.pumpAndSettle();
        expect(
          tester.getTopLeft(source).dy,
          closeTo(sourceTop - distance, 0.01),
        );
        _expectPhysicalThumb(tester, fixture);
      },
    );
  }

  for (final reverse in [false, true]) {
    for (final flushOnRelease in [false, true]) {
      testWidgets(
        'תיקון pixels מעביר יעד ממתין למערכת החדשה: '
        'reverse=$reverse release=$flushOnRelease',
        (tester) async {
          final fixture = await _pumpList(
            tester,
            heights: List.filled(1000, 100.0),
            reverse: reverse,
          );
          final position = fixture.pixels.position;
          fixture.pixels.jumpTo(position.maxScrollExtent / 2);
          await tester.pumpAndSettle();
          final gesture = await tester.startGesture(
            tester.getRect(_thumb).center,
            kind: PointerDeviceKind.mouse,
          );
          await gesture.moveBy(const Offset(0, 40));
          await tester.pump(const Duration(milliseconds: 16));
          final beforeDrag = position.pixels;
          final range = position.maxScrollExtent - position.minScrollExtent;
          final movementRange =
              tester.getRect(_track).height - tester.getRect(_thumb).height;
          final distance = (reverse ? -1 : 1) * 3.5 * range / movementRange;
          await gesture.moveBy(const Offset(0, 1));
          final immediateTarget = position.pixels;
          for (var i = 0; i < 10; i++) {
            await gesture.moveBy(const Offset(0, 0.25));
          }
          expect(position.pixels, immediateTarget);

          position.correctBy(10000);
          final context = tester.element(find.byType(ScrollablePositionedList));
          ScrollMetricsNotification(
            metrics: position.copyWith(),
            context: context,
          ).dispatch(context);
          expect(position.pixels, immediateTarget + 10000);
          final target = beforeDrag + distance + 10000;
          if (flushOnRelease) {
            await gesture.up();
            expect(position.pixels, closeTo(target, 0.01));
          } else {
            await tester.pump(const Duration(milliseconds: 16));
            expect(position.pixels, closeTo(target, 0.01));
            await gesture.up();
          }
          await tester.pumpAndSettle();
          expect(position.pixels, closeTo(target, 0.01));
          _expectPhysicalThumb(tester, fixture);
        },
      );
    }
  }

  for (final reverse in [false, true]) {
    for (final bottom in [false, true]) {
      for (final returnBeforeRelease in [false, true]) {
        testWidgets(
          returnBeforeRelease
              ? 'קצה ממתין וחזרה 1px נוחתים ליד הקצה: '
                    'reverse=$reverse bottom=$bottom'
              : 'גרירה לקצה אחרי הגדלת טווח מגיעה לקצה התוכן: '
                    'reverse=$reverse bottom=$bottom',
          (tester) async {
            final fixture = await _pumpList(
              tester,
              heights: List.filled(1000, 100.0),
              reverse: reverse,
            );
            final position = fixture.pixels.position;
            fixture.pixels.jumpTo(position.maxScrollExtent / 2);
            await tester.pumpAndSettle();
            final gesture = await tester.startGesture(
              tester.getRect(_thumb).center,
              kind: PointerDeviceKind.mouse,
            );
            await gesture.moveBy(const Offset(0, 40));
            await tester.pump(const Duration(milliseconds: 16));
            final beforeUpdate = position.pixels;
            final update = fixture.item.listController!.updateEstimatedExtents({
              for (var index = 600; index < 1000; index++) index: 200,
            });
            await tester.pump(const Duration(milliseconds: 16));
            await update;
            expect(position.pixels, closeTo(beforeUpdate, 0.01));

            final track = tester.getRect(_track);
            final movementRange = track.height - tester.getRect(_thumb).height;
            final pixelsPerDragPixel =
                (position.maxScrollExtent - position.minScrollExtent) /
                movementRange;
            final firstTarget =
                position.pixels +
                (reverse ? -1 : 1) * (bottom ? 1 : -1) * pixelsPerDragPixel;
            if (returnBeforeRelease) {
              await gesture.moveBy(Offset(0, bottom ? 1 : -1));
              expect(position.pixels, closeTo(firstTarget, 0.01));
            }
            var target = bottom != reverse
                ? position.maxScrollExtent
                : position.minScrollExtent;
            await gesture.moveTo(
              bottom
                  ? track.bottomCenter - const Offset(0, 1)
                  : track.topCenter + const Offset(0, 1),
            );
            if (returnBeforeRelease) {
              expect(position.pixels, closeTo(firstTarget, 0.01));
              await gesture.moveBy(Offset(0, bottom ? -1 : 1));
              expect(position.pixels, closeTo(firstTarget, 0.01));
              target += bottom != reverse
                  ? -pixelsPerDragPixel
                  : pixelsPerDragPixel;
            }
            await gesture.up();
            expect(position.pixels, closeTo(target, 0.01));
            await tester.pumpAndSettle();
            if (!returnBeforeRelease) {
              expect(
                position.pixels,
                closeTo(
                  bottom != reverse
                      ? position.maxScrollExtent
                      : position.minScrollExtent,
                  0.01,
                ),
              );
            }
            _expectPhysicalThumb(tester, fixture);
          },
        );
      }
    }
  }

  testWidgets('הודעות מטריקות זהות אינן מתזמנות בנייה נוספת', (tester) async {
    final fixture = await _pumpList(tester);
    final context = tester.element(find.byType(ScrollablePositionedList));
    ScrollMetricsNotification(
      metrics: fixture.pixels.position.copyWith(),
      context: context,
    ).dispatch(context);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('הפס אינו מפעיל חישוב מיקומי פריטים בכל פריים', (tester) async {
    final fixture = await _pumpList(tester);
    fixture.pixels.jumpTo(1250);
    await tester.pumpAndSettle();
    expect(fixture.item.listController!.itemPositions.value, isEmpty);
    _expectPhysicalThumb(tester, fixture);
  });

  testWidgets('קפיצת אינדקס שקטה מעדכנת את הפס בלי positions listener', (
    tester,
  ) async {
    final fixture = await _pumpList(tester);
    final jumped = fixture.item.jumpToAsync(index: 50, offset: -23);
    await tester.pump();
    await jumped;
    await tester.pumpAndSettle();
    expect(fixture.pixels.offset, closeTo(5023, 0.01));
    expect(fixture.item.listController!.itemPositions.value, isEmpty);
    _expectPhysicalThumb(tester, fixture);
  });

  testWidgets('החלפת בקר וסילוק הרכיב באמצע גרירה אינם משאירים callbacks', (
    tester,
  ) async {
    final first = await _pumpList(tester);
    final gesture = await tester.startGesture(tester.getRect(_thumb).center);
    await gesture.moveBy(const Offset(0, 40));
    await gesture.moveBy(const Offset(0, 20));
    final second = await _pumpList(tester, heights: List.filled(40, 300));
    expect(first.pixels.hasClients, isFalse);
    expect(second.pixels.offset, 0);
    _expectPhysicalThumb(tester, second);
    await gesture.up();
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);
  });

  testWidgets('הודעות גלילה פנימיות אינן משנות את האגודל החיצוני', (
    tester,
  ) async {
    final nested = ScrollController();
    addTearDown(nested.dispose);
    final fixture = await _pumpList(
      tester,
      heights: [300, 1700],
      itemBuilder: (_, index) => index == 0
          ? SizedBox(
              height: 300,
              child: ListView.builder(
                controller: nested,
                itemCount: 100,
                itemBuilder: (_, index) => const SizedBox(height: 100),
              ),
            )
          : const SizedBox(height: 1700),
    );
    final before = tester.getRect(_thumb);
    nested.jumpTo(1000);
    await tester.pumpAndSettle();
    expect(fixture.pixels.offset, 0);
    expect(tester.getRect(_thumb), before);
    _expectPhysicalThumb(tester, fixture);
  });
}
