import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/widgets/misc/edge_drag_handoff.dart';

const _outerStart = 200.0;
const _innerMax = 800.0;

/// issue #3359: גלילה בשתי אצבעות בלוח מגע נתקעה ברשימה המקוננת בקצה.
void main() {
  late ScrollController outer;
  late ScrollController inner;

  setUp(() {
    outer = ScrollController(initialScrollOffset: _outerStart);
    inner = ScrollController();
  });

  tearDown(() {
    outer.dispose();
    inner.dispose();
  });

  Future<Offset> pumpNested(
    WidgetTester tester, {
    bool withOuter = true,
    bool keepCardBuilt = false,
    ValueNotifier<bool>? showCard,
    VoidCallback? onHeaderTap,
  }) async {
    final card = SizedBox(
      height: 200,
      child: EdgeDragHandoff(
        builder: (_, physics) => ListView.builder(
          controller: inner,
          physics: physics,
          itemExtent: 50,
          itemCount: 20,
          itemBuilder: (_, i) => Text('פריט $i'),
        ),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: withOuter
            ? ListView(
                controller: outer,
                // מאפשר לבדוק את הכרטיס אחרי שהתנופה הוציאה אותו מהמסך.
                scrollCacheExtent: keepCardBuilt
                    ? const ScrollCacheExtent.pixels(3000)
                    : null,
                children: [
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: onHeaderTap,
                    child: const SizedBox(height: 300),
                  ),
                  if (showCard == null)
                    card
                  else
                    ValueListenableBuilder<bool>(
                      valueListenable: showCard,
                      builder: (_, show, _) =>
                          show ? card : const SizedBox(height: 200),
                    ),
                  const SizedBox(height: 2000),
                ],
              )
            : Align(alignment: Alignment.topCenter, child: card),
      ),
    );
    return tester.getCenter(find.byType(EdgeDragHandoff));
  }

  /// [steps] הם תזוזות האצבעות; שלילי = גלילה קדימה.
  Future<void> trackpadPan(
    WidgetTester tester,
    Offset at,
    List<double> steps,
  ) async {
    final gesture = await tester.createGesture(
      kind: PointerDeviceKind.trackpad,
    );
    await gesture.panZoomStart(at);
    var pan = Offset.zero;
    for (final step in steps) {
      for (var i = 0; i < step.abs() ~/ 10; i++) {
        pan += Offset(0, step.sign * 10);
        await gesture.panZoomUpdate(at, pan: pan);
        await tester.pump();
      }
    }
    await gesture.panZoomEnd();
    await tester.pumpAndSettle();
  }

  testWidgets('לוח מגע: מחווה שמתחילה בראש הרשימה גוללת את הספר', (
    tester,
  ) async {
    final at = await pumpNested(tester);
    await trackpadPan(tester, at, [120]);

    expect(inner.offset, 0);
    expect(outer.offset, lessThan(_outerStart - 60));
  });

  testWidgets('לוח מגע: מחווה שהזיזה את הרשימה נשארת בה גם בקצה', (
    tester,
  ) async {
    final at = await pumpNested(tester);
    await trackpadPan(tester, at, [-1200]);

    expect(inner.offset, _innerMax);
    expect(outer.offset, _outerStart);
  });

  testWidgets('לוח מגע: אחרי העברה גם שינוי כיוון נשאר בספר', (tester) async {
    final at = await pumpNested(tester);
    inner.jumpTo(_innerMax);
    await tester.pump();

    final gesture = await tester.createGesture(
      kind: PointerDeviceKind.trackpad,
    );
    await gesture.panZoomStart(at);
    var pan = Offset.zero;
    for (var i = 0; i < 12; i++) {
      pan += const Offset(0, -10);
      await gesture.panZoomUpdate(at, pan: pan);
      await tester.pump();
    }
    final peak = outer.offset;
    expect(peak, greaterThan(_outerStart + 60));
    for (var i = 0; i < 6; i++) {
      pan += const Offset(0, 10);
      await gesture.panZoomUpdate(at, pan: pan);
      await tester.pump();
    }
    await gesture.panZoomEnd();
    await tester.pumpAndSettle();

    expect(inner.offset, _innerMax);
    expect(outer.offset, moreOrLessEquals(peak - 60, epsilon: 1));
  });

  testWidgets('מגע: הטלה מקצה הרשימה ממשיכה בתנופה בספר', (tester) async {
    final at = await pumpNested(tester, keepCardBuilt: true);
    inner.jumpTo(_innerMax);
    await tester.pump();

    await tester.flingFrom(at, const Offset(0, -100), 2000);
    await tester.pumpAndSettle();

    expect(inner.offset, _innerMax);
    expect(outer.offset, greaterThan(_outerStart + 200));
  });

  testWidgets('מחווה ארוכה ממשיכה גם כשהכרטיס יוצא מטווח הרשימה', (
    tester,
  ) async {
    final at = await pumpNested(tester);
    inner.jumpTo(_innerMax);
    await tester.pump();

    final gesture = await tester.createGesture(
      kind: PointerDeviceKind.trackpad,
    );
    await gesture.panZoomStart(at);
    var pan = Offset.zero;
    for (var i = 0; i < 150; i++) {
      pan += const Offset(0, -10);
      await gesture.panZoomUpdate(at, pan: pan);
      await tester.pump();
    }
    expect(outer.offset, greaterThan(_outerStart + 1450));
    await gesture.panZoomEnd();
    await tester.pumpAndSettle();
    expect(find.byType(EdgeDragHandoff), findsNothing);
  });

  testWidgets('שארית תת-פיקסלית מהקצה נחשבת קצה', (tester) async {
    final at = await pumpNested(tester);
    inner.jumpTo(_innerMax - 0.1);
    await tester.pump();

    await trackpadPan(tester, at, [-120]);

    expect(outer.offset, greaterThan(_outerStart + 60));
    expect(inner.offset, _innerMax - 0.1);
  });

  testWidgets('בלי רשימה חיצונית הרשימה מתנהגת כרגיל', (tester) async {
    final at = await pumpNested(tester, withOuter: false);
    await trackpadPan(tester, at, [60, -200]);

    expect(inner.offset, greaterThan(100));
  });

  Future<TestGesture> startHandoff(WidgetTester tester, Offset at) async {
    final gesture = await tester.createGesture(
      kind: PointerDeviceKind.trackpad,
    );
    await gesture.panZoomStart(at);
    for (var i = 1; i <= 6; i++) {
      await gesture.panZoomUpdate(at, pan: Offset(0, 10.0 * i));
      await tester.pump();
    }
    expect(outer.offset, lessThan(_outerStart));
    expect(outer.position.isScrollingNotifier.value, isTrue);
    return gesture;
  }

  testWidgets('פירוק הקורא בזמן העברה אינו מפעיל אב מושבת', (tester) async {
    final at = await pumpNested(tester);
    final gesture = await startHandoff(tester, at);
    await tester.pumpWidget(const SizedBox.shrink());
    await gesture.panZoomUpdate(at, pan: const Offset(0, 100));
    await gesture.panZoomEnd();
    await tester.pumpAndSettle();
    expect(outer.hasClients, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('הסרת הכרטיס בלבד משחררת את גרירת האב', (tester) async {
    final show = ValueNotifier(true);
    addTearDown(show.dispose);
    final at = await pumpNested(tester, showCard: show);
    final gesture = await startHandoff(tester, at);
    show.value = false;
    await tester.pump();
    expect(find.byType(EdgeDragHandoff), findsNothing);
    expect(outer.position.isScrollingNotifier.value, isFalse);
    final afterRemoval = outer.offset;
    await gesture.panZoomUpdate(at, pan: const Offset(0, 100));
    await gesture.panZoomEnd();
    await tester.pumpAndSettle();
    expect(outer.offset, afterRemoval);
    expect(tester.takeException(), isNull);
    show.value = true;
    await tester.pump();
    final next = await startHandoff(
      tester,
      tester.getCenter(find.byType(EdgeDragHandoff)),
    );
    await next.panZoomEnd();
    await tester.pumpAndSettle();
    expect(outer.offset, lessThan(afterRemoval));
    expect(outer.position.isScrollingNotifier.value, isFalse);
  });

  testWidgets('שחרור כרטיס שהוסר אינו מבטל ניווט חדש של האב', (tester) async {
    final show = ValueNotifier(true);
    addTearDown(show.dispose);
    final at = await pumpNested(tester, showCard: show);
    final gesture = await startHandoff(tester, at);
    tester.binding.addPostFrameCallback((_) {
      outer.animateTo(
        800,
        duration: const Duration(milliseconds: 200),
        curve: Curves.linear,
      );
    });
    show.value = false;
    await tester.pump();
    await gesture.panZoomEnd();
    await tester.pumpAndSettle();
    expect(outer.offset, 800);
    expect(outer.position.isScrollingNotifier.value, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('גרירת לוח מגע מועברת אינה בולעת קליק עכבר בספר', (tester) async {
    var clicks = 0;
    final at = await pumpNested(tester, onHeaderTap: () => clicks++);
    final gesture = await startHandoff(tester, at);
    await tester.tapAt(const Offset(400, 50), kind: PointerDeviceKind.mouse);
    await tester.pump();
    expect(clicks, 1);
    await gesture.panZoomEnd();
    await tester.pumpAndSettle();
    expect(outer.position.isScrollingNotifier.value, isFalse);
  });

  testWidgets('ביטול מגע מועבר משחרר את פעילות האב', (tester) async {
    final at = await pumpNested(tester);
    final gesture = await tester.startGesture(at);
    for (var i = 0; i < 6; i++) {
      await gesture.moveBy(const Offset(0, 20));
      await tester.pump();
    }
    expect(outer.offset, lessThan(_outerStart));
    expect(outer.position.isScrollingNotifier.value, isTrue);
    await gesture.cancel();
    await tester.pumpAndSettle();
    expect(outer.position.isScrollingNotifier.value, isFalse);
    expect(tester.takeException(), isNull);
  });
}
