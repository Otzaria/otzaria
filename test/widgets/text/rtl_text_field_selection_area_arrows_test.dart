import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/widgets/text/rtl_text_field.dart';

void main() {
  // #5868: חץ למעלה/למטה בשדה שמתחת ל-SelectionArea זרק TypeError.
  testWidgets('חיצים אנכיים בשדה בתוך SelectionArea מזיזים ובוחרים', (
    tester,
  ) async {
    final controller = TextEditingController(text: 'אבג\nדהו');
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SelectionArea(
            child: RtlTextField(controller: controller, maxLines: null),
          ),
        ),
      ),
    );
    await tester.tap(find.byType(TextField));
    await tester.pump();
    controller.selection = const TextSelection.collapsed(offset: 1);
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(
      (controller.selection.baseOffset, controller.selection.extentOffset),
      (5, 5),
    );

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    expect(
      (controller.selection.baseOffset, controller.selection.extentOffset),
      (5, 1),
    );
  });
}
