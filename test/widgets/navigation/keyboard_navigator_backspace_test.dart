import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/widgets/navigation/keyboard_navigator.dart';

/// issue #1061 (אותו פגם): זיהוי "שדה בפוקוס" לפי `context.widget` מחזיר
/// false גם בהקלדה בשדה, ואז Backspace בתוך שדה טקסט הפעיל את onBack.
void main() {
  testWidgets('Backspace בשדה ממוקד מוחק תו ולא מפעיל onBack', (tester) async {
    final controller = TextEditingController();
    var backCalls = 0;
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: KeyboardNavigator(
            currentTabIndex: 0,
            totalTabs: 2,
            onTabChange: (_) {},
            onBack: () => backCalls++,
            child: TextField(controller: controller),
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'אבג');
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pump();

    expect(backCalls, 0, reason: 'הקלדה בשדה — Backspace אינו "חזרה"');
    expect(controller.text, 'אב');
  });

  testWidgets('Backspace כשהפוקוס מחוץ לשדה מפעיל onBack', (tester) async {
    final buttonNode = FocusNode();
    var backCalls = 0;
    addTearDown(buttonNode.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: KeyboardNavigator(
            currentTabIndex: 0,
            totalTabs: 2,
            onTabChange: (_) {},
            onBack: () => backCalls++,
            child: ElevatedButton(
              focusNode: buttonNode,
              onPressed: () {},
              child: const Text('כפתור'),
            ),
          ),
        ),
      ),
    );

    buttonNode.requestFocus();
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pump();

    expect(backCalls, 1);
  });
}
