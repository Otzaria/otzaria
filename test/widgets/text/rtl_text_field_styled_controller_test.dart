import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/widgets/text/rtl_text_field.dart';

class _StyledController extends TextEditingController {
  _StyledController(super.value) : super.fromValue();

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final newline = text.indexOf('\n');
    return TextSpan(
      style: style,
      semanticsIdentifier: 'styled-text',
      children: [
        for (var index = 0; index < text.length; index++)
          TextSpan(
            text: text[index],
            style: TextStyle(
              fontWeight: index < newline ? FontWeight.bold : null,
              fontStyle: index > newline ? FontStyle.italic : null,
              decoration:
                  withComposing &&
                      value.composing.isValid &&
                      index >= value.composing.start &&
                      index < value.composing.end
                  ? TextDecoration.underline
                  : null,
            ),
          ),
      ],
    );
  }
}

void main() {
  for (final composing in [
    TextRange.empty,
    const TextRange(start: 1, end: 4),
  ]) {
    for (final withComposing in [false, true]) {
      testWidgets(
        'controller רגיל שקול לקודם: composing=$composing, paint=$withComposing',
        (
          tester,
        ) async {
          final controller = TextEditingController.fromValue(
            TextEditingValue(
              text: 'אב\nגד',
              selection: const TextSelection.collapsed(offset: 4),
              composing: composing,
            ),
          );
          addTearDown(controller.dispose);
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: RtlTextField(controller: controller, maxLines: null),
              ),
            ),
          );
          void matchesPreviousController() {
            final editor = tester.widget<EditableText>(
              find.byType(EditableText),
            );
            final reference = TextEditingController.fromValue(
              editor.controller.value,
            );
            final context = tester.element(find.byType(EditableText));
            final actual = editor.controller.buildTextSpan(
              context: context,
              style: editor.style,
              withComposing: withComposing,
            );
            final expected = reference.buildTextSpan(
              context: context,
              style: editor.style,
              withComposing: withComposing,
            );
            expect(actual.toPlainText(), editor.controller.text);
            expect(actual.compareTo(expected), RenderComparison.identical);
            reference.dispose();
          }

          matchesPreviousController();
          await tester.showKeyboard(find.byType(EditableText));
          tester.testTextInput.updateEditingValue(
            TextEditingValue(
              text: 'אבו\nגד',
              selection: const TextSelection.collapsed(offset: 6),
              composing: composing.isValid
                  ? const TextRange(start: 2, end: 6)
                  : TextRange.empty,
            ),
          );
          await tester.pump();
          matchesPreviousController();
          tester.testTextInput.updateEditingValue(
            const TextEditingValue(
              text: 'אבו\nגד',
              selection: TextSelection.collapsed(offset: 6),
            ),
          );
          await tester.pump();
          matchesPreviousController();
          controller.value = TextEditingValue(
            text: 'חדש\nאב',
            selection: const TextSelection.collapsed(offset: 6),
            composing: composing,
          );
          await tester.pump();
          matchesPreviousController();
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }
  }

  testWidgets('CRLF קיים נשמר גם כשהספאנים מפצלים את מעבר השורה', (
    tester,
  ) async {
    final controller = _StyledController(
      const TextEditingValue(
        text: 'אב\r\nגד',
        composing: TextRange(start: 2, end: 3),
      ),
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RtlTextField(controller: controller, maxLines: null),
        ),
      ),
    );
    final editor = tester.widget<EditableText>(find.byType(EditableText));
    final span = editor.controller.buildTextSpan(
      context: tester.element(find.byType(EditableText)),
      style: editor.style,
      withComposing: true,
    );
    expect(controller.text, 'אב\r\nגד');
    expect(span.toPlainText(), editor.controller.text);
    expect(span.toPlainText(), 'אב\r\nגד');
    await tester.showKeyboard(find.byType(EditableText));
    for (final input in ['אב\nגדה', 'אב\r\nגד\nה']) {
      tester.testTextInput.updateEditingValue(
        TextEditingValue(
          text: input,
          selection: TextSelection.collapsed(offset: input.length),
          composing: TextRange(start: input.length - 1, end: input.length),
        ),
      );
      await tester.pump();
      final current = tester.widget<EditableText>(find.byType(EditableText));
      expect(current.controller.text, input);
      expect(
        current.controller
            .buildTextSpan(
              context: tester.element(find.byType(EditableText)),
              style: current.style,
              withComposing: true,
            )
            .toPlainText(),
        input,
      );
      expect(controller.text, input.replaceAll('\r\n', '\n'));
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('עורך רב שורי שומר סגנון וממפה בחירה ו-IME דרך CRLF', (
    tester,
  ) async {
    final controller = _StyledController(
      const TextEditingValue(
        text: 'אב\nגד',
        selection: TextSelection(baseOffset: 1, extentOffset: 4),
        composing: TextRange(start: 3, end: 5),
      ),
    );
    addTearDown(controller.dispose);
    final changes = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Directionality(
            textDirection: TextDirection.rtl,
            child: RtlTextField(
              controller: controller,
              maxLines: null,
              onChanged: changes.add,
            ),
          ),
        ),
      ),
    );

    EditableText editor() => tester.widget(find.byType(EditableText));
    TextSpan span() => editor().controller.buildTextSpan(
      context: tester.element(find.byType(EditableText)),
      style: editor().style,
      withComposing: true,
    );
    TextStyle at(int offset) {
      for (final child in span().children!.cast<TextSpan>()) {
        if (offset < child.text!.length) return child.style!;
        offset -= child.text!.length;
      }
      throw RangeError('אין תו במיקום המבוקש');
    }

    expect(editor().controller.text, 'אב\r\nגד');
    expect(span().toPlainText(), editor().controller.text);
    expect(span().semanticsIdentifier, 'styled-text');
    expect(
      editor().controller.selection,
      const TextSelection(baseOffset: 1, extentOffset: 5),
    );
    expect(
      editor().controller.value.composing,
      const TextRange(start: 4, end: 6),
    );
    expect(at(0).fontWeight, FontWeight.bold);
    expect(at(4).fontStyle, FontStyle.italic);
    expect(at(4).decoration, TextDecoration.underline);

    await tester.showKeyboard(find.byType(EditableText));
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'אב\r\nגדה',
        selection: TextSelection.collapsed(offset: 7),
        composing: TextRange(start: 4, end: 7),
      ),
    );
    await tester.pump();
    expect(controller.text, 'אב\nגדה');
    expect(controller.selection.extentOffset, 6);
    expect(controller.value.composing, const TextRange(start: 3, end: 6));
    expect(changes, ['אב\nגדה']);
    expect(span().toPlainText(), editor().controller.text);
    expect(at(6).fontStyle, FontStyle.italic);
    expect(at(6).decoration, TextDecoration.underline);

    controller.value = const TextEditingValue(
      text: 'חדש\nאב',
      selection: TextSelection(baseOffset: 4, extentOffset: 6),
      composing: TextRange(start: 4, end: 6),
    );
    await tester.pump();
    expect(editor().controller.text, 'חדש\nאב');
    expect(span().toPlainText(), editor().controller.text);
    expect(
      editor().controller.selection,
      const TextSelection(baseOffset: 4, extentOffset: 6),
    );
    expect(
      editor().controller.value.composing,
      const TextRange(start: 4, end: 6),
    );
    expect(at(0).fontWeight, FontWeight.bold);
    expect(at(5).fontStyle, FontStyle.italic);
    expect(at(5).decoration, TextDecoration.underline);
    expect(changes, ['אב\nגדה']);
    controller.value = controller.value.copyWith(composing: TextRange.empty);
    await tester.pump();
    expect(editor().controller.text, 'חדש\r\nאב');
    expect(span().toPlainText(), editor().controller.text);
    expect(
      editor().controller.selection,
      const TextSelection(baseOffset: 5, extentOffset: 7),
    );
    expect(editor().controller.value.composing, TextRange.empty);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
