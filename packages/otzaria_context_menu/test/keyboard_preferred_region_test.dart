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

/// בקורא הפוקוס יושב על רכיב שמעל אזורי התפריט (שורה לכל אזור). המקש פותח
/// את תפריט **השורה הנבחרת** (`keyboardPreferred`), ורק כשאין כזו (או שאינה
/// נראית) את השורה הנראית העליונה, כמו קודם (סעיף 10).
void main() {
  late FocusNode screenFocus;
  final secondaryTaps = <Offset>[];

  setUp(() {
    screenFocus = FocusNode(debugLabel: 'screen');
    secondaryTaps.clear();
  });
  tearDown(() => screenFocus.dispose());

  Widget region(String label, {bool preferred = false}) => ContextMenuRegion(
    presentation: _presentation(),
    registerEscape: (handler) => () {},
    keyboardPreferred: preferred,
    onSecondaryTapDown: (details) => secondaryTaps.add(details.globalPosition),
    menuBuilder: (_, _) => [
      AppContextMenuEntry(label: 'פעולה של $label', onTap: () {}),
    ],
    child: SizedBox(height: 80, child: Center(child: Text(label))),
  );

  Future<void> mount(WidgetTester tester, List<Widget> regions) async {
    tester.view.physicalSize = const Size(800, 400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: Focus(
              focusNode: screenFocus,
              child: SingleChildScrollView(child: Column(children: regions)),
            ),
          ),
        ),
      ),
    );
    screenFocus.requestFocus();
    await tester.pump();
  }

  Future<void> menuKey(WidgetTester tester) async {
    await tester.sendKeyEvent(LogicalKeyboardKey.contextMenu);
    await tester.pumpAndSettle();
  }

  testWidgets('opens the preferred (selected) row, not the top one', (
    tester,
  ) async {
    await mount(tester, [
      region('א'),
      region('ב'),
      region('ג', preferred: true),
    ]);

    await menuKey(tester);

    expect(find.text('פעולה של ג'), findsOneWidget);
    expect(find.text('פעולה של א'), findsNothing);
    expect(secondaryTaps, hasLength(1));
    final row = tester.getRect(find.text('ג'));
    expect(
      (secondaryTaps.single - row.center).distance,
      lessThan(60),
      reason: 'the anchor is on the preferred row',
    );
  });

  testWidgets('without a preferred row the top visible one opens', (
    tester,
  ) async {
    await mount(tester, [region('א'), region('ב'), region('ג')]);

    await menuKey(tester);

    expect(find.text('פעולה של א'), findsOneWidget);
  });

  testWidgets('a preferred row scrolled out of view is skipped', (
    tester,
  ) async {
    // שש שורות של 80 בחלון של 400: האחרונה מחוץ למסך.
    await mount(tester, [
      for (final label in ['א', 'ב', 'ג', 'ד', 'ה']) region(label),
      region('ו', preferred: true),
      region('ז'),
    ]);
    expect(find.text('ז').hitTestable(), findsNothing);

    await menuKey(tester);

    expect(find.text('פעולה של א'), findsOneWidget);
    expect(find.text('פעולה של ו'), findsNothing);
  });
}
