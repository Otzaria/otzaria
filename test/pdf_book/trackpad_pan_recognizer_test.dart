import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/pdf_book/utils/trackpad_pan_recognizer.dart';

/// בודק את חלוקת המחוות בין נעילת הציר, הזום ומעבר הכרטיסיות.
void main() {
  late List<Offset> panDeltas;
  late int panEnds;
  late int scaleUpdates;
  late int tabSwipeUpdates;
  late List<PointerEvent> forwardedEvents;

  Widget buildHarness({
    bool canPanHorizontally = true,
    bool forwardScaling = false,
  }) {
    panDeltas = [];
    panEnds = 0;
    scaleUpdates = 0;
    tabSwipeUpdates = 0;
    forwardedEvents = [];
    return Directionality(
      textDirection: TextDirection.rtl,
      // מדמה את מזהה ההחלקה בין כרטיסיות שעוטף את כל הכרטיסיות.
      child: RawGestureDetector(
        gestures: {
          HorizontalDragGestureRecognizer:
              GestureRecognizerFactoryWithHandlers<
                HorizontalDragGestureRecognizer
              >(
                () => HorizontalDragGestureRecognizer(
                  supportedDevices: const {PointerDeviceKind.trackpad},
                ),
                (recognizer) => recognizer.onUpdate = (_) => tabSwipeUpdates++,
              ),
        },
        child: Stack(
          children: [
            // מדמה את ה-InteractiveViewer של pdfrx שמתחת לשכבת ה-overlay.
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onScaleUpdate: (_) => scaleUpdates++,
              child: const SizedBox.expand(),
            ),
            Positioned.fill(
              child: RawGestureDetector(
                behavior: HitTestBehavior.translucent,
                gestures: {
                  TrackpadPanRecognizer:
                      GestureRecognizerFactoryWithHandlers<
                        TrackpadPanRecognizer
                      >(
                        () => TrackpadPanRecognizer(
                          onPanDelta: (delta, position) => panDeltas.add(delta),
                          onPanEnd: () => panEnds++,
                          canPanHorizontally: () => canPanHorizontally,
                          onPanZoomEvent: forwardScaling
                              ? forwardedEvents.add
                              : null,
                        ),
                        (recognizer) {},
                      ),
                },
                child: const SizedBox.expand(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> horizontalSwipe(WidgetTester tester) async {
    final gesture = await tester.createGesture(
      kind: PointerDeviceKind.trackpad,
    );
    const center = Offset(400, 300);
    await gesture.panZoomStart(center);
    for (var dx = 8.0; dx <= 80; dx += 8) {
      await gesture.panZoomUpdate(center, pan: Offset(dx, 1));
    }
    await gesture.panZoomEnd();
    await tester.pump();
  }

  testWidgets('בלי גלילה לרוחב, מחווה אופקית עוברת למעבר בין כרטיסיות', (
    tester,
  ) async {
    await tester.pumpWidget(buildHarness(canPanHorizontally: false));
    await horizontalSwipe(tester);

    expect(panDeltas, isEmpty);
    expect(tabSwipeUpdates, greaterThan(0));
  });

  testWidgets('כשיש גלילה לרוחב, מחווה אופקית מזיזה את הדף', (tester) async {
    await tester.pumpWidget(buildHarness());
    await horizontalSwipe(tester);

    expect(panDeltas, isNotEmpty);
    expect(tabSwipeUpdates, 0);
  });

  testWidgets('מחוות pan נתבעת אצלנו ולא מגיעה ל-onScaleUpdate שמתחת', (
    tester,
  ) async {
    await tester.pumpWidget(buildHarness());

    final gesture = await tester.createGesture(
      kind: PointerDeviceKind.trackpad,
    );
    const center = Offset(400, 300);
    await gesture.panZoomStart(center);
    // pan מצטבר: התזוזה הראשונה קטנה מסף התביעה, השנייה חוצה אותו.
    await gesture.panZoomUpdate(center, pan: const Offset(0, 4));
    expect(panDeltas, isEmpty);
    await gesture.panZoomUpdate(center, pan: const Offset(1, 14));
    await gesture.panZoomUpdate(center, pan: const Offset(1, 30));
    await gesture.panZoomEnd();
    await tester.pump();

    // התזוזה שנצברה עד התביעה לא נבלעת - מדווחת במלואה.
    expect(panDeltas, const [Offset(1, 14), Offset(0, 16)]);
    expect(panEnds, 1);
    expect(scaleUpdates, 0);
  });

  testWidgets('pinch נדחה אצלנו ומגיע ל-ScaleGestureRecognizer שמתחת', (
    tester,
  ) async {
    await tester.pumpWidget(buildHarness());

    final gesture = await tester.createGesture(
      kind: PointerDeviceKind.trackpad,
    );
    const center = Offset(400, 300);
    await gesture.panZoomStart(center);
    await gesture.panZoomUpdate(center, scale: 1.1);
    await gesture.panZoomUpdate(center, scale: 1.3);
    await gesture.panZoomEnd();
    await tester.pump();

    expect(panDeltas, isEmpty);
    expect(panEnds, 0);
    expect(scaleUpdates, greaterThan(0));
  });

  testWidgets('תזוזה זעירה מתחת לסף לא תובעת ולא מדווחת', (tester) async {
    await tester.pumpWidget(buildHarness());

    final gesture = await tester.createGesture(
      kind: PointerDeviceKind.trackpad,
    );
    const center = Offset(400, 300);
    await gesture.panZoomStart(center);
    await gesture.panZoomUpdate(center, pan: const Offset(0, 3));
    await gesture.panZoomEnd();
    await tester.pump();

    expect(panDeltas, isEmpty);
    expect(panEnds, 0);
  });

  testWidgets('מחווה שנייה אחרי pinch מתחילה נקייה ונתבעת כ-pan', (
    tester,
  ) async {
    await tester.pumpWidget(buildHarness());

    final gesture = await tester.createGesture(
      kind: PointerDeviceKind.trackpad,
    );
    const center = Offset(400, 300);
    await gesture.panZoomStart(center);
    await gesture.panZoomUpdate(center, scale: 1.2);
    await gesture.panZoomEnd();
    await tester.pump();

    final second = await tester.createGesture(
      kind: PointerDeviceKind.trackpad,
    );
    await second.panZoomStart(center);
    await second.panZoomUpdate(center, pan: const Offset(0, 20));
    await second.panZoomEnd();
    await tester.pump();

    expect(panDeltas, const [Offset(0, 20)]);
    expect(panEnds, 1);
  });

  testWidgets('pan שהופך ל-pinch מעביר זום ו-pan מצטברים ביחס לנקודת המעבר', (
    tester,
  ) async {
    await tester.pumpWidget(buildHarness(forwardScaling: true));
    final gesture = await tester.createGesture(
      kind: PointerDeviceKind.trackpad,
    );
    const center = Offset(400, 300);
    await gesture.panZoomStart(center);
    await gesture.panZoomUpdate(center, pan: const Offset(0, 8));
    await gesture.panZoomUpdate(center, pan: const Offset(2, 12), scale: 1.1);
    await gesture.panZoomUpdate(center, pan: const Offset(5, 20), scale: 1.3);
    await gesture.panZoomUpdate(center, pan: const Offset(9, 30), scale: 1);
    await gesture.panZoomUpdate(center, pan: const Offset(10, 40), scale: 0.8);
    await gesture.panZoomEnd();

    expect(panDeltas, const [Offset(0, 8)]);
    expect(panEnds, 1);
    expect(scaleUpdates, 0);
    expect(tabSwipeUpdates, 0);
    expect(forwardedEvents.first, isA<PointerPanZoomStartEvent>());
    expect(forwardedEvents.first.position, center);
    final updates = forwardedEvents
        .whereType<PointerPanZoomUpdateEvent>()
        .toList();
    expect(updates.map((event) => event.scale), [1.1, 1.3, 1, 0.8]);
    expect(updates.map((event) => event.pan), const [
      Offset(2, 4),
      Offset(5, 12),
      Offset(9, 22),
      Offset(10, 32),
    ]);
    expect(updates.map((event) => event.position), everyElement(center));
    expect(updates.first.panDelta, const Offset(2, 4));
    expect(forwardedEvents.last, isA<PointerPanZoomEndEvent>());
  });

  testWidgets('פירוק בזמן pan מאפס את נעילת הציר פעם אחת', (tester) async {
    await tester.pumpWidget(buildHarness());
    final gesture = await tester.createGesture(
      kind: PointerDeviceKind.trackpad,
    );
    const center = Offset(400, 300);
    await gesture.panZoomStart(center);
    await gesture.panZoomUpdate(center, pan: const Offset(0, 8));
    await tester.pumpWidget(const SizedBox.shrink());
    expect(panEnds, 1);
    await gesture.panZoomEnd();
    expect(panEnds, 1);
  });

  testWidgets('פירוק בזמן pinch שהתחיל כ-pan מבטל את המחווה המקורית', (
    tester,
  ) async {
    await tester.pumpWidget(buildHarness(forwardScaling: true));
    final gesture = await tester.createGesture(
      kind: PointerDeviceKind.trackpad,
    );
    const center = Offset(400, 300);
    await gesture.panZoomStart(center);
    await gesture.panZoomUpdate(center, pan: const Offset(0, 8));
    await gesture.panZoomUpdate(center, pan: const Offset(0, 8), scale: 1.2);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(forwardedEvents.last, isA<PointerPanZoomEndEvent>());
    expect(panEnds, 1);
    await gesture.panZoomEnd();
  });

  testWidgets('מחווה חדשה מסיימת pinch שנקטע ומתעלמת מהסיום המאוחר שלו', (
    tester,
  ) async {
    await tester.pumpWidget(buildHarness(forwardScaling: true));
    final interrupted = await tester.createGesture(
      pointer: 21,
      kind: PointerDeviceKind.trackpad,
    );
    final next = await tester.createGesture(
      pointer: 22,
      kind: PointerDeviceKind.trackpad,
    );
    const center = Offset(400, 300);
    await interrupted.panZoomStart(center);
    await interrupted.panZoomUpdate(center, pan: const Offset(0, 8));
    await interrupted.panZoomUpdate(
      center,
      pan: const Offset(0, 8),
      scale: 1.2,
    );
    await next.panZoomStart(center);
    expect(forwardedEvents.last, isA<PointerPanZoomEndEvent>());
    expect(panEnds, 1);
    await next.panZoomUpdate(center, pan: const Offset(10, 0));
    await interrupted.panZoomEnd();
    await next.panZoomUpdate(center, pan: const Offset(14, 0), scale: 1.1);
    await next.panZoomEnd();

    expect(panDeltas, const [Offset(0, 8), Offset(10, 0)]);
    expect(panEnds, 2);
    expect(
      forwardedEvents.whereType<PointerPanZoomUpdateEvent>().map(
        (event) => event.scale,
      ),
      [1.2, 1.1],
    );
    expect(scaleUpdates, 0);
    expect(tabSwipeUpdates, 0);
  });

  testWidgets('pinch מתחילת המחווה נשאר ב-pdfrx בלי העברה כפולה', (
    tester,
  ) async {
    await tester.pumpWidget(buildHarness(forwardScaling: true));
    final gesture = await tester.createGesture(
      kind: PointerDeviceKind.trackpad,
    );
    const center = Offset(400, 300);
    await gesture.panZoomStart(center);
    await gesture.panZoomUpdate(center, scale: 1.1);
    await gesture.panZoomUpdate(center, scale: 1.3);
    await gesture.panZoomEnd();
    expect(forwardedEvents, isEmpty);
    expect(panDeltas, isEmpty);
    expect(scaleUpdates, greaterThan(0));
  });
}
