import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/widgets/text/rtl_selection_shortcuts.dart';

// issue #4992 (flutter/flutter#196478): קצה בחירה שנגלל הרחק מהתצוגה נשאר בלי
// מיקום, ו-Shift+חץ זרק Null check מתוך SelectableRegion.
void main() {
  const keys = [
    LogicalKeyboardKey.arrowDown,
    LogicalKeyboardKey.arrowUp,
    LogicalKeyboardKey.arrowLeft,
    LogicalKeyboardKey.arrowRight,
  ];

  Future<ValueGetter<String?>> pumpAndSelect(
    WidgetTester tester,
    ScrollController controller, {
    required int lastLine,
  }) async {
    String? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Center(
            child: SizedBox(
              width: 300,
              height: 600,
              // כמו ב-AppSelectionArea: ה-wrapper מעל ה-SelectionArea.
              child: RtlSelectionShortcuts(
                child: SelectionArea(
                  onSelectionChanged: (content) =>
                      selected = content?.plainText,
                  child: ListView.builder(
                    controller: controller,
                    itemExtent: 40,
                    itemCount: 100,
                    itemBuilder: (_, i) => Text('שורה מספר $i בספר'),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('שורה מספר 0 בספר')),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    await gesture.moveTo(
      tester.getCenter(find.text('שורה מספר $lastLine בספר')),
    );
    await gesture.up();
    await tester.pumpAndSettle();
    return () => selected;
  }

  Future<void> shiftArrow(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(key);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
  }

  for (final key in keys) {
    testWidgets('Shift+${key.keyLabel} with both selection edges scrolled '
        'out of view does not throw', (tester) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await pumpAndSelect(tester, controller, lastLine: 2);

      controller.jumpTo(2000);
      await tester.pumpAndSettle();
      await shiftArrow(tester, key);

      expect(tester.takeException(), isNull);
      expect(rtlSelectionPriming, isFalse);
    });

    testWidgets('Shift+${key.keyLabel} with only the selection start '
        'scrolled out of view does not throw', (tester) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await pumpAndSelect(tester, controller, lastLine: 13);

      // שורה 0 מחוץ ל-cache extent, שורה 13 עדיין גלויה.
      controller.jumpTo(400);
      await tester.pumpAndSettle();
      await shiftArrow(tester, key);

      expect(tester.takeException(), isNull);
      expect(rtlSelectionPriming, isFalse);
    });

    testWidgets('Shift+${key.keyLabel} with visible edges still changes '
        'the selection', (tester) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      final selected = await pumpAndSelect(tester, controller, lastLine: 2);
      final before = selected();
      expect(before, isNotEmpty);

      await shiftArrow(tester, key);

      expect(tester.takeException(), isNull);
      expect(selected(), isNot(before));
    });
  }
}
