import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/widgets/text/rtl_text_field.dart';

/// לחיצה בסוף שורה בשדה רב-שורתי RTL צריכה להשאיר את הסמן באותה שורה
/// (otzaria issue #5747), גם עם עוקף ה-\r של #1716.
void main() {
  Widget host(Widget child) => MaterialApp(
    home: Scaffold(
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: SizedBox(width: 400, child: child),
      ),
    ),
  );

  RenderEditable renderEditable(WidgetTester tester) =>
      tester.state<EditableTextState>(find.byType(EditableText)).renderEditable;

  TextEditingController rawController(WidgetTester tester) =>
      tester.widget<EditableText>(find.byType(EditableText)).controller;

  /// לחיצת עכבר 20px משמאל לקצה החזותי של [0, lineEnd) (שורה ראשונה).
  Future<double> clickLeftOfFirstLine(WidgetTester tester, int lineEnd) async {
    final editable = renderEditable(tester);
    final boxes = editable.getBoxesForSelection(
      TextSelection(baseOffset: 0, extentOffset: lineEnd),
    );
    final left = boxes.map((box) => box.left).reduce((a, b) => a < b ? a : b);
    final lineY = (boxes.first.top + boxes.first.bottom) / 2;
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(gesture.removePointer);
    await gesture.down(
      editable.localToGlobal(
        Offset((left - 20).clamp(1, double.infinity), lineY),
      ),
    );
    await tester.pump();
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 500));
    return lineY;
  }

  double caretY(WidgetTester tester) => renderEditable(
    tester,
  ).getLocalRectForCaret(rawController(tester).selection.extent).center.dy;

  /// הקלדת תו במיקום הסמן, כפי שהמקלדת של המערכת שולחת אותו.
  Future<void> typeAtCaret(WidgetTester tester, String char) async {
    final raw = rawController(tester).value;
    final offset = raw.selection.start;
    tester.testTextInput.updateEditingValue(
      TextEditingValue(
        text: raw.text.replaceRange(offset, raw.selection.end, char),
        selection: TextSelection.collapsed(offset: offset + char.length),
      ),
    );
    await tester.pump();
  }

  group('לחיצה בסוף שורה משאירה את הסמן בשורה (issue #5747)', () {
    testWidgets('שבירת שורה קשה: הסמן נשאר בסוף השורה הראשונה', (tester) async {
      final controller = TextEditingController(text: 'שורה ראשונה\nשורה שניה');
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        host(RtlTextField(controller: controller, maxLines: null)),
      );

      final lineY = await clickLeftOfFirstLine(tester, 11);

      expect(controller.selection, const TextSelection.collapsed(offset: 11));
      expect(caretY(tester), moreOrLessEquals(lineY, epsilon: 6));
    });

    testWidgets('הקלדה אחרי הלחיצה ממשיכה את השורה ולא יוצרת שורה חדשה', (
      tester,
    ) async {
      final controller = TextEditingController(text: 'שורה ראשונה\nשורה שניה');
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        host(RtlTextField(controller: controller, maxLines: null)),
      );

      await clickLeftOfFirstLine(tester, 11);
      await typeAtCaret(tester, 'X');

      expect(controller.text, 'שורה ראשונהX\nשורה שניה');
      expect(controller.selection, const TextSelection.collapsed(offset: 12));
    });

    testWidgets('שורה מעורבת שמסתיימת באנגלית: הסמן נשאר בשורה', (
      tester,
    ) async {
      final controller = TextEditingController(text: 'שורה abc\nשורה שניה');
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        host(RtlTextField(controller: controller, maxLines: null)),
      );

      final lineY = await clickLeftOfFirstLine(tester, 8);
      await typeAtCaret(tester, 'X');

      expect(caretY(tester), moreOrLessEquals(lineY, epsilon: 6));
      expect(controller.text.split('\n'), hasLength(2));
      expect(controller.text, isNot(contains('\r')));
    });

    testWidgets('גלישה רכה: הסמן מצויר בשורה החזותית הראשונה', (tester) async {
      const text = 'אבגדה וזחטי כלמנס עפצקר שתאבג דהוזח טיכלמ';
      final controller = TextEditingController(text: text);
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        host(RtlTextField(controller: controller, maxLines: null)),
      );
      final editable = renderEditable(tester);
      final firstY = editable
          .getLocalRectForCaret(const TextPosition(offset: 0))
          .center
          .dy;
      var wrap = 1;
      while (editable
              .getLocalRectForCaret(TextPosition(offset: wrap))
              .center
              .dy <
          firstY + 2) {
        wrap++;
      }

      final lineY = await clickLeftOfFirstLine(tester, wrap);

      expect(controller.selection.baseOffset, wrap);
      expect(caretY(tester), moreOrLessEquals(lineY, epsilon: 6));
    });
  });
}
