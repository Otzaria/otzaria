import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/text_book/view/reading_viewport/reader_gesture_detector.dart';

void main() {
  testWidgets('הגלילה נשארת ברשימה שהייתה מתחת לסמן בתחילת המחווה', (
    tester,
  ) async {
    final outer = ScrollController();
    final inner = ScrollController();
    addTearDown(outer.dispose);
    addTearDown(inner.dispose);
    const innerKey = ValueKey('inner-list');
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderGestureDetector(
          beginPinch: () => null,
          endPinch: () {},
          child: ListView(
            controller: outer,
            children: [
              SizedBox(
                height: 180,
                child: Transform.scale(
                  scale: 0.5,
                  child: _list(controller: inner, key: innerKey),
                ),
              ),
              const SizedBox(height: 1500),
            ],
          ),
        ),
      ),
    );
    final atInner = tester.getCenter(find.byKey(innerKey));
    final first = await tester.createGesture(kind: PointerDeviceKind.trackpad);
    await first.panZoomStart(atInner, timeStamp: Duration.zero);
    await first.panZoomUpdate(
      atInner,
      pan: const Offset(6, -1),
      timeStamp: const Duration(milliseconds: 10),
    );
    expect(inner.offset, 0);
    await first.panZoomUpdate(
      atInner,
      pan: const Offset(7, -24),
      timeStamp: const Duration(milliseconds: 20),
    );
    expect(inner.offset, 48);
    expect(outer.offset, 0);
    await first.panZoomUpdate(
      atInner,
      pan: const Offset(6, -12),
      timeStamp: const Duration(milliseconds: 30),
    );
    expect(inner.offset, 24);
    await first.panZoomEnd(timeStamp: const Duration(milliseconds: 40));
    await tester.pumpAndSettle();

    const atOuter = Offset(400, 250);
    final second = await tester.createGesture(kind: PointerDeviceKind.trackpad);
    await second.panZoomStart(
      atOuter,
      timeStamp: const Duration(milliseconds: 50),
    );
    await second.panZoomUpdate(
      atOuter,
      pan: const Offset(0, -4),
      timeStamp: const Duration(milliseconds: 60),
    );
    expect(outer.offset, 4);
    expect(inner.offset, 24);
    await second.panZoomEnd(timeStamp: const Duration(milliseconds: 70));
    await tester.pumpAndSettle();
  });

  testWidgets('בסיום גלילה מהירה נשמרת התנופה שנתנה הרשימה', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderGestureDetector(
          beginPinch: () => null,
          endPinch: () {},
          child: _list(controller: controller),
        ),
      ),
    );
    const center = Offset(300, 250);
    final gesture = await tester.createGesture(
      kind: PointerDeviceKind.trackpad,
    );
    await gesture.panZoomStart(center, timeStamp: Duration.zero);
    for (var i = 1; i <= 6; i++) {
      await gesture.panZoomUpdate(
        center,
        pan: Offset(0, -15.0 * i),
        timeStamp: Duration(milliseconds: 10 * i),
      );
      await tester.pump();
    }
    expect(controller.offset, 90);
    await gesture.panZoomEnd(timeStamp: const Duration(milliseconds: 70));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(controller.offset, greaterThan(90));
    await tester.pumpAndSettle();
  });

  testWidgets('הסרת רשימה תוך כדי גרירה משחררת אותה ומאפשרת גלילה חדשה', (
    tester,
  ) async {
    final before = ScrollController();
    final after = ScrollController();
    final replaceList = ValueNotifier(false);
    addTearDown(before.dispose);
    addTearDown(after.dispose);
    addTearDown(replaceList.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderGestureDetector(
          beginPinch: () => null,
          endPinch: () {},
          child: ValueListenableBuilder(
            valueListenable: replaceList,
            builder: (_, replaced, _) => _list(
              controller: replaced ? after : before,
              key: ValueKey(replaced),
            ),
          ),
        ),
      ),
    );
    const center = Offset(300, 250);
    final first = await tester.createGesture(kind: PointerDeviceKind.trackpad);
    await first.panZoomStart(center);
    await first.panZoomUpdate(center, pan: const Offset(0, -10));
    expect(before.offset, 10);

    replaceList.value = true;
    await tester.pump();
    expect(before.hasClients, isFalse);
    await first.panZoomUpdate(center, pan: const Offset(0, -20));
    await first.panZoomEnd();
    expect(after.offset, 0);
    expect(tester.takeException(), isNull);

    final second = await tester.createGesture(kind: PointerDeviceKind.trackpad);
    await second.panZoomStart(center);
    await second.panZoomUpdate(center, pan: const Offset(0, -6));
    expect(after.offset, 6);
    await second.panZoomEnd();
    await tester.pumpAndSettle();
  });

  for (final pinching in [false, true]) {
    testWidgets('פירוק הקורא בזמן ${pinching ? 'צביטה' : 'גלילה'}', (
      tester,
    ) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      final zoom = <double>[];
      var ended = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: ReaderGestureDetector(
            beginPinch: () => zoom.add,
            endPinch: () => ended++,
            child: _list(controller: controller),
          ),
        ),
      );
      const center = Offset(300, 250);
      final gesture = await tester.createGesture(
        kind: PointerDeviceKind.trackpad,
      );
      await gesture.panZoomStart(center);
      await gesture.panZoomUpdate(
        center,
        pan: const Offset(0, -10),
        scale: pinching ? 1.2 : 1,
      );
      expect(controller.offset, pinching ? 0 : 10);
      expect(zoom, pinching ? [1.2] : isEmpty);

      await tester.pumpWidget(const SizedBox.shrink());
      expect(controller.hasClients, isFalse);
      await gesture.panZoomUpdate(
        center,
        pan: const Offset(0, -20),
        scale: 1.4,
      );
      await gesture.panZoomEnd();
      await tester.pumpAndSettle();

      expect(zoom, pinching ? [1.2] : isEmpty);
      expect(ended, 0);
      expect(tester.takeException(), isNull);
    });
  }
}

Widget _list({required ScrollController controller, Key? key}) =>
    ListView.builder(
      key: key,
      controller: controller,
      padding: EdgeInsets.zero,
      itemCount: 50,
      itemExtent: 50,
      itemBuilder: (_, _) => const SizedBox.expand(),
    );
