import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/widgets/text/otzaria_search_field.dart';

/// issue #4608 — בשדה צר השאילתה נחתכת; בריחוף מוצג הטקסט המלא.
void main() {
  const longQuery = 'את שמע ישראל ה׳ אלהינו ה׳ אחד ואהבת את ה׳ אלהיך';

  Future<(TextEditingController, FocusNode)> pumpField(
    WidgetTester tester,
    String text,
  ) async {
    final controller = TextEditingController(text: text);
    final focusNode = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: Center(
              child: SizedBox(
                width: 160,
                child: OtzariaSearchField(
                  controller: controller,
                  focusNode: focusNode,
                  hintText: 'חפש כאן...',
                  onClear: () {},
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return (controller, focusNode);
  }

  Future<void> hoverField(WidgetTester tester) async {
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(gesture.removePointer);
    await gesture.addPointer(location: Offset.zero);
    await gesture.moveTo(tester.getCenter(find.byType(EditableText)));
    await tester.pumpAndSettle(const Duration(seconds: 1));
  }

  testWidgets('טקסט שנחתך מוצג בטולטיפ בריחוף', (tester) async {
    await pumpField(tester, longQuery);
    await hoverField(tester);

    expect(find.byTooltip(longQuery), findsOneWidget);
    expect(find.text(longQuery), findsNWidgets(2));
  });

  testWidgets('טקסט שנכנס בשדה אינו מקבל טולטיפ', (tester) async {
    await pumpField(tester, 'שמע');

    expect(find.byTooltip('שמע'), findsNothing);
  });

  testWidgets('בעריכה אין טולטיפ, והפוקוס נשמר במעבר', (tester) async {
    final (_, focusNode) = await pumpField(tester, longQuery);
    expect(find.byTooltip(longQuery), findsOneWidget);

    focusNode.requestFocus();
    await tester.pumpAndSettle();

    expect(find.byTooltip(longQuery), findsNothing);
    expect(focusNode.hasFocus, isTrue);
  });

  testWidgets('ריחוף על כפתור בשדה מציג רק את הטולטיפ של הכפתור', (
    tester,
  ) async {
    await pumpField(tester, longQuery);
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(gesture.removePointer);
    await gesture.addPointer(location: Offset.zero);
    await gesture.moveTo(tester.getCenter(find.byTooltip('נקה')));
    await tester.pumpAndSettle(const Duration(seconds: 1));

    expect(find.text('נקה'), findsOneWidget);
    expect(find.text(longQuery), findsOneWidget);
  });
}
