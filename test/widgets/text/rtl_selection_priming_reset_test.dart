import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/widgets/text/rtl_selection_shortcuts.dart';

// #4992: כשרק קצה ההתחלה נגלל מחוץ ל-cache extent, ה-priming זורק מתוך
// SelectableRegion (flutter/flutter#196478). הדגל חייב להתאפס בכל זאת.
void main() {
  for (final key in [
    LogicalKeyboardKey.arrowLeft,
    LogicalKeyboardKey.arrowRight,
  ]) {
    testWidgets('Shift+${key.keyLabel} that throws during priming does not '
        'leave rtlSelectionPriming set', (tester) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      String? delivered;
      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Center(
              child: SizedBox(
                width: 300,
                height: 600,
                child: RtlSelectionShortcuts(
                  child: SelectionArea(
                    onSelectionChanged: (content) {
                      if (rtlSelectionPriming) return;
                      delivered = content?.plainText;
                    },
                    child: ListView.builder(
                      controller: controller,
                      itemExtent: 40,
                      itemCount: 100,
                      itemBuilder: (_, i) => Text('שורה מספר $i בספר'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      Future<void> dragSelect(int from, int to) async {
        final gesture = await tester.startGesture(
          tester.getCenter(find.text('שורה מספר $from בספר')),
          kind: PointerDeviceKind.mouse,
        );
        await tester.pump();
        await gesture.moveTo(
          tester.getCenter(find.text('שורה מספר $to בספר')),
        );
        await gesture.up();
        await tester.pumpAndSettle();
      }

      await dragSelect(0, 13);
      controller.jumpTo(400);
      await tester.pumpAndSettle();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(key);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();
      // החריגה עצמה היא באג של Flutter ונשארת עד שהתיקון שם ייכנס ל-SDK.
      tester.takeException();

      expect(rtlSelectionPriming, isFalse);
      delivered = null;
      await dragSelect(12, 14);
      expect(delivered, isNotEmpty);
    });
  }
}
