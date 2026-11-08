import 'dart:async';

import 'package:flutter/gestures.dart';
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

Future<void> _showMenu(
  WidgetTester tester,
  GlobalKey<ContextMenuRegionState> key,
  List<AppContextMenuEntry> entries,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ContextMenuRegion(
          key: key,
          presentation: _presentation(),
          registerEscape: (_) => () {},
          menuBuilder: (_, _) => entries,
          child: const SizedBox.expand(),
        ),
      ),
    ),
  );
  await key.currentState!.openMenuAt(const Offset(150, 100));
  await tester.pumpAndSettle();
}

Future<TestGesture> _moveMouseTo(WidgetTester tester, String label) async {
  final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await mouse.addPointer(location: Offset.zero);
  await mouse.moveTo(tester.getCenter(find.text(label)));
  await tester.pump();
  return mouse;
}

void main() {
  testWidgets('closed submenus do not build 120 descendant lists eagerly', (
    tester,
  ) async {
    final key = GlobalKey<ContextMenuRegionState>();
    final builds = List<int>.filled(120, 0);
    final entries = [
      for (var i = 0; i < builds.length; i++)
        AppContextMenuEntry(
          label: 'Group $i',
          childrenBuilder: () {
            builds[i]++;
            return [
              AppContextMenuEntry(label: 'Action $i', onTap: () {}),
            ];
          },
        ),
    ];

    await _showMenu(tester, key, entries);
    expect(builds.reduce((a, b) => a + b), 0);

    final mouse = await _moveMouseTo(tester, 'Group 0');
    addTearDown(mouse.removePointer);
    expect(builds.first, 1);
    expect(builds.skip(1).every((count) => count == 0), isTrue);

    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    expect(find.text('Action 0'), findsOneWidget);
    expect(builds.skip(1).every((count) => count == 0), isTrue);
  });

  testWidgets('a submenu reads fresh entries and coalesces stream bursts', (
    tester,
  ) async {
    final key = GlobalKey<ContextMenuRegionState>();
    final changes = StreamController<Object?>.broadcast(sync: true);
    addTearDown(changes.close);
    var revision = 0;
    var builds = 0;

    await _showMenu(tester, key, [
      AppContextMenuEntry(
        label: 'Dynamic',
        childrenRefreshStream: changes.stream,
        childrenBuilder: () {
          builds++;
          return [
            AppContextMenuEntry(
              label: 'Version $revision',
              onTap: () {},
            ),
          ];
        },
      ),
    ]);

    revision = 1;
    for (var i = 0; i < 100; i++) {
      changes.add(null);
    }
    await tester.pump();
    expect(builds, 0, reason: 'No unused submenu or stream work');

    final mouse = await _moveMouseTo(tester, 'Dynamic');
    addTearDown(mouse.removePointer);
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    expect(builds, 1);
    expect(find.text('Version 1'), findsOneWidget);

    revision = 2;
    for (var i = 0; i < 100; i++) {
      changes.add(null);
    }
    await tester.pump();
    await tester.pumpAndSettle();
    expect(builds, 2, reason: 'A burst rebuilds an open submenu once');
    expect(find.text('Version 2'), findsOneWidget);
    expect(find.text('Version 1'), findsNothing);
  });

  testWidgets('an empty submenu can become enabled after a stream update', (
    tester,
  ) async {
    final key = GlobalKey<ContextMenuRegionState>();
    final changes = StreamController<Object?>.broadcast(sync: true);
    addTearDown(changes.close);
    var ready = false;

    await _showMenu(tester, key, [
      AppContextMenuEntry(
        label: 'Loading',
        childrenRefreshStream: changes.stream,
        childrenBuilder: () => ready
            ? [AppContextMenuEntry(label: 'Ready', onTap: () {})]
            : const <AppContextMenuEntry>[],
      ),
    ]);
    final mouse = await _moveMouseTo(tester, 'Loading');
    addTearDown(mouse.removePointer);
    await tester.pumpAndSettle();
    expect(find.text('Ready'), findsNothing);

    await mouse.moveTo(const Offset(10, 10));
    ready = true;
    changes.add(null);
    await tester.pump();
    await mouse.moveTo(tester.getCenter(find.text('Loading')));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    expect(find.text('Ready'), findsOneWidget);
  });
}
