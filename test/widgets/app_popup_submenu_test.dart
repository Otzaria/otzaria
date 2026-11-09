import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/widgets/misc/app_popup_menu.dart';

class _MenuLog {
  final selections = <String>[];
  int closed = 0;
}

Future<_MenuLog> _pumpMenu(
  WidgetTester tester, {
  TextDirection direction = TextDirection.rtl,
  Alignment alignment = Alignment.center,
  bool withDivider = false,
  List<PopupMenuEntry<String>>? children,
}) async {
  final log = _MenuLog();
  final metrics = AppMenuMetrics.create(compactMenus: false);
  await tester.pumpWidget(
    MaterialApp(
      home: Directionality(
        textDirection: direction,
        child: Scaffold(
          body: Align(
            alignment: alignment,
            child: SizedBox(
              width: 80,
              height: 36,
              child: AppPopupMenuButton<String>(
                itemBuilder: (context) => [
                  buildAppSubmenuPopupMenuItem<String>(
                    context: context,
                    metrics: metrics,
                    label: 'אפשרויות',
                    menuChildren:
                        children ??
                        [
                          buildAppPopupMenuItem<String>(
                            context,
                            const AppMenuEntry(
                              value: 'child',
                              label: 'פעולה פנימית',
                            ),
                            metrics,
                            null,
                          ),
                          if (withDivider) const PopupMenuDivider(),
                          buildAppPopupMenuItem<String>(
                            context,
                            const AppMenuEntry(
                              value: 'disabled',
                              label: 'פעולה מושבתת',
                              enabled: false,
                            ),
                            metrics,
                            null,
                          ),
                        ],
                    onSelected: log.selections.add,
                  ),
                  buildAppPopupMenuItem<String>(
                    context,
                    const AppMenuEntry(value: 'sibling', label: 'פעולה אחרת'),
                    metrics,
                    null,
                  ),
                ],
                onSelected: log.selections.add,
                onMenuClosed: () => log.closed++,
                child: const Center(child: Text('פתח')),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('פתח'));
  await tester.pumpAndSettle();
  return log;
}

Future<TestGesture> _mouseOver(
  WidgetTester tester,
  Finder target,
) async {
  final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await mouse.addPointer(location: Offset.zero);
  addTearDown(mouse.removePointer);
  await mouse.moveTo(tester.getCenter(target));
  await tester.pump();
  return mouse;
}

bool _arrowPointsRight(WidgetTester tester) {
  final arrowFinder = find.byWidgetPredicate(
    (widget) =>
        widget is Icon &&
        (widget.icon == FluentIcons.chevron_left_16_regular ||
            widget.icon == FluentIcons.chevron_right_16_regular),
  );
  expect(arrowFinder, findsOneWidget);
  final icon = tester.widget<Icon>(arrowFinder);
  final direction =
      icon.textDirection ?? Directionality.of(tester.element(arrowFinder));
  final glyphPointsRight = icon.icon == FluentIcons.chevron_right_16_regular;
  final isMirrored =
      icon.icon!.matchTextDirection && direction == TextDirection.rtl;
  return glyphPointsRight != isMirrored;
}

void _expectArrowPointsToChild(WidgetTester tester) {
  final parent = tester.getRect(find.text('אפשרויות'));
  final child = tester.getRect(find.text('פעולה פנימית'));
  expect(
    _arrowPointsRight(tester),
    child.center.dx > parent.center.dx,
    reason: 'כיוון החץ המצויר, לאחר שיקוף RTL, חייב להצביע אל הילד',
  );
}

void main() {
  testWidgets('לחיצה פותחת תת-תפריט ובחירת ילד מופעלת פעם אחת וסוגרת הכול', (
    tester,
  ) async {
    final log = await _pumpMenu(tester);
    expect(find.text('פעולה פנימית'), findsNothing);

    await tester.tap(find.text('אפשרויות'));
    await tester.pumpAndSettle();
    expect(find.text('פעולה פנימית'), findsOneWidget);

    await tester.tap(find.text('פעולה פנימית'));
    await tester.pumpAndSettle();
    expect(log.selections, ['child']);
    expect(log.closed, 1);
    expect(find.text('אפשרויות'), findsNothing);
    expect(find.text('פעולה פנימית'), findsNothing);
  });

  testWidgets('ריחוף פותח תת-תפריט אחרי השהיה', (tester) async {
    await _pumpMenu(tester);
    await _mouseOver(tester, find.text('אפשרויות'));

    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('פעולה פנימית'), findsNothing);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(find.text('פעולה פנימית'), findsOneWidget);
  });

  testWidgets('ריחוף חולף אינו פותח תת-תפריט', (tester) async {
    await _pumpMenu(tester);
    final mouse = await _mouseOver(tester, find.text('אפשרויות'));

    await tester.pump(const Duration(milliseconds: 100));
    await mouse.moveTo(tester.getCenter(find.text('פעולה אחרת')));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    expect(find.text('פעולה פנימית'), findsNothing);
    expect(find.text('אפשרויות'), findsOneWidget);
  });

  testWidgets('מעבר מאב לילד משאיר את תת-התפריט פתוח', (tester) async {
    await _pumpMenu(tester);
    final mouse = await _mouseOver(tester, find.text('אפשרויות'));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();

    await mouse.moveTo(tester.getCenter(find.text('פעולה פנימית')));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    expect(find.text('פעולה פנימית'), findsOneWidget);
    expect(find.text('אפשרויות'), findsOneWidget);
  });

  for (final direction in TextDirection.values) {
    for (final clickTarget in ['label', 'top', 'left', 'right']) {
      testWidgets('לחיצה אחרי ריחוף משאירה תת-תפריט פתוח: $direction, '
          'target=$clickTarget (issue #3777)', (tester) async {
        final log = await _pumpMenu(tester, direction: direction);
        final mouse = await _mouseOver(tester, find.text('אפשרויות'));
        await tester.pump(const Duration(milliseconds: 600));
        await tester.pumpAndSettle();
        expect(find.text('פעולה פנימית'), findsOneWidget);

        final row = tester.getRect(
          find.ancestor(
            of: find.text('אפשרויות'),
            matching: find.byType(SubmenuButton),
          ),
        );
        final position = switch (clickTarget) {
          'top' => Offset(row.center.dx, row.top + 2),
          'left' => Offset(row.left + 2, row.center.dy),
          'right' => Offset(row.right - 2, row.center.dy),
          _ => tester.getCenter(find.text('אפשרויות')),
        };
        await mouse.moveTo(position);
        await mouse.down(position);
        await mouse.up();
        await tester.pumpAndSettle();
        expect(find.text('פעולה פנימית'), findsOneWidget);
        expect(log.closed, 0);
        expect(log.selections, isEmpty);

        await tester.tap(find.text('פעולה פנימית'));
        await tester.pumpAndSettle();
        expect(log.selections, ['child']);
        expect(log.closed, 1);
      });
    }

    for (final leaveFromChild in [false, true]) {
      for (final outside in [false, true]) {
        testWidgets(
          'יציאה מתת-תפריט סוגרת רק את הילד: $direction, '
          'child=$leaveFromChild, outside=$outside',
          (tester) async {
            final log = await _pumpMenu(tester, direction: direction);
            final mouse = await _mouseOver(tester, find.text('אפשרויות'));
            await tester.pump(const Duration(milliseconds: 600));
            await tester.pumpAndSettle();
            if (leaveFromChild) {
              await mouse.moveTo(tester.getCenter(find.text('פעולה פנימית')));
              await tester.pump();
            }
            await mouse.moveTo(
              outside ? Offset.zero : tester.getCenter(find.text('פעולה אחרת')),
            );
            await tester.pump(const Duration(milliseconds: 600));
            await tester.pumpAndSettle();

            expect(find.text('פעולה פנימית'), findsNothing);
            expect(find.text('אפשרויות'), findsOneWidget);
            expect(log.selections, isEmpty);
            expect(log.closed, 0);
          },
        );
      }
    }

    testWidgets('גרירת עכבר החוצה סוגרת את הילד: $direction', (tester) async {
      await _pumpMenu(tester, direction: direction);
      final mouse = await _mouseOver(tester, find.text('אפשרויות'));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      await mouse.down(tester.getCenter(find.text('אפשרויות')));
      await mouse.moveTo(Offset.zero);
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      expect(find.text('פעולה פנימית'), findsNothing);
      await mouse.up();
    });

    testWidgets('יציאת העכבר מהחלון סוגרת את הילד: $direction', (tester) async {
      await _pumpMenu(tester, direction: direction);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(tester.getCenter(find.text('אפשרויות')));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      expect(find.text('פעולה פנימית'), findsOneWidget);
      await mouse.removePointer();
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      expect(find.text('פעולה פנימית'), findsNothing);
    });

    testWidgets('תנועות בחלון אחר אינן משנות את סגירת הילד: $direction', (
      tester,
    ) async {
      await _pumpMenu(tester, direction: direction);
      final mouse = await _mouseOver(tester, find.text('אפשרויות'));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      final router = GestureBinding.instance.pointerRouter;
      router.route(
        PointerHoverEvent(
          viewId: tester.view.viewId + 1,
          position: Offset.zero,
        ),
      );
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      expect(find.text('פעולה פנימית'), findsOneWidget);

      await mouse.moveTo(Offset.zero);
      router.route(
        PointerHoverEvent(
          viewId: tester.view.viewId + 1,
          position: tester.getCenter(find.text('אפשרויות')),
        ),
      );
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      expect(find.text('פעולה פנימית'), findsNothing);
    });

    testWidgets('ריפוד הפאנל שומר ילד פתוח ומעבר החוצה סוגר: $direction', (
      tester,
    ) async {
      final log = await _pumpMenu(tester, direction: direction);
      final mouse = await _mouseOver(tester, find.text('אפשרויות'));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      Rect? panel;
      final item = find.ancestor(
        of: find.text('פעולה פנימית'),
        matching: find.byType(MenuItemButton),
      );
      tester.element(item).visitAncestorElements((
        element,
      ) {
        if (element.widget is! Material) return true;
        final box = element.findRenderObject()! as RenderBox;
        panel = box.localToGlobal(Offset.zero) & box.size;
        return false;
      });
      final padding = Offset(panel!.center.dx, panel!.top + 2);
      expect(
        padding.dy,
        lessThan(tester.getRect(item).top),
      );
      await mouse.moveTo(padding);
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      expect(find.text('פעולה פנימית'), findsOneWidget);

      await mouse.moveTo(Offset.zero);
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      expect(find.text('פעולה פנימית'), findsNothing);
      expect(find.text('אפשרויות'), findsOneWidget);
      expect(log.closed, 0);
    });

    testWidgets('ניווט במקלדת מפעיל ילד פעם אחת: $direction', (tester) async {
      final log = await _pumpMenu(tester, direction: direction);
      await tester.tap(find.text('אפשרויות'));
      await tester.pumpAndSettle();
      final parent = tester.getCenter(find.text('אפשרויות'));
      final child = tester.getCenter(find.text('פעולה פנימית'));
      await tester.sendKeyEvent(
        child.dx > parent.dx
            ? LogicalKeyboardKey.arrowRight
            : LogicalKeyboardKey.arrowLeft,
      );
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(log.selections, ['child']);
      expect(log.closed, 1);
      expect(find.text('אפשרויות'), findsNothing);
    });

    testWidgets('חזרה לאב מבטלת סגירת תת-תפריט: $direction', (tester) async {
      await _pumpMenu(tester, direction: direction);
      final mouse = await _mouseOver(tester, find.text('אפשרויות'));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      await mouse.moveTo(tester.getCenter(find.text('פעולה אחרת')));
      await tester.pump(const Duration(milliseconds: 100));
      await mouse.moveTo(tester.getCenter(find.text('אפשרויות')));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();

      expect(find.text('פעולה פנימית'), findsOneWidget);
    });
  }

  // issue #4479
  for (final direction in TextDirection.values) {
    for (final alignment in [Alignment.centerLeft, Alignment.centerRight]) {
      testWidgets('החץ כבר מצביע לכיוון הפתיחה לפני שהתת-תפריט נפתח, '
          'והוא לא מתהפך אחר כך: $direction, $alignment', (tester) async {
        await _pumpMenu(tester, direction: direction, alignment: alignment);
        final before = _arrowPointsRight(tester);

        await _mouseOver(tester, find.text('אפשרויות'));
        await tester.pump(const Duration(milliseconds: 600));
        await tester.pumpAndSettle();
        _expectArrowPointsToChild(tester);
        expect(_arrowPointsRight(tester), before);
      });
    }

    for (final alignment in [Alignment.centerLeft, Alignment.centerRight]) {
      testWidgets('הסמן עובר אל התת-תפריט הפתוח: הוא נשאר פתוח והחץ לא משתנה, '
          '$direction, $alignment', (tester) async {
        await _pumpMenu(tester, direction: direction, alignment: alignment);
        final mouse = await _mouseOver(tester, find.text('אפשרויות'));
        await tester.pump(const Duration(milliseconds: 600));
        await tester.pumpAndSettle();
        final before = _arrowPointsRight(tester);

        await mouse.moveTo(tester.getCenter(find.text('פעולה פנימית')));
        await tester.pump(const Duration(milliseconds: 900));
        await tester.pumpAndSettle();
        expect(find.text('פעולה פנימית'), findsOneWidget);
        _expectArrowPointsToChild(tester);
        expect(_arrowPointsRight(tester), before);
      });
    }

    for (final opened in [false, true]) {
      testWidgets('הסמן עוזב את שורת התת-תפריט: השורה לא נשארת בפוקוס, '
          '$direction, נפתח=$opened', (tester) async {
        await _pumpMenu(tester, direction: direction);
        final submenu = find.ancestor(
          of: find.text('אפשרויות'),
          matching: find.byType(SubmenuButton),
        );
        final mouse = await _mouseOver(tester, find.text('אפשרויות'));
        await tester.pump(Duration(milliseconds: opened ? 600 : 100));
        expect(
          tester.widget<SubmenuButton>(submenu).focusNode!.hasFocus,
          isTrue,
        );

        await mouse.moveTo(tester.getCenter(find.text('פעולה אחרת')));
        await tester.pump(const Duration(milliseconds: 600));
        await tester.pumpAndSettle();
        expect(find.text('פעולה פנימית'), findsNothing);
        expect(
          tester.widget<SubmenuButton>(submenu).focusNode!.hasFocus,
          isFalse,
        );
      });
    }
  }

  testWidgets('לחיצה אחת על אח פועלת גם כאשר תת-תפריט פתוח', (tester) async {
    final log = await _pumpMenu(tester);
    await tester.tap(find.text('אפשרויות'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('פעולה אחרת'));
    await tester.pumpAndSettle();
    expect(log.selections, ['sibling']);
    expect(log.closed, 1);
    expect(find.text('אפשרויות'), findsNothing);
    expect(find.text('פעולה פנימית'), findsNothing);
  });

  testWidgets('ילד מושבת אינו מפעיל פעולה ואינו סוגר את התפריט', (
    tester,
  ) async {
    final log = await _pumpMenu(tester);
    await tester.tap(find.text('אפשרויות'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('פעולה מושבתת'));
    await tester.pumpAndSettle();
    expect(log.selections, isEmpty);
    expect(log.closed, 0);
    expect(find.text('אפשרויות'), findsOneWidget);
    expect(find.text('פעולה פנימית'), findsOneWidget);
  });

  testWidgets('הסרת מארח עם תת-תפריט פתוח מנקה overlays וטיימרים', (
    tester,
  ) async {
    final log = await _pumpMenu(tester);
    final mouse = await _mouseOver(tester, find.text('אפשרויות'));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    await mouse.moveTo(tester.getCenter(find.text('פעולה אחרת')));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(log.selections, isEmpty);
    expect(find.text('אפשרויות'), findsNothing);
    expect(find.text('פעולה פנימית'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Escape סוגר קודם את הילד ואחר כך את תפריט האב', (tester) async {
    final log = await _pumpMenu(tester);
    await tester.tap(find.text('אפשרויות'));
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('פעולה פנימית'), findsNothing);
    expect(find.text('אפשרויות'), findsOneWidget);
    expect(log.closed, 0);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('אפשרויות'), findsNothing);
    expect(log.selections, isEmpty);
    expect(log.closed, 1);
  });

  testWidgets('תת-תפריט מציג מפריד בין הילדים', (tester) async {
    await _pumpMenu(tester, withDivider: true);
    await tester.tap(find.text('אפשרויות'));
    await tester.pumpAndSettle();

    expect(find.byType(Divider), findsOneWidget);
    final first = tester.getRect(find.text('פעולה פנימית'));
    final second = tester.getRect(find.text('פעולה מושבתת'));
    final divider = tester.getRect(find.byType(Divider));
    expect(divider.center.dy, greaterThan(first.bottom));
    expect(divider.center.dy, lessThan(second.top));
  });

  testWidgets('פעולת ילד חושפת תווית ופעולה נגישה', (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      final log = await _pumpMenu(tester);
      await tester.tap(find.text('אפשרויות'));
      await tester.pumpAndSettle();

      final action = find.text('פעולה פנימית');
      final data = tester.getSemantics(action).getSemanticsData();
      expect(data.label, 'פעולה פנימית');
      expect(data.hasAction(SemanticsAction.tap), isTrue);
      await tester.tap(action);
      await tester.pumpAndSettle();
      expect(log.selections, ['child']);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('ילד עם onTap וללא value מופעל פעם אחת וסוגר את השרשרת', (
    tester,
  ) async {
    var tapped = 0;
    final log = await _pumpMenu(
      tester,
      children: [
        PopupMenuItem<String>(
          onTap: () => tapped++,
          child: const Text('פעולה ללא ערך'),
        ),
      ],
    );
    await tester.tap(find.text('אפשרויות'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('פעולה ללא ערך'));
    await tester.pumpAndSettle();

    expect(tapped, 1);
    expect(log.selections, isEmpty);
    expect(log.closed, 1);
    expect(find.text('אפשרויות'), findsNothing);
    expect(find.text('פעולה ללא ערך'), findsNothing);
  });

  testWidgets('ילד עם onTap ו-value מפעיל כל callback פעם אחת', (tester) async {
    var tapped = 0;
    final log = await _pumpMenu(
      tester,
      children: [
        PopupMenuItem<String>(
          value: 'custom',
          onTap: () => tapped++,
          child: const Text('פעולה עם ערך'),
        ),
      ],
    );
    await tester.tap(find.text('אפשרויות'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('פעולה עם ערך'));
    await tester.pumpAndSettle();

    expect(tapped, 1);
    expect(log.selections, ['custom']);
    expect(log.closed, 1);
    expect(find.text('אפשרויות'), findsNothing);
  });

  testWidgets('שורת תת-תפריט האב שומרת על צפיפות התפריט', (tester) async {
    await _pumpMenu(tester);
    final metrics = AppMenuMetrics.create(compactMenus: false);
    final entry = find.ancestor(
      of: find.text('אפשרויות'),
      matching: find.byType(PopupMenuItem<String>),
    );
    expect(entry, findsOneWidget);
    expect(tester.getSize(entry).height, metrics.itemHeight);
  });

  testWidgets('מרווח מרכזי הילדים נשאר בגובה שורת התפריט', (tester) async {
    await _pumpMenu(tester);
    await tester.tap(find.text('אפשרויות'));
    await tester.pumpAndSettle();
    final metrics = AppMenuMetrics.create(compactMenus: false);
    final first = tester.getCenter(find.text('פעולה פנימית'));
    final second = tester.getCenter(find.text('פעולה מושבתת'));

    expect(second.dy - first.dy, metrics.itemHeight);
  });

  for (final direction in TextDirection.values) {
    for (final alignment in [Alignment.centerLeft, Alignment.centerRight]) {
      testWidgets('תת-תפריט נשאר בגבולות חלון צר: $direction, $alignment', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(340, 500);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await _pumpMenu(tester, direction: direction, alignment: alignment);
        await tester.tap(find.text('אפשרויות'));
        await tester.pumpAndSettle();

        for (final label in ['פעולה פנימית', 'פעולה מושבתת']) {
          final rect = tester.getRect(find.text(label));
          expect(rect.left, greaterThanOrEqualTo(0));
          expect(rect.right, lessThanOrEqualTo(340));
          expect(rect.top, greaterThanOrEqualTo(0));
          expect(rect.bottom, lessThanOrEqualTo(500));
        }
        _expectArrowPointsToChild(tester);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('החץ המצויר פונה אל הילד במרכז חלון רחב: $direction', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await _pumpMenu(tester, direction: direction);
      await tester.tap(find.text('אפשרויות'));
      await tester.pumpAndSettle();

      _expectArrowPointsToChild(tester);
      expect(tester.takeException(), isNull);
    });
  }
}
