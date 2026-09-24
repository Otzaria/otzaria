import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/text_book/view/text_book_screen.dart';

void main() {
  testWidgets(
    'Alt+↓ בשדה טקסט נשאר לשדה, ובאזור בחירה עובר לקיצור (issue #1516)',
    (
      tester,
    ) async {
      final fieldFocus = FocusNode();
      final textFocus = FocusNode();
      addTearDown(fieldFocus.dispose);
      addTearDown(textFocus.dispose);
      var reached = 0;
      KeyEventResult handler(KeyEvent event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.arrowDown) {
          reached++;
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      }

      FocusManager.instance.addLateKeyEventHandler(handler);
      addTearDown(
        () => FocusManager.instance.removeLateKeyEventHandler(handler),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Focus(
              canRequestFocus: false,
              onKeyEvent: passSegmentArrowsToGlobalShortcuts,
              child: Column(
                children: [
                  TextField(focusNode: fieldFocus),
                  SelectionArea(
                    focusNode: textFocus,
                    child: const Text('טקסט הספר'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      Future<void> sendAltDown() async {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
        await tester.pump();
      }

      fieldFocus.requestFocus();
      await tester.pump();
      await sendAltDown();
      expect(reached, 0, reason: 'בשדה טקסט Alt+↓ מזיז את הסמן');

      textFocus.requestFocus();
      await tester.pump();
      await sendAltDown();
      expect(reached, 1, reason: 'באזור הבחירה Alt+↓ מגיע לקיצור הגלובלי');
    },
  );
}
