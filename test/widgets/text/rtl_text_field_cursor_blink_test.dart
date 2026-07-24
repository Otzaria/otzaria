import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/widgets/text/rtl_text_field.dart';

/// בודק את ניהול הבהוב הסמן של [RtlTextField]:
/// ההבהוב ממומש ע"י החלפת cursorColor בין הצבע שסופק לשקוף — חצי-מחזור של
/// 500ms, איפוס מיידי (גלוי) אחרי כל פעולה, והיעלמות הסמן אחרי 8 שניות
/// של חוסר פעילות.
void main() {
  const cursorColor = Color(0xFF123456);

  Color? currentCursorColor(WidgetTester tester) =>
      tester.widget<TextField>(find.byType(TextField)).cursorColor;

  Future<(TextEditingController, FocusNode)> pumpFocusedField(
    WidgetTester tester,
  ) async {
    final controller = TextEditingController(text: 'אבג דהו');
    final focusNode = FocusNode();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Directionality(
            textDirection: TextDirection.rtl,
            child: RtlTextField(
              controller: controller,
              focusNode: focusNode,
              cursorColor: cursorColor,
            ),
          ),
        ),
      ),
    );
    focusNode.requestFocus();
    await tester.pump();
    controller.selection = const TextSelection.collapsed(offset: 1);
    await tester.pump();
    return (controller, focusNode);
  }

  testWidgets('הסמן מהבהב: גלוי, נסתר אחרי 500ms, וחוזר חלילה', (tester) async {
    await pumpFocusedField(tester);

    expect(
      currentCursorColor(tester),
      cursorColor,
      reason: 'מיד אחרי פעולה הסמן חייב להיות גלוי',
    );

    await tester.pump(const Duration(milliseconds: 500));
    expect(
      currentCursorColor(tester),
      Colors.transparent,
      reason: 'אחרי חצי-מחזור הסמן נסתר',
    );

    await tester.pump(const Duration(milliseconds: 500));
    expect(
      currentCursorColor(tester),
      cursorColor,
      reason: 'אחרי מחזור שלם הסמן גלוי שוב',
    );
  });

  testWidgets('תזוזת סמן בחץ מאפסת את מחזור ההבהוב — הסמן נראה מיידית', (
    tester,
  ) async {
    await pumpFocusedField(tester);

    // מתקדמים לשלב ה"נסתר" של המחזור.
    await tester.pump(const Duration(milliseconds: 500));
    expect(currentCursorColor(tester), Colors.transparent);

    // חץ ימין ויזואלי (offset יורד 1 → 0) — הסמן חייב להופיע מיידית.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(
      currentCursorColor(tester),
      cursorColor,
      reason: 'תזוזת הסמן חייבת לאפס את ההבהוב למצב גלוי',
    );
  });

  testWidgets('אחרי 8 שניות של חוסר פעילות ההבהוב נעצר והסמן נעלם', (
    tester,
  ) async {
    final (controller, _) = await pumpFocusedField(tester);

    // חולפים על פני כל תקופת ההבהוב (16 חצאי-מחזור = 8 שניות).
    for (var i = 0; i < 16; i++) {
      await tester.pump(const Duration(milliseconds: 500));
    }
    expect(
      currentCursorColor(tester),
      Colors.transparent,
      reason: 'בתום תקופת ההבהוב הסמן חייב להיעלם',
    );

    // ההבהוב באמת נעצר — גם אחרי חצאי-מחזור נוספים הסמן נשאר נסתר.
    await tester.pump(const Duration(milliseconds: 500));
    expect(currentCursorColor(tester), Colors.transparent);
    await tester.pump(const Duration(milliseconds: 500));
    expect(currentCursorColor(tester), Colors.transparent);

    // פעולה חדשה מחזירה את הסמן מיידית.
    controller.selection = const TextSelection.collapsed(offset: 2);
    await tester.pump();
    expect(
      currentCursorColor(tester),
      cursorColor,
      reason: 'פעולה אחרי ההיעלמות חייבת להחזיר את הסמן',
    );
  });

  testWidgets('הקלדה מאפסת את מחזור ההבהוב', (tester) async {
    final (controller, _) = await pumpFocusedField(tester);

    await tester.pump(const Duration(milliseconds: 500));
    expect(currentCursorColor(tester), Colors.transparent);

    // שינוי טקסט (כמו הקלדה) — הסמן חוזר להיות גלוי מיידית.
    controller.text = 'אבג דהוז';
    await tester.pump();
    expect(currentCursorColor(tester), cursorColor);
  });
}
