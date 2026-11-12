import 'package:flutter/gestures.dart' show kDoubleTapTimeout;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:window_manager/window_manager.dart';

/// The 0.6 nativeapi drag widget addresses an explicit native window rather
/// than invoking the removed window_manager MethodChannel.
class _TrackingWindow extends Window {
  _TrackingWindow() : super.borrowed(0);

  final resizedEdges = <ResizeEdge>[];

  @override
  void startResizing(ResizeEdge edge) => resizedEdges.add(edge);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // #3187: physical screen edges must remain stable under RTL.
  testWidgets('resizing still targets physical edges under RTL', (
    tester,
  ) async {
    final window = _TrackingWindow();
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.rtl,
        child: DragToResizeArea(window: window, child: const SizedBox.expand()),
      ),
    );
    final size = tester.view.physicalSize / tester.view.devicePixelRatio;

    await tester.dragFrom(Offset(2, size.height / 2), const Offset(-40, 0));
    await tester.dragFrom(
      Offset(size.width - 2, size.height / 2),
      const Offset(40, 0),
    );
    await tester.dragFrom(const Offset(2, 2), const Offset(-40, -40));
    await tester.dragFrom(
      Offset(size.width - 2, size.height - 2),
      const Offset(40, 40),
    );

    await tester.pump(kDoubleTapTimeout);

    expect(window.resizedEdges, [
      ResizeEdge.left,
      ResizeEdge.right,
      ResizeEdge.topLeft,
      ResizeEdge.bottomRight,
    ]);
  });
}
