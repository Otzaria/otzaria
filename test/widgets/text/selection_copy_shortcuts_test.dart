import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/widgets/text/selection_copy_shortcuts.dart';

/// בודק את [SelectionCopyShortcuts]: Ctrl+C / Cmd+C מפעילים את [onCopy] בשני
/// מצבי הפוקוס — כשה-SelectableRegion ממוקד (דרך [CopySelectionTextIntent])
/// וכשהפוקוס במקום אחר בתת-העץ (דרך ה-Shortcuts המפורש).
void main() {
  testWidgets('Ctrl+C מפעיל onCopy כשהפוקוס בתת-העץ', (tester) async {
    var copyCount = 0;
    final focusNode = FocusNode();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SelectionCopyShortcuts(
            onCopy: () => copyCount++,
            child: Focus(
              focusNode: focusNode,
              autofocus: true,
              child: const Text('שלום עולם'),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    focusNode.requestFocus();
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();

    expect(copyCount, 1);
    focusNode.dispose();
  });

  testWidgets('CopySelectionTextIntent מיורט ל-onCopy', (tester) async {
    var copyCount = 0;
    late BuildContext innerContext;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SelectionCopyShortcuts(
            onCopy: () => copyCount++,
            child: Builder(
              builder: (context) {
                innerContext = context;
                return const Text('שלום עולם');
              },
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    Actions.invoke(innerContext, CopySelectionTextIntent.copy);
    await tester.pump();

    expect(copyCount, 1);
  });

  // רגרסיה: כשה-SelectableRegion עצמו ממוקד (בחירה פעילה), Ctrl+C נתפס דרך
  // מנגנון ה-override של CopySelectionTextIntent — שעובד רק אם העטיפה *מעל*
  // ה-SelectionArea. עטיפה מתחתיו לא נראית למנגנון ולכן אינה מיירטת.
  testWidgets('Ctrl+C מיורט כש-SelectionArea ממוקד והעטיפה מעליו', (
    tester,
  ) async {
    var copyCount = 0;
    final fn = FocusNode();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SelectionCopyShortcuts(
            onCopy: () => copyCount++,
            child: SelectionArea(
              focusNode: fn,
              child: const Text('שלום עולם'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    fn.requestFocus();
    await tester.pump();
    tester
        .state<SelectableRegionState>(find.byType(SelectableRegion))
        .selectAll();
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();

    expect(copyCount, 1);
    fn.dispose();
  });

  // issue #674: התסמין שדווח היה "פריט ריק בלוח הגזירים". המקור הוא
  // SelectableRegion._copy של Flutter, שכותב את הבחירה ללוח בלי לבדוק שהיא
  // אינה ריקה. שני הטסטים הבאים מתעדים את ההתנהגות בלי העטיפה ואיתה.
  group('Ctrl+C על SelectionArea בלי בחירה', () {
    late List<String?> clipboardWrites;

    void mockClipboard(WidgetTester tester) {
      clipboardWrites = <String?>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboardWrites.add((call.arguments as Map?)?['text'] as String?);
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
    }

    testWidgets('יירוט *מתחת* ל-SelectionArea אינו נראה — ההעתקה נשארת של '
        'Flutter', (tester) async {
      // זה הדפוס השבור שהוליד את #674: Actions עם CopySelectionTextIntent
      // שממוקם בתוך ה-SelectionArea. מנגנון ה-override מחפש רק כלפי מעלה,
      // ולכן רצה העתקת ברירת המחדל של Flutter — שכותבת ללוח את הבחירה בלי
      // לבדוק שהיא אינה ריקה.
      mockClipboard(tester);
      var copyCount = 0;
      final fn = FocusNode();
      addTearDown(fn.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SelectionArea(
              focusNode: fn,
              child: Actions(
                actions: <Type, Action<Intent>>{
                  CopySelectionTextIntent:
                      CallbackAction<CopySelectionTextIntent>(
                        onInvoke: (_) {
                          copyCount++;
                          return null;
                        },
                      ),
                },
                child: const Text('שלום עולם'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      fn.requestFocus();
      await tester.pump();
      tester
          .state<SelectableRegionState>(find.byType(SelectableRegion))
          .selectAll();
      await tester.pump();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();

      expect(
        copyCount,
        0,
        reason: 'יירוט מתחת ל-SelectionArea אינו נראה למנגנון ה-override',
      );
      expect(
        clipboardWrites,
        isNotEmpty,
        reason: 'במקום זאת רצה ההעתקה של Flutter, שכותבת ישירות ללוח',
      );
    });

    testWidgets('עם העטיפה — ההעתקה מנותבת ל-onCopy ולא נכתב ללוח כלום', (
      tester,
    ) async {
      mockClipboard(tester);
      var copyCount = 0;
      final fn = FocusNode();
      addTearDown(fn.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SelectionCopyShortcuts(
              // המסלול של אוצריא בודק ריקנות ומציג הודעה במקום להעתיק.
              onCopy: () => copyCount++,
              child: SelectionArea(
                focusNode: fn,
                child: const Text('שלום עולם'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      fn.requestFocus();
      await tester.pump();

      final region = tester.state<SelectableRegionState>(
        find.byType(SelectableRegion),
      );
      region.selectAll();
      await tester.pump();
      region.clearSelection();
      await tester.pump();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();

      expect(copyCount, 1, reason: 'ההעתקה חייבת לעבור דרך המסלול שלנו');
      expect(
        clipboardWrites,
        isEmpty,
        reason: 'Flutter לא יכתוב ללוח בעצמו כשהעטיפה מיירטת',
      );
    });

    testWidgets('עם בחירה פעילה — ההעתקה מנותבת ל-onCopy ולא ל-Flutter', (
      tester,
    ) async {
      mockClipboard(tester);
      var copyCount = 0;
      final fn = FocusNode();
      addTearDown(fn.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SelectionCopyShortcuts(
              onCopy: () => copyCount++,
              child: SelectionArea(
                focusNode: fn,
                child: const Text('שלום עולם'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      fn.requestFocus();
      await tester.pump();
      tester
          .state<SelectableRegionState>(find.byType(SelectableRegion))
          .selectAll();
      await tester.pump();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();

      expect(copyCount, 1);
      expect(clipboardWrites, isEmpty);
    });
  });

  testWidgets('Ctrl+X אינו מעתיק ואינו נבלע — משוחרר לקיצור הגלובלי', (
    tester,
  ) async {
    var copyCount = 0;
    final unhandled = <LogicalKeyboardKey>[];
    KeyEventResult lateHandler(KeyEvent event) {
      if (event is KeyDownEvent) unhandled.add(event.logicalKey);
      return KeyEventResult.ignored;
    }

    FocusManager.instance.addLateKeyEventHandler(lateHandler);
    addTearDown(
      () => FocusManager.instance.removeLateKeyEventHandler(lateHandler),
    );

    final fn = FocusNode();
    addTearDown(fn.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SelectionCopyShortcuts(
            onCopy: () => copyCount++,
            child: SelectionArea(
              focusNode: fn,
              child: const Text('שלום עולם'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    fn.requestFocus();
    await tester.pump();
    tester
        .state<SelectableRegionState>(find.byType(SelectableRegion))
        .selectAll();
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyX);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();

    expect(copyCount, 0);
    expect(unhandled, contains(LogicalKeyboardKey.keyX));
  });

  group('SelectionCutFallthrough', () {
    testWidgets('Ctrl+X על טקסט לקריאה בלבד אינו מעתיק ואינו נבלע', (
      tester,
    ) async {
      final clipboardWrites = <String>[];
      final unhandled = <LogicalKeyboardKey>[];
      KeyEventResult lateHandler(KeyEvent event) {
        if (event is KeyDownEvent) unhandled.add(event.logicalKey);
        return KeyEventResult.ignored;
      }

      FocusManager.instance.addLateKeyEventHandler(lateHandler);
      addTearDown(
        () => FocusManager.instance.removeLateKeyEventHandler(lateHandler),
      );
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboardWrites.add(call.arguments['text'] as String);
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );

      final fn = FocusNode();
      addTearDown(fn.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SelectionCutFallthrough(
              child: SelectionArea(
                focusNode: fn,
                child: const Text('שלום עולם'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      fn.requestFocus();
      await tester.pump();
      tester
          .state<SelectableRegionState>(find.byType(SelectableRegion))
          .selectAll();
      await tester.pump();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyX);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();

      expect(clipboardWrites, isEmpty);
      expect(unhandled, contains(LogicalKeyboardKey.keyX));
    });

    testWidgets('Ctrl+C ממשיך להעתיק כרגיל דרך פעולת ברירת המחדל', (
      tester,
    ) async {
      final clipboardWrites = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboardWrites.add(call.arguments['text'] as String);
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );

      final fn = FocusNode();
      addTearDown(fn.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SelectionCutFallthrough(
              child: SelectionArea(
                focusNode: fn,
                child: const Text('שלום עולם'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      fn.requestFocus();
      await tester.pump();
      tester
          .state<SelectableRegionState>(find.byType(SelectableRegion))
          .selectAll();
      await tester.pump();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();

      expect(clipboardWrites, ['שלום עולם']);
    });

    testWidgets('Ctrl+X בשדה קלט מקונן גוזר כרגיל', (tester) async {
      final clipboardWrites = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboardWrites.add(call.arguments['text'] as String);
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );

      final controller = TextEditingController(text: 'טקסט לגזירה');
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SelectionCutFallthrough(
              child: SelectionArea(
                child: TextField(controller: controller, autofocus: true),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      controller.selection = const TextSelection(
        baseOffset: 0,
        extentOffset: 11,
      );
      await tester.pump();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyX);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();

      expect(clipboardWrites, ['טקסט לגזירה']);
      expect(controller.text, isEmpty);
    });
  });

  group('שדה קלט מקונן תחת SelectionCopyShortcuts', () {
    for (final cut in [false, true]) {
      testWidgets('Ctrl+${cut ? 'X' : 'C'} פועל על בחירת השדה ולא על onCopy', (
        tester,
      ) async {
        final clipboardWrites = <String>[];
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async {
            if (call.method == 'Clipboard.setData') {
              clipboardWrites.add(call.arguments['text'] as String);
            }
            return null;
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            null,
          ),
        );
        var copyCount = 0;
        final controller = TextEditingController(text: 'נוסח מתוקן');
        addTearDown(controller.dispose);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SelectionCopyShortcuts(
                onCopy: () => copyCount++,
                child: SelectionArea(
                  child: TextField(controller: controller, autofocus: true),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        controller.selection = const TextSelection(
          baseOffset: 0,
          extentOffset: 4,
        );
        await tester.pump();

        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(
          cut ? LogicalKeyboardKey.keyX : LogicalKeyboardKey.keyC,
        );
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pump();

        expect(copyCount, 0);
        expect(clipboardWrites, ['נוסח']);
        expect(controller.text, cut ? ' מתוקן' : 'נוסח מתוקן');
      });
    }
  });
}
