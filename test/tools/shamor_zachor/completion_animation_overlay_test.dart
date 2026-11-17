import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria_icons/otzaria_icons.dart';
import 'package:otzaria/tools/shamor_zachor/widgets/completion_animation_overlay.dart';
import 'package:otzaria/widgets/layout/app_card.dart';

void main() {
  Future<void> show(
    WidgetTester tester, {
    String message = 'סיימת!',
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () =>
                  CompletionAnimationOverlay.show(context, message),
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

  testWidgets('אייקון הסיום הוא ספר עם וי', (tester) async {
    await show(tester);
    await tester.pump(const Duration(milliseconds: 700));
    final icon = tester.widget<Icon>(find.byType(Icon));
    expect(icon.icon, OtzariaIcons.book_checkmark_24_regular);
  });

  group('לפי כללי מערכת העיצוב', () {
    const longMessage =
        'אשריך! תזכה ללמוד ספרים אחרים ולסיימם! ותזכה גם לחזור ולהתחזק בלימוד';

    testWidgets('הכרטיס הוא AppCard בצל של AppShadows', (tester) async {
      await show(tester, message: longMessage);
      await tester.pump(const Duration(milliseconds: 700));
      expect(find.byType(AppCard), findsOneWidget);
      final cs = Theme.of(tester.element(find.byType(AppCard))).colorScheme;
      final shadowed = tester
          .widgetList<DecoratedBox>(
            find.ancestor(
              of: find.byType(AppCard),
              matching: find.byType(DecoratedBox),
            ),
          )
          .where(
            (box) => listEquals(
              (box.decoration as BoxDecoration).boxShadow,
              AppShadows.floating(cs),
            ),
          );
      expect(shadowed, isNotEmpty);
      await tester.pumpAndSettle();
    });

    testWidgets('הודעה ארוכה עוברת שורה ברוחב חלונית ואינה פורסת את הכלי', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await show(tester, message: longMessage);
      await tester.pump(const Duration(milliseconds: 700));
      expect(
        tester.getSize(find.byType(AppCard)).width,
        lessThanOrEqualTo(LayoutConstraints.overlayPanelWidth),
      );
      await tester.pumpAndSettle();
    });

    testWidgets('גודל וריווח מהטוקנים: טקסט titleLarge ואייקון iconXL', (
      tester,
    ) async {
      await show(tester, message: longMessage);
      await tester.pump(const Duration(milliseconds: 700));
      final text = tester.widget<Text>(find.text(longMessage));
      expect(
        text.style,
        Theme.of(tester.element(find.text(longMessage))).textTheme.titleLarge,
      );
      expect(
        tester.getSize(find.byType(Icon)).height,
        AppTokens.iconXL,
      );
      await tester.pumpAndSettle();
    });
  });
}
