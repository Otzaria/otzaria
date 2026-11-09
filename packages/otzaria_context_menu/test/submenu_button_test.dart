import 'package:flutter/gestures.dart';
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

Widget _host({
  required MenuController controller,
  FocusNode? focus,
  bool preserveFocus = true,
  List<Widget>? menuChildren,
}) => MaterialApp(
  home: Scaffold(
    body: Focus(
      focusNode: focus,
      child: Center(
        child: AppSubmenuButton(
          controller: controller,
          preserveFocus: preserveFocus,
          presentation: _presentation(),
          maxWidth: 200,
          menuChildren:
              menuChildren ??
              [
                MenuItemButton(
                  onPressed: () {},
                  child: const Text('פעולה פנימית'),
                ),
              ],
          child: const Text('אפשרויות'),
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets(
    'global pointer tracking is active only while focusable menus are open',
    (tester) async {
      final controller = MenuController();
      final router = GestureBinding.instance.pointerRouter;
      final routes = router.debugGlobalRouteCount;
      await tester.pumpWidget(
        _host(controller: controller, preserveFocus: false),
      );
      expect(router.debugGlobalRouteCount, routes);

      controller.open();
      await tester.pumpAndSettle();
      expect(router.debugGlobalRouteCount, routes + 1);
      controller.close();
      await tester.pumpAndSettle();
      expect(router.debugGlobalRouteCount, routes);

      controller.open();
      await tester.pumpAndSettle();
      expect(router.debugGlobalRouteCount, routes + 1);
      await tester.pumpWidget(_host(controller: controller));
      expect(router.debugGlobalRouteCount, routes);

      await tester.pumpWidget(const SizedBox.shrink());
      expect(router.debugGlobalRouteCount, routes);
    },
  );

  testWidgets('many closed focusable submenus add no global pointer routes', (
    tester,
  ) async {
    final router = GestureBinding.instance.pointerRouter;
    final baseline = router.debugGlobalRouteCount;
    final controllers = [for (var i = 0; i < 40; i++) MenuController()];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Column(
              children: [
                for (var i = 0; i < controllers.length; i++)
                  AppSubmenuButton(
                    controller: controllers[i],
                    presentation: _presentation(),
                    maxWidth: 200,
                    preserveFocus: false,
                    menuChildren: [
                      MenuItemButton(
                        onPressed: () {},
                        child: const Text('Action'),
                      ),
                    ],
                    child: Text('Menu $i'),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    expect(router.debugGlobalRouteCount, baseline);
    controllers.first.open();
    await tester.pumpAndSettle();
    expect(router.debugGlobalRouteCount, baseline + 1);
    controllers.first.close();
    await tester.pumpAndSettle();
    expect(router.debugGlobalRouteCount, baseline);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(router.debugGlobalRouteCount, baseline);
  });

  for (final preserveFocus in [false, true]) {
    testWidgets(
      'replacing an open controller preserves pointer tracking '
      '(preserveFocus: $preserveFocus)',
      (tester) async {
        final oldController = MenuController();
        final controller = MenuController();
        final router = GestureBinding.instance.pointerRouter;
        final routes = router.debugGlobalRouteCount;
        await tester.pumpWidget(
          _host(controller: oldController, preserveFocus: preserveFocus),
        );
        oldController.open();
        await tester.pumpAndSettle();

        await tester.pumpWidget(
          _host(controller: controller, preserveFocus: preserveFocus),
        );
        await tester.pumpAndSettle();
        expect(oldController.isOpen, isFalse);
        expect(controller.isOpen, isTrue);
        expect(find.text('פעולה פנימית'), findsOneWidget);
        expect(router.debugGlobalRouteCount, routes + (preserveFocus ? 0 : 1));

        router.route(
          PointerHoverEvent(
            kind: PointerDeviceKind.mouse,
            position: Offset.zero,
            viewId: tester.view.viewId,
          ),
        );
        await tester.pump(const Duration(milliseconds: 401));
        await tester.pumpAndSettle();
        expect(controller.isOpen, preserveFocus);
        controller.close();
        await tester.pumpAndSettle();
        expect(router.debugGlobalRouteCount, routes);
        await tester.pumpWidget(const SizedBox.shrink());
        expect(router.debugGlobalRouteCount, routes);
      },
    );
  }

  testWidgets('replacing a closed controller adds no global pointer route', (
    tester,
  ) async {
    final oldController = MenuController();
    final controller = MenuController();
    final router = GestureBinding.instance.pointerRouter;
    final routes = router.debugGlobalRouteCount;
    await tester.pumpWidget(
      _host(controller: oldController, preserveFocus: false),
    );
    await tester.pumpWidget(
      _host(controller: controller, preserveFocus: false),
    );
    expect(oldController.isOpen, isFalse);
    expect(controller.isOpen, isFalse);
    expect(router.debugGlobalRouteCount, routes);
    controller.open();
    await tester.pumpAndSettle();
    expect(router.debugGlobalRouteCount, routes + 1);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(router.debugGlobalRouteCount, routes);
  });

  for (final preserveFocus in [false, true]) {
    for (final open in [false, true]) {
      for (final replaceController in [false, true]) {
        testWidgets(
          'changing preserveFocus from $preserveFocus resets tracking '
          '(open: $open, replaceController: $replaceController)',
          (tester) async {
            final oldController = MenuController();
            final controller = replaceController
                ? MenuController()
                : oldController;
            final router = GestureBinding.instance.pointerRouter;
            final routes = router.debugGlobalRouteCount;
            await tester.pumpWidget(
              _host(controller: oldController, preserveFocus: preserveFocus),
            );
            if (open) {
              oldController.open();
              await tester.pumpAndSettle();
            }
            await tester.pumpWidget(
              _host(controller: controller, preserveFocus: !preserveFocus),
            );
            await tester.pumpAndSettle();
            expect(oldController.isOpen, isFalse);
            expect(controller.isOpen, isFalse);
            expect(router.debugGlobalRouteCount, routes);

            controller.open();
            await tester.pumpAndSettle();
            expect(controller.isOpen, isTrue);
            expect(
              router.debugGlobalRouteCount,
              routes + (preserveFocus ? 1 : 0),
            );
            controller.close();
            await tester.pumpAndSettle();
            expect(router.debugGlobalRouteCount, routes);
            await tester.pumpWidget(const SizedBox.shrink());
            expect(router.debugGlobalRouteCount, routes);
          },
        );
      }
    }
  }

  testWidgets('controller replacement preserves a pending pointer exit close', (
    tester,
  ) async {
    final oldController = MenuController();
    final controller = MenuController();
    final router = GestureBinding.instance.pointerRouter;
    final routes = router.debugGlobalRouteCount;
    await tester.pumpWidget(
      _host(controller: oldController, preserveFocus: false),
    );
    oldController.open();
    await tester.pumpAndSettle();
    router.route(
      PointerHoverEvent(
        kind: PointerDeviceKind.mouse,
        position: Offset.zero,
        viewId: tester.view.viewId,
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpWidget(
      _host(controller: controller, preserveFocus: false),
    );
    expect(controller.isOpen, isTrue);
    expect(router.debugGlobalRouteCount, routes + 1);
    await tester.pump(const Duration(milliseconds: 201));
    await tester.pumpAndSettle();
    expect(controller.isOpen, isFalse);
    expect(router.debugGlobalRouteCount, routes);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'disposing an open submenu cancels its pending pointer exit close',
    (
      tester,
    ) async {
      final controller = MenuController();
      final router = GestureBinding.instance.pointerRouter;
      final routes = router.debugGlobalRouteCount;
      await tester.pumpWidget(
        _host(controller: controller, preserveFocus: false),
      );
      controller.open();
      await tester.pumpAndSettle();
      router.route(
        PointerHoverEvent(
          kind: PointerDeviceKind.mouse,
          position: Offset.zero,
          viewId: tester.view.viewId,
        ),
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 401));
      expect(controller.isOpen, isFalse);
      expect(router.debugGlobalRouteCount, routes);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('removing open submenu children releases pointer tracking', (
    tester,
  ) async {
    final controller = MenuController();
    final router = GestureBinding.instance.pointerRouter;
    final routes = router.debugGlobalRouteCount;
    await tester.pumpWidget(
      _host(controller: controller, preserveFocus: false),
    );
    controller.open();
    await tester.pumpAndSettle();
    expect(router.debugGlobalRouteCount, routes + 1);
    await tester.pumpWidget(
      _host(
        controller: controller,
        preserveFocus: false,
        menuChildren: const [],
      ),
    );
    await tester.pumpAndSettle();
    expect(controller.isOpen, isFalse);
    expect(router.debugGlobalRouteCount, routes);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('shared submenu delays hover without stealing the source focus', (
    tester,
  ) async {
    final controller = MenuController();
    final focus = FocusNode();
    addTearDown(focus.dispose);
    await tester.pumpWidget(_host(controller: controller, focus: focus));
    focus.requestFocus();
    await tester.pump();
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(find.text('אפשרויות')));
    await tester.pump(const Duration(milliseconds: 100));
    expect(controller.isOpen, isFalse);
    expect(focus.hasPrimaryFocus, isTrue);

    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(controller.isOpen, isTrue);
    expect(find.text('פעולה פנימית'), findsOneWidget);
    expect(focus.hasPrimaryFocus, isTrue);
  });

  testWidgets('focusable nested submenu supports keyboard activation', (
    tester,
  ) async {
    final rootController = MenuController();
    final controller = MenuController();
    var selected = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: MenuAnchor(
              controller: rootController,
              menuChildren: [
                AppSubmenuButton(
                  controller: controller,
                  presentation: _presentation(),
                  maxWidth: 200,
                  preserveFocus: false,
                  menuChildren: [
                    MenuItemButton(
                      onPressed: () => selected++,
                      child: const Text('פעולה פנימית'),
                    ),
                  ],
                  child: const Text('אפשרויות'),
                ),
              ],
              builder: (context, menu, child) => TextButton(
                onPressed: menu.open,
                child: const Text('פתח'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('פתח'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('אפשרויות'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(selected, 1);
    expect(controller.isOpen, isFalse);
    expect(rootController.isOpen, isFalse);
    expect(find.text('פעולה פנימית'), findsNothing);
  });

  testWidgets('removing a submenu during the hover delay cancels its opening', (
    tester,
  ) async {
    final controller = MenuController();
    await tester.pumpWidget(_host(controller: controller));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(find.text('אפשרויות')));
    await tester.pump(const Duration(milliseconds: 100));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(controller.isOpen, isFalse);
    expect(find.text('פעולה פנימית'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('nested overlay determines the submenu side and its arrow', (
    tester,
  ) async {
    final controller = MenuController();
    const anchorKey = ValueKey('nested-submenu-anchor');
    const actionKey = ValueKey('nested-submenu-action');
    final overlayEntry = OverlayEntry(
      builder: (context) => Stack(
        children: [
          Positioned(
            left: 160,
            top: 60,
            width: 70,
            height: 40,
            child: Material(
              child: AppSubmenuButton(
                key: anchorKey,
                controller: controller,
                presentation: _presentation(),
                maxWidth: 180,
                preserveFocus: false,
                childBuilder: (_, openToRight) => Text(
                  openToRight ? 'ימינה' : 'שמאלה',
                ),
                menuChildren: [
                  MenuItemButton(
                    key: actionKey,
                    onPressed: () {},
                    child: const SizedBox(width: 130, child: Text('פעולה')),
                  ),
                ],
                child: const SizedBox.shrink(),
              ),
            ),
          ),
        ],
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              Positioned(
                left: 100,
                top: 100,
                width: 250,
                height: 250,
                child: Overlay(initialEntries: [overlayEntry]),
              ),
            ],
          ),
        ),
      ),
    );
    controller.open();
    await tester.pumpAndSettle();

    final anchorRect = tester.getRect(find.byKey(anchorKey));
    final actionRect = tester.getRect(find.byKey(actionKey));
    expect(actionRect.center.dx, lessThan(anchorRect.center.dx));
    expect(find.text('שמאלה'), findsOneWidget);
    expect(find.text('ימינה'), findsNothing);
  });
}
