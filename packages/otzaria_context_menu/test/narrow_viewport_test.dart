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
  for (final width in [120.0, 154.0, 160.0, 320.0]) {
    for (final direction in TextDirection.values) {
      testWidgets('menu fits viewport width $width in $direction', (
        tester,
      ) async {
        await tester.binding.setSurfaceSize(Size(width, 400));
        addTearDown(() => tester.binding.setSurfaceSize(null));

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
                    AppContextMenuEntry(label: 'Copy', onTap: () {}),
                  ],
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ),
        );

        await key.currentState!.openMenuAt(Offset(width / 2, 100));
        await tester.pumpAndSettle();
        final panel = tester.getRect(
          find.byWidgetPredicate(
            (widget) =>
                widget is Material &&
                widget.clipBehavior == Clip.antiAlias &&
                widget.elevation == 3,
          ),
        );

        expect(panel.left, greaterThanOrEqualTo(0));
        expect(panel.right, lessThanOrEqualTo(width + 0.1));
        expect(find.text('Copy'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
