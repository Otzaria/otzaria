import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/models/plugin_search_field_action.dart';
import 'package:otzaria/plugins/services/plugin_search_field_actions_registry.dart';
import 'package:otzaria/plugins/services/plugin_search_field_session_service.dart';
import 'package:otzaria/plugins/view/plugin_search_field_actions.dart';
import 'package:otzaria/widgets/text/rtl_text_field.dart';

const _buttonKey = ValueKey('plugin-search-field-action:voice:dictate');
const _selected = TextSelection(baseOffset: 9, extentOffset: 0);
const _caret = TextSelection.collapsed(offset: 9);

void main() {
  late TextEditingController controller;
  late FocusNode focus;
  late PluginSearchFieldActionsRegistry registry;
  late PluginSearchFieldSessionService sessions;
  late List<Map<String, dynamic>> invoked;

  void registerAction({String id = 'dictate', bool onlyWithText = false}) {
    registry.registerPayload('voice', {
      'id': id,
      'title': 'חיפוש בדיבור',
      'icon': 'mic_24_regular',
      if (onlyWithText) 'visibleWhen': 'nonEmptyText',
    });
  }

  setUp(() {
    controller = TextEditingController(text: 'שלום עולם');
    focus = FocusNode();
    registry = PluginSearchFieldActionsRegistry.forTesting();
    registerAction();
    invoked = [];
    sessions = PluginSearchFieldSessionService.forTesting((
      pluginId,
      topic,
      payload, {
      preferBackground = false,
      instanceId,
      viewId,
      windowKeys,
    }) async {
      if (topic == PluginSearchFieldSessionService.invokedTopic) {
        invoked.add(payload);
      }
    });
  });

  tearDown(() {
    controller.dispose();
    focus.dispose();
    registry.dispose();
    sessions.dispose();
  });

  Future<void> pumpField(WidgetTester tester) async {
    addTearDown(() => tester.pumpWidget(const SizedBox()));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Directionality(
            textDirection: TextDirection.rtl,
            child: RtlTextField(
              controller: controller,
              focusNode: focus,
              autofocus: true,
              decoration: InputDecoration(
                suffixIcon: PluginSearchFieldActions(
                  field: PluginSearchField.findRef,
                  controller: controller,
                  registry: registry,
                  sessions: sessions,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  void dictate({required bool replacesSelection}) {
    expect(invoked, hasLength(1));
    expect(invoked.single['selectionStart'], replacesSelection ? 0 : 9);
    expect(invoked.single['selectionEnd'], 9);
    sessions.setFieldText(
      'voice',
      invoked.single['sessionId'] as String,
      'חדש',
    );
    expect(controller.text, replacesSelection ? 'חדש' : 'שלום עולם חדש');
  }

  for (final mode in ['keyboard', 'cancel', 'drag', 'secondary']) {
    testWidgets(
      '$mode ולאחריו חצים ו־Tab+Enter משתמשים בבחירה הנוכחית',
      (tester) async {
        await pumpField(tester);
        controller.selection = _selected;
        if (mode != 'keyboard') {
          final gesture = await tester.startGesture(
            tester.getCenter(find.byKey(_buttonKey)),
            kind: PointerDeviceKind.mouse,
            buttons: mode == 'secondary'
                ? kSecondaryMouseButton
                : kPrimaryMouseButton,
          );
          await tester.pump(kPressTimeout * 2);
          if (mode == 'cancel') {
            await gesture.cancel();
          } else {
            if (mode == 'drag') {
              await gesture.moveBy(const Offset(100, 100));
              await tester.pump();
            }
            await gesture.up();
          }
          await tester.pump();
          expect(invoked, isEmpty);
        }
        focus.requestFocus();
        await tester.pump();
        for (var i = 0; i < 12; i++) {
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
        }
        expect(controller.selection, _caret);
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        expect(focus.hasPrimaryFocus, isFalse);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        dictate(replacesSelection: false);
        await tester.pumpWidget(const SizedBox());
      },
      variant: TargetPlatformVariant.desktop(),
    );
  }

  for (final kind in [PointerDeviceKind.mouse, PointerDeviceKind.touch]) {
    for (final delay in [Duration.zero, kPressTimeout * 2]) {
      testWidgets(
        '$kind אחרי $delay מחליף בחירה גם בכפתור שתלוי בטקסט',
        (tester) async {
          registerAction(onlyWithText: true);
          await pumpField(tester);
          controller.selection = _selected;
          final gesture = await tester.startGesture(
            tester.getCenter(find.byKey(_buttonKey)),
            kind: kind,
          );
          await tester.pump(delay);
          await gesture.up();
          await tester.pump();
          dictate(replacesSelection: true);
          await tester.pumpWidget(const SizedBox());
        },
        variant: TargetPlatformVariant.all(),
      );
    }
  }

  for (final change in ['controller', 'action', 'text']) {
    testWidgets(
      'החלפת $change תוך כדי לחיצה לא משחזרת בחירה ישנה',
      (tester) async {
        await pumpField(tester);
        controller.selection = _selected;
        final gesture = await tester.startGesture(
          tester.getCenter(find.byKey(_buttonKey)),
          kind: PointerDeviceKind.mouse,
        );
        await tester.pump(kPressTimeout * 2);
        if (change == 'controller') {
          final previous = controller;
          controller = TextEditingController(text: previous.text)
            ..selection = _caret;
          await pumpField(tester);
          previous.dispose();
        } else if (change == 'action') {
          registerAction();
          controller.selection = _caret;
          await tester.pump();
        } else {
          controller.value = const TextEditingValue(
            text: 'טקסט אחר!',
            selection: _caret,
          );
        }
        await gesture.up();
        await tester.pump();
        expect(invoked, hasLength(1));
        expect(invoked.single['selectionStart'], 9);
        sessions.setFieldText(
          'voice',
          invoked.single['sessionId'] as String,
          'חדש',
        );
        expect(
          controller.text,
          change == 'text' ? 'טקסט אחר! חדש' : 'שלום עולם חדש',
        );
        await tester.pumpWidget(const SizedBox());
      },
      variant: TargetPlatformVariant.desktop(),
    );
  }

  testWidgets(
    'מקלדת בזמן לחצן מוחזק משתמשת בבחירה הנוכחית',
    (tester) async {
      await pumpField(tester);
      controller.selection = _selected;
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(_buttonKey)),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump(kPressTimeout * 2);
      controller.selection = _caret;
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(focus.hasPrimaryFocus, isFalse);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      dictate(replacesSelection: false);
      await gesture.cancel();
    },
    variant: TargetPlatformVariant.desktop(),
  );

  for (final secondary in [false, true]) {
    testWidgets(
      'pointer נוסף (secondary: $secondary) לא מדליף בחירה בין הפעלות',
      (tester) async {
        await pumpField(tester);
        controller.selection = _selected;
        final position = tester.getCenter(find.byKey(_buttonKey));
        final kind = secondary
            ? PointerDeviceKind.mouse
            : PointerDeviceKind.touch;
        final first = await tester.startGesture(
          position,
          pointer: 1,
          kind: kind,
        );
        await tester.pump(kPressTimeout * 2);
        final second = await tester.startGesture(
          position,
          pointer: 2,
          kind: kind,
          buttons: secondary ? kSecondaryMouseButton : kPrimaryButton,
        );
        await second.cancel();
        await tester.pump();
        await first.up();
        await tester.pump();
        if (secondary) {
          // תפריט ההקשר מבטל את מחוות הלחצן הראשי.
          expect(invoked, isEmpty);
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          focus.requestFocus();
          controller.selection = _caret;
          await tester.pump();
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.pump();
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pump();
        }
        dictate(replacesSelection: !secondary);
      },
      variant: TargetPlatformVariant.all(),
    );
  }

  testWidgets(
    'ניקוי שחרור של גרירה לא מוחק מחווה חדשה באותו תור אירועים',
    (tester) async {
      await pumpField(tester);
      controller.selection = _selected;
      final position = tester.getCenter(find.byKey(_buttonKey));
      final first = await tester.startGesture(
        position,
        pointer: 1,
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump(kPressTimeout * 2);
      final outside = position + const Offset(100, 100);
      await first.moveTo(outside);
      await tester.pump();
      tester.binding.handlePointerEvent(
        PointerUpEvent(
          pointer: 1,
          position: outside,
          kind: PointerDeviceKind.mouse,
        ),
      );
      controller.selection = _selected;
      tester.binding.handlePointerEvent(
        PointerDownEvent(
          pointer: 2,
          position: position,
          kind: PointerDeviceKind.mouse,
          buttons: kPrimaryButton,
        ),
      );
      await tester.pump(kPressTimeout * 2);
      tester.binding.handlePointerEvent(
        PointerUpEvent(
          pointer: 2,
          position: position,
          kind: PointerDeviceKind.mouse,
        ),
      );
      await tester.pump();
      dictate(replacesSelection: true);
    },
    variant: TargetPlatformVariant.desktop(),
  );
}
