import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/widgets/layout/context_overlay_panel.dart';
import 'package:otzaria/widgets/layout/floating_panel.dart';
import 'package:otzaria/widgets/layout/resizable_drag_handle.dart';

// בחלון צר מרוחב הפאנל השמור הפאנל מוצג מצומצם. הידית חייבת להיות כולה בתוך
// החלון, והגרירה הראשונה חייבת לשנות את הרוחב המוצג (בלי "אזור מת").

Future<void> _pump(WidgetTester tester, {double windowWidth = 300}) async {
  tester.view.physicalSize = Size(windowWidth, 600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Stack(
          children: [
            const SizedBox.expand(),
            ContextOverlayPanel(
              isOpen: true,
              onClose: () {},
              child: const Text('x'),
            ),
          ],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('חלון 300: הידית כולה בתוך החלון', (tester) async {
    await _pump(tester);

    final handle = tester.getRect(find.byType(ResizableDragHandle));
    expect(handle.left, greaterThanOrEqualTo(0));
    expect(handle.right, lessThanOrEqualTo(300));
    expect(handle.width, handleHitSize(tester.element(find.byType(Text))));
  });

  testWidgets('חלון 300: הגרירה הראשונה משנה את הרוחב המוצג', (tester) async {
    await _pump(tester);

    final panel = find.byType(FloatingPanel);
    expect(tester.getSize(panel).width, 280);

    final handle = tester.getRect(find.byType(ResizableDragHandle));
    await tester.dragFrom(handle.center, const Offset(-16, 0));
    await tester.pumpAndSettle();

    expect(tester.getSize(panel).width, 264);
  });

  testWidgets('חלון רחב: מיקום הידית ללא שינוי (קצה הפאנל פחות 4)', (
    tester,
  ) async {
    await _pump(tester, windowWidth: 1000);

    final handle = tester.getRect(find.byType(ResizableDragHandle));
    // RTL: הפאנל בשמאל, 10 שוליים + 350 רוחב - kPaneHandleInnerReach.
    expect(handle.left, 10 + 350 - kPaneHandleInnerReach);
  });
}
