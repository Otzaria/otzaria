import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/tools/shamor_zachor/widgets/completion_animation_overlay.dart';

void main() {
  Future<void> show(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () =>
                  CompletionAnimationOverlay.show(context, 'סיימת!'),
              child: const Text('הצג'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('הצג'));
    await tester.pump();
  }

  testWidgets('"סיימת!" מוצג ונעלם בסוף האנימציה', (tester) async {
    await show(tester);
    expect(find.text('סיימת!'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.text('סיימת!'), findsNothing);
  });

  testWidgets('הפחתת אנימציות: מצב הסיום מיד (q6b)', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await show(tester);
    await tester.pump();
    expect(find.text('סיימת!'), findsNothing);
  });
}
