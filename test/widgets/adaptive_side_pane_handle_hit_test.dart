import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/widgets/layout/adaptive_side_pane.dart';
import 'package:otzaria/widgets/layout/resizable_drag_handle.dart';

// שטח הלחיצה של הידית בפריסה הרחבה (סעיף 12): החלק שיוצא החוצה מקצה החלונית
// חייב לקבל נגיעות באמת. בפריסה הרחבה הידית יושבת בתוך משבצת החלונית, ומה
// שגלש מחוץ למשבצת לא היה מקבל נגיעה (הלחיצה נבלעה, או הגיעה לתוכן הראשי).

Widget _app(Widget child, {required bool touch}) => MaterialApp(
  theme: ThemeData(
    materialTapTargetSize: touch
        ? MaterialTapTargetSize.padded
        : MaterialTapTargetSize.shrinkWrap,
  ),
  home: Scaffold(body: child),
);

void main() {
  for (final touch in [true, false]) {
    testWidgets(
      'פריסה רחבה, ${touch ? 'מגע' : 'עכבר'}: גרירה מהקצה החיצוני של הידית '
      'משנה את רוחב החלונית',
      (tester) async {
        tester.view.physicalSize = const Size(1000, 600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        final widths = <double>[];
        await tester.pumpWidget(
          _app(
            AdaptiveSidePane(
              isOpen: true,
              paneWidth: 300,
              minMainContentWidth: 400,
              isResizable: true,
              onClose: () {},
              onPaneWidthChanged: widths.add,
              mainContent: const SizedBox.expand(),
              paneContent: const SizedBox.expand(),
            ),
            touch: touch,
          ),
        );
        await tester.pumpAndSettle();

        final handle = tester.getRect(find.byType(ResizableDragHandle));
        // 2px מהקצה החיצוני, הרחוק ביותר מהחלונית.
        await tester.dragFrom(
          Offset(handle.left + 2, handle.center.dy),
          const Offset(-40, 0),
        );
        await tester.pumpAndSettle();

        expect(widths, isNotEmpty);
        expect(widths.last, greaterThan(300));
      },
    );
  }
}
