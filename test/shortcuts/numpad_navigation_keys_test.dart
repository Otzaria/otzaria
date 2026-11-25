import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/shortcuts/numpad_navigation_keys.dart';
import 'package:otzaria/widgets/misc/progressive_scrolling.dart';
import 'package:positioned_sliver_list/positioned_list.dart';

/// שולח אירוע כמו ה-engine של Windows: KeyData דרך PlatformDispatcher.onKeyData
/// ואחריו הודעת ה-raw שמשחררת את התור של KeyEventManager.
Future<void> _send(
  WidgetTester tester,
  ui.KeyEventType type,
  PhysicalKeyboardKey physical,
  LogicalKeyboardKey logical, {
  String? character,
  bool synthesized = false,
}) async {
  tester.binding.platformDispatcher.onKeyData!(
    ui.KeyData(
      timeStamp: Duration.zero,
      type: type,
      physical: physical.usbHidUsage,
      logical: logical.keyId,
      character: character,
      synthesized: synthesized,
    ),
  );
  if (synthesized) return;
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    SystemChannels.keyEvent.name,
    SystemChannels.keyEvent.codec.encodeMessage(
      KeyEventSimulator.getKeyData(
        logical,
        platform: 'windows',
        isDown: type != ui.KeyEventType.up,
        physicalKey: physical,
      ),
    ),
    (_) {},
  );
  await tester.pump();
}

/// לחיצה ושחרור מסונתזים של NumLock — כמו סנכרון מצב הנעילה של ה-engine.
Future<void> _toggleNumLock(WidgetTester tester) async {
  for (final type in [ui.KeyEventType.down, ui.KeyEventType.up]) {
    await _send(
      tester,
      type,
      PhysicalKeyboardKey.numLock,
      LogicalKeyboardKey.numLock,
      synthesized: true,
    );
  }
}

bool get _numLockOn => HardwareKeyboard.instance.lockModesEnabled.contains(
  KeyboardLockMode.numLock,
);

void main() {
  late List<KeyEvent> events;

  setUp(() => events = []);

  /// מתקין את המיפוי על ה-dispatcher של הבדיקה ומחזיר את המקורי בסיומה.
  void install() {
    final original = ui.PlatformDispatcher.instance.onKeyData;
    addTearDown(() => ui.PlatformDispatcher.instance.onKeyData = original);
    installNumpadNavigationKeys();
  }

  final windows = TargetPlatformVariant.only(TargetPlatform.windows);

  Widget recorder({Widget? child}) => MaterialApp(
    home: Focus(
      autofocus: true,
      onKeyEvent: (_, event) {
        events.add(event);
        return KeyEventResult.ignored;
      },
      child: child ?? const SizedBox(),
    ),
  );

  testWidgets(
    'NumLock כבוי: ספרון 8 נמסר כחץ למעלה, משוחרר ונוקה מהמקשים הלחוצים',
    (tester) async {
      install();
      await tester.pumpWidget(recorder());
      expect(_numLockOn, isFalse);

      await _send(
        tester,
        ui.KeyEventType.down,
        PhysicalKeyboardKey.numpad8,
        LogicalKeyboardKey.numpad8,
      );
      expect(events.single.logicalKey, LogicalKeyboardKey.arrowUp);
      expect(events.single.physicalKey, PhysicalKeyboardKey.numpad8);
      expect(
        HardwareKeyboard.instance.isLogicalKeyPressed(
          LogicalKeyboardKey.arrowUp,
        ),
        isTrue,
      );

      await _send(
        tester,
        ui.KeyEventType.repeat,
        PhysicalKeyboardKey.numpad8,
        LogicalKeyboardKey.numpad8,
      );
      await _send(
        tester,
        ui.KeyEventType.up,
        PhysicalKeyboardKey.numpad8,
        LogicalKeyboardKey.numpad8,
      );
      expect(events.map((e) => e.runtimeType), [
        KeyDownEvent,
        KeyRepeatEvent,
        KeyUpEvent,
      ]);
      expect(
        events.map((e) => e.logicalKey),
        everyElement(LogicalKeyboardKey.arrowUp),
      );
      expect(HardwareKeyboard.instance.logicalKeysPressed, isEmpty);
      expect(HardwareKeyboard.instance.physicalKeysPressed, isEmpty);
    },
    variant: windows,
  );

  testWidgets('NumLock כבוי: כל מקשי הספרון ממופים למקשי הניווט', (
    tester,
  ) async {
    install();
    await tester.pumpWidget(recorder());
    final cases = [
      (
        PhysicalKeyboardKey.numpad7,
        LogicalKeyboardKey.numpad7,
        LogicalKeyboardKey.home,
      ),
      (
        PhysicalKeyboardKey.numpad8,
        LogicalKeyboardKey.numpad8,
        LogicalKeyboardKey.arrowUp,
      ),
      (
        PhysicalKeyboardKey.numpad9,
        LogicalKeyboardKey.numpad9,
        LogicalKeyboardKey.pageUp,
      ),
      (
        PhysicalKeyboardKey.numpad4,
        LogicalKeyboardKey.numpad4,
        LogicalKeyboardKey.arrowLeft,
      ),
      (
        PhysicalKeyboardKey.numpad6,
        LogicalKeyboardKey.numpad6,
        LogicalKeyboardKey.arrowRight,
      ),
      (
        PhysicalKeyboardKey.numpad1,
        LogicalKeyboardKey.numpad1,
        LogicalKeyboardKey.end,
      ),
      (
        PhysicalKeyboardKey.numpad2,
        LogicalKeyboardKey.numpad2,
        LogicalKeyboardKey.arrowDown,
      ),
      (
        PhysicalKeyboardKey.numpad3,
        LogicalKeyboardKey.numpad3,
        LogicalKeyboardKey.pageDown,
      ),
      (
        PhysicalKeyboardKey.numpad0,
        LogicalKeyboardKey.numpad0,
        LogicalKeyboardKey.insert,
      ),
      (
        PhysicalKeyboardKey.numpadDecimal,
        LogicalKeyboardKey.numpadDecimal,
        LogicalKeyboardKey.delete,
      ),
    ];
    for (final (physical, logical, navigation) in cases) {
      for (final type in [ui.KeyEventType.down, ui.KeyEventType.up]) {
        await _send(tester, type, physical, logical);
      }
      expect(events.map((e) => e.logicalKey), [navigation, navigation]);
      events.clear();
    }
    expect(HardwareKeyboard.instance.physicalKeysPressed, isEmpty);
  }, variant: windows);

  testWidgets('NumLock כבוי: ספרון 3 גולל רשימה כמו PageDown', (
    tester,
  ) async {
    install();
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: ListView(
          controller: controller,
          children: [
            const Focus(autofocus: true, child: SizedBox(height: 50)),
            for (var i = 0; i < 100; i++) const SizedBox(height: 50),
          ],
        ),
      ),
    );
    await tester.pump();
    expect(controller.offset, 0);

    await _send(
      tester,
      ui.KeyEventType.down,
      PhysicalKeyboardKey.numpad3,
      LogicalKeyboardKey.numpad3,
    );
    await _send(
      tester,
      ui.KeyEventType.up,
      PhysicalKeyboardKey.numpad3,
      LogicalKeyboardKey.numpad3,
    );
    await tester.pumpAndSettle();
    expect(controller.offset, greaterThan(0));
  }, variant: windows);

  testWidgets('NumLock דולק: הספרות לא משתנות, גם עם Ctrl (מעבר לטאב)', (
    tester,
  ) async {
    install();
    await tester.pumpWidget(recorder());
    await _toggleNumLock(tester);
    expect(_numLockOn, isTrue);
    events.clear();

    await _send(
      tester,
      ui.KeyEventType.down,
      PhysicalKeyboardKey.numpad8,
      LogicalKeyboardKey.numpad8,
      character: '8',
    );
    await _send(
      tester,
      ui.KeyEventType.up,
      PhysicalKeyboardKey.numpad8,
      LogicalKeyboardKey.numpad8,
    );
    await _send(
      tester,
      ui.KeyEventType.down,
      PhysicalKeyboardKey.controlLeft,
      LogicalKeyboardKey.controlLeft,
    );
    await _send(
      tester,
      ui.KeyEventType.down,
      PhysicalKeyboardKey.numpad1,
      LogicalKeyboardKey.numpad1,
    );
    expect(HardwareKeyboard.instance.isControlPressed, isTrue);
    await _send(
      tester,
      ui.KeyEventType.up,
      PhysicalKeyboardKey.numpad1,
      LogicalKeyboardKey.numpad1,
    );
    await _send(
      tester,
      ui.KeyEventType.up,
      PhysicalKeyboardKey.controlLeft,
      LogicalKeyboardKey.controlLeft,
    );

    expect(events.map((e) => e.logicalKey), [
      LogicalKeyboardKey.numpad8,
      LogicalKeyboardKey.numpad8,
      LogicalKeyboardKey.controlLeft,
      LogicalKeyboardKey.numpad1,
      LogicalKeyboardKey.numpad1,
      LogicalKeyboardKey.controlLeft,
    ]);
    expect(events.first.character, '8');

    await _toggleNumLock(tester);
    expect(_numLockOn, isFalse);
  }, variant: windows);

  testWidgets('שחרור אחרי החלפת NumLock מזווג למקש שנבחר בלחיצה', (
    tester,
  ) async {
    install();
    await tester.pumpWidget(recorder());

    await _send(
      tester,
      ui.KeyEventType.down,
      PhysicalKeyboardKey.numpad8,
      LogicalKeyboardKey.numpad8,
    );
    await _toggleNumLock(tester);
    await _send(
      tester,
      ui.KeyEventType.up,
      PhysicalKeyboardKey.numpad8,
      LogicalKeyboardKey.numpad8,
    );
    final numpad8 = events.where(
      (e) => e.physicalKey == PhysicalKeyboardKey.numpad8,
    );
    expect(numpad8.map((e) => e.logicalKey), [
      LogicalKeyboardKey.arrowUp,
      LogicalKeyboardKey.arrowUp,
    ]);
    expect(HardwareKeyboard.instance.logicalKeysPressed, isEmpty);
    await _toggleNumLock(tester);
  }, variant: windows);

  testWidgets('ספרון 8 וחץ למעלה הייעודי נשארים שני מקשים פיזיים נפרדים', (
    tester,
  ) async {
    install();
    await tester.pumpWidget(recorder());

    await _send(
      tester,
      ui.KeyEventType.down,
      PhysicalKeyboardKey.arrowUp,
      LogicalKeyboardKey.arrowUp,
    );
    await _send(
      tester,
      ui.KeyEventType.down,
      PhysicalKeyboardKey.numpad8,
      LogicalKeyboardKey.numpad8,
    );
    expect(HardwareKeyboard.instance.physicalKeysPressed, {
      PhysicalKeyboardKey.arrowUp,
      PhysicalKeyboardKey.numpad8,
    });
    await _send(
      tester,
      ui.KeyEventType.up,
      PhysicalKeyboardKey.arrowUp,
      LogicalKeyboardKey.arrowUp,
    );
    expect(HardwareKeyboard.instance.physicalKeysPressed, {
      PhysicalKeyboardKey.numpad8,
    });
    expect(
      HardwareKeyboard.instance.isLogicalKeyPressed(
        LogicalKeyboardKey.arrowUp,
      ),
      isTrue,
    );
    await _send(
      tester,
      ui.KeyEventType.up,
      PhysicalKeyboardKey.numpad8,
      LogicalKeyboardKey.numpad8,
    );
    expect(HardwareKeyboard.instance.physicalKeysPressed, isEmpty);
    expect(HardwareKeyboard.instance.logicalKeysPressed, isEmpty);
  }, variant: windows);

  testWidgets('NumLock כבוי: החזקת ספרון 2/8 בקורא גוללת ברצף כמו החצים '
      'ונעצרת בשחרור', (tester) async {
    install();
    final item = ItemScrollController();
    final focus = FocusNode();
    addTearDown(focus.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: ProgressiveScroll(
          focusNode: focus,
          scrollController: item,
          child: ScrollablePositionedList.builder(
            itemScrollController: item,
            itemCount: 10000,
            estimateExtent: (_, width) => 100,
            itemBuilder: (_, index) =>
                SizedBox(height: 100, child: Text('שורה $index')),
          ),
        ),
      ),
    );
    focus.requestFocus();
    await tester.pump();

    Future<double> hold(
      PhysicalKeyboardKey physical,
      LogicalKeyboardKey key,
    ) async {
      await _send(tester, ui.KeyEventType.down, physical, key);
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      await _send(tester, ui.KeyEventType.up, physical, key);
      await tester.pumpAndSettle();
      final released = item.scrollController!.offset;
      await tester.pump(const Duration(milliseconds: 500));
      expect(item.scrollController!.offset, released);
      return released;
    }

    // צעד בודד הוא 100; החזקה של חצי שנייה גוללת ברצף מעבר לו.
    final down = await hold(
      PhysicalKeyboardKey.numpad2,
      LogicalKeyboardKey.numpad2,
    );
    expect(down, greaterThan(200));
    final up = await hold(
      PhysicalKeyboardKey.numpad8,
      LogicalKeyboardKey.numpad8,
    );
    expect(up, lessThan(down - 100));
    expect(HardwareKeyboard.instance.physicalKeysPressed, isEmpty);
  }, variant: windows);

  testWidgets('מחוץ ל-Windows אין מיפוי', (tester) async {
    install();
    await tester.pumpWidget(recorder());

    for (final type in [ui.KeyEventType.down, ui.KeyEventType.up]) {
      await _send(
        tester,
        type,
        PhysicalKeyboardKey.numpad8,
        LogicalKeyboardKey.numpad8,
      );
    }
    expect(
      events.map((e) => e.logicalKey),
      everyElement(LogicalKeyboardKey.numpad8),
    );
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
}
