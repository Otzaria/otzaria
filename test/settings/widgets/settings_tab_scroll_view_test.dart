import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/settings/widgets/settings_tab_scroll_view.dart';

/// מתיחה אלסטית (מק) שנמחקת בפריסה מחדש הייתה הרעד של issue #1386.
void main() {
  testWidgets('מתיחה בסוף העמוד שורדת פריסה מחדש של התוכן', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    final controller = ScrollController();
    addTearDown(controller.dispose);
    var extraHeight = 0.0;
    late StateSetter rebuild;

    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            rebuild = setState;
            return Scaffold(
              body: PrimaryScrollController(
                controller: controller,
                child: SettingsTabScrollView(
                  child: Column(
                    children: [
                      for (var i = 0; i < 20; i++)
                        SizedBox(height: 50, child: Text('שורה $i')),
                      SizedBox(height: 10 + extraHeight),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
    controller.jumpTo(controller.position.maxScrollExtent);
    await tester.pump();

    final pointer = TestPointer(1, PointerDeviceKind.trackpad);
    final center = tester.getCenter(find.byType(Scaffold));
    await tester.sendEventToBinding(pointer.panZoomStart(center));
    var pan = Offset.zero;
    for (var i = 0; i < 8; i++) {
      pan += const Offset(0, -12);
      await tester.sendEventToBinding(pointer.panZoomUpdate(center, pan: pan));
      await tester.pump(const Duration(milliseconds: 8));
    }
    final position = controller.position;
    final overscrollBefore = position.pixels - position.maxScrollExtent;
    expect(overscrollBefore, greaterThan(5));

    // שינוי זעיר בגובה התוכן — כמו שורה שנבנית מחדש תחת הסמן.
    rebuild(() => extraHeight = 0.02);
    await tester.pump();

    expect(
      position.pixels - position.maxScrollExtent,
      greaterThanOrEqualTo(overscrollBefore - 0.1),
      reason: 'הפריסה מחדש מחקה את המתיחה, והמסך היה קופץ לקצה',
    );

    await tester.sendEventToBinding(pointer.panZoomEnd());
    await tester.pumpAndSettle();
    debugDefaultTargetPlatformOverride = null;
  });
}
