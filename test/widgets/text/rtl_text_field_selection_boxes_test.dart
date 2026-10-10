import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/widgets/text/rtl_text_field.dart';

void main() {
  // issue #1765: עם BoxWidthStyle.max, בטקסט RTL רב-שורתי כל בחירה בשורה
  // שאינה האחרונה מצוירת גם עד הקצה השמאלי של השדה.
  testWidgets('בחירת תו בשורה שאינה אחרונה מצוירת בתיבה אחת בלבד', (
    tester,
  ) async {
    final controller = TextEditingController(
      text:
          'שלום עולם טוב מאוד היום הזה ועוד מילים רבות כדי שהשורה '
          'תהיה ארוכה ותישבר לכמה שורות בתוך השדה הזה שלנו כאן',
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: SizedBox(
              width: 400,
              child: RtlTextField(controller: controller, maxLines: null),
            ),
          ),
        ),
      ),
    );

    final editable = tester
        .state<EditableTextState>(find.byType(EditableText))
        .renderEditable;
    const selection = TextSelection(baseOffset: 2, extentOffset: 3);
    final firstLineEnd = editable
        .getLineAtOffset(const TextPosition(offset: 2))
        .end;
    expect(firstLineEnd, lessThan(controller.text.length));

    expect(editable.getBoxesForSelection(selection), hasLength(1));
  });
}
