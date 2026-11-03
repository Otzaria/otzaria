import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/widgets/navigation/panel_tab_header.dart';

void main() {
  bool isNearEdge(RRect rrect, Offset point) {
    const deltas = [
      Offset(0.01, 0),
      Offset(-0.01, 0),
      Offset(0, 0.01),
      Offset(0, -0.01),
    ];
    final inside = rrect.contains(point);
    return deltas.any((delta) => rrect.contains(point + delta) != inside);
  }

  testWidgets(
    'PanelOpenHandle is a path with the geometry of its rounded rect',
    (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.centerLeft,
              child: PanelOpenHandle(onTap: () {}),
            ),
          ),
        ),
      );
      final container = tester.widget<AnimatedContainer>(
        find.descendant(
          of: find.byType(PanelOpenHandle),
          matching: find.byType(AnimatedContainer),
        ),
      );
      final decoration = container.decoration! as ShapeDecoration;

      for (final width in [20.0, 30.0, 41.0, 48.0]) {
        final rect = Rect.fromLTWH(0, 0, width, 80);
        final path = decoration.shape.getOuterPath(rect);
        final rrect = RRect.fromRectAndCorners(
          rect,
          topRight: const Radius.circular(40),
          bottomRight: const Radius.circular(40),
        );
        for (var x = 0.25; x < width; x += 0.5) {
          for (var y = 0.25; y < 80; y += 0.5) {
            final point = Offset(x, y);
            if (isNearEdge(rrect, point)) continue;
            expect(
              path.contains(point),
              rrect.contains(point),
              reason: 'width $width at $point',
            );
          }
        }
      }
    },
  );

  testWidgets('PositionedPanelOpenHandle sits a tenth down its container', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 300,
            height: 400,
            child: Stack(
              children: [PositionedPanelOpenHandle(onTap: () {})],
            ),
          ),
        ),
      ),
    );
    final rect = tester.getRect(find.byType(PanelOpenHandle));
    expect(rect.left, 0);
    expect(rect.top, 40);
  });
}
