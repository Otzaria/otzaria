import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:otzaria/widgets/smart_text/raised_markers.dart';
import 'package:otzaria/widgets/smart_text/render_settings.dart';
import 'package:otzaria/widgets/smart_text/smart_text_widget.dart';

// תגי הדגשת החיפוש של highLight מזוהים במסלול המהיר ומוצגים בדיוק כמו ב-HtmlWidget.
// רווח לפני `>` זהה בפרסור HTML אך אינו מזוהה במסלול המהיר — כך נבנה הייחוס.
const _needle = 'ברכה';
const _opens = [
  '<span style="color: red">',
  '<span style="color: red; ">',
  '<span style="color: blue; background-color: rgba(255, 255, 0, 0.8);">',
  '<span style="background-color: rgba(255, 255, 0, 0.8); color: black">',
];

class _Rendered {
  final Rect root;
  final List<Rect> paragraphs;
  final List<TextBox> boxes;
  final TextStyle style;

  _Rendered(this.root, this.paragraphs, this.boxes, this.style);
}

Future<_Rendered> _render(
  WidgetTester tester,
  String html, {
  required bool expectHtmlWidget,
}) async {
  final key = GlobalKey();
  await tester.pumpWidget(
    MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: 300,
              child: SelectionArea(
                child: SmartTextWidget(
                  key: key,
                  text: html,
                  settings: const RenderSettings(fontSize: 20, lineHeight: 1.6),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  expect(
    find.byType(HtmlWidget),
    expectHtmlWidget ? findsOneWidget : findsNothing,
    reason: html,
  );

  final paragraphs = find.descendant(
    of: find.byKey(key),
    matching: find.byWidgetPredicate((w) => w is RichText),
  );
  final boxes = <TextBox>[];
  TextStyle? style;
  for (final element in paragraphs.evaluate()) {
    final richText = element.widget as RichText;
    final render = element.renderObject! as RenderParagraph;
    boxes.addAll(
      render.getBoxesForSelection(
        TextSelection(
          baseOffset: 0,
          extentOffset: richText.text.toPlainText().length,
        ),
      ),
    );
    void visit(InlineSpan span, TextStyle inherited) {
      if (style != null || span is! TextSpan) return;
      final merged = span.style == null
          ? inherited
          : inherited.merge(span.style);
      if (span.text?.contains(_needle) ?? false) {
        style = merged;
        return;
      }
      for (final child in span.children ?? const <InlineSpan>[]) {
        visit(child, merged);
      }
    }

    visit(richText.text, const TextStyle());
  }
  return _Rendered(
    tester.getRect(find.byKey(key)),
    [
      for (final element in paragraphs.evaluate())
        tester.getRect(find.byWidget(element.widget)),
    ],
    boxes,
    style!,
  );
}

void main() {
  const marker = '<span class="$kFootnoteMarkerClass">1</span>';
  final bodies = <String Function(String open)>[
    (open) => 'לפני $open$_needle</span> אחרי',
    (open) => '<b>מודגש $open$_needle</span></b> <small>(קטן)</small>',
    (open) => '$open<b>$_needle</b> ועוד</span>$marker סוף',
    (open) => '$open$_needle$marker</span> והמשך',
    (open) => '<h2>כותרת $open$_needle</span></h2>',
    (open) =>
        '$open$_needle</span> שורה ארוכה שנשברת לכמה שורות $open$_needle</span> ברוחב צר',
  ];

  for (final open in _opens) {
    testWidgets('$open — זהה ל-HtmlWidget', (tester) async {
      final reference = open.replaceFirst('">', '" >');
      for (final body in bodies) {
        final fast = await _render(tester, body(open), expectHtmlWidget: false);
        final html = await _render(
          tester,
          body(reference),
          expectHtmlWidget: true,
        );
        final reason = body(open);
        expect(fast.root, html.root, reason: reason);
        expect(fast.paragraphs, html.paragraphs, reason: reason);
        expect(fast.boxes, html.boxes, reason: reason);
        expect(
          fast.style.color?.toARGB32(),
          html.style.color?.toARGB32(),
          reason: reason,
        );
        expect(
          fast.style.background?.color.toARGB32(),
          html.style.background?.color.toARGB32(),
          reason: reason,
        );
        expect(fast.style.backgroundColor, html.style.backgroundColor);
        expect(fast.style.fontSize, html.style.fontSize, reason: reason);
        expect(fast.style.fontWeight, html.style.fontWeight, reason: reason);
      }
    });
  }

  testWidgets('הדגשה מקוננת או style אחר — נשארים ב-HtmlWidget', (
    tester,
  ) async {
    for (final html in [
      '${_opens[0]}א ${_opens[2]}$_needle</span></span>',
      '<span style="color: green">$_needle</span>',
    ]) {
      await _render(tester, html, expectHtmlWidget: true);
    }
  });
}
