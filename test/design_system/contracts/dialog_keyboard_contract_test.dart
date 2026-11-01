import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/widgets/misc/keyboard_dialog_navigation.dart';
import 'package:otzaria/widgets/widgets_exports.dart';

import 'contract_harness.dart';

void main() {
  group('DialogKeyboardNavigator', () {
    late int confirms;
    late int cancels;
    late List<int> focusChanges;
    late FocusNode inner;
    late FocusNode textField;

    setUp(() {
      confirms = 0;
      cancels = 0;
      focusChanges = [];
      inner = FocusNode();
      textField = FocusNode();
    });

    tearDown(() {
      inner.dispose();
      textField.dispose();
    });

    Future<void> pump(
      WidgetTester tester, {
      required int focusedIndex,
      bool handleEnterKey = true,
    }) async {
      await pumpInApp(
        tester,
        DialogKeyboardNavigator(
          focusedIndex: focusedIndex,
          onFocusChange: focusChanges.add,
          onConfirm: () => confirms++,
          onCancel: () => cancels++,
          textFieldFocusNode: textField,
          handleEnterKey: handleEnterKey,
          child: Column(
            children: [
              Focus(focusNode: inner, child: const Text('פנימי')),
              Focus(focusNode: textField, child: const Text('שדה')),
            ],
          ),
        ),
      );
      inner.requestFocus();
      await tester.pump();
    }

    testWidgets('Enter על אינדקס 1 מאשר', (tester) async {
      await pump(tester, focusedIndex: 1);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect((confirms, cancels), (1, 0));
    });

    testWidgets('Enter על אינדקס 0 מבטל', (tester) async {
      await pump(tester, focusedIndex: 0);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect((confirms, cancels), (0, 1));
    });

    testWidgets('Enter מכל רכיב פנימי שאינו שדה הטקסט מופעל על הדיאלוג', (
      tester,
    ) async {
      await pump(tester, focusedIndex: 1);
      expect(inner.hasPrimaryFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(confirms, 1);
    });

    testWidgets('handleEnterKey=false מתעלם מ-Enter', (tester) async {
      await pump(tester, focusedIndex: 1, handleEnterKey: false);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect((confirms, cancels), (0, 0));
    });

    testWidgets('Escape מבטל', (tester) async {
      await pump(tester, focusedIndex: 1);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      expect((confirms, cancels), (0, 1));
    });

    testWidgets('שני החיצים האופקיים מחליפים בין 0 ל-1', (tester) async {
      await pump(tester, focusedIndex: 1);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      expect(focusChanges, [0, 0]);
    });

    testWidgets('Enter בשדה הטקסט מאשר גם כשהאינדקס 0', (tester) async {
      await pump(tester, focusedIndex: 0);
      textField.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect((confirms, cancels), (1, 0));
    });

    testWidgets('בשדה הטקסט Escape וחיצים עוברים הלאה', (tester) async {
      await pump(tester, focusedIndex: 1);
      textField.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      expect((confirms, cancels), (0, 0));
      expect(focusChanges, isEmpty);
    });
  });

  group('AppDialog — מקלדת', () {
    testWidgets('twoActions: Enter מחזיר true', (tester) async {
      final outcome = await showInApp<bool>(
        tester,
        const AppDialog.twoActions(title: 'כותרת', content: 'תוכן'),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(outcome.closed, isTrue);
      expect(outcome.value, isTrue);
    });

    testWidgets('twoActions: Escape מחזיר false', (tester) async {
      final outcome = await showInApp<bool>(
        tester,
        const AppDialog.twoActions(title: 'כותרת', content: 'תוכן'),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(outcome.closed, isTrue);
      expect(outcome.value, isFalse);
    });

    testWidgets('warning: Enter מחזיר false (הביטול ממוקד)', (tester) async {
      final outcome = await showInApp<bool>(
        tester,
        const AppDialog.warning(title: 'כותרת', content: 'תוכן'),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(outcome.value, isFalse);
    });

    testWidgets('warning: חץ ואז Enter מחזיר true', (tester) async {
      final outcome = await showInApp<bool>(
        tester,
        const AppDialog.warning(title: 'כותרת', content: 'תוכן'),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(outcome.value, isTrue);
    });

    testWidgets('twoActions עם handleEnterKey=false: Enter לא סוגר', (
      tester,
    ) async {
      final outcome = await showInApp<bool>(
        tester,
        const AppDialog.twoActions(
          title: 'כותרת',
          content: 'תוכן',
          handleEnterKey: false,
        ),
      );
      // הפוקוס על כפתור האישור; Enter עובר ל-Shortcuts של האפליקציה ומפעיל אותו.
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(outcome.value, isTrue);
    });
  });

  group('AppCustomContentDialog — מקלדת', () {
    const focusedBody = Focus(autofocus: true, child: Text('גוף'));

    testWidgets('בלי onConfirm Enter לא סוגר ו-Escape סוגר', (tester) async {
      final outcome = await showInApp<void>(
        tester,
        const AppCustomContentDialog(title: 'רשימה', child: focusedBody),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(outcome.closed, isFalse);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(outcome.closed, isTrue);
    });

    for (final handleEnterKey in [false, true]) {
      testWidgets('onConfirm עם handleEnterKey=$handleEnterKey', (
        tester,
      ) async {
        var confirms = 0;
        await showInApp<void>(
          tester,
          AppCustomContentDialog(
            title: 'רשימה',
            onConfirm: () => confirms++,
            handleEnterKey: handleEnterKey,
            child: focusedBody,
          ),
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        expect(confirms, handleEnterKey ? 1 : 0);
      });
    }

    testWidgets('בלי רכיב ממוקד בתוכן Enter לא מגיע ל-onConfirm', (
      tester,
    ) async {
      var confirms = 0;
      await showInApp<void>(
        tester,
        AppCustomContentDialog(
          title: 'רשימה',
          onConfirm: () => confirms++,
          handleEnterKey: true,
          child: const Text('גוף'),
        ),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(confirms, 0);
    });

    testWidgets('canDismiss=false: Escape לא סוגר', (tester) async {
      final outcome = await showInApp<void>(
        tester,
        const AppCustomContentDialog(
          title: 'רשימה',
          canDismiss: false,
          child: focusedBody,
        ),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(outcome.closed, isFalse);
    });
  });

  group('SelectionDialog — מקלדת', () {
    const items = [
      SelectionItem(label: 'אלף', value: 1),
      SelectionItem(label: 'בית', value: 2),
    ];

    testWidgets('לחיצה על פריט מחזירה את ערכו', (tester) async {
      final outcome = await showInApp<int>(
        tester,
        const SelectionDialog<int>(title: 'בחירה', items: items),
      );
      await tester.tap(find.text('בית'));
      await tester.pumpAndSettle();
      expect(outcome.value, 2);
    });

    testWidgets('Enter בשדה החיפוש לא סוגר', (tester) async {
      final outcome = await showInApp<int>(
        tester,
        const SelectionDialog<int>(title: 'בחירה', items: items),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(outcome.closed, isFalse);
    });

    testWidgets('Enter על פריט ממוקד סוגר עם null ולא בוחר אותו', (
      tester,
    ) async {
      final outcome = await showInApp<int>(
        tester,
        const SelectionDialog<int>(title: 'בחירה', items: items),
      );
      Focus.of(tester.element(find.text('בית'))).requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(outcome.closed, isTrue);
      expect(outcome.value, isNull);
    });
  });
}
