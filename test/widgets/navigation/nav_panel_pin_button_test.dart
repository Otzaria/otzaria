import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/widgets/navigation/nav_side_panel.dart';

void main() {
  Future<void> pump(
    WidgetTester tester, {
    required bool isPinned,
    bool isGloballyPinned = false,
  }) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: NavPanelPinButton(
          isPinned: isPinned,
          isGloballyPinned: isGloballyPinned,
          onToggle: () {},
        ),
      ),
    ),
  );

  testWidgets('נעיצה בהגדרות: הכפתור מסביר שהנעיצה נקבעה שם', (tester) async {
    await pump(tester, isPinned: false, isGloballyPinned: true);

    expect(find.byTooltip('החלונית נעוצה לפי ההגדרות'), findsOneWidget);
    expect(find.byTooltip('בטל נעיצה'), findsNothing);
  });

  testWidgets('בלי נעיצה בהגדרות: הכפתור מציע את הפעולה', (tester) async {
    await pump(tester, isPinned: true);
    expect(find.byTooltip('בטל נעיצה'), findsOneWidget);

    await pump(tester, isPinned: false);
    expect(find.byTooltip('נעץ את החלונית'), findsOneWidget);
  });
}
