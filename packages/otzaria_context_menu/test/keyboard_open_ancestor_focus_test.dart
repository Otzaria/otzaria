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

/// בקורא ובצפיין ה-PDF הפוקוס יושב על רכיב שהוא **מעל** אזורי התפריט
/// (ה-Focus של המסך כולו), לא בתוכם. Shift+F10 / Menu צריכים לפתוח גם שם
/// את תפריט האזור שבתוכו, ולהחזיר את הפוקוס בסגירה.
void main() {
  late FocusNode screenFocus;
  late FocusNode unrelatedFocus;
  final handlers = <OnKeyEventCallback>[];
  final secondaryTaps = <Offset>[];

  setUp(() {
    screenFocus = FocusNode(debugLabel: 'screen');
    unrelatedFocus = FocusNode(debugLabel: 'unrelated');
    handlers.clear();
    secondaryTaps.clear();
  });
  tearDown(() {
    screenFocus.dispose();
    unrelatedFocus.dispose();
  });

  VoidCallback register(OnKeyEventCallback handler) {
    handlers.add(handler);
    return () => handlers.remove(handler);
  }

  Widget region(String label) => ContextMenuRegion(
    presentation: _presentation(),
    registerEscape: register,
    onSecondaryTapDown: (details) => secondaryTaps.add(details.globalPosition),
    menuBuilder: (_, _) => [
      AppContextMenuEntry(label: 'פעולה של $label', onTap: () {}),
    ],
    child: SizedBox(height: 80, child: Center(child: Text(label))),
  );

  Future<void> mount(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: Column(
              children: [
                Focus(
                  focusNode: screenFocus,
                  child: Column(children: [region('א'), region('ב')]),
                ),
                Focus(focusNode: unrelatedFocus, child: const Text('מחוץ')),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> shiftF10(WidgetTester tester) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.f10);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.f10);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();
  }

  testWidgets('Shift+F10 with focus above the regions opens the top one', (
    tester,
  ) async {
    await mount(tester);
    screenFocus.requestFocus();
    await tester.pump();
    expect(screenFocus.hasPrimaryFocus, isTrue);

    await shiftF10(tester);

    expect(find.text('פעולה של א'), findsOneWidget);
    expect(find.text('פעולה של ב'), findsNothing);
    final region = tester.getRect(find.text('א'));
    final item = tester.getRect(find.text('פעולה של א'));
    expect(
      (item.center - region.center).distance,
      lessThan(400),
      reason: 'the menu opens near the region, not at the screen origin',
    );
  });

  testWidgets('the Menu key does the same, and Escape returns the focus', (
    tester,
  ) async {
    await mount(tester);
    screenFocus.requestFocus();
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.contextMenu);
    await tester.pumpAndSettle();
    expect(find.text('פעולה של א'), findsOneWidget);

    // התפריט שנפתח במקלדת מקבל פוקוס; Escape סוגר ומחזיר אותו למסך.
    final escape = handlers.last;
    escape(
      const KeyDownEvent(
        physicalKey: PhysicalKeyboardKey.escape,
        logicalKey: LogicalKeyboardKey.escape,
        timeStamp: Duration.zero,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('פעולה של א'), findsNothing);
    expect(screenFocus.hasPrimaryFocus, isTrue);
  });

  testWidgets('focus on a node with no region below it opens nothing', (
    tester,
  ) async {
    await mount(tester);
    unrelatedFocus.requestFocus();
    await tester.pump();

    await shiftF10(tester);

    expect(find.text('פעולה של א'), findsNothing);
    expect(find.text('פעולה של ב'), findsNothing);
  });

  testWidgets('a keyboard-opened menu reports its anchor like a right-click', (
    tester,
  ) async {
    await mount(tester);
    screenFocus.requestFocus();
    await tester.pump();

    await shiftF10(tester);

    // אתרים כמו הקורא והמפרשים מכינים את הקשר התפריט (השורה, הבחירה)
    // ב-onSecondaryTapDown; בלעדיו תפריט שנפתח במקלדת מציג הקשר ישן.
    expect(secondaryTaps, hasLength(1));
    final region = tester.getRect(find.text('א'));
    expect(
      (secondaryTaps.single - region.center).distance,
      lessThan(200),
      reason: 'the anchor is inside the region that opened',
    );
  });

  testWidgets('focus inside the region reports the anchor as well', (
    tester,
  ) async {
    final inner = FocusNode(debugLabel: 'inner');
    addTearDown(inner.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: ContextMenuRegion(
              presentation: _presentation(),
              registerEscape: register,
              onSecondaryTapDown: (details) =>
                  secondaryTaps.add(details.globalPosition),
              menuBuilder: (_, _) => [
                AppContextMenuEntry(label: 'פעולה', onTap: () {}),
              ],
              child: TextButton(
                focusNode: inner,
                onPressed: () {},
                child: const Text('פריט'),
              ),
            ),
          ),
        ),
      ),
    );
    inner.requestFocus();
    await tester.pump();

    await shiftF10(tester);

    expect(find.text('פעולה'), findsOneWidget);
    expect(secondaryTaps, hasLength(1));
    final button = tester.getRect(find.widgetWithText(TextButton, 'פריט'));
    expect(secondaryTaps.single.dy, closeTo(button.bottom, 6));
  });
}
