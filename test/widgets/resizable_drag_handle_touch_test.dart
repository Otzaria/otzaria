import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/widgets/layout/adaptive_side_pane.dart';
import 'package:otzaria/widgets/layout/resizable_drag_handle.dart';

// ידית שינוי גודל במסך מגע (סעיף 12, החלטת הבעלים א): הידית גלויה גם כשלא
// נוגעים בה, ושטח הלחיצה 32 ויוצא החוצה מקצה החלונית; בעכבר שום דבר לא משתנה.

Widget _app(Widget child, {required bool touch}) => MaterialApp(
  theme: ThemeData(
    materialTapTargetSize: touch
        ? MaterialTapTargetSize.padded
        : MaterialTapTargetSize.shrinkWrap,
  ),
  home: Scaffold(body: SizedBox(height: 300, child: child)),
);

/// צבעי הפסים הגלויים בידית (DecoratedBox בצבע שאינו שקוף), לפי הגובה.
Map<double, Color> _visible(WidgetTester tester) => {
  for (final e in tester.widgetList<DecoratedBox>(
    find.descendant(
      of: find.byType(ResizableDragHandle),
      matching: find.byType(DecoratedBox),
    ),
  ))
    if ((e.decoration as BoxDecoration).color case final c? when c.a > 0)
      tester.getSize(find.byWidget(e)).height: c,
};

void main() {
  testWidgets('מגע: שטח הלחיצה 32 והידית גלויה במנוחה', (tester) async {
    await tester.pumpWidget(
      _app(
        ResizableDragHandle(
          isVertical: true,
          showDivider: false,
          onDragDelta: (_) {},
        ),
        touch: true,
      ),
    );

    expect(tester.getSize(find.byType(ResizableDragHandle)).width, 32);
    expect(_visible(tester).keys, [24.0]);
  });

  testWidgets('עכבר: שטח הלחיצה 24 והידית שקופה במנוחה', (tester) async {
    await tester.pumpWidget(
      _app(
        ResizableDragHandle(
          isVertical: true,
          showDivider: false,
          onDragDelta: (_) {},
        ),
        touch: false,
      ),
    );

    expect(tester.getSize(find.byType(ResizableDragHandle)).width, 24);
    expect(_visible(tester), isEmpty);
  });

  testWidgets(
    'מגע בחלונית צד: הקצה הפנימי של הידית במקומו והיתרה יוצאת החוצה',
    (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1000, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      Future<Rect> handleRect({required bool touch}) async {
        await tester.pumpWidget(
          _app(
            SizedBox(
              width: 1000,
              child: AdaptiveSidePane(
                isOpen: true,
                paneWidth: 300,
                minMainContentWidth: 400,
                isResizable: true,
                onClose: () {},
                onPaneWidthChanged: (_) {},
                mainContent: const SizedBox.expand(),
                paneContent: const SizedBox.expand(),
              ),
            ),
            touch: touch,
          ),
        );
        await tester.pumpAndSettle();
        return tester.getRect(find.byType(ResizableDragHandle));
      }

      final mouse = await handleRect(touch: false);
      final touch = await handleRect(touch: true);

      expect(mouse.width, 24);
      expect(touch.width, 32);
      // החלונית בימין: הקצה הפנימי (הימני של הידית, בתוך החלונית) לא זז,
      // והתוספת של 8 יוצאת החוצה, אל התוכן.
      expect(touch.right, mouse.right);
      expect(touch.left, mouse.left - 8);
      expect(_visible(tester).keys, [24.0]);
    },
  );
}
