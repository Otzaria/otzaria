import 'dart:async';

import 'package:flutter/gestures.dart' show kDoubleTapTimeout;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/windowing/app_drag_to_move_area.dart';
import 'package:otzaria/core/windowing/app_window_controller.dart';
import 'package:otzaria/core/windowing/app_virtual_window_frame.dart';
import 'package:otzaria/core/windowing/app_window_id.dart';
import 'package:otzaria/core/windowing/app_window_scope.dart';
import 'package:otzaria/core/windowing/multiview/host_window_app_window_controller.dart';
import 'package:otzaria/core/windowing/window_manager_app_window_controller.dart';
import 'package:otzaria/core/windowing/window_role.dart';
import 'package:window_manager/legacy.dart' show ResizeEdge;

import '../../test_helpers/fake_view_window.dart';
import '../../test_helpers/second_test_view.dart';

void main() {
  late StubWindowController stub;
  late FakeViewWindowNative native;

  Future<void> pumpFrame(
    WidgetTester tester, {
    Key? childKey,
    Widget? child,
  }) async {
    stub = StubWindowController(SecondTestView(tester.view));
    native = FakeViewWindowNative();
    final window = HostWindowAppWindowController(
      id: const AppWindowId('window-view-2'),
      handle: StubWindowHandle(stub, (_) {}, fakeHwnd: 5),
      onClose: () async {},
      native: native,
    );
    await tester.pumpWidget(
      AppWindowScope(
        controller: window,
        geometry: window,
        role: const AppWindowRole.view(),
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: AppVirtualWindowFrame(
            child: child ?? _Counter(key: childKey),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('הקצה העליון משנה את גודל החלון הזה, והפינות לפי המסך', (
    tester,
  ) async {
    await pumpFrame(tester);
    final width = tester.view.physicalSize.width / tester.view.devicePixelRatio;

    await tester.dragFrom(const Offset(2, 2), const Offset(0, 60));
    await tester.dragFrom(Offset(width / 2, 2), const Offset(0, 60));
    await tester.dragFrom(Offset(width - 2, 2), const Offset(0, 60));
    expect(native.resized, [
      (5, ResizeEdge.topLeft),
      (5, ResizeEdge.top),
      (5, ResizeEdge.topRight),
    ]);

    // מתחת לפס הלחיצה מגיעה לתוכן.
    await tester.dragFrom(Offset(width / 2, 40), const Offset(0, 60));
    expect(native.resized, hasLength(3));
    await tester.pump(kDoubleTapTimeout);
  });

  testWidgets('מתחת לפס של 8 פיקסלים סרגל הכותרת גורר את החלון', (
    tester,
  ) async {
    // כמו בראשי: רק 8 הפיקסלים העליונים משנים גודל, וכל השאר גורר.
    await pumpFrame(
      tester,
      child: const AppDragToMoveArea(child: SizedBox.expand()),
    );
    final width = tester.view.physicalSize.width / tester.view.devicePixelRatio;

    for (final y in [10.0, 15.0, 25.0, 35.0]) {
      await tester.dragFrom(Offset(width / 2, y), const Offset(90, 72));
      await tester.pump(kDoubleTapTimeout);
    }
    expect(native.dragged, [5, 5, 5, 5]);
    expect(native.resized, isEmpty);

    await tester.dragFrom(Offset(width / 2, 5), const Offset(0, -40));
    expect(native.resized, [(5, ResizeEdge.top)]);
    expect(native.dragged, hasLength(4));
    await tester.pump(kDoubleTapTimeout);
  });

  testWidgets('בלי פסים כשהחלון ממוקסם, והתוכן אינו נבנה מחדש', (tester) async {
    final childKey = GlobalKey<_CounterState>();
    await pumpFrame(tester, childKey: childKey);
    final state = childKey.currentState;

    stub.maximized = true;
    stub.notify();
    // המצב נשאל אסינכרונית, וה-setState נבנה בפריים שאחריו.
    await tester.pump();
    await tester.pump();
    await tester.dragFrom(const Offset(400, 2), const Offset(0, 60));
    expect(native.resized, isEmpty);
    expect(childKey.currentState, same(state));

    stub.maximized = false;
    stub.notify();
    // המצב נשאל אסינכרונית, וה-setState נבנה בפריים שאחריו.
    await tester.pump();
    await tester.pump();
    await tester.dragFrom(const Offset(400, 2), const Offset(0, 60));
    expect(native.resized, [(5, ResizeEdge.top)]);
    expect(childKey.currentState, same(state));
    await tester.pump(kDoubleTapTimeout);
  });

  testWidgets('out-of-order maximize replies cannot hide active resize edges', (
    tester,
  ) async {
    final first = Completer<bool>();
    final second = Completer<bool>();
    final window = _DelayedResizeWindow([first.future, second.future]);
    addTearDown(window.changes.dispose);

    await tester.pumpWidget(
      AppWindowScope(
        controller: window,
        geometry: const WindowManagerAppWindowController(),
        child: const Directionality(
          textDirection: TextDirection.rtl,
          child: AppVirtualWindowFrame(child: SizedBox.expand()),
        ),
      ),
    );
    expect(window.reads, 1);

    window.changes.fire();
    expect(window.reads, 2);
    second.complete(false); // Most recent state: normal, resizable.
    await tester.pump();
    first.complete(true); // Stale result: maximized, must be ignored.
    await tester.pump();

    await tester.dragFrom(const Offset(400, 2), const Offset(0, 60));
    expect(window.resizeEdges, [ResizeEdge.top]);
    await tester.pump(kDoubleTapTimeout);
  });

  testWidgets('חלון בלי שינוי גודל משלו מקבל את התוכן כמו שהוא', (
    tester,
  ) async {
    await tester.pumpWidget(
      const AppWindowScope(
        controller: WindowManagerAppWindowController(),
        geometry: WindowManagerAppWindowController(),
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: AppVirtualWindowFrame(child: SizedBox.expand()),
        ),
      ),
    );
    expect(
      find.descendant(
        of: find.byType(AppVirtualWindowFrame),
        matching: find.byType(MouseRegion),
      ),
      findsNothing,
    );
  });
}

class _Counter extends StatefulWidget {
  const _Counter({super.key});

  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}

class _DelayedResizeWindow extends Fake
    implements AppWindowController, AppWindowResizing {
  _DelayedResizeWindow(this.maximizedReplies);

  final List<Future<bool>> maximizedReplies;
  final changes = _TestWindowStateChanges();
  final resizeEdges = <ResizeEdge>[];
  int reads = 0;

  @override
  Listenable get stateChanges => changes;

  @override
  Future<bool> isMaximized() {
    reads++;
    return maximizedReplies.removeAt(0);
  }

  @override
  Future<bool> isFullScreen() async => false;

  @override
  Future<void> startResizing(ResizeEdge edge) async {
    resizeEdges.add(edge);
  }

  @override
  Future<void> maximizeVertically() async {}
}

class _TestWindowStateChanges extends ChangeNotifier {
  void fire() => notifyListeners();
}
