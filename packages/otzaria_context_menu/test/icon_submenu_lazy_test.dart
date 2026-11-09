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

class _Harness {
  final key = GlobalKey<ContextMenuRegionState>();
  final focus = FocusNode();
  final text = TextEditingController(text: 'טקסט עברי מסומן');
  final builds = <int, int>{};
  final taps = <int>[];
  OnKeyEventCallback? escape;
  var revision = 1;
  var enabled = true;
  var reuseAction = false;
  var extraEntries = 0;
  AppContextMenuIconAction? _action;

  Future<void> mount(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: ContextMenuRegion(
              key: key,
              presentation: _presentation(),
              registerEscape: (handler) {
                escape = handler;
                return () => escape = null;
              },
              menuBuilder: (_, _) {
                return [
                  AppContextMenuEntry.iconRow([
                    if (reuseAction && _action != null)
                      _action!
                    else
                      _action = AppContextMenuIconAction(
                        icon: Icons.link,
                        label: 'קישור',
                        enabled: enabled,
                        submenuBuilder: () {
                          final version = revision;
                          builds.update(
                            version,
                            (count) => count + 1,
                            ifAbsent: () => 1,
                          );
                          return [
                            AppContextMenuSubAction(
                              label: 'גרסה $version',
                              onTap: () => taps.add(version),
                            ),
                            const AppContextMenuSubAction(
                              label: 'מושבת',
                              enabled: false,
                            ),
                          ];
                        },
                      ),
                  ]),
                  for (var i = 0; i < extraEntries; i++)
                    AppContextMenuEntry(label: 'פריט $i', onTap: () {}),
                ];
              },
              child: TextField(focusNode: focus, controller: text),
            ),
          ),
        ),
      ),
    );
    focus.requestFocus();
    text.selection = const TextSelection(baseOffset: 0, extentOffset: 4);
    await tester.pumpAndSettle();
    await key.currentState!.openMenuAt(const Offset(200, 150));
    await tester.pumpAndSettle();
  }

  MenuController controller(WidgetTester tester) =>
      tester.widget<MenuAnchor>(find.byType(MenuAnchor)).controller!;

  void sendEscape() => escape?.call(
    const KeyDownEvent(
      physicalKey: PhysicalKeyboardKey.escape,
      logicalKey: LogicalKeyboardKey.escape,
      timeStamp: Duration.zero,
    ),
  );

  void dispose() {
    focus.dispose();
    text.dispose();
  }
}

void main() {
  testWidgets('icon submenu entries load on demand and refresh each opening', (
    tester,
  ) async {
    var built = 0;
    var revision = 1;
    var tapped = 0;
    final key = GlobalKey<ContextMenuRegionState>();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ContextMenuRegion(
            key: key,
            presentation: _presentation(),
            registerEscape: (_) => () {},
            menuBuilder: (_, _) => [
              AppContextMenuEntry.iconRow([
                AppContextMenuIconAction(
                  icon: Icons.link,
                  label: 'Links',
                  submenuBuilder: () {
                    built++;
                    return [
                      AppContextMenuSubAction(
                        label: 'Version $revision',
                        onTap: () => tapped++,
                      ),
                    ];
                  },
                ),
              ]),
            ],
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );

    await key.currentState!.openMenuAt(const Offset(160, 100));
    await tester.pumpAndSettle();
    expect(built, 0);

    await tester.tap(find.text('Links'));
    await tester.pumpAndSettle();
    expect(built, 1);
    expect(find.text('Version 1'), findsOneWidget);
    await tester.tap(find.text('Version 1'));
    await tester.pumpAndSettle();
    expect(tapped, 1);
    expect(find.text('Links'), findsNothing);

    revision = 2;
    await key.currentState!.openMenuAt(const Offset(160, 100));
    await tester.pumpAndSettle();
    expect(built, 1);
    await tester.tap(find.text('Links'));
    await tester.pumpAndSettle();
    expect(built, 2);
    expect(find.text('Version 2'), findsOneWidget);
  });

  testWidgets('disabled icon submenus never call expensive builders', (
    tester,
  ) async {
    var built = 0;
    final key = GlobalKey<ContextMenuRegionState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ContextMenuRegion(
            key: key,
            presentation: _presentation(),
            registerEscape: (_) => () {},
            menuBuilder: (_, _) => [
              AppContextMenuEntry.iconRow([
                AppContextMenuIconAction(
                  icon: Icons.link,
                  label: 'Disabled',
                  enabled: false,
                  submenuBuilder: () {
                    built++;
                    return [const AppContextMenuSubAction(label: 'Hidden')];
                  },
                ),
              ]),
            ],
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
    await key.currentState!.openMenuAt(const Offset(160, 100));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Disabled'));
    await tester.pumpAndSettle();
    expect(built, 0);
    expect(find.text('Hidden'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final pending in [false, true]) {
    for (final useShowMenu in [false, true]) {
      testWidgets(
        'replacing ${pending ? 'pending' : 'open'} icon submenu via '
        '${useShowMenu ? 'showMenu' : 'openMenuAt'} refreshes its actions',
        (tester) async {
          final h = _Harness();
          addTearDown(h.dispose);
          await h.mount(tester);
          final oldController = h.controller(tester);
          await tester.tap(find.text('קישור'));
          if (!pending) await tester.pumpAndSettle();
          h.revision = 2;
          if (useShowMenu) {
            await h.key.currentState!.showMenu();
          } else {
            await h.key.currentState!.openMenuAt(const Offset(230, 150));
          }
          await tester.pumpAndSettle();
          final newController = h.controller(tester);
          expect(newController, isNot(same(oldController)));
          expect(oldController.isOpen, false);
          expect(newController.isOpen, true);
          expect(find.text('גרסה 1'), findsNothing);
          expect(find.text('גרסה 2'), findsOneWidget);
          expect(h.builds, {1: 1, 2: 1});
          expect(h.focus.hasPrimaryFocus, true);
          expect(
            h.text.selection,
            const TextSelection(baseOffset: 0, extentOffset: 4),
          );
          await tester.tap(find.text('מושבת'));
          await tester.pumpAndSettle();
          expect(h.taps, isEmpty);
          await tester.tap(find.text('גרסה 2'));
          await tester.pumpAndSettle();
          expect(h.taps, [2]);
          expect(find.text('קישור'), findsNothing);
          expect(h.focus.hasPrimaryFocus, true);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('two activations before a frame close the submenu', (
    tester,
  ) async {
    final h = _Harness();
    addTearDown(h.dispose);
    await h.mount(tester);
    await tester.tap(find.text('קישור'));
    await tester.tap(find.text('קישור'));
    await tester.pumpAndSettle();
    expect(h.controller(tester).isOpen, false);
    expect(find.text('גרסה 1'), findsNothing);
    expect(h.builds, {1: 1});
    expect(tester.takeException(), isNull);
  });

  testWidgets('wheel scrolling before the frame cancels opening', (
    tester,
  ) async {
    final h = _Harness()..extraEntries = 40;
    addTearDown(h.dispose);
    await h.mount(tester);
    final scrollable = Scrollable.of(tester.element(find.text('פריט 0')));
    await tester.tap(find.text('קישור'));
    await tester.sendEventToBinding(
      PointerScrollEvent(
        kind: PointerDeviceKind.mouse,
        position: tester.getCenter(find.text('קישור')),
        scrollDelta: const Offset(0, 200),
      ),
    );
    expect(scrollable.position.pixels, greaterThan(0));
    await tester.pumpAndSettle();
    expect(h.controller(tester).isOpen, false);
    expect(find.text('גרסה 1'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('replacing a controller refreshes a reused action builder', (
    tester,
  ) async {
    final h = _Harness()..reuseAction = true;
    addTearDown(h.dispose);
    await h.mount(tester);
    await tester.tap(find.text('קישור'));
    await tester.pumpAndSettle();
    h.revision = 2;
    await h.key.currentState!.showMenu();
    await tester.pumpAndSettle();
    expect(h.controller(tester).isOpen, true);
    expect(find.text('גרסה 1'), findsNothing);
    expect(find.text('גרסה 2'), findsOneWidget);
    expect(h.builds, {1: 1, 2: 1});
    await tester.tap(find.text('גרסה 2'));
    await tester.pumpAndSettle();
    expect(h.taps, [2]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('disabling a replacement preserves an already opened submenu', (
    tester,
  ) async {
    final h = _Harness();
    addTearDown(h.dispose);
    await h.mount(tester);
    await tester.tap(find.text('קישור'));
    h.revision = 2;
    h.enabled = false;
    await h.key.currentState!.showMenu();
    await tester.pumpAndSettle();
    expect(h.controller(tester).isOpen, true);
    expect(find.text('גרסה 1'), findsNothing);
    expect(find.text('גרסה 2'), findsOneWidget);
    await tester.tap(find.text('קישור'));
    await tester.pumpAndSettle();
    expect(h.controller(tester).isOpen, true);
    expect(h.taps, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Escape closes the submenu and reopening refreshes entries', (
    tester,
  ) async {
    final h = _Harness();
    addTearDown(h.dispose);
    await h.mount(tester);
    await tester.tap(find.text('קישור'));
    await tester.pumpAndSettle();
    h.sendEscape();
    await tester.pumpAndSettle();
    expect(find.text('קישור'), findsOneWidget);
    expect(find.text('גרסה 1'), findsNothing);
    await tester.tap(find.text('קישור'));
    await tester.pumpAndSettle();
    expect(h.builds, {1: 2});
    h.sendEscape();
    await tester.pumpAndSettle();
    h.sendEscape();
    await tester.pumpAndSettle();
    expect(find.text('קישור'), findsNothing);
    expect(h.focus.hasPrimaryFocus, true);
    expect(tester.takeException(), isNull);
  });

  for (final unmount in [false, true]) {
    testWidgets('${unmount ? 'unmount' : 'Escape'} before frame is safe', (
      tester,
    ) async {
      final h = _Harness();
      addTearDown(h.dispose);
      await h.mount(tester);
      await tester.tap(find.text('קישור'));
      if (unmount) {
        await tester.pumpWidget(const SizedBox.shrink());
      } else {
        h.sendEscape();
      }
      await tester.pumpAndSettle();
      expect(find.text('קישור'), unmount ? findsNothing : findsOneWidget);
      expect(find.text('גרסה 1'), findsNothing);
      if (!unmount) {
        h.sendEscape();
        await tester.pumpAndSettle();
        expect(find.text('קישור'), findsNothing);
      }
      expect(tester.takeException(), isNull);
    });
  }
}
