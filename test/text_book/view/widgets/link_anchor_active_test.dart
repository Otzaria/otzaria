import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/text_book/utils/link_anchor_markers.dart';
import 'package:otzaria/text_book/utils/link_anchor_variants.dart';
import 'package:otzaria/text_book/view/widgets/continuous_reading_paragraph.dart';
import 'package:otzaria/widgets/smart_text/render_settings.dart';
import 'package:otzaria/widgets/smart_text/smart_text_widget.dart';
import 'package:otzaria/widgets/smart_text/text_renderer_service.dart';

// סמן-האות שחלונית התצוגה שלו פתוחה מודגש ברקע — בשני מסלולי הרינדור.
void main() {
  const fontSize = 20.0;
  const base = TextStyle(fontSize: fontSize, fontFamily: 'FrankRuhlCLM');
  const settings = RenderSettings(
    fontSize: fontSize,
    fontFamily: 'FrankRuhlCLM',
  );
  const linkColor = Color(0xFF0000FF);
  const activeBackground = Color(0xFFCCE5FF);
  const linkStyle = TextStyle(
    color: linkColor,
    decoration: TextDecoration.underline,
  );

  Link anchorLink(String path2, {String? label}) => Link(
    heRef: '$path2 א, א',
    index1: 4,
    path2: path2,
    index2: 1,
    connectionType: 'commentary',
    anchorStart: 2,
    anchorLabel: label ?? 'א',
  );

  group('injectLinkAnchorMarkers — סימון הסמן הפעיל', () {
    test('רק העוגן שב-activeIndex מקבל link-anchor-active', () {
      final result = injectLinkAnchorMarkers(
        rawLine: 'אבגד',
        anchorLinks: [
          anchorLink('משנה ברורה', label: 'א'),
          anchorLink('באר היטב', label: 'ב'),
        ],
        styleIndexByCommentator: const {'משנה ברורה': 0, 'באר היטב': 1},
        lineIndex: 7,
        activeIndex: 1,
      );
      expect(result, contains('link-anchor-1 link-anchor-active'));
      expect(result, isNot(contains('link-anchor-0 link-anchor-active')));
    });

    test('בלי activeIndex אין סימון פעיל כלל', () {
      final result = injectLinkAnchorMarkers(
        rawLine: 'אבגד',
        anchorLinks: [anchorLink('משנה ברורה')],
        styleIndexByCommentator: const {'משנה ברורה': 0},
        lineIndex: 7,
      );
      expect(result, isNot(contains('link-anchor-active')));
    });

    test('activeIndex מחוץ לטווח אינו מסמן דבר', () {
      final result = injectLinkAnchorMarkers(
        rawLine: 'אבגד',
        anchorLinks: [anchorLink('משנה ברורה')],
        styleIndexByCommentator: const {'משנה ברורה': 0},
        lineIndex: 7,
        activeIndex: 5,
      );
      expect(result, isNot(contains('link-anchor-active')));
    });
  });

  group('עיצוב הסמן הפעיל', () {
    String activeMarker(int variantIndex) =>
        'לפני <a class="link-anchor link-anchor-$variantIndex link-anchor-active" '
        'href="otzaria://anchor?ref=3_0">(א)</a> אחרי';

    TextStyle continuousStyleOf(String html, String needle) {
      final spans = buildInlineHtmlSpans(
        TextRendererService.processText(html, settings),
        base,
        onTapUrl: (_) async => true,
        linkStyle: linkStyle,
        anchorActiveBackground: activeBackground,
      );
      return _findStyle(spans, needle, base)!;
    }

    test('קריאה רציפה — רקע והדגשה', () {
      final style = continuousStyleOf(activeMarker(0), '(א)');
      expect(_background(style), activeBackground.toARGB32());
      expect(style.fontWeight, FontWeight.bold);
      expect(style.color, linkColor);
    });

    test('קריאה רציפה — סמן לא-פעיל בלי רקע', () {
      final style = continuousStyleOf(
        'לפני <a class="link-anchor link-anchor-0" '
            'href="otzaria://anchor?ref=3_0">(א)</a> אחרי',
        '(א)',
      );
      expect(_background(style), isNull);
    });

    test('הווריאנט נשמר גם כשהסמן פעיל', () {
      // וריאנט 3 = כתב רש"י; ההדגשה מתווספת עליו ולא מחליפה אותו.
      expect(
        continuousStyleOf(activeMarker(3), '(א)').fontFamily,
        kLinkAnchorRashiFont,
      );
      // וריאנט 5 = קו תחתון, סימנו המבחין של המפרש — חייב לשרוד את ההדגשה.
      expect(
        continuousStyleOf(activeMarker(5), '(א)').decoration,
        TextDecoration.underline,
      );
    });

    testWidgets('שני המסלולים מדגישים את הסמן הפעיל באותו אופן', (
      tester,
    ) async {
      for (var index = 0; index < kLinkAnchorVariants.length; index++) {
        final html = activeMarker(index);
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(
              colorScheme:
                  ColorScheme.fromSeed(
                    seedColor: Colors.blue,
                  ).copyWith(
                    primary: linkColor,
                    primaryContainer: activeBackground,
                  ),
            ),
            home: Scaffold(
              body: SmartTextWidget(
                text: html,
                settings: settings,
                onAnchorTap: (_) {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final htmlStyle = _findWidgetStyle(tester, '(א)')!;
        final continuousStyle = continuousStyleOf(html, '(א)');

        expect(
          _background(continuousStyle),
          _background(htmlStyle),
          reason: 'רקע, וריאנט $index',
        );
        expect(
          _background(htmlStyle),
          activeBackground.toARGB32(),
          reason: 'הרקע חייב להיות מיושם בפועל, וריאנט $index',
        );
        expect(
          continuousStyle.fontFamily,
          htmlStyle.fontFamily,
          reason: 'גופן, וריאנט $index',
        );
        expect(
          continuousStyle.decoration ?? TextDecoration.none,
          htmlStyle.decoration ?? TextDecoration.none,
          reason: 'קו תחתון, וריאנט $index',
        );
        expect(
          continuousStyle.fontWeight,
          FontWeight.bold,
          reason: 'הדגשה, וריאנט $index',
        );
      }
    });
  });
}

/// צבע הרקע האפקטיבי כ-ARGB: fwfh מיישם background-color דרך
/// TextStyle.background (Paint) והמסלול הרציף דרך backgroundColor — שקולים
/// ויזואלית. ההשוואה כמספר ולא כאובייקט Color, שערוצי ה-double שלו נוצרים
/// בדיוק שונה בכל מסלול.
int? _background(TextStyle style) =>
    (style.backgroundColor ?? style.background?.color)?.toARGB32();

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
