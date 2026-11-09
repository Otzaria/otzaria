import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  testWidgets('refreshed nested submenus do not accumulate controllers', (
    tester,
  ) async {
    final key = GlobalKey<ContextMenuRegionState>();
    final stream = StreamController<Object?>.broadcast(sync: true);
    addTearDown(stream.close);
    var index = 0;
    OnKeyEventCallback? escapeHandler;

    Future<void> pressEscape() async {
      expect(
        escapeHandler!(
          const KeyDownEvent(
            physicalKey: PhysicalKeyboardKey.escape,
            logicalKey: LogicalKeyboardKey.escape,
            timeStamp: Duration.zero,
          ),
        ),
        KeyEventResult.handled,
      );
      await tester.pumpAndSettle();
    }

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ContextMenuRegion(
            key: key,
            presentation: _presentation(),
            registerEscape: (handler) {
              escapeHandler = handler;
              return () => escapeHandler = null;
            },
            menuBuilder: (_, _) => [
              AppContextMenuEntry(
                label: 'Root',
                childrenRefreshStream: stream.stream,
                childrenBuilder: () => [
                  AppContextMenuEntry(
                    label: 'Nested',
                    children: [
                      AppContextMenuEntry(label: 'Action $index', onTap: () {}),
                    ],
                  ),
                ],
              ),
            ],
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );

    final state = key.currentState!;
    await state.openMenuAt(const Offset(150, 100));
    await tester.pumpAndSettle();
    // The current eager submenu loader creates one nested controller ahead
    // of opening; a separate lazy-loading change may defer that work.
    expect(state.debugTrackedSubmenuControllerCount, inInclusiveRange(1, 2));

    await tester.tap(find.text('Root'));
    await tester.pumpAndSettle();
    expect(find.text('Nested'), findsOneWidget);
    expect(state.debugTrackedSubmenuControllerCount, 2);

    for (var i = 0; i < 12; i++) {
      index++;
      stream.add(null);
      await tester.pumpAndSettle();
      expect(
        state.debugTrackedSubmenuControllerCount,
        2,
        reason: 'Old MenuControllers must be unregistered after refresh $i',
      );
    }

    await tester.tap(find.text('Nested'));
    await tester.pumpAndSettle();
    expect(find.text('Action 12'), findsOneWidget);

    await state.openMenuAt(const Offset(250, 100));
    await tester.pumpAndSettle();
    expect(state.debugTrackedSubmenuControllerCount, 2);
    expect(find.text('Action 12'), findsOneWidget);
    expect(find.text('Nested'), findsOneWidget);
    expect(find.text('Root'), findsOneWidget);

    await pressEscape();
    expect(find.text('Action 12'), findsNothing);
    expect(find.text('Nested'), findsOneWidget);
    expect(state.debugTrackedSubmenuControllerCount, 2);

    await pressEscape();
    expect(find.text('Nested'), findsNothing);
    expect(find.text('Root'), findsOneWidget);
    expect(state.debugTrackedSubmenuControllerCount, 1);

    await pressEscape();
    expect(find.text('Root'), findsNothing);
    expect(state.debugTrackedSubmenuControllerCount, 0);
    expect(escapeHandler, isNull);
  });
}
