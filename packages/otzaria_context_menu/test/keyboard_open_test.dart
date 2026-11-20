import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria_context_menu/otzaria_context_menu.dart';

class _EscapeStack {
  final handlers = <OnKeyEventCallback>[];

  VoidCallback register(OnKeyEventCallback handler) {
    if (handlers.isEmpty) {
      FocusManager.instance.addEarlyKeyEventHandler(_dispatch);
    }
    handlers.add(handler);
    return () {
      handlers.remove(handler);
      if (handlers.isEmpty) {
        FocusManager.instance.removeEarlyKeyEventHandler(_dispatch);
      }
    };
  }

  KeyEventResult _dispatch(KeyEvent event) {
    for (final handler in handlers.reversed.toList()) {
      final result = handler(event);
      if (result != KeyEventResult.ignored) return result;
    }
    return KeyEventResult.ignored;
  }

  void dispose() {
    handlers.clear();
    FocusManager.instance.removeEarlyKeyEventHandler(_dispatch);
  }
}

MenuPresentation _presentation() => MenuPresentation(
  metrics: AppMenuMetrics.create(compactMenus: false),
  borderRadius: BorderRadius.circular(8),
  iconBuilder: (context, icon, size, color, mirrorForRtl) =>
      SizedBox.square(dimension: size),
  selectedMarkBuilder: (context, size, color) => Text(
    '✓',
    style: TextStyle(fontSize: size, color: color),
  ),
  submenuArrowBuilder: (context, openToRight, size, color) =>
      Text(openToRight ? '›' : '‹', style: TextStyle(fontSize: size)),
  downArrowBuilder: (context, size, color) => Text(
    '⌄',
    style: TextStyle(fontSize: size, color: color),
  ),
);

void main() {
  late _EscapeStack escapes;
  late FocusNode openerFocus;
  late List<String> activated;
  VoidCallback? firstAction;

  setUp(() {
    escapes = _EscapeStack();
    openerFocus = FocusNode(debugLabel: 'opener');
    activated = [];
  });
  tearDown(() {
    escapes.dispose();
    openerFocus.dispose();
  });

  Future<void> mount(
    WidgetTester tester, {
    TextDirection direction = TextDirection.rtl,
    int regionCount = 1,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: direction,
          child: Scaffold(
            body: Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.only(top: 100),
                child: ContextMenuRegion(
                  presentation: _presentation(),
                  registerEscape: escapes.register,
                  menuBuilder: (_, _) => [
                    AppContextMenuEntry(
                      label: 'ראשון',
                      onTap: () {
                        activated.add('first');
                        firstAction?.call();
                      },
                    ),
                    AppContextMenuEntry(
                      label: 'שני',
                      onTap: () => activated.add('second'),
                    ),
                  ],
                  child: TextButton(
                    key: const ValueKey('opener'),
                    focusNode: openerFocus,
                    onPressed: () {},
                    child: const Text('פריט ברשימה'),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    openerFocus.requestFocus();
    await tester.pump();
    expect(openerFocus.hasPrimaryFocus, isTrue);
  }

  Future<void> shiftF10(WidgetTester tester) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.f10);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.f10);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();
  }

  testWidgets('Shift+F10 on the focused item opens the menu next to it', (
    tester,
  ) async {
    await mount(tester);
    await shiftF10(tester);

    expect(find.text('ראשון'), findsOneWidget);
    expect(find.text('שני'), findsOneWidget);
    final opener = tester.getRect(find.byKey(const ValueKey('opener')));
    final firstRow = tester.getRect(find.text('ראשון'));
    expect(
      firstRow.top,
      greaterThanOrEqualTo(opener.bottom - 1),
      reason: 'the menu opens below the focused item, not at the screen origin',
    );
    expect(
      (firstRow.center.dx - opener.center.dx).abs(),
      lessThan(250),
      reason: 'the menu is anchored near the focused item horizontally too',
    );
  });

  testWidgets('the Menu key opens the menu as well', (tester) async {
    await mount(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.contextMenu);
    await tester.pumpAndSettle();
    expect(find.text('ראשון'), findsOneWidget);
  });

  testWidgets('a keyboard-opened menu is operable: arrows move, Enter runs', (
    tester,
  ) async {
    await mount(tester);
    await shiftF10(tester);

    expect(
      FocusManager.instance.primaryFocus,
      isNot(openerFocus),
      reason: 'focus moves into the menu so arrows and Enter reach it',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(activated, ['second']);
    expect(find.text('שני'), findsNothing);
    expect(openerFocus.hasPrimaryFocus, isTrue);
  });

  testWidgets('the first enabled item is focused when the menu opens', (
    tester,
  ) async {
    await mount(tester);
    await shiftF10(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(activated, ['first']);
  });

  testWidgets('Escape closes a keyboard-opened menu and returns focus', (
    tester,
  ) async {
    await mount(tester);
    await shiftF10(tester);
    expect(find.text('ראשון'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.text('ראשון'), findsNothing);
    expect(activated, isEmpty);
    expect(openerFocus.hasPrimaryFocus, isTrue);
    expect(escapes.handlers, isEmpty);
  });

  testWidgets('works in LTR and keeps the menu inside the viewport', (
    tester,
  ) async {
    await mount(tester, direction: TextDirection.ltr);
    await shiftF10(tester);
    final menu = tester.getRect(find.text('ראשון'));
    final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
    expect(menu.left, greaterThanOrEqualTo(0));
    expect(menu.right, lessThanOrEqualTo(screen.width));
  });

  testWidgets('pointer-opened menus still do not take focus', (tester) async {
    await mount(tester);
    final region = tester.state<ContextMenuRegionState>(
      find.byType(ContextMenuRegion),
    );
    await region.openMenuAt(const Offset(100, 300));
    await tester.pumpAndSettle();
    expect(find.text('ראשון'), findsOneWidget);
    expect(
      openerFocus.hasPrimaryFocus,
      isTrue,
      reason: 'mouse and touch keep the selection owner focused',
    );
  });

  testWidgets('an action that opens a dialog keeps focus in the dialog', (
    tester,
  ) async {
    await mount(tester);
    firstAction = () => showDialog<void>(
      context: tester.element(find.byKey(const ValueKey('opener'))),
      builder: (_) => AlertDialog(
        content: TextButton(
          key: const ValueKey('in-dialog'),
          autofocus: true,
          onPressed: () {},
          child: const Text('בדיאלוג'),
        ),
      ),
    );
    await shiftF10(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('in-dialog')), findsOneWidget);
    expect(
      openerFocus.hasPrimaryFocus,
      isFalse,
      reason: 'restoring focus must not steal it from the dialog',
    );
    expect(
      FocusManager.instance.primaryFocus?.context
          ?.findAncestorWidgetOfExactType<AlertDialog>(),
      isNotNull,
      reason: 'the dialog keeps primary focus after the menu closed',
    );
  });

  testWidgets('an action that removes the opener does not touch its dead '
      'context when focus is restored', (tester) async {
    final removed = ValueNotifier<bool>(false);
    addTearDown(removed.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: const EdgeInsets.only(top: 100),
              child: ValueListenableBuilder<bool>(
                valueListenable: removed,
                builder: (context, gone, _) => ContextMenuRegion(
                  presentation: _presentation(),
                  registerEscape: escapes.register,
                  menuBuilder: (_, _) => [
                    AppContextMenuEntry(
                      label: 'הסר',
                      onTap: () => removed.value = true,
                    ),
                  ],
                  child: gone
                      ? const SizedBox(width: 10, height: 10)
                      : TextButton(
                          focusNode: openerFocus,
                          onPressed: () {},
                          child: const Text('פריט ברשימה'),
                        ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    openerFocus.requestFocus();
    await tester.pump();
    await shiftF10(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(removed.value, isTrue);
    expect(find.text('פריט ברשימה'), findsNothing);
    expect(find.text('הסר'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
