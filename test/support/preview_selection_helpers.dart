import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// גורר את העכבר לרוחב [target] — כמו משתמש שמסמן טקסט בחלונית.
Future<void> dragAcross(WidgetTester tester, Finder target) async {
  final rect = tester.getRect(target);
  final gesture = await tester.startGesture(
    rect.centerLeft + const Offset(2, 0),
    kind: PointerDeviceKind.mouse,
  );
  await tester.pump();
  await gesture.moveTo(rect.center);
  await tester.pump();
  await gesture.moveTo(rect.centerRight - const Offset(2, 0));
  await tester.pump();
  await gesture.up();
  await tester.pumpAndSettle();
}

/// האם קיים סימון טקסט פעיל ב-`AppSelectionArea` שעוטף את [target].
///
/// נמדד דרך התנהגות המשתמש: לחיצה ימנית פותחת את תפריט ההקשר של אזור
/// הבחירה, ופריט "העתק" מאופשר רק כשיש טקסט מסומן.
Future<bool> selectionExistsInPanel(
  WidgetTester tester,
  Finder target,
) async {
  final gesture = await tester.startGesture(
    tester.getCenter(target),
    kind: PointerDeviceKind.mouse,
    buttons: kSecondaryButton,
  );
  await gesture.up();
  await tester.pumpAndSettle();

  final copyItem = find.ancestor(
    of: find.text('העתק'),
    matching: find.byType(MenuItemButton),
  );
  if (copyItem.evaluate().isEmpty) return false;
  return tester.widget<MenuItemButton>(copyItem.first).onPressed != null;
}

/// תוכן תצוגה מקדימה שמונה כמה פעמים נבנה מאפס — כדי לזהות בנייה מחדש
/// של החלונית (שקוטעת גרירת סימון וגורמת להבהוב).
class CountingPreviewContent extends StatefulWidget {
  const CountingPreviewContent({super.key});

  static int builds = 0;

  @override
  State<CountingPreviewContent> createState() => _CountingPreviewContentState();
}

class _CountingPreviewContentState extends State<CountingPreviewContent> {
  @override
  void initState() {
    super.initState();
    CountingPreviewContent.builds++;
  }

  @override
  Widget build(BuildContext context) =>
      const SizedBox(width: 200, height: 60, child: Text('תוכן נספר'));
}
