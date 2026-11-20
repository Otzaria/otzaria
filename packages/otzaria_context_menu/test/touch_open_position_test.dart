import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria_context_menu/otzaria_context_menu.dart';
import 'package:otzaria_context_menu/src/menu_placement.dart';

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

const _fingerRadius = 24.0; // חצי משטח לחיצה של 48

Finder get _panel => find.byWidgetPredicate(
  (widget) =>
      widget is Material &&
      widget.clipBehavior == Clip.antiAlias &&
      widget.elevation == 3,
);

Future<Rect> _openByTouch(
  WidgetTester tester, {
  required Size screen,
  required Offset at,
  TextDirection direction = TextDirection.rtl,
  int items = 7,
}) async {
  await tester.binding.setSurfaceSize(screen);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: Directionality(
        textDirection: direction,
        child: Scaffold(
          body: ContextMenuRegion(
            presentation: _presentation(),
            registerEscape: (_) => () {},
            menuBuilder: (_, _) => [
              for (var i = 0; i < items; i++)
                AppContextMenuEntry(label: 'פעולה $i', onTap: () {}),
            ],
            child: const ColoredBox(
              color: Colors.transparent,
              child: SizedBox.expand(),
            ),
          ),
        ),
      ),
    ),
  );
  final gesture = await tester.startGesture(at, kind: PointerDeviceKind.touch);
  await tester.pump(const Duration(milliseconds: 700));
  await gesture.up();
  await tester.pumpAndSettle();
  return tester.getRect(_panel);
}

bool _coversFinger(Rect panel, Offset at) =>
    panel.overlaps(Rect.fromCircle(center: at, radius: _fingerRadius));

void main() {
  const phone = Size(390, 740);

  group('menu opened by a long press with a finger', () {
    for (final direction in TextDirection.values) {
      testWidgets('$direction: mid-screen opens above the finger', (
        tester,
      ) async {
        const at = Offset(195, 400);
        final panel = await _openByTouch(
          tester,
          screen: phone,
          at: at,
          direction: direction,
        );
        expect(panel.bottom, lessThanOrEqualTo(at.dy - _fingerRadius));
        expect(_coversFinger(panel, at), isFalse);
      });
    }

    testWidgets('near the bottom the menu stays above the finger', (
      tester,
    ) async {
      const at = Offset(195, 700);
      final panel = await _openByTouch(tester, screen: phone, at: at);
      expect(_coversFinger(panel, at), isFalse);
      expect(panel.bottom, lessThanOrEqualTo(at.dy - _fingerRadius));
    });

    testWidgets('near the top, with no room above, it opens below the finger '
        'and not under it', (tester) async {
      const at = Offset(195, 60);
      final panel = await _openByTouch(tester, screen: phone, at: at);
      expect(_coversFinger(panel, at), isFalse);
      expect(panel.top, greaterThanOrEqualTo(at.dy + _fingerRadius));
      expect(panel.bottom, lessThanOrEqualTo(phone.height));
    });

    testWidgets('near the right and left edges the menu stays on screen and '
        'clear of the finger', (tester) async {
      for (final at in const [Offset(375, 300), Offset(15, 300)]) {
        final panel = await _openByTouch(tester, screen: phone, at: at);
        expect(panel.left, greaterThanOrEqualTo(0));
        expect(panel.right, lessThanOrEqualTo(phone.width));
        expect(_coversFinger(panel, at), isFalse, reason: 'finger at $at');
        await tester.pumpWidget(const SizedBox());
      }
    });

    testWidgets('on a wide short screen, with no room above or below, it opens '
        'beside the finger', (tester) async {
      const screen = Size(760, 300);
      const at = Offset(380, 150);
      final panel = await _openByTouch(tester, screen: screen, at: at);
      expect(_coversFinger(panel, at), isFalse);
      expect(
        panel.right <= at.dx - _fingerRadius ||
            panel.left >= at.dx + _fingerRadius,
        isTrue,
        reason: 'beside: $panel for finger $at',
      );
    });

    testWidgets('with no spot clear of the finger it still opens inside the '
        'screen', (tester) async {
      const screen = Size(320, 400);
      const at = Offset(160, 200);
      final panel = await _openByTouch(
        tester,
        screen: screen,
        at: at,
        items: 9,
      );
      expect(panel.top, greaterThanOrEqualTo(0));
      expect(panel.bottom, lessThanOrEqualTo(screen.height));
      expect(panel.left, greaterThanOrEqualTo(0));
      expect(panel.right, lessThanOrEqualTo(screen.width));
    });
  });

  testWidgets('a right-click with a mouse still opens at the pointer', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(phone);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: ContextMenuRegion(
              presentation: _presentation(),
              registerEscape: (_) => () {},
              menuBuilder: (_, _) => [
                for (var i = 0; i < 4; i++)
                  AppContextMenuEntry(label: 'פעולה $i', onTap: () {}),
              ],
              child: const ColoredBox(
                color: Colors.transparent,
                child: SizedBox.expand(),
              ),
            ),
          ),
        ),
      ),
    );
    const at = Offset(250, 300);
    final gesture = await tester.startGesture(
      at,
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await gesture.up();
    await tester.pumpAndSettle();
    final panel = tester.getRect(_panel);
    // RTL: התפריט גדל שמאלה מהמצביע וצמוד אליו מלמעלה.
    expect(panel.right, closeTo(at.dx, 0.5));
    expect(panel.top, closeTo(at.dy, 0.5));
  });

  group('placeMenuAwayFromFinger', () {
    const overlay = Size(390, 740);
    const panel = Size(200, 300);

    test('above when there is room', () {
      final result = placeMenuAwayFromFinger(
        overlay: overlay,
        anchor: const Offset(195, 400),
        panel: panel,
        isRtl: true,
      );
      expect(result.side, TouchMenuSide.above);
      expect(result.topLeft.dy + panel.height, 400 - kFingerClearance);
    });

    test('RTL grows left and LTR grows right from the finger column', () {
      final rtl = placeMenuAwayFromFinger(
        overlay: overlay,
        anchor: const Offset(300, 400),
        panel: panel,
        isRtl: true,
      );
      final ltr = placeMenuAwayFromFinger(
        overlay: overlay,
        anchor: const Offset(100, 400),
        panel: panel,
        isRtl: false,
      );
      expect(rtl.topLeft.dx + panel.width, 300);
      expect(ltr.topLeft.dx, 100);
    });

    test('below when only below has room, offset past the finger', () {
      final result = placeMenuAwayFromFinger(
        overlay: overlay,
        anchor: const Offset(195, 100),
        panel: panel,
        isRtl: true,
      );
      expect(result.side, TouchMenuSide.below);
      expect(result.topLeft.dy, 100 + kFingerClearance);
    });

    test('beside before below when the width allows it', () {
      final result = placeMenuAwayFromFinger(
        overlay: const Size(760, 400),
        anchor: const Offset(380, 200),
        panel: const Size(200, 300),
        isRtl: true,
      );
      expect(result.side, TouchMenuSide.beside);
      expect(
        result.topLeft.dx + 200,
        lessThanOrEqualTo(380 - kFingerClearance),
      );
    });

    test('falls back inside the screen when nothing clears the finger', () {
      final result = placeMenuAwayFromFinger(
        overlay: const Size(320, 400),
        anchor: const Offset(160, 200),
        panel: const Size(250, 360),
        isRtl: true,
      );
      expect(result.side, TouchMenuSide.fallback);
      expect(result.topLeft.dx, greaterThanOrEqualTo(8));
      expect(result.topLeft.dx + 250, lessThanOrEqualTo(312));
      expect(result.topLeft.dy, greaterThanOrEqualTo(8));
      expect(result.topLeft.dy + 360, lessThanOrEqualTo(392));
    });
  });
}
