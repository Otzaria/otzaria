import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/pdf_book/utils/trackpad_pan_recognizer.dart';

/// בדיקות הזירה (gesture arena) של TrackpadPanRecognizer: מחוות pan של
/// לוח מגע נתבעות אצלנו ולא מגיעות ל-ScaleGestureRecognizer שמתחת
/// (שמדמה את ה-InteractiveViewer של pdfrx), ואילו pinch נמסר הלאה.
void main() {
  late List<Offset> panDeltas;
  late int panEnds;
  late int scaleUpdates;

  Widget buildHarness() {
    panDeltas = [];
    panEnds = 0;
    scaleUpdates = 0;
    return Directionality(
      textDirection: TextDirection.rtl,
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
                      ),
                      (recognizer) {},
                    ),
              },
              child: const SizedBox.expand(),
            ),
          ),
        ],
      ),
    );
  }

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
}
