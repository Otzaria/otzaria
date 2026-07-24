import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// רגרסיה: בצורת הדף, שחרור הפוקוס מ-KeyboardListener של תוכן הספר חייב
/// להסתמך על [FocusNode.hasPrimaryFocus] ולא על [FocusNode.hasFocus].
///
/// ה-KeyboardListener (עם _bookContentFocusNode) עוטף את כל גוף המסך, כולל
/// פאנל החיפוש. `hasFocus` מחזיר true גם כששדה החיפוש (צאצא) ממוקד, ולכן
/// `unfocus()` המבוסס עליו הבריח את הסמן משדה החיפוש בכל הקלדה.
void main() {
  testWidgets(
    'unfocus מבוסס hasPrimaryFocus לא מבריח פוקוס משדה חיפוש (צאצא)',
    (tester) async {
      final contentNode = FocusNode(debugLabel: 'bookContent');
      final searchNode = FocusNode(debugLabel: 'search');
      addTearDown(contentNode.dispose);
      addTearDown(searchNode.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: KeyboardListener(
              focusNode: contentNode,
              onKeyEvent: (_) {},
              child: Scaffold(
                body: TextField(focusNode: searchNode),
              ),
            ),
          ),
        ),
      );

      // שדה החיפוש (צאצא) מקבל פוקוס.
      searchNode.requestFocus();
      await tester.pump();

      // ה-node של תוכן הספר "רואה" את הפוקוס של הצאצא — זה בדיוק המקור לבאג.
      expect(contentNode.hasFocus, isTrue);
      expect(contentNode.hasPrimaryFocus, isFalse);
      expect(searchNode.hasPrimaryFocus, isTrue);

      // הלוגיקה המתוקנת של ענף צורת-הדף: משחררים רק אם ה-node עצמו ממוקד.
      if (contentNode.hasPrimaryFocus) {
        contentNode.unfocus();
      }
      await tester.pump();

      // שדה החיפוש שומר על הפוקוס.
      expect(
        searchNode.hasPrimaryFocus,
        isTrue,
        reason: 'unfocus המבוסס hasFocus היה מבריח את הסמן מהשדה',
      );
    },
  );

  testWidgets(
    'כאשר ה-node עצמו ממוקד — unfocus משחרר אותו כצפוי',
    (tester) async {
      final contentNode = FocusNode(debugLabel: 'bookContent');
      addTearDown(contentNode.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: KeyboardListener(
            focusNode: contentNode,
            onKeyEvent: (_) {},
            child: const Scaffold(body: SizedBox.expand()),
          ),
        ),
      );

      contentNode.requestFocus();
      await tester.pump();
      expect(contentNode.hasPrimaryFocus, isTrue);

      if (contentNode.hasPrimaryFocus) {
        contentNode.unfocus();
      }
      await tester.pump();

      expect(contentNode.hasPrimaryFocus, isFalse);
    },
  );
}
