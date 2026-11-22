import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/shortcuts/shortcut_helper.dart';
import 'package:otzaria/widgets/misc/ctrl_wheel_zoom.dart';

/// On Mac browsers zoom with Cmd + wheel; Ctrl + wheel is the system
/// accessibility zoom there. Other platforms keep Ctrl only (Win + wheel is
/// not a zoom key).
void main() {
  late List<bool> zooms;

  tearDown(() => ShortcutHelper.isMacForTesting = null);

  Future<void> pumpZoom(WidgetTester tester) async {
    zooms = [];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CtrlWheelZoom(
            onZoom: zooms.add,
            child: ListView.builder(
              itemCount: 100,
              itemBuilder: (_, i) => SizedBox(height: 50, child: Text('$i')),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> wheel(WidgetTester tester, double dy) async {
    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    pointer.hover(tester.getCenter(find.byType(ListView)));
    await tester.sendEventToBinding(pointer.scroll(Offset(0, dy)));
    await tester.pump();
  }

  testWidgets('Mac: Cmd + wheel zooms', (tester) async {
    ShortcutHelper.isMacForTesting = true;
    await pumpZoom(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);

    await wheel(tester, -100);

    expect(zooms, [true]);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
  });

  testWidgets('Mac: Ctrl + wheel still zooms', (tester) async {
    ShortcutHelper.isMacForTesting = true;
    await pumpZoom(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);

    await wheel(tester, 100);

    expect(zooms, [false]);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  });

  testWidgets('Mac: Cmd + Shift + wheel is left to the scrollable', (
    tester,
  ) async {
    ShortcutHelper.isMacForTesting = true;
    await pumpZoom(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);

    await wheel(tester, -100);

    expect(zooms, isEmpty);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
  });

  testWidgets('other platforms: Win + wheel does not zoom', (tester) async {
    ShortcutHelper.isMacForTesting = false;
    await pumpZoom(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);

    await wheel(tester, -100);

    expect(zooms, isEmpty);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
  });
}
