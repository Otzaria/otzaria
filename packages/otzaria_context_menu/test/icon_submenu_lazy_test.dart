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
}
