import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/view/plugin_correction_controller.dart';

TextStyle _styleAt(TextSpan span, int offset, [TextStyle? inherited]) {
  final style = (inherited ?? const TextStyle()).merge(span.style);
  final length = span.text?.length ?? 0;
  if (offset < length) return style;
  offset -= length;
  for (final child in span.children ?? <InlineSpan>[]) {
    final length = child.toPlainText().length;
    if (offset < length) return _styleAt(child as TextSpan, offset, style);
    offset -= length;
  }
  throw RangeError.index(offset, span.toPlainText());
}

void main() {
  testWidgets('אות חוזרת בגבול סגנון יורשת לפי מיקום הסמן האמיתי', (
    tester,
  ) async {
    final controller = PluginCorrectionController('<b>א</b><i>א</i>');
    addTearDown(controller.dispose);
    await tester.pumpWidget(const SizedBox());
    controller.selection = const TextSelection.collapsed(offset: 1);
    controller.value = const TextEditingValue(
      text: 'אאא',
      selection: TextSelection.collapsed(offset: 2),
    );
    final span = controller.buildTextSpan(
      context: tester.element(find.byType(SizedBox)),
      style: const TextStyle(fontSize: 20),
      withComposing: true,
    );
    expect(_styleAt(span, 1).fontWeight, FontWeight.bold);
    expect(_styleAt(span, 1).fontStyle, isNull);
    expect(_styleAt(span, 2).fontStyle, FontStyle.italic);
  });

  testWidgets('מטמון spans מתעדכן לפי טקסט, composing, מקור וסגנון בלבד', (
    tester,
  ) async {
    final controller = PluginCorrectionController('<u>אב</u><i>גד</i>');
    addTearDown(controller.dispose);
    await tester.pumpWidget(const SizedBox());
    TextSpan build({bool composing = true, double size = 20}) =>
        controller.buildTextSpan(
          context: tester.element(find.byType(SizedBox)),
          style: TextStyle(fontSize: size),
          withComposing: composing,
        );
    final original = build();
    expect(build(), same(original));
    controller.selection = const TextSelection(baseOffset: 0, extentOffset: 2);
    expect(build(), same(original));
    controller.value = controller.value.copyWith(
      composing: const TextRange(start: 1, end: 3),
    );
    final composed = build();
    expect(composed, isNot(same(original)));
    expect(build(), same(composed));
    expect(_styleAt(composed, 1).decoration, TextDecoration.underline);
    expect(_styleAt(composed, 2).fontStyle, FontStyle.italic);
    expect(_styleAt(composed, 2).decoration, TextDecoration.underline);
    final plain = build(composing: false);
    expect(_styleAt(plain, 2).decoration, isNull);
    expect(build(), same(composed));
    expect(build(composing: false), same(plain));
    final larger = build(size: 25);
    expect(_styleAt(larger, 0).fontSize, 25);
    expect(build(size: 25), same(larger));
    controller.text = 'אבוגד';
    expect(build().toPlainText(), 'אבוגד');
    expect(build(), isNot(same(composed)));
    controller.setSource('<b>אבוגד</b>');
    expect(_styleAt(build(), 0).fontWeight, FontWeight.bold);
    expect(
      () => controller.value = controller.value.copyWith(
        composing: const TextRange(start: 0, end: 100),
      ),
      throwsAssertionError,
    );
    expect(_styleAt(build(), 0).decoration, isNull);
  });

  for (final source in ['<br>אב', 'אב<br>', '<br>אב<br>']) {
    test('המרה סימטרית גם כשהתיקון הסיר את שולי $source', () {
      final controller = PluginCorrectionController(source);
      addTearDown(controller.dispose);
      for (final canonical in [controller.source.plain, 'אם', '', ' אמת ']) {
        expect(
          controller.forService(controller.forEditor(canonical)),
          canonical,
        );
      }
    });
  }

  for (final offset in [0, 2, 4]) {
    testWidgets('הוספה במיקום $offset יורשת מהקודם, ובתחילה מהראשון', (
      tester,
    ) async {
      final controller = PluginCorrectionController('<b>אב</b><i>גד</i>');
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.rtl,
          child: SizedBox(),
        ),
      );
      controller.value = TextEditingValue(
        text: controller.text.replaceRange(offset, offset, 'ו'),
        selection: TextSelection.collapsed(offset: offset + 1),
      );
      final span = controller.buildTextSpan(
        context: tester.element(find.byType(SizedBox)),
        style: const TextStyle(fontSize: 20),
        withComposing: false,
      );
      final inserted = _styleAt(span, offset);
      expect(inserted.fontWeight, offset < 4 ? FontWeight.bold : null);
      expect(inserted.fontStyle, offset == 4 ? FontStyle.italic : null);
    });
  }

  for (final tag in ['b', 'i', 'u', 'strong', 'em', 'big', 'small']) {
    testWidgets('תג $tag עם מאפיינים ומרכאות שומר את סגנונו', (tester) async {
      final controller = PluginCorrectionController(
        '<$tag title="x > y">אב</$tag><!-- <b> -->גד',
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.rtl,
          child: SizedBox(),
        ),
      );
      TextStyle styled(String raw) {
        final reference = PluginCorrectionController(raw);
        addTearDown(reference.dispose);
        return _styleAt(
          reference.buildTextSpan(
            context: tester.element(find.byType(SizedBox)),
            style: const TextStyle(fontSize: 20),
            withComposing: false,
          ),
          0,
        );
      }

      final span = controller.buildTextSpan(
        context: tester.element(find.byType(SizedBox)),
        style: const TextStyle(fontSize: 20),
        withComposing: false,
      );
      expect(_styleAt(span, 0), styled('<$tag>אב</$tag>'));
      expect(_styleAt(span, span.toPlainText().length - 1), styled('גד'));
    });
  }

  testWidgets('תגיות באותיות גדולות, הערות ותג סגור אינם מדליפים סגנון', (
    tester,
  ) async {
    final controller = PluginCorrectionController(
      '<B title="<i> >">אב</B><!-- <i> --><b/>גד',
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(const SizedBox());
    final span = controller.buildTextSpan(
      context: tester.element(find.byType(SizedBox)),
      style: const TextStyle(fontSize: 20),
      withComposing: false,
    );
    expect(_styleAt(span, 0).fontWeight, FontWeight.bold);
    final last = _styleAt(span, span.toPlainText().length - 1);
    expect(last.fontWeight, isNull);
    expect(last.fontStyle, isNull);
  });
}
