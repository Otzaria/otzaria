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

void main() {
  late FocusNode opener;
  late List<String> activated;

  setUp(() {
    opener = FocusNode(debugLabel: 'opener');
    activated = [];
  });
  tearDown(() => opener.dispose());

  Future<ContextMenuRegionState> mount(
    WidgetTester tester, {
    TextDirection direction = TextDirection.rtl,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: direction,
          child: Scaffold(
            body: Center(
              child: ContextMenuRegion(
                presentation: _presentation(),
                registerEscape: (_) => () {},
                menuBuilder: (_, _) => [
                  AppContextMenuEntry(
                    label: 'ראשון',
                    onTap: () => activated.add('first'),
                  ),
                  AppContextMenuEntry(
                    label: 'עוד',
                    children: [
                      AppContextMenuEntry(
                        label: 'פנימי',
                        onTap: () => activated.add('inner'),
                      ),
                    ],
                  ),
                  AppContextMenuEntry(
                    label: 'אחרון',
                    onTap: () => activated.add('last'),
                  ),
                ],
                child: TextButton(
                  focusNode: opener,
                  onPressed: () {},
                  child: const Text('פריט ברשימה'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    opener.requestFocus();
    await tester.pump();
    return tester.state<ContextMenuRegionState>(find.byType(ContextMenuRegion));
  }

  Future<void> shiftF10(WidgetTester tester) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.f10);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.f10);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();
  }

  Future<void> key(WidgetTester tester, LogicalKeyboardKey k) async {
    await tester.sendKeyEvent(k);
    await tester.pumpAndSettle();
  }

  // החץ שפותח את תת-התפריט הוא זה שמצביע לצד שאליו הוא נפתח, וסימן השורה
  // ('›' או '‹') מראה איזה צד נבחר.
  (LogicalKeyboardKey open, LogicalKeyboardKey close) sideArrows() =>
      find.text('›').evaluate().isNotEmpty
      ? (LogicalKeyboardKey.arrowRight, LogicalKeyboardKey.arrowLeft)
      : (LogicalKeyboardKey.arrowLeft, LogicalKeyboardKey.arrowRight);

  bool onSubmenuRow() =>
      FocusManager.instance.primaryFocus?.debugLabel == 'AppSubmenuButton';

  for (final direction in TextDirection.values) {
    testWidgets('a keyboard-opened menu: the arrows reach the submenu row, '
        'open it, and Enter runs its item ($direction)', (tester) async {
      await mount(tester, direction: direction);
      await shiftF10(tester);

      await key(tester, LogicalKeyboardKey.arrowDown);
      expect(
        onSubmenuRow(),
        isTrue,
        reason: 'the submenu row is part of the arrow-key traversal',
      );

      await key(tester, sideArrows().$1);
      expect(find.text('פנימי'), findsOneWidget);
      expect(activated, isEmpty, reason: 'the row itself runs nothing');

      await key(tester, LogicalKeyboardKey.enter);
      expect(activated, ['inner']);
      expect(find.text('פנימי'), findsNothing);
      expect(opener.hasPrimaryFocus, isTrue);
    });
  }

  testWidgets('a keyboard-opened submenu closes with the arrow opposite to '
      'the opening one and focus returns to its row', (tester) async {
    await mount(tester);
    await shiftF10(tester);
    await key(tester, LogicalKeyboardKey.arrowDown);

    await key(tester, sideArrows().$1);
    expect(find.text('פנימי'), findsOneWidget);
    // הצד נקבע מחדש בפתיחה לפי המקום שנותר, ולכן קוראים אותו שוב.
    await key(tester, sideArrows().$2);
    expect(find.text('פנימי'), findsNothing);
    expect(onSubmenuRow(), isTrue);
    expect(activated, isEmpty);
  });

  testWidgets('pointer-opened menus keep the focus-preserving submenu rows', (
    tester,
  ) async {
    final region = await mount(tester);
    await region.openMenuAt(const Offset(100, 300));
    await tester.pumpAndSettle();

    final rowButton = find.ancestor(
      of: find.text('עוד'),
      matching: find.byType(SubmenuButton),
    );
    final submenu = tester.widget<SubmenuButton>(rowButton);
    expect(
      submenu.focusNode?.canRequestFocus,
      isFalse,
      reason: 'mouse and touch must not move focus off the text field',
    );
    expect(opener.hasPrimaryFocus, isTrue);
  });
}
