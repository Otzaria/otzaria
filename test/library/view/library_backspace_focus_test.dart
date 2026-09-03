import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/library/view/library_browser.dart';
import 'package:otzaria/utils/ui/editable_focus.dart';
import 'package:otzaria/widgets/text/otzaria_search_field.dart';

/// issue #1061 — Backspace בשדה חיפוש הספרייה מחק את כל השורה: זיהוי
/// "שדה טקסט בפוקוס" בדק את `primaryFocus.context.widget`, אבל צומת
/// הפוקוס של TextField נקשר לווידג'ט Focus פנימי — הזיהוי החזיר false,
/// וה-Backspace סווג כ"פוקוס מחוץ לשדה" שסוגר את החיפוש כולו.
void main() {
  testWidgets('שדה החיפוש ממוקד — הזיהוי מכיר בו כשדה טקסט', (tester) async {
    final node = FocusNode(debugLabel: 'library-search');
    final controller = TextEditingController(text: 'חידושי הרשבע');
    addTearDown(() {
      node.dispose();
      controller.dispose();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OtzariaSearchField(
            controller: controller,
            hintText: 'איתור ספר',
            focusNode: node,
          ),
        ),
      ),
    );
    node.requestFocus();
    await tester.pump();
    expect(node.hasFocus, isTrue);

    expect(
      isEditableTextFocusTarget(),
      isTrue,
      reason: 'הפוקוס בשדה — Backspace חייב להישאר מחיקת תו',
    );

    expect(
      resolveLibraryBackspaceAction(
        isEditableTextFocused: isEditableTextFocusTarget(),
        isLibrarySearchFocused: node.hasFocus,
        isSearchTextEmpty: controller.text.isEmpty,
      ),
      LibraryBackspaceAction.none,
      reason: 'שדה ממוקד עם טקסט — אסור לנקות את החיפוש',
    );
  });

  testWidgets('שדה ממוקד וריק — Backspace עדיין עולה תיקייה (התנהגות #899)', (
    tester,
  ) async {
    final node = FocusNode();
    final controller = TextEditingController();
    addTearDown(() {
      node.dispose();
      controller.dispose();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OtzariaSearchField(
            controller: controller,
            hintText: 'איתור ספר',
            focusNode: node,
          ),
        ),
      ),
    );
    node.requestFocus();
    await tester.pump();

    expect(
      resolveLibraryBackspaceAction(
        isEditableTextFocused: isEditableTextFocusTarget(),
        isLibrarySearchFocused: node.hasFocus,
        isSearchTextEmpty: controller.text.isEmpty,
      ),
      LibraryBackspaceAction.navigateUp,
    );
  });

  testWidgets('הפוקוס מחוץ לכל שדה — הזיהוי מחזיר false', (tester) async {
    final buttonNode = FocusNode();
    addTearDown(buttonNode.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ElevatedButton(
            focusNode: buttonNode,
            onPressed: () {},
            child: const Text('כפתור'),
          ),
        ),
      ),
    );
    buttonNode.requestFocus();
    await tester.pump();

    expect(isEditableTextFocusTarget(), isFalse);
  });

  testWidgets('Backspace אמיתי בשדה עם טקסט מוחק תו אחד, לא את החיפוש', (
    tester,
  ) async {
    final node = FocusNode();
    final controller = TextEditingController();
    var searchCleared = false;
    addTearDown(() {
      node.dispose();
      controller.dispose();
    });

    // אותו חיווט כמו במסך הספרייה: Focus עוטף-מסך שמכריע לפי
    // resolveLibraryBackspaceAction, מעל השדה — ולכן מקבל את המקש לפניו.
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Focus(
            canRequestFocus: false,
            skipTraversal: true,
            onKeyEvent: (n, event) {
              if (event is! KeyDownEvent ||
                  event.logicalKey != LogicalKeyboardKey.backspace) {
                return KeyEventResult.ignored;
              }
              final action = resolveLibraryBackspaceAction(
                isEditableTextFocused: isEditableTextFocusTarget(),
                isLibrarySearchFocused: node.hasFocus,
                isSearchTextEmpty: controller.text.isEmpty,
              );
              if (action == LibraryBackspaceAction.clearSearch) {
                controller.clear();
                searchCleared = true;
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            child: OtzariaSearchField(
              controller: controller,
              hintText: 'איתור ספר',
              focusNode: node,
            ),
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'אבג');
    await tester.pump();
    expect(node.hasFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pump();

    expect(
      searchCleared,
      isFalse,
      reason: 'Backspace בשדה עם טקסט סווג כניקוי החיפוש כולו — issue #1061',
    );
    expect(controller.text, 'אב');
  });
}
