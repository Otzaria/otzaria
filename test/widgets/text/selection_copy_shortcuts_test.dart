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
    await tester.pumpWidget(MaterialApp(
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
    ));
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
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SelectionCopyShortcuts(
          onCopy: () => copyCount++,
          child: Builder(builder: (context) {
            innerContext = context;
            return const Text('שלום עולם');
          }),
        ),
      ),
    ));
    await tester.pump();

    Actions.invoke(innerContext, CopySelectionTextIntent.copy);
    await tester.pump();

    expect(copyCount, 1);
  });

  // רגרסיה: כשה-SelectableRegion עצמו ממוקד (בחירה פעילה), Ctrl+C נתפס דרך
  // מנגנון ה-override של CopySelectionTextIntent — שעובד רק אם העטיפה *מעל*
  // ה-SelectionArea. עטיפה מתחתיו לא נראית למנגנון ולכן אינה מיירטת.
  testWidgets('Ctrl+C מיורט כש-SelectionArea ממוקד והעטיפה מעליו',
      (tester) async {
    var copyCount = 0;
    final fn = FocusNode();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SelectionCopyShortcuts(
          onCopy: () => copyCount++,
          child: SelectionArea(
            focusNode: fn,
            child: const Text('שלום עולם'),
          ),
        ),
      ),
    ));
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
}
