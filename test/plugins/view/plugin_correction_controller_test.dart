import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/view/plugin_correction_controller.dart';
import 'package:otzaria/widgets/smart_text/inline_html_document.dart';
import 'package:otzaria/widgets/smart_text/render_settings.dart';
import 'package:otzaria/widgets/smart_text/smart_text_widget.dart';

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

  const readerCases = {
    'צבע ב-style של b': '<b style="color: #ff0000">אב</b>',
    'h2 רגיל': '<h2>אב</h2>',
    'H2 באותיות גדולות': '<H2>אב</H2>',
    'הערה לפני h2': '<!--הערה--><h2>אב</h2>',
    'טקסט בלי צבע מפורש': 'אב',
    'b בלי צבע מפורש': '<b>אב</b>',
  };
  for (final MapEntry(key: name, value: html) in readerCases.entries) {
    testWidgets('העורך מציג כמו הקורא: $name', (tester) async {
      const base = TextStyle(fontSize: 20, color: Color(0xFF203040));
      final line = InlineHtmlDocument.parseLine(html, base)!;
      final reader = line.style.merge(line.document.runs.first.style);
      final controller = PluginCorrectionController(html);
      addTearDown(controller.dispose);
      await tester.pumpWidget(const SizedBox());
      TextStyle editorAt(int offset) => _styleAt(
        controller.buildTextSpan(
          context: tester.element(find.byType(SizedBox)),
          style: base,
          withComposing: true,
        ),
        offset,
        base,
      );
      void expectReader(TextStyle actual) {
        expect(actual.color, reader.color);
        expect(actual.fontSize, reader.fontSize);
        expect(actual.fontWeight, reader.fontWeight);
      }

      expectReader(editorAt(0));
      controller.value = const TextEditingValue(
        text: 'אגב',
        selection: TextSelection.collapsed(offset: 2),
      );
      expectReader(editorAt(1));
      controller.value = controller.value.copyWith(
        composing: const TextRange(start: 1, end: 2),
      );
      final composing = editorAt(1);
      expectReader(composing);
      expect(composing.decoration, TextDecoration.underline);
    });
  }

  group('רצף רווחים שהקורא כיווץ', () {
    const base = TextStyle(fontSize: 20, color: Color(0xFF203040));
    const red = Color(0xFFFF0000);
    final cases = <String, (String, List<Color>)>{
      'באמצע, אותו סגנון משני הצדדים': (
        '<b style="color:#ff0000">אב   גד</b>',
        [red, red, red],
      ),
      'באמצע, סגנונות שונים': (
        '<b style="color:#ff0000">אב</b>   <i>גד</i>',
        [base.color!, base.color!, base.color!],
      ),
      'בתחילה': ('   <b style="color:#ff0000">אב</b>', [base.color!]),
      'בסוף': ('<b style="color:#ff0000">אב</b>   ', [base.color!]),
    };
    for (final MapEntry(key: name, value: (html, colors)) in cases.entries) {
      testWidgets(name, (tester) async {
        final controller = PluginCorrectionController(html);
        addTearDown(controller.dispose);
        await tester.pumpWidget(const SizedBox());
        final span = controller.buildTextSpan(
          context: tester.element(find.byType(SizedBox)),
          style: base,
          withComposing: false,
        );
        final text = controller.text;
        final spaces = [
          for (var i = 0; i < text.length; i++)
            if (text[i] == ' ') i,
        ];
        expect(spaces, hasLength(3));
        // הרווח הראשון ברצף מוצמד לרווח שהקורא מציג; השאר מכווצים.
        final collapsed = name == 'בתחילה' ? spaces : spaces.skip(1);
        for (final (index, offset) in collapsed.indexed) {
          expect(
            _styleAt(span, offset, base).color,
            colors[index.clamp(0, colors.length - 1)],
            reason: 'רווח $offset',
          );
        }
        expect(_styleAt(span, text.indexOf('א'), base).color, red);
      });
    }
  });

  testWidgets('החלפת ערכת נושא עם אותו baseStyle אינה מחזירה צבע קישור ישן', (
    tester,
  ) async {
    const html = '<a href="https://example.com">אב</a>';
    const base = TextStyle(fontSize: 20);
    const host = Key('host');
    final controller = PluginCorrectionController(html);
    addTearDown(controller.dispose);
    Future<(Color?, Color?)> readerAndEditor(Color seed) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(colorSchemeSeed: seed),
          home: Scaffold(
            body: Column(
              children: [
                const SizedBox(key: host),
                SmartTextWidget(text: html, settings: const RenderSettings()),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final reader = tester
          .renderObjectList<RenderParagraph>(
            find.descendant(
              of: find.byType(SmartTextWidget),
              matching: find.byType(RichText),
            ),
          )
          .single
          .text;
      final editor = controller.buildTextSpan(
        context: tester.element(find.byKey(host)),
        style: base,
        withComposing: false,
      );
      return (
        _styleAt(reader as TextSpan, 0).color,
        _styleAt(editor, 0, base).color,
      );
    }

    final (blueReader, blueEditor) = await readerAndEditor(Colors.blue);
    expect(blueEditor, blueReader);
    final (greenReader, greenEditor) = await readerAndEditor(Colors.green);
    expect(greenReader, isNot(blueReader));
    expect(greenEditor, greenReader);
  });

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
