import 'package:flutter/gestures.dart';
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
  submenuArrowBuilder: (context, openToRight, size, color) => Text(
    openToRight ? '›' : '‹',
    style: TextStyle(fontSize: size, color: color),
  ),
  downArrowBuilder: (context, size, color) => Text(
    '⌄',
    style: TextStyle(fontSize: size, color: color),
  ),
);

Future<GlobalKey<ContextMenuRegionState>> _mount(
  WidgetTester tester, {
  required _EscapeStack escapes,
  required List<AppContextMenuEntry> Function() entries,
  FocusNode? focus,
  TextDirection direction = TextDirection.rtl,
  void Function(BuildContext, Offset)? onMenuOpening,
}) async {
  final key = GlobalKey<ContextMenuRegionState>();
  await tester.pumpWidget(
    MaterialApp(
      home: Directionality(
        textDirection: direction,
        child: Scaffold(
          body: Focus(
            focusNode: focus,
            autofocus: focus != null,
            child: ContextMenuRegion(
              key: key,
              presentation: _presentation(),
              registerEscape: escapes.register,
              menuBuilder: (_, _) => entries(),
              onMenuOpening: onMenuOpening,
              child: const SizedBox.expand(),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return key;
}

void main() {
  late _EscapeStack escapes;

  setUp(() => escapes = _EscapeStack());
  tearDown(() => escapes.dispose());

  testWidgets(
    'right click opens and an action runs once without app services',
    (tester) async {
      var selected = 0;
      await _mount(
        tester,
        escapes: escapes,
        entries: () => [
          AppContextMenuEntry(label: 'פעולה', onTap: () => selected++),
        ],
      );
      final mouse = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryButton,
      );
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.down(const Offset(100, 100));
      await mouse.up();
      await tester.pumpAndSettle();
      expect(find.text('פעולה'), findsOneWidget);
      expect(escapes.handlers, isNotEmpty);

      await tester.tap(find.text('פעולה'));
      await tester.pumpAndSettle();
      expect(selected, 1);
      expect(find.text('פעולה'), findsNothing);
      expect(escapes.handlers, isEmpty);
    },
  );

  testWidgets(
    'opening hook runs before the overlay and receives its position',
    (tester) async {
      Offset? openingPosition;
      bool? menuWasVisible;
      final key = await _mount(
        tester,
        escapes: escapes,
        onMenuOpening: (_, position) {
          openingPosition = position;
          menuWasVisible = find.text('פעולה').evaluate().isNotEmpty;
        },
        entries: () => [AppContextMenuEntry(label: 'פעולה', onTap: () {})],
      );

      await key.currentState!.openMenuAt(const Offset(120, 140));
      await tester.pumpAndSettle();
      expect(openingPosition, const Offset(120, 140));
      expect(menuWasVisible, isFalse);
      expect(find.text('פעולה'), findsOneWidget);
    },
  );

  testWidgets(
    'keepOpen updates children and Escape closes one level at a time',
    (tester) async {
      final focus = FocusNode();
      addTearDown(focus.dispose);
      var selected = false;
      final key = await _mount(
        tester,
        escapes: escapes,
        focus: focus,
        entries: () => [
          AppContextMenuEntry(
            label: 'אפשרויות',
            childrenBuilder: () => [
              AppContextMenuEntry(
                label: selected ? 'סומן' : 'סמן',
                keepOpen: true,
                onTap: () => selected = !selected,
              ),
            ],
          ),
        ],
      );
      focus.requestFocus();
      await tester.pump();
      await key.currentState!.openMenuAt(const Offset(100, 100));
      await tester.pumpAndSettle();
      await tester.tap(find.text('אפשרויות'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('סמן'));
      await tester.pumpAndSettle();
      expect(selected, isTrue);
      expect(find.text('סומן'), findsOneWidget);
      expect(focus.hasPrimaryFocus, isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('סומן'), findsNothing);
      expect(find.text('אפשרויות'), findsOneWidget);
      expect(focus.hasPrimaryFocus, isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('אפשרויות'), findsNothing);
      expect(escapes.handlers, isEmpty);
      expect(focus.hasPrimaryFocus, isTrue);
    },
  );

  testWidgets(
    'hover preserves the source focus and disposal removes handlers',
    (tester) async {
      final focus = FocusNode();
      addTearDown(focus.dispose);
      final key = await _mount(
        tester,
        escapes: escapes,
        focus: focus,
        entries: () => [
          AppContextMenuEntry(
            label: 'אפשרויות',
            children: [AppContextMenuEntry(label: 'ילד', onTap: () {})],
          ),
        ],
      );
      focus.requestFocus();
      await tester.pump();
      await key.currentState!.openMenuAt(const Offset(100, 100));
      await tester.pumpAndSettle();
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(find.text('אפשרויות')));
      await tester.pump(const Duration(milliseconds: 100));
      expect(focus.hasPrimaryFocus, isTrue);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(find.text('ילד'), findsNothing);
      expect(escapes.handlers, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  Future<void> mountNested(
    WidgetTester tester, {
    required List<AppContextMenuEntry> innerEntries,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ContextMenuRegion(
            presentation: _presentation(),
            registerEscape: escapes.register,
            menuBuilder: (_, _) => [
              AppContextMenuEntry(label: 'חיצוני', onTap: () {}),
            ],
            child: Center(
              child: SizedBox.square(
                dimension: 200,
                child: ContextMenuRegion(
                  presentation: _presentation(),
                  registerEscape: escapes.register,
                  menuBuilder: (_, _) => innerEntries,
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    final mouse = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryButton,
    );
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.down(tester.getCenter(find.byType(Center)));
    await mouse.up();
    await tester.pumpAndSettle();
  }

  // issue #3037: כרטיס מפרשים בתוך פסקה רציפה פתח גם את תפריט הפסקה.
  testWidgets('right click in a nested region opens only the inner menu', (
    tester,
  ) async {
    await mountNested(
      tester,
      innerEntries: [AppContextMenuEntry(label: 'פנימי', onTap: () {})],
    );
    expect(find.text('פנימי'), findsOneWidget);
    expect(find.text('חיצוני'), findsNothing);
  });

  testWidgets('a nested region with no entries leaves the click to the outer', (
    tester,
  ) async {
    await mountNested(tester, innerEntries: const []);
    expect(find.text('חיצוני'), findsOneWidget);
  });

  testWidgets('a second right click with the same pointer opens again', (
    tester,
  ) async {
    var built = 0;
    await _mount(
      tester,
      escapes: escapes,
      entries: () {
        built++;
        return [AppContextMenuEntry(label: 'פעולה', onTap: () {})];
      },
    );
    final mouse = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryButton,
    );
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    for (var i = 0; i < 2; i++) {
      await mouse.down(const Offset(100, 100));
      await mouse.up();
      await tester.pumpAndSettle();
    }
    expect(built, 2);
  });

  for (final direction in TextDirection.values) {
    testWidgets('menu inherits the opener direction: $direction', (
      tester,
    ) async {
      final key = await _mount(
        tester,
        escapes: escapes,
        direction: direction,
        entries: () => [AppContextMenuEntry(label: 'פעולה', onTap: () {})],
      );
      await key.currentState!.openMenuAt(const Offset(100, 100));
      await tester.pumpAndSettle();

      expect(Directionality.of(tester.element(find.text('פעולה'))), direction);
    });
  }

  testWidgets('rapid context-menu replacement leaves one overlay and handler', (
    tester,
  ) async {
    final key = await _mount(
      tester,
      escapes: escapes,
      entries: () => [AppContextMenuEntry(label: 'Action', onTap: () {})],
    );
    for (var i = 0; i < 15; i++) {
      await key.currentState!.openMenuAt(Offset(100 + i.toDouble(), 100));
    }
    await tester.pumpAndSettle();
    expect(find.text('Action'), findsOneWidget);
    expect(escapes.handlers, hasLength(1));
    expect(tester.takeException(), isNull);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Action'), findsNothing);
    expect(escapes.handlers, isEmpty);
    expect(tester.takeException(), isNull);

    await key.currentState!.openMenuAt(const Offset(100, 100));
    await tester.pumpAndSettle();
    expect(find.text('Action'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(escapes.handlers, isEmpty);
    expect(tester.takeException(), isNull);
  });
  testWidgets('close callback releases resources on Escape and replacement', (
    tester,
  ) async {
    final key = GlobalKey<ContextMenuRegionState>();
    var closes = 0;
    var opens = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ContextMenuRegion(
            key: key,
            presentation: _presentation(),
            registerEscape: escapes.register,
            menuBuilder: (_, _) => [
              AppContextMenuEntry(label: 'Copy', onTap: () {}),
            ],
            onMenuOpening: (_, _) => opens++,
            onMenuClosed: () => closes++,
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );

    await key.currentState!.openMenuAt(const Offset(100, 100));
    await tester.pumpAndSettle();
    expect(opens, 1);
    expect(closes, 0);

    await key.currentState!.openMenuAt(const Offset(150, 150));
    await tester.pumpAndSettle();
    expect(opens, 2);
    expect(closes, 1);
    expect(find.text('Copy'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(closes, 2);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(closes, 2);

    await key.currentState!.openMenuAt(const Offset(100, 100));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    expect(closes, 3);
  });
}
