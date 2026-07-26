import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/text_book/view/widgets/continuous_reading_paragraph.dart';
import 'package:otzaria/widgets/smart_text/render_settings.dart';
import 'package:otzaria/widgets/smart_text/simple_inline_html.dart';
import 'package:otzaria/widgets/smart_text/smart_text_widget.dart';
import 'package:otzaria/widgets/smart_text/text_renderer_service.dart';

// שלושה מסלולי רינדור מציגים את אותן שורות: SimpleInlineHtml (המסלול המהיר),
// HtmlWidget, והקריאה הרציפה. המסלול נבחר לפי ה-markup שבשורה, ולכן יחס גדלים
// שונה בין המסלולים משנה את גודל הסוגריים בין שורות שכנות באותו ספר —
// formatTextWithParentheses עוטף כל טקסט בסוגריים ב-<small>.
void main() {
  const fontSize = 20.0;
  const base = TextStyle(fontSize: fontSize, fontFamily: 'FrankRuhlCLM');
  const settings = RenderSettings(
    fontSize: fontSize,
    fontFamily: 'FrankRuhlCLM',
  );

  // span עם class אינו ברשימה הלבנה של המסלול המהיר ומכריח נפילה ל-HtmlWidget.
  const forceHtmlWidget = ' <span class="x">.</span>';

  Future<double?> sizeInWidget(
    WidgetTester tester,
    String html,
    String needle,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SmartTextWidget(text: html, settings: settings),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return _findWidgetStyle(tester, needle)?.fontSize;
  }

  double? sizeInContinuous(String html, String needle) {
    final spans = buildInlineHtmlSpans(
      TextRendererService.processText(html, settings),
      base,
    );
    return _findStyle(spans, needle, base)?.fontSize;
  }

  const cases = <String, (String, double)>{
    '<small>': ('קטן', kHtmlSmallerFontScale),
    '<big>': ('גדול', kHtmlLargerFontScale),
    '<sup>': ('עילי', kHtmlSmallerFontScale),
  };

  String htmlFor(String tag, String needle) {
    final name = tag.substring(1, tag.length - 1);
    return 'בסיס <$name>$needle</$name>';
  }

  group('יחס הגדלים זהה בשלושת המסלולים', () {
    cases.forEach((tag, expectation) {
      final (needle, scale) = expectation;
      testWidgets('$tag — מהיר, HtmlWidget וקריאה רציפה', (tester) async {
        final html = htmlFor(tag, needle);
        final expected = fontSize * scale;

        final fastPath = await sizeInWidget(tester, html, needle);
        final htmlWidget = await sizeInWidget(
          tester,
          html + forceHtmlWidget,
          needle,
        );
        final continuous = sizeInContinuous(html, needle);

        expect(fastPath, closeTo(expected, 0.001), reason: 'מסלול מהיר');
        expect(htmlWidget, closeTo(expected, 0.001), reason: 'HtmlWidget');
        expect(continuous, closeTo(expected, 0.001), reason: 'קריאה רציפה');
      });
    });

    testWidgets('סוגריים מקוננים — הקטנה מצטברת זהה בכל המסלולים', (
      tester,
    ) async {
      const html = 'בסיס <small><small>כפול</small></small>';
      final expected = fontSize * kHtmlSmallerFontScale * kHtmlSmallerFontScale;

      expect(
        await sizeInWidget(tester, html, 'כפול'),
        closeTo(expected, 0.001),
        reason: 'מסלול מהיר',
      );
      expect(
        await sizeInWidget(tester, html + forceHtmlWidget, 'כפול'),
        closeTo(expected, 0.001),
        reason: 'HtmlWidget',
      );
      expect(
        sizeInContinuous(html, 'כפול'),
        closeTo(expected, 0.001),
        reason: 'קריאה רציפה',
      );
    });

    testWidgets('שורה עם סוגריים — אותו גודל עם קישור ובלעדיו', (tester) async {
      // התרחיש שהמשתמש רואה: שתי שורות שכנות, אחת עם קישור ואחת בלי, נופלות
      // למסלולים שונים — הסוגריים חייבים להיראות זהה בשתיהן.
      const plain = 'אמר רבי (הגהה) ליעקב';
      const withLink =
          'אמר רבי (הגהה) <a href="otzaria://open/book/1">ליעקב</a>';

      final plainSize = await sizeInWidget(tester, plain, '(הגהה)');
      final linkedSize = await sizeInWidget(tester, withLink, '(הגהה)');

      expect(plainSize, closeTo(fontSize * kHtmlSmallerFontScale, 0.001));
      expect(linkedSize, closeTo(plainSize!, 0.001));
    });
  });

  group('נטייה', () {
    testWidgets('sup חשוף אינו נוטה באף מסלול', (tester) async {
      const html = 'בסיס <sup>עילי</sup>';

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SmartTextWidget(
              text: html + forceHtmlWidget,
              settings: settings,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        _findWidgetStyle(tester, 'עילי')!.fontStyle ?? FontStyle.normal,
        FontStyle.normal,
        reason: 'HtmlWidget',
      );

      final spans = buildInlineHtmlSpans(
        TextRendererService.processText(html, settings),
        base,
      );
      expect(
        _findStyle(spans, 'עילי', base)!.fontStyle ?? FontStyle.normal,
        FontStyle.normal,
        reason: 'קריאה רציפה',
      );
    });
  });
}

TextStyle? _findStyle(List<InlineSpan> spans, String needle, TextStyle base) {
  TextStyle? found;
  void visit(InlineSpan span, TextStyle inherited) {
    if (found != null || span is! TextSpan) return;
    final style = span.style == null ? inherited : inherited.merge(span.style);
    if (span.text != null && span.text!.contains(needle)) {
      found = style;
      return;
    }
    for (final child in span.children ?? const <InlineSpan>[]) {
      visit(child, style);
    }
  }

  for (final span in spans) {
    visit(span, base);
    if (found != null) break;
  }
  return found;
}

TextStyle? _findWidgetStyle(WidgetTester tester, String needle) {
  TextStyle? found;
  void visit(InlineSpan span, TextStyle inherited) {
    if (found != null || span is! TextSpan) return;
    final style = span.style == null ? inherited : inherited.merge(span.style);
    if (span.text != null && span.text!.contains(needle)) {
      found = style;
      return;
    }
    for (final child in span.children ?? const <InlineSpan>[]) {
      visit(child, style);
    }
  }

  for (final richText in tester.widgetList<RichText>(find.byType(RichText))) {
    visit(richText.text, const TextStyle());
    if (found != null) break;
  }
  return found;
}
