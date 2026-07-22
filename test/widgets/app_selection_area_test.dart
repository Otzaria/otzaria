import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/widgets/misc/app_menu_exports.dart';
import 'package:otzaria/widgets/misc/app_selection_area.dart';

void main() {
  Widget buildHarness({required Widget child}) {
    return MaterialApp(
      locale: const Locale('he', 'IL'),
      home: Scaffold(
        body: Directionality(
          textDirection: TextDirection.rtl,
          child: AppSelectionArea(child: child),
        ),
      ),
    );
  }

  Future<void> rightClickAt(WidgetTester tester, Offset position) async {
    final gesture = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryButton,
    );
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(position);
    await gesture.down(position);
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
  }

  testWidgets('לחיצה ימנית פותחת את תפריט אוצריא ולא את תפריט ברירת המחדל', (
    tester,
  ) async {
    await tester.pumpWidget(buildHarness(child: const Text('טקסט לדוגמה')));
    await tester.pumpAndSettle();

    await rightClickAt(tester, tester.getCenter(find.text('טקסט לדוגמה')));

    expect(
      find.text('העתק'),
      findsOneWidget,
      reason: 'תפריט ההקשר של אוצריא חייב להכיל "העתק"',
    );
    expect(
      find.byType(AdaptiveTextSelectionToolbar),
      findsNothing,
      reason: 'תפריט ברירת המחדל של Flutter חייב להיות מדוכא',
    );
  });

  testWidgets('"העתק" מנוטרל כשאין טקסט נבחר', (tester) async {
    await tester.pumpWidget(buildHarness(child: const Text('טקסט לדוגמה')));
    await tester.pumpAndSettle();

    await rightClickAt(tester, tester.getCenter(find.text('טקסט לדוגמה')));

    final copyItem = tester.widget<MenuItemButton>(
      find.ancestor(
        of: find.text('העתק'),
        matching: find.byType(MenuItemButton),
      ),
    );
    expect(
      copyItem.onPressed,
      isNull,
      reason: 'ללא בחירה פעילה "העתק" צריך להיות מנוטרל',
    );
  });

  testWidgets('AppContextMenuRegion עוטף את התוכן', (tester) async {
    await tester.pumpWidget(buildHarness(child: const Text('טקסט לדוגמה')));
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byType(AppContextMenuRegion),
        matching: find.text('טקסט לדוגמה'),
      ),
      findsOneWidget,
    );
  });
}
