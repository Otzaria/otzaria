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

Future<void> _openMenu(
  WidgetTester tester, {
  required double width,
  required TextDirection direction,
  required List<AppContextMenuEntry> entries,
}) async {
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
            menuBuilder: (_, _) => entries,
            child: const SizedBox.expand(),
          ),
        ),
      ),
    ),
  );
  await key.currentState!.openMenuAt(Offset(width / 2, 100));
  await tester.pumpAndSettle();
}

void main() {
  for (final width in [120.0, 154.0, 160.0, 320.0]) {
    for (final direction in TextDirection.values) {
      testWidgets('menu fits viewport width $width in $direction', (
        tester,
      ) async {
        await _openMenu(
          tester,
          width: width,
          direction: direction,
          entries: [AppContextMenuEntry(label: 'Copy', onTap: () {})],
        );
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

  for (final width in [120.0, 154.0, 160.0, 320.0]) {
    for (final direction in TextDirection.values) {
      testWidgets(
        'selected and disabled actions fit width $width in $direction',
        (
          tester,
        ) async {
          var invoked = false;
          await _openMenu(
            tester,
            width: width,
            direction: direction,
            entries: [
              AppContextMenuEntry(
                label: 'פעולה נבחרת עם כיתוב ארוך',
                icon: Icons.copy,
                isSelected: true,
                onTap: () => invoked = true,
              ),
              const AppContextMenuEntry(
                label: 'תפריט מושבת',
                children: [
                  AppContextMenuEntry(label: 'פעולה מושבתת', enabled: false),
                ],
              ),
              AppContextMenuEntry(
                label: 'תפריט עצל ריק',
                childrenBuilder: () => [],
              ),
            ],
          );
          expect(tester.takeException(), isNull);
          expect(find.text('✓'), findsOneWidget);
          for (final label in ['תפריט מושבת', 'תפריט עצל ריק']) {
            expect(
              tester
                  .widget<MenuItemButton>(
                    find.widgetWithText(MenuItemButton, label),
                  )
                  .enabled,
              isFalse,
            );
          }
          await tester.tap(
            find.widgetWithText(MenuItemButton, 'פעולה נבחרת עם כיתוב ארוך'),
          );
          await tester.pumpAndSettle();
          expect(invoked, isTrue);
        },
      );

      testWidgets(
        'submenu action remains usable at width $width in $direction',
        (
          tester,
        ) async {
          var invoked = false;
          await _openMenu(
            tester,
            width: width,
            direction: direction,
            entries: [
              AppContextMenuEntry(
                label: 'אפשרויות',
                children: [
                  AppContextMenuEntry(
                    label: 'פעולה פנימית',
                    onTap: () => invoked = true,
                  ),
                ],
              ),
            ],
          );
          expect(tester.takeException(), isNull);
          await tester.tap(find.byType(SubmenuButton));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(find.text('פעולה פנימית'), findsOneWidget);
          await tester.tap(find.byType(MenuItemButton));
          await tester.pumpAndSettle();
          expect(invoked, isTrue);
        },
      );
    }
  }
}
