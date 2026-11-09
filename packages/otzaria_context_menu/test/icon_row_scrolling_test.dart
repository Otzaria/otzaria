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
    testWidgets('crowded icon rows scroll without overflow ($direction)', (
      tester,
    ) async {
      final key = GlobalKey<ContextMenuRegionState>();
      var selected = -1;
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
                  AppContextMenuEntry.iconRow([
                    for (var i = 0; i < 12; i++)
                      AppContextMenuIconAction(
                        icon: Icons.search,
                        label: 'Action $i',
                        onTap: () => selected = i,
                      ),
                  ]),
                ],
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ),
      );
      await key.currentState!.openMenuAt(const Offset(160, 100));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      final scroll = find.byKey(const ValueKey('context-icon-row-scroll'));
      expect(scroll, findsOneWidget);

      await tester.drag(
        scroll,
        Offset(direction == TextDirection.ltr ? -1100 : 1100, 0),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Action 11'));
      await tester.pumpAndSettle();

      expect(selected, 11);
      expect(find.text('Action 11'), findsNothing);
    });
  }
}
