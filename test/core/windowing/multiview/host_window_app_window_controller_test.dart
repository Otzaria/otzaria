import 'package:flutter/rendering.dart';
import 'package:otzaria/core/windowing/multiview/cocoa_view_window_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/windowing/app_window_id.dart';
import 'package:otzaria/core/windowing/multiview/host_window_app_window_controller.dart';
import 'package:window_manager/legacy.dart' show ResizeEdge;

import '../../../test_helpers/fake_view_window.dart';
import '../../../test_helpers/second_test_view.dart';

void main() {
  testWidgets('Cocoa שומר נקודות מסך גם כשלתצוגה DPR 2', (tester) async {
    final view = SecondTestView(tester.view)..devicePixelRatio = 2;
    final handle = StubWindowHandle(
      StubWindowController(view),
      (_) {},
      fakeHwnd: 7,
    );
    const native = CocoaViewWindowNative();
    var rect = const Rect.fromLTWH(-1600, 100, 800, 600);
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(CocoaViewWindowNative.defaultChannel, (
      call,
    ) async {
      if (call.method == 'setFrame') {
        final args = call.arguments as Map;
        rect = Rect.fromLTWH(
          args['x'] as double,
          args['y'] as double,
          args['width'] as double,
          args['height'] as double,
        );
      }
      if (call.method == 'frame') {
        return {
          'x': rect.left,
          'y': rect.top,
          'width': rect.width,
          'height': rect.height,
        };
      }
      if (call.method == 'visibleFrame') {
        return {'x': 0, 'y': 0, 'width': 1440, 'height': 900, 'scale': 2};
      }
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(
        CocoaViewWindowNative.defaultChannel,
        null,
      ),
    );
    final window = HostWindowAppWindowController(
      id: const AppWindowId('window-view-2'),
      handle: handle,
      onClose: () async {},
      native: native,
    );
    expect(await window.getBounds(), rect);
    const target = Rect.fromLTWH(1500, 120, 900, 700);
    await window.setBounds(target);
    expect(rect, target);
    expect(await window.getBounds(), target);
  });

  testWidgets('גבולות לוגיים לפי ה-DPR של התצוגה, ופעולות על החלון הזה', (
    tester,
  ) async {
    final view = SecondTestView(tester.view)..devicePixelRatio = 1.5;
    final stub = StubWindowController(view);
    final handle = StubWindowHandle(stub, (_) {}, fakeHwnd: 7);
    final native = FakeViewWindowNative()
      ..rects[7] = const Rect.fromLTWH(300, 150, 1200, 900)
      ..area = const Rect.fromLTWH(0, 0, 3000, 2000);
    var closes = 0;
    final window = HostWindowAppWindowController(
      id: const AppWindowId('window-view-2'),
      handle: handle,
      onClose: () async => closes++,
      native: native,
    );

    expect(await window.getBounds(), const Rect.fromLTWH(200, 100, 800, 600));
    await window.setBounds(const Rect.fromLTWH(10, 20, 400, 300));
    expect(native.rects[7], const Rect.fromLTWH(15, 30, 600, 450));
    await window.setSize(const Size(800, 600));
    expect(native.rects[7], const Rect.fromLTWH(15, 30, 1200, 900));
    await window.center();
    expect(native.rects[7]!.center, const Offset(1500, 1000));

    await window.maximize();
    expect(await window.isMaximized(), isTrue);
    await window.unmaximize();
    expect(await window.isMaximized(), isFalse);
    await window.minimize();
    expect(await window.isMinimized(), isTrue);
    // focus אינו SW_RESTORE על חלון גלוי: רק חלון ממוזער חוזר.
    await window.focus();
    expect(await window.isMinimized(), isFalse);
    expect(native.focused, [7]);
    await window.startDragging();
    expect(native.dragged, [7]);
    await window.startResizing(ResizeEdge.topLeft);
    expect(native.resized, [(7, ResizeEdge.topLeft)]);
    await window.maximizeVertically();
    expect(native.maximizedVertically, [7]);
    await window.setMinimumSize(const Size(420, 400));
    expect(
      stub.constraints,
      const BoxConstraints(minWidth: 420, minHeight: 400),
    );
    expect(await window.isVisible(), isTrue);
    expect(window.stateChanges, same(handle.changes));

    await window.close();
    expect(closes, 1);
    expect(window.quitApplication, throwsUnsupportedError);

    // אחרי ההריסה אין HWND, והשאילתות אינן זורקות.
    handle.markDestroyed();
    await window.startResizing(ResizeEdge.top);
    expect(native.resized, hasLength(1));
    expect(await window.isVisible(), isFalse);
    expect(await window.getBounds(), Rect.zero);
    expect(await window.isMaximized(), isFalse);
  });
}
