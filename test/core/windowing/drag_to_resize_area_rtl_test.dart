import 'package:flutter/gestures.dart' show kDoubleTapTimeout;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:window_manager/legacy.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final resizedEdges = <String>[];

  setUp(() {
    resizedEdges.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('window_manager'), (
          call,
        ) async {
          if (call.method == 'startResizing') {
            resizedEdges.add((call.arguments as Map)['resizeEdge'] as String);
          }
          return false;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('window_manager'), null);
  });

  // #3187: תחת RTL של האפליקציה, גרירת הקצה השמאלי שינתה את הקצה הימני.
  testWidgets('קצוות שינוי הגודל לפי המסך גם תחת RTL', (tester) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.rtl,
        child: DragToResizeArea(child: SizedBox.expand()),
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

    expect(resizedEdges, ['left', 'right', 'topLeft', 'bottomRight']);
  });
}
