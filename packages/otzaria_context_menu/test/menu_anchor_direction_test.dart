import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria_context_menu/otzaria_context_menu.dart';

MenuPresentation _presentation() => MenuPresentation(
  metrics: AppMenuMetrics.create(compactMenus: false),
  borderRadius: BorderRadius.circular(8),
  iconBuilder: (context, icon, size, color, mirrorForRtl) =>
      SizedBox.square(dimension: size),
  selectedMarkBuilder: (context, size, color) => const Text('✓'),
  submenuArrowBuilder: (context, openToRight, size, color) =>
      Text(openToRight ? '›' : '‹'),
  downArrowBuilder: (context, size, color) => const Text('⌄'),
);

void main() {
  for (final direction in TextDirection.values) {
    for (final anchorX in [15.0, 480.0, 785.0]) {
      testWidgets('context menu at $anchorX follows $direction', (
        tester,
      ) async {
        final key = GlobalKey<ContextMenuRegionState>();
        await tester.pumpWidget(
          MaterialApp(
            home: Directionality(
              textDirection: direction,
              child: Scaffold(
                body: ContextMenuRegion(
                  key: key,
                  presentation: _presentation(),
                  registerEscape: (_) => () {},
                  menuBuilder: (_, _) => [
                    AppContextMenuEntry(label: 'Action', onTap: () {}),
                  ],
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ),
        );
        await key.currentState!.openMenuAt(Offset(anchorX, 160));
        await tester.pumpAndSettle();

        final panel = tester.getRect(
          find.byWidgetPredicate(
            (widget) =>
                widget is Material &&
                widget.clipBehavior == Clip.antiAlias &&
                widget.elevation == 3,
          ),
        );
        expect(panel.left, greaterThanOrEqualTo(8));
        expect(panel.right, lessThanOrEqualTo(792));

        if (anchorX == 480.0) {
          if (direction == TextDirection.ltr) {
            expect(panel.left, moreOrLessEquals(anchorX, epsilon: 1));
          } else {
            expect(panel.right, moreOrLessEquals(anchorX, epsilon: 1));
          }
        }
        expect(tester.takeException(), isNull);
      });
    }
  }
}
