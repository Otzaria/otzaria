import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/book_common/utils/link_anchor_variants.dart';
import 'package:otzaria/text_book/view/widgets/continuous_reading_paragraph.dart';
import 'package:otzaria/widgets/smart_text/render_settings.dart';
import 'package:otzaria/widgets/smart_text/smart_text_widget.dart';
import 'package:otzaria/widgets/smart_text/text_renderer_service.dart';

// סמן-האות של המפרש חייב להיראות זהה בשני מסלולי הרינדור. עד לתיקון, מצב
// הקריאה הרציפה התעלם לגמרי מהווריאנט וכל המפרשים קיבלו סמן זהה.
void main() {
  const base = TextStyle(fontSize: 20, fontFamily: 'FrankRuhlCLM');
  const settings = RenderSettings(fontSize: 20, fontFamily: 'FrankRuhlCLM');
  const linkStyle = TextStyle(
    color: Color(0xFF0000FF),
    decoration: TextDecoration.underline,
  );

  String marker(int variantIndex, String letter) =>
      'לפני <a class="link-anchor link-anchor-$variantIndex" '
      'href="otzaria://anchor?ref=3_0">'
      '${wrapLinkAnchorLetter(letter, variantIndex)}</a> אחרי';

  // הייצור מריץ processText על השורה לפני הפירסור בשני המסלולים; בלעדיו
  // עיצוב הסוגריים (<small> סביב "(א)") היה חסר כאן ומקלקל את ההשוואה.
  TextStyle continuousStyleOf(
    String html,
    String needle, {
    bool hideRaisedMarkers = true,
  }) {
    final spans = buildInlineHtmlSpans(
      TextRendererService.processText(html, settings),
      base,
      onTapUrl: (_) async => true,
      linkStyle: linkStyle,
      hideRaisedMarkers: hideRaisedMarkers,
    );
    return _findStyle(spans, needle, base)!;
  }

  group('קריאה רציפה — הווריאנט מיושם', () {
    test('כתב רש"י (וריאנט 3) מוחל על סמן-האות', () {
      final style = continuousStyleOf(marker(3, 'א'), '(א)');
      expect(style.fontFamily, kLinkAnchorRashiFont);
    });

    test('מודגש (וריאנט 0) — בלי נטייה כפויה', () {
      final style = continuousStyleOf(marker(0, 'ב'), '(ב)');
      expect(style.fontWeight, FontWeight.bold);
      expect(style.fontStyle, isNot(FontStyle.italic));
      expect(style.fontFamily, 'FrankRuhlCLM');
    });

    test('נטוי (וריאנט 1) — נטוי בלי הדגשה', () {
      final style = continuousStyleOf(marker(1, 'ג'), '(ג)');
      expect(style.fontStyle, FontStyle.italic);
      expect(style.fontWeight ?? FontWeight.normal, FontWeight.normal);
    });

    test('כל הווריאנטים נבדלים זה מזה בפועל', () {
      // הסוגריים נכתבים לתוך הטקסט ולא ל-TextStyle, ולכן הם חלק מהחתימה:
      // שני וריאנטים באותו סגנון נבדלים בעטיפת האות בלבד.
      final signatures =
          <
            (
              String?,
              FontWeight?,
              FontStyle?,
              TextDecoration?,
              LinkAnchorDelimiter,
            )
          >{};
      for (var index = 0; index < kLinkAnchorVariants.length; index++) {
        final letter = wrapLinkAnchorLetter('א', index);
        final style = continuousStyleOf(marker(index, 'א'), letter);
        signatures.add((
          style.fontFamily,
          style.fontWeight,
          style.fontStyle,
          style.decoration,
          kLinkAnchorVariants[index].delimiter,
        ));
      }
      expect(signatures.length, kLinkAnchorVariants.length);
    });

    test('הסמן מוקטן ביחס לטקסט הסובב', () {
      final style = continuousStyleOf(marker(0, 'א'), '(א)');
      final around = continuousStyleOf(marker(0, 'א'), 'לפני');
      expect(style.fontSize, lessThan(around.fontSize!));
      expect(
        style.fontSize,
        closeTo(around.fontSize! * kLinkAnchorMarkerScale, 0.001),
      );
    });

    test('צבע הנושא מוחל על הסמן אצל קורא בלי שכבת ציור', () {
      final style = continuousStyleOf(
        marker(2, 'א'),
        '(א)',
        hideRaisedMarkers: false,
      );
      expect(style.color, linkStyle.color);
    });

    test('עם שכבת הציור הגליף שקוף — הצבע עובר לציור המורם', () {
      final style = continuousStyleOf(marker(2, 'א'), '(א)');
      expect(style.color!.toARGB32() >> 24, 0);
    });

    test('ציטוט לינקר נשאר בגופן הטקסט בלי קו תחתון', () {
      final style = continuousStyleOf(
        'לפני <a class="link-anchor-range" '
            'href="otzaria://anchor?ref=3_0&range=1">ציטוט</a> אחרי',
        'ציטוט',
      );
      expect(style.fontFamily, base.fontFamily);
      expect(style.fontStyle, isNot(FontStyle.italic));
      expect(style.decoration, TextDecoration.none);
      expect(style.color, linkStyle.color);
    });

    test('סמן הערת-ספר ממשיך לקבל הקטנה ונטייה', () {
      final style = continuousStyleOf(
        'א <a class="book-note-marker" '
            'href="otzaria://book-note?line=1&note=0">ב</a>',
        'ב',
      );
      expect(style.fontSize, base.fontSize! * 0.75);
      expect(style.fontStyle, FontStyle.italic);
    });
  });

  group('שקילות בין מסלולי הרינדור', () {
    testWidgets('ציטוט לינקר — בלי קו תחתון בשני המסלולים', (tester) async {
      const html =
          'לפני <a class="link-anchor-range" '
          'href="otzaria://anchor?ref=3_0&range=1">ציטוט</a> אחרי';

      await tester.pumpWidget(
        MaterialApp(
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

      final htmlStyle = _findWidgetStyle(tester, 'ציטוט')!;
      final continuousStyle = continuousStyleOf(html, 'ציטוט');

      for (final style in [htmlStyle, continuousStyle]) {
        expect(style.decoration ?? TextDecoration.none, TextDecoration.none);
      }
    });

    for (var index = 0; index < kLinkAnchorVariants.length; index++) {
      testWidgets('וריאנט $index — אותו גופן/משקל/נטייה בשני המסלולים', (
        tester,
      ) async {
        final html = marker(index, 'א');

        await tester.pumpWidget(
          MaterialApp(
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

        final letter = wrapLinkAnchorLetter('א', index);
        final htmlStyle = _findWidgetStyle(tester, letter)!;
        final continuousStyle = continuousStyleOf(html, letter);

        expect(
          continuousStyle.fontFamily,
          htmlStyle.fontFamily,
          reason: 'גופן, וריאנט $index',
        );
        expect(
          continuousStyle.fontWeight ?? FontWeight.normal,
          htmlStyle.fontWeight ?? FontWeight.normal,
          reason: 'משקל, וריאנט $index',
        );
        expect(
          continuousStyle.fontStyle ?? FontStyle.normal,
          htmlStyle.fontStyle ?? FontStyle.normal,
          reason: 'נטייה, וריאנט $index',
        );
        expect(
          continuousStyle.fontSize,
          htmlStyle.fontSize,
          reason: 'גודל, וריאנט $index',
        );
      });
    }
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
