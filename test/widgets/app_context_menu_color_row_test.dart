import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/widgets/misc/app_context_menu.dart';
import 'package:otzaria/widgets/misc/app_popup_menu.dart';

void main() {
  testWidgets('color row exposes accessible targets and closes after tap', (
    tester,
  ) async {
    final key = GlobalKey<AppContextMenuRegionState>();
    String? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppContextMenuRegion(
            key: key,
            menuBuilder: (_, _) => [
              AppContextMenuEntry.colorRow([
                AppContextMenuColorAction(
                  id: 'orange',
                  color: Colors.orange,
                  label: 'Orange',
                  selected: true,
                  onTap: () => selected = 'orange',
                ),
                const AppContextMenuColorAction(
                  id: 'blue',
                  color: Colors.blue,
                  label: 'Blue',
                ),
                const AppContextMenuColorAction(
                  id: 'remove',
                  color: Colors.transparent,
                  label: 'Remove highlight',
                  icon: Icons.cleaning_services,
                ),
              ]),
            ],
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );

    await key.currentState!.openMenuAt(const Offset(100, 100));
    await tester.pumpAndSettle();

    expect(
      tester.getSize(find.byKey(const ValueKey('context-color-row'))).height,
      36,
      reason: 'The color tray must have the same fixed height as a menu row',
    );

    final orange = find.byKey(const ValueKey('context-color-orange'));
    expect(orange, findsOneWidget);
    expect(tester.getSize(orange), const Size.square(32));
    expect(find.byIcon(Icons.cleaning_services), findsOneWidget);
    final row = find.byKey(const ValueKey('context-color-row'));
    final first = tester.getRect(
      find.byKey(const ValueKey('context-color-orange')),
    );
    final last = tester.getRect(
      find.byKey(const ValueKey('context-color-remove')),
    );
    expect(
      ((first.left + last.right) / 2 - tester.getCenter(row).dx).abs(),
      lessThan(0.01),
      reason: 'A color tray that fits must be centered inside the menu row',
    );
    expect(
      tester.getSemantics(orange),
      matchesSemantics(
        label: 'Orange',
        isButton: true,
        isSelected: true,
        hasSelectedState: true,
        isFocusable: true,
        hasFocusAction: true,
        hasTapAction: true,
      ),
    );

    await tester.tap(orange);
    await tester.pumpAndSettle();

    expect(selected, 'orange');
    expect(orange, findsNothing);
  });

  testWidgets('12 colors stay on one scrollable RTL row on a narrow screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(220, 400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final key = GlobalKey<AppContextMenuRegionState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: AppContextMenuRegion(
              key: key,
              menuBuilder: (_, _) => [
                AppContextMenuEntry.colorRow([
                  for (var index = 0; index < 12; index++)
                    AppContextMenuColorAction(
                      id: 'color-$index',
                      color: Colors.primaries[index],
                      label: 'Color $index',
                    ),
                ]),
              ],
              child: const SizedBox.expand(),
            ),
          ),
        ),
      ),
    );

    await key.currentState!.openMenuAt(const Offset(110, 100));
    await tester.pumpAndSettle();

    final row = find.byKey(const ValueKey('context-color-row'));
    expect(tester.getSize(row).height, 36);
    expect(tester.getSize(row).width, lessThanOrEqualTo(220));
    expect(
      find.descendant(of: row, matching: find.byType(SingleChildScrollView)),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('context-color-color-0')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('context-color-color-11')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
