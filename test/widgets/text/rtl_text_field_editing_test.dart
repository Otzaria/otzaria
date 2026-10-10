import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:ui' show SemanticsAction;
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/widgets/text/rtl_text_field.dart';
import 'package:otzaria/widgets/text/rtl_hard_break_workaround.dart';

Widget host(Widget child) => MaterialApp(
  home: Scaffold(
    body: Directionality(textDirection: TextDirection.rtl, child: child),
  ),
);
void main() {
  testWidgets('keyboard copy does not leak internal CR', (tester) async {
    String? clipboard;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboard = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final controller = TextEditingController(text: 'אבג\nדהו');
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      host(RtlTextField(controller: controller, maxLines: null)),
    );
    await tester.tap(find.byType(TextField));
    controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: controller.text.length,
    );
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(clipboard, 'אבג\nדהו');
  });

  testWidgets('controller listeners can normalize user edits', (tester) async {
    final controller = TextEditingController();
    final changes = <String>[];
    controller.addListener(() {
      if (controller.text.contains('x')) {
        controller.value = controller.value.copyWith(
          text: controller.text.replaceAll('x', 'y'),
        );
      }
    });
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      host(
        RtlTextField(
          controller: controller,
          maxLines: null,
          onChanged: changes.add,
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), 'אב\nx');
    await tester.pump();
    expect(controller.text, 'אב\ny');
    expect(changes, ['אב\ny']);
    expect(
      collapseHardBreaks(
        tester.widget<EditableText>(find.byType(EditableText)).controller.text,
      ),
      controller.text,
    );
  });

  testWidgets('controller replacement and multiline changes do not crash', (
    tester,
  ) async {
    final a = TextEditingController(text: 'א\nב');
    final b = TextEditingController(text: 'ג\nד');
    addTearDown(a.dispose);
    addTearDown(b.dispose);
    await tester.pumpWidget(host(RtlTextField(controller: a, maxLines: null)));
    await tester.tap(find.byType(TextField));
    await tester.pumpWidget(host(RtlTextField(controller: b, maxLines: null)));
    await tester.pumpWidget(host(RtlTextField(controller: b)));
    await tester.pumpWidget(host(RtlTextField(controller: b, maxLines: null)));
    expect(tester.takeException(), null);
  });

  testWidgets('composing preserves range and commit expands breaks', (
    tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      host(RtlTextField(controller: controller, maxLines: null)),
    );
    await tester.tap(find.byType(TextField));
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'אב\nדה',
        selection: TextSelection.collapsed(offset: 5),
        composing: TextRange(start: 3, end: 5),
      ),
    );
    await tester.pump();
    expect(controller.value.composing, const TextRange(start: 3, end: 5));
    expect(
      tester.widget<EditableText>(find.byType(EditableText)).controller.text,
      'אב\nדה',
    );
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'אב\nדה',
        selection: TextSelection.collapsed(offset: 5),
      ),
    );
    await tester.pump();
    expect(
      tester.widget<EditableText>(find.byType(EditableText)).controller.text,
      'אב\r\nדה',
    );
    expect(controller.text, 'אב\nדה');
  });

  testWidgets('IME committed collapsed composing expands breaks', (
    tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      host(RtlTextField(controller: controller, maxLines: null)),
    );
    await tester.tap(find.byType(TextField));
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'אב\nדה',
        selection: TextSelection.collapsed(offset: 5),
        composing: TextRange(start: 3, end: 5),
      ),
    );
    await tester.pump();
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'אב\nדה',
        selection: TextSelection.collapsed(offset: 5),
        composing: TextRange.collapsed(5),
      ),
    );
    await tester.pump();
    expect(
      tester.widget<EditableText>(find.byType(EditableText)).controller.text,
      'אב\r\nדה',
    );
  });

  test('formatter adapter must not alter active composing input', () {
    final formatter = CleanSpaceFormatterAdapter([
      TextInputFormatter.withFunction((oldValue, newValue) => newValue),
    ]);
    const composingValue = TextEditingValue(
      text: 'אב\nדה',
      selection: TextSelection.collapsed(offset: 5),
      composing: TextRange(start: 3, end: 5),
    );
    expect(
      formatter.formatEditUpdate(TextEditingValue.empty, composingValue),
      composingValue,
    );
  });
  for (final key in [LogicalKeyboardKey.backspace, LogicalKeyboardKey.delete]) {
    testWidgets('deletes complete CRLF via ${key.keyLabel}', (tester) async {
      final controller = TextEditingController(text: 'אב\nגד');
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        host(RtlTextField(controller: controller, maxLines: null)),
      );
      await tester.tap(find.byType(TextField));
      controller.selection = TextSelection.collapsed(
        offset: key == LogicalKeyboardKey.backspace ? 3 : 2,
      );
      await tester.pump();
      await tester.sendKeyEvent(key);
      await tester.pump();
      expect(controller.text, 'אבגד');
      expect(controller.selection.extentOffset, 2);
    });
  }
  for (final platform in [TargetPlatform.windows, TargetPlatform.macOS]) {
    for (final cut in [false, true]) {
      testWidgets(
        '$platform keyboard ${cut ? 'cut' : 'copy'} uses clean text',
        (tester) async {
          String? clipboard;
          tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            (call) async {
              if (call.method == 'Clipboard.setData') {
                clipboard = (call.arguments as Map)['text'] as String?;
              }
              return null;
            },
          );
          addTearDown(
            () => tester.binding.defaultBinaryMessenger
                .setMockMethodCallHandler(SystemChannels.platform, null),
          );
          final controller = TextEditingController(text: 'אב😀\nדה');
          final changes = <String>[];
          addTearDown(controller.dispose);
          await tester.pumpWidget(
            host(
              RtlTextField(
                controller: controller,
                maxLines: null,
                onChanged: changes.add,
              ),
            ),
          );
          await tester.tap(find.byType(TextField));
          controller.selection = TextSelection(
            baseOffset: controller.text.length,
            extentOffset: 2,
          );
          await tester.pump();
          final modifier = platform == TargetPlatform.macOS
              ? LogicalKeyboardKey.metaLeft
              : LogicalKeyboardKey.controlLeft;
          await tester.sendKeyDownEvent(modifier);
          await tester.sendKeyEvent(
            cut ? LogicalKeyboardKey.keyX : LogicalKeyboardKey.keyC,
          );
          await tester.sendKeyUpEvent(modifier);
          await tester.pump();
          expect(clipboard, '😀\nדה');
          expect(controller.text, cut ? 'אב' : 'אב😀\nדה');
          expect(changes, cut ? ['אב'] : isEmpty);
          expect(
            controller.selection,
            cut
                ? const TextSelection.collapsed(offset: 2)
                : TextSelection(
                    baseOffset: controller.text.length,
                    extentOffset: 2,
                  ),
          );
        },
        variant: TargetPlatformVariant.only(platform),
      );
    }
  }
  testWidgets('external edits, selection and composing do not call onChanged', (
    tester,
  ) async {
    final controller = TextEditingController(text: 'א\nב');
    final changes = <String>[];
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      host(
        RtlTextField(
          controller: controller,
          maxLines: null,
          onChanged: changes.add,
        ),
      ),
    );
    controller.text = 'ג\nד';
    controller.selection = const TextSelection.collapsed(offset: 2);
    await tester.pump();
    expect(changes, isEmpty);
    await tester.tap(find.byType(TextField));
    await tester.enterText(find.byType(TextField), 'ג\nדה');
    await tester.pump();
    expect(changes, ['ג\nדה']);
    changes.clear();
    controller.text = 'א\nב';
    controller.selection = const TextSelection.collapsed(offset: 1);
    await tester.pump();
    expect(changes, isEmpty);
    await tester.enterText(find.byType(TextField), 'ג\nדה');
    await tester.pump();
    expect(changes, ['ג\nדה']);
  });
  testWidgets('keyboard paste normalizes CRLF and preserves emoji offsets', (
    tester,
  ) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async =>
          call.method == 'Clipboard.getData' ? {'text': '😀\r\nב\rג'} : null,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final controller = TextEditingController(text: 'א');
    final changes = <String>[];
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      host(
        RtlTextField(
          controller: controller,
          maxLines: null,
          onChanged: changes.add,
        ),
      ),
    );
    await tester.tap(find.byType(TextField));
    controller.selection = const TextSelection.collapsed(offset: 1);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(controller.text, 'א😀\nב\nג');
    expect(controller.selection.extentOffset, controller.text.length);
    expect(changes, ['א😀\nב\nג']);
  });
  testWidgets('composition commit does not duplicate a clean onChanged', (
    tester,
  ) async {
    final controller = TextEditingController();
    final changes = <String>[];
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      host(
        RtlTextField(
          controller: controller,
          maxLines: null,
          onChanged: changes.add,
        ),
      ),
    );
    await tester.tap(find.byType(TextField));
    const value = TextEditingValue(
      text: 'אב\nדה',
      selection: TextSelection.collapsed(offset: 5),
      composing: TextRange(start: 3, end: 5),
    );
    tester.testTextInput.updateEditingValue(value);
    await tester.pump();
    tester.testTextInput.updateEditingValue(
      value.copyWith(composing: const TextRange.collapsed(5)),
    );
    await tester.pump();
    expect(changes, ['אב\nדה']);
  });
  testWidgets('accessibility copy uses clean text', (tester) async {
    final semantics = tester.ensureSemantics();
    String? clipboard;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboard = (call.arguments as Map)['text'] as String?;
        }
        if (call.method == 'Clipboard.hasStrings') return {'value': true};
        if (call.method == 'Clipboard.getData') return {'text': clipboard};
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final controller = TextEditingController(text: 'א\nב');
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      host(RtlTextField(controller: controller, maxLines: null)),
    );
    await tester.tap(find.byType(TextField));
    controller.selection = const TextSelection(baseOffset: 0, extentOffset: 3);
    await tester.pump();
    final node = tester.getSemantics(find.byType(EditableText));
    node.owner!.performAction(
      node.id,
      SemanticsAction.copy,
    );
    await tester.pump();
    expect(clipboard, 'א\nב');
    expect(node.getSemanticsData().flagsCollection.isTextField, isTrue);
    expect(
      node.getSemanticsData().hasAction(SemanticsAction.setSelection),
      isTrue,
    );
    expect(node.getSemanticsData().hasAction(SemanticsAction.setText), isTrue);
    expect(node.getSemanticsData().hasAction(SemanticsAction.focus), isTrue);
    expect(controller.selection.isCollapsed, isTrue);
    controller.selection = const TextSelection(baseOffset: 0, extentOffset: 3);
    await tester.pump();
    node.owner!.performAction(node.id, SemanticsAction.cut);
    await tester.pump();
    expect(controller.text, '');
    expect(node.getSemanticsData().hasAction(SemanticsAction.copy), isFalse);
    expect(node.getSemanticsData().hasAction(SemanticsAction.cut), isFalse);
    node.owner!.performAction(node.id, SemanticsAction.setText, 'חדש\nטקסט');
    await tester.pump();
    expect(controller.text, 'חדש\nטקסט');
    expect(node.getSemanticsData().hasAction(SemanticsAction.copy), isFalse);
    final raw = tester
        .widget<EditableText>(find.byType(EditableText))
        .controller;
    node.owner!.performAction(node.id, SemanticsAction.setSelection, {
      'base': 0,
      'extent': raw.text.length,
    });
    await tester.pump();
    expect(
      controller.selection,
      TextSelection(baseOffset: 0, extentOffset: controller.text.length),
    );
    expect(node.getSemanticsData().hasAction(SemanticsAction.paste), isTrue);
    node.owner!.performAction(node.id, SemanticsAction.paste);
    await tester.pump();
    expect(controller.text, 'א\nב');
    semantics.dispose();
  });
  testWidgets('alternating controller selections reuse both large strings', (
    tester,
  ) async {
    final controller = TextEditingController(text: '${'א\n' * 100000}ב');
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      host(RtlTextField(controller: controller, maxLines: 3)),
    );
    final raw = tester
        .widget<EditableText>(find.byType(EditableText))
        .controller;
    raw.value = raw.value.copyWith(text: '${raw.text}ג');
    final cleanText = controller.text;
    final rawText = raw.text;
    for (var i = 1; i < 10; i++) {
      raw.selection = TextSelection.collapsed(offset: i * 3);
      expect(identical(controller.text, cleanText), isTrue);
      controller.selection = TextSelection.collapsed(offset: i * 2);
      expect(identical(raw.text, rawText), isTrue);
    }
  });
  for (final obscure in [true, false]) {
    testWidgets(
      'semantics do not advertise copy for ${obscure ? 'obscured' : 'disabled'} fields',
      (tester) async {
        final semantics = tester.ensureSemantics();
        final controller = TextEditingController(text: 'סוד');
        addTearDown(controller.dispose);
        await tester.pumpWidget(
          host(
            RtlTextField(
              controller: controller,
              maxLines: obscure ? 1 : 3,
              obscureText: obscure,
              enabled: obscure,
            ),
          ),
        );
        controller.selection = const TextSelection(
          baseOffset: 0,
          extentOffset: 3,
        );
        await tester.pump();
        final node = tester.getSemantics(find.byType(EditableText));
        expect(
          node.getSemanticsData().hasAction(SemanticsAction.copy),
          isFalse,
        );
        expect(node.getSemanticsData().hasAction(SemanticsAction.cut), isFalse);
        semantics.dispose();
      },
    );
  }
  testWidgets('multiline toggle resets the onChanged baseline', (tester) async {
    final controller = TextEditingController(text: 'א');
    final changes = <String>[];
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      host(RtlTextField(controller: controller, onChanged: changes.add)),
    );
    await tester.tap(find.byType(TextField));
    await tester.enterText(find.byType(TextField), 'ב');
    changes.clear();
    await tester.pumpWidget(
      host(
        RtlTextField(
          controller: controller,
          maxLines: null,
          onChanged: changes.add,
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), 'א');
    await tester.pump();
    expect(changes, ['א']);
  });
  testWidgets('clipboard failure reports its exception, context and stack', (
    tester,
  ) async {
    final error = PlatformException(code: 'clipboard_unavailable');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') throw error;
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final controller = TextEditingController(text: 'א\nב');
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      host(RtlTextField(controller: controller, maxLines: null)),
    );
    await tester.tap(find.byType(TextField));
    controller.selection = const TextSelection(baseOffset: 0, extentOffset: 3);
    await tester.pump();
    final reported = <FlutterErrorDetails>[];
    final originalOnError = FlutterError.onError;
    FlutterError.onError = reported.add;
    try {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(reported, hasLength(1));
      expect(reported.single.exception, isA<PlatformException>());
      expect((reported.single.exception as PlatformException).code, error.code);
      expect(reported.single.stack, isNotNull);
      expect(reported.single.stack.toString(), isNotEmpty);
      expect(reported.single.context?.toDescription(), contains('העתקת טקסט'));
      expect(controller.text, 'א\nב');
    } finally {
      FlutterError.onError = originalOnError;
    }
  });
}
