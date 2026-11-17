import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/widgets/layout/chrome_auto_hide.dart';

/// הסתרת הסרגלים בגלילה בטלפון: גלילה למטה מסתירה, גלילה למעלה או הקשה
/// מציגות, ובלי ההסתרה (מחשב, קורא מסך) הסרגלים תמיד גלויים.
void main() {
  const barKey = Key('bar');
  const bottomKey = Key('bottom');

  Future<ChromeAutoHideController> pump(
    WidgetTester tester, {
    bool enabled = true,
    bool disableAnimations = false,
    double bottomInset = 0,
  }) async {
    final controller = ChromeAutoHideController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(
            size: const Size(400, 800),
            disableAnimations: disableAnimations,
            padding: EdgeInsets.only(bottom: bottomInset),
          ),
          child: ChromeAutoHideScope(
            controller: controller,
            enabled: enabled,
            child: Column(
              children: [
                const ChromeAutoHide(
                  child: SizedBox(key: barKey, height: 56),
                ),
                Expanded(
                  child: ChromeAutoHideScrollListener(
                    child: ListView(
                      children: [
                        for (var i = 0; i < 100; i++)
                          SizedBox(height: 40, child: Text('שורה $i')),
                      ],
                    ),
                  ),
                ),
                const ChromeAutoHide(
                  keepBottomInset: true,
                  child: SizedBox(key: bottomKey, height: 64),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return controller;
  }

  double visibleHeight(WidgetTester tester, Key key) => tester
      .getSize(
        find.ancestor(of: find.byKey(key), matching: find.byType(ClipRect)),
      )
      .height;

  testWidgets('גלילה למטה מסתירה, גלילה למעלה מציגה', (tester) async {
    final controller = await pump(tester);
    expect(visibleHeight(tester, barKey), 56);

    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(controller.visible, isFalse);
    expect(visibleHeight(tester, barKey), 0);
    expect(visibleHeight(tester, bottomKey), 0);
    // הסרגל המוסתר לא תופס לחיצות.
    expect(find.byKey(barKey).hitTestable(), findsNothing);

    await tester.drag(find.byType(ListView), const Offset(0, 100));
    await tester.pumpAndSettle();
    expect(controller.visible, isTrue);
    expect(visibleHeight(tester, barKey), 56);
    expect(visibleHeight(tester, bottomKey), 64);
  });

  testWidgets('הקשה בתוכן מציגה את הסרגלים', (tester) async {
    final controller = await pump(tester);
    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(controller.visible, isFalse);

    await tester.tap(find.byType(ListView));
    await tester.pumpAndSettle();
    expect(controller.visible, isTrue);
  });

  testWidgets('כבוי (מחשב, קורא מסך): הסרגלים נשארים', (tester) async {
    await pump(tester, enabled: false);
    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(visibleHeight(tester, barKey), 56);
    expect(visibleHeight(tester, bottomKey), 64);
  });

  testWidgets('הפחתת תנועה: ההסתרה מיידית, בלי אנימציה', (tester) async {
    await pump(tester, disableAnimations: true);
    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pump();
    await tester.pump();
    expect(visibleHeight(tester, barKey), 0);
  });

  testWidgets('הסרגל התחתון משאיר את שוליי המערכת', (tester) async {
    await pump(tester, bottomInset: 24);
    final column = find.ancestor(
      of: find.byKey(bottomKey),
      matching: find.byType(Column),
    );
    expect(tester.getSize(column.first).height, 64 + 24);
    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(tester.getSize(column.first).height, 24);
  });
}
