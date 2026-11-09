import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show SelectedContent;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria_context_menu/otzaria_context_menu.dart';

final _scroll = find.byKey(const ValueKey('context-icon-row-scroll'));
const _source = 'בראשית ברא אלהים את השמים ואת הארץ';

MenuPresentation _presentation() => MenuPresentation(
  metrics: AppMenuMetrics.create(compactMenus: false),
  borderRadius: BorderRadius.circular(8),
  iconBuilder: (context, icon, size, color, mirror) =>
      SizedBox.square(dimension: size),
  selectedMarkBuilder: (context, size, color) => const Text('✓'),
  submenuArrowBuilder: (context, right, size, color) => Text(right ? '›' : '‹'),
  downArrowBuilder: (context, size, color) => const Text('⌄'),
);

Future<GlobalKey<ContextMenuRegionState>> _mount(
  WidgetTester tester, {
  TextDirection direction = TextDirection.rtl,
  double scale = 1,
  int count = 12,
  int trailingCount = 1,
  bool submenu = false,
  FocusNode? focus,
  ValueChanged<SelectedContent?>? onSelectionChanged,
  VoidCallback? action,
}) async {
  final key = GlobalKey<ContextMenuRegionState>();
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(platform: TargetPlatform.windows),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Directionality(
        textDirection: direction,
        child: Scaffold(
          body: SelectionArea(
            focusNode: focus,
            contextMenuBuilder: (_, _) => const SizedBox.shrink(),
            onSelectionChanged: onSelectionChanged,
            child: ContextMenuRegion(
              key: key,
              presentation: _presentation(),
              registerEscape: (handler) {
                FocusManager.instance.addEarlyKeyEventHandler(handler);
                return () =>
                    FocusManager.instance.removeEarlyKeyEventHandler(handler);
              },
              shouldPreserveSelectionOnSecondaryTap: (_) => true,
              menuBuilder: (_, _) => [
                AppContextMenuEntry.iconRow([
                  for (var i = 0; i < count; i++)
                    AppContextMenuIconAction(
                      icon: Icons.search,
                      label: 'פעולה $i',
                      tooltip: 'רמז $i',
                      onTap: action ?? () {},
                      submenuBuilder: submenu && i == count - 1
                          ? () => [
                              AppContextMenuSubAction(
                                label: 'קישור למקטע',
                                onTap: action ?? () {},
                              ),
                            ]
                          : null,
                    ),
                ]),
                for (var i = 0; i < trailingCount; i++)
                  AppContextMenuEntry(
                    label: 'תווית ארוכה למדי לשמירת רוחב תפריט קבוע $i',
                    onTap: () {},
                  ),
              ],
              child: const Center(child: Text(_source)),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return key;
}

ScrollableState _state(WidgetTester tester) => tester.state<ScrollableState>(
  find.descendant(of: _scroll, matching: find.byType(Scrollable)),
);

Future<void> _wheel(WidgetTester tester, Offset delta) async {
  await tester.sendEventToBinding(
    PointerScrollEvent(
      kind: PointerDeviceKind.mouse,
      position: tester.getCenter(_scroll),
      scrollDelta: delta,
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _selectSource(WidgetTester tester) async {
  final rect = tester.getRect(find.text(_source));
  final mouse = await tester.startGesture(
    rect.centerLeft + const Offset(2, 0),
    kind: PointerDeviceKind.mouse,
  );
  await mouse.moveTo(rect.center);
  await tester.pump();
  await mouse.moveTo(rect.centerRight - const Offset(2, 0));
  await mouse.up();
  await tester.pumpAndSettle();
}

void main() {
  for (final direction in TextDirection.values) {
    for (final jump in [false, true]) {
      testWidgets(
        'parent scrolling closes icon submenu ($direction, jump=$jump)',
        (
          tester,
        ) async {
          final focus = FocusNode();
          addTearDown(focus.dispose);
          String? selected;
          final key = await _mount(
            tester,
            direction: direction,
            focus: focus,
            onSelectionChanged: (value) => selected = value?.plainText,
            count: 1,
            submenu: true,
            trailingCount: 40,
          );
          await _selectSource(tester);
          expect(selected, isNotEmpty);
          final before = selected;
          await key.currentState!.openMenuAt(const Offset(400, 100));
          await tester.pumpAndSettle();
          await tester.tap(find.text('פעולה 0'));
          await tester.pumpAndSettle();
          expect(find.text('קישור למקטע'), findsOneWidget);
          final target = find.text('תווית ארוכה למדי לשמירת רוחב תפריט קבוע 5');
          final position = Scrollable.of(tester.element(target)).position;
          expect(position.pixels, 0);
          if (jump) {
            position.jumpTo(300);
          } else {
            await tester.sendEventToBinding(
              PointerScrollEvent(
                kind: PointerDeviceKind.mouse,
                position: tester.getCenter(target),
                scrollDelta: const Offset(0, 300),
              ),
            );
          }
          await tester.pumpAndSettle();
          expect(position.pixels, greaterThan(0));
          expect(find.text('פעולה 0').hitTestable(), findsNothing);
          expect(find.text('קישור למקטע'), findsNothing);
          expect(_scroll, findsOneWidget);
          expect(selected, before);
          expect(focus.hasPrimaryFocus, isTrue);
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await tester.pumpAndSettle();
          expect(_scroll, findsNothing);
          expect(selected, before);
          expect(focus.hasPrimaryFocus, isTrue);
          expect(tester.takeException(), isNull);
        },
      );
    }
    testWidgets(
      'horizontal scrolling closes submenu and disposal cleans up ($direction)',
      (
        tester,
      ) async {
        final key = await _mount(tester, direction: direction, submenu: true);
        await key.currentState!.openMenuAt(const Offset(400, 100));
        await tester.pumpAndSettle();
        await tester.drag(
          _scroll,
          Offset(direction == TextDirection.rtl ? 2000 : -2000, 0),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('פעולה 11'));
        await tester.pumpAndSettle();
        expect(find.text('קישור למקטע'), findsOneWidget);
        await tester.drag(
          _scroll,
          Offset(direction == TextDirection.rtl ? -2000 : 2000, 0),
        );
        await tester.pumpAndSettle();
        expect(find.text('קישור למקטע'), findsNothing);
        expect(_scroll, findsOneWidget);
        await tester.drag(
          _scroll,
          Offset(direction == TextDirection.rtl ? 2000 : -2000, 0),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('פעולה 11'));
        await tester.pumpAndSettle();
        expect(find.text('קישור למקטע'), findsOneWidget);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        expect(find.text('קישור למקטע'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
  for (final direction in TextDirection.values) {
    for (final scale in [1.0, 2.0, 3.0]) {
      for (final count in [1, 4, 12]) {
        testWidgets('layout $direction scale=$scale count=$count', (
          tester,
        ) async {
          final key = await _mount(
            tester,
            direction: direction,
            scale: scale,
            count: count,
          );
          await key.currentState!.openMenuAt(const Offset(400, 150));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          if (count == 1) {
            final panel = find
                .ancestor(of: _scroll, matching: find.byType(Material))
                .first;
            expect(
              tester.getCenter(_scroll).dx,
              closeTo(tester.getCenter(panel).dx, 0.1),
            );
            expect(_state(tester).position.maxScrollExtent, 0);
          }
          if (_state(tester).position.maxScrollExtent > 0) {
            await tester.drag(
              _scroll,
              Offset(direction == TextDirection.rtl ? 2000 : -2000, 0),
            );
            await tester.pumpAndSettle();
          }
          expect(find.text('פעולה ${count - 1}').hitTestable(), findsOneWidget);
          expect(tester.takeException(), isNull);
        });
      }
    }
    testWidgets('desktop input $direction', (tester) async {
      final key = await _mount(tester, direction: direction);
      await key.currentState!.openMenuAt(const Offset(400, 150));
      await tester.pumpAndSettle();
      final position = _state(tester).position;
      expect(position.maxScrollExtent, greaterThan(0));
      await tester.drag(
        _scroll,
        Offset(direction == TextDirection.rtl ? 500 : -500, 0),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();
      expect(position.pixels, 0);
      await _wheel(tester, const Offset(0, 200));
      expect(position.pixels, 0);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await _wheel(
        tester,
        Offset(0, direction == TextDirection.rtl ? -2000 : 2000),
      );
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      expect(position.pixels, position.maxScrollExtent);
      expect(find.text('פעולה 11').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
    testWidgets('selection and submenu survive scrolling $direction', (
      tester,
    ) async {
      final focus = FocusNode();
      addTearDown(focus.dispose);
      String? selected;
      var acted = false;
      await _mount(
        tester,
        direction: direction,
        submenu: true,
        focus: focus,
        onSelectionChanged: (value) => selected = value?.plainText,
        action: () => acted = true,
      );
      await _selectSource(tester);
      final rect = tester.getRect(find.text(_source));
      expect(selected, isNotEmpty);
      final before = selected;
      final rightClick = await tester.startGesture(
        rect.center,
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryButton,
      );
      await rightClick.up();
      await tester.pumpAndSettle();
      expect(selected, before);
      expect(focus.hasPrimaryFocus, isTrue);
      await tester.drag(
        _scroll,
        Offset(direction == TextDirection.rtl ? 2000 : -2000, 0),
      );
      await tester.pumpAndSettle();
      expect(selected, before);
      expect(focus.hasPrimaryFocus, isTrue);
      await tester.tap(find.text('פעולה 11'));
      await tester.pumpAndSettle();
      expect(find.text('קישור למקטע'), findsOneWidget);
      expect(selected, before);
      expect(focus.hasPrimaryFocus, isTrue);
      await tester.tap(find.text('קישור למקטע'));
      await tester.pumpAndSettle();
      expect(acted, isTrue);
      expect(_scroll, findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
