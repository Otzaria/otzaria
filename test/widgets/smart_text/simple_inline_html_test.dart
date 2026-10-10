import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/widgets/smart_text/simple_inline_html.dart';

void main() {
  const baseStyle = TextStyle(fontSize: 20);

  group('SimpleInlineHtml.tryParse — מסלול מהיר', () {
    test('טקסט פשוט ללא תגים מוחזר כ-span יחיד עם כיווץ רווחים', () {
      final span = SimpleInlineHtml.tryParse('  שלום   עולם ', baseStyle);
      expect(span, isNotNull);
      expect(span!.toPlainText(), 'שלום עולם');
    });

    test('תגי b/strong מקבלים משקל bold', () {
      final span = SimpleInlineHtml.tryParse(
        '<b>דיבור המתחיל</b> ביאור',
        baseStyle,
      );
      expect(span, isNotNull);
      expect(span!.toPlainText(), 'דיבור המתחיל ביאור');

      final children = span.children!.cast<TextSpan>();
      expect(children.first.text, 'דיבור המתחיל');
      expect(children.first.style?.fontWeight, FontWeight.bold);
      expect(children.last.style?.fontWeight, isNull);
    });

    test('בולד בגופן משתנה מקבל FontVariation wght 700', () {
      const variableBase = TextStyle(fontSize: 20, fontFamily: 'Rubik');
      final span = SimpleInlineHtml.tryParse('<b>אב</b> גד', variableBase);
      final children = span!.children!.cast<TextSpan>();
      expect(children.first.style?.fontWeight, FontWeight.bold);
      expect(children.first.style?.fontVariations, const [
        FontVariation('wght', 700),
      ]);
      // ספאן לא-מודגש יורש את הבסיס — בלי FontVariation משלו.
      expect(children.last.style?.fontVariations, isNull);
    });

    test('בולד בגופן לא-משתנה אינו מוסיף FontVariation', () {
      const base = TextStyle(fontSize: 20, fontFamily: 'FrankRuhlCLM');
      final span = SimpleInlineHtml.tryParse('<b>אב</b>', base);
      final child = span!.children!.first as TextSpan;
      expect(child.style?.fontWeight, FontWeight.bold);
      expect(child.style?.fontVariations, isNull);
    });

    test('קינון b+i משלב bold ו-italic', () {
      final span = SimpleInlineHtml.tryParse('<b><i>אב</i></b>', baseStyle);
      final child = span!.children!.first as TextSpan;
      expect(child.style?.fontWeight, FontWeight.bold);
      expect(child.style?.fontStyle, FontStyle.italic);
    });

    // היחסים חייבים להיות אלה של fwfh: שורה נופלת למסלול המהיר או ל-HtmlWidget
    // לפי ה-markup שבה, וכל טקסט בסוגריים נעטף ב-<small>. יחס שונה היה מציג
    // סוגריים בגודל אחר בשורות שכנות באותו ספר.
    test('big ו-small משנים גודל גופן ביחסי fwfh', () {
      final bigSpan = SimpleInlineHtml.tryParse('<big>אב</big>', baseStyle);
      final bigChild = bigSpan!.children!.first as TextSpan;
      expect(
        bigChild.style?.fontSize,
        closeTo(20 * kHtmlLargerFontScale, 0.01),
      );
      expect(bigChild.style?.fontSize, closeTo(24, 0.01));

      final smallSpan = SimpleInlineHtml.tryParse(
        '<small>(הגהה)</small>',
        baseStyle,
      );
      final smallChild = smallSpan!.children!.first as TextSpan;
      expect(
        smallChild.style?.fontSize,
        closeTo(20 * kHtmlSmallerFontScale, 0.01),
      );
      expect(smallChild.style?.fontSize, closeTo(16.667, 0.01));
    });

    test('small מקונן מצטבר כמו ב-fwfh', () {
      final span = SimpleInlineHtml.tryParse(
        '<small><small>אב</small></small>',
        baseStyle,
      );
      final child = span!.children!.first as TextSpan;
      expect(
        child.style?.fontSize,
        closeTo(20 * kHtmlSmallerFontScale * kHtmlSmallerFontScale, 0.01),
      );
    });

    test('br הופך לשורה חדשה ובולע רווחים צמודים', () {
      final span = SimpleInlineHtml.tryParse('שורה א <br> שורה ב', baseStyle);
      expect(span!.toPlainText(), 'שורה א\nשורה ב');
    });

    test('תג סוגר עודף לא מפיל את הפרסור', () {
      final span = SimpleInlineHtml.tryParse('אב</b> גד', baseStyle);
      expect(span, isNotNull);
      expect(span!.toPlainText(), 'אב גד');
    });

    test('טקסט ריק מחזיר span ריק (לא null)', () {
      final span = SimpleInlineHtml.tryParse('   ', baseStyle);
      expect(span, isNotNull);
      expect(span!.toPlainText(), isEmpty);
    });

    test('אמפרסנד חשוף בטקסט אינו נחשב entity', () {
      final span = SimpleInlineHtml.tryParse('א & ב', baseStyle);
      expect(span, isNotNull);
      expect(span!.toPlainText(), 'א & ב');
    });

    test('&nbsp; ו-&thinsp; מפוענחים ואינם מתכווצים', () {
      final span = SimpleInlineHtml.tryParse(
        'א&nbsp;&nbsp;ב&thinsp;ג',
        baseStyle,
      );
      expect(span!.toPlainText(), 'א  ב ג');
    });

    group('נפילה ל-HtmlWidget (מחזיר null)', () {
      final cases = <String, String>{
        // סימונים מורמים (footnote-marker-number / raised-sup) הם היוצא
        // מן הכלל היחיד — נתמכים במסלול המהיר; ראו raised_markers_test.
        'תג עם attributes': '<span class="unknown-class">א</span>',
        'קישור': '<a href="x">קישור</a>',
        'כותרת': '<h2>כותרת</h2>',
        'הדגשת חיפוש': 'לפני <span style="background-color:yellow">מילה</span>',
        'HTML entity': 'א&amp;ב',
        'entity מספרי': 'א&#1488;ב',
        'תג לא מוכר': '<sup>1</sup>',
      };

      cases.forEach((description, html) {
        test(description, () {
          expect(SimpleInlineHtml.tryParse(html, baseStyle), isNull);
        });
      });
    });
  });

  group('SimpleInlineHtml.tryParse — מטמון', () {
    const html = '<b>דיבור המתחיל</b> ביאור <small>(א)</small>';

    test('אותו קלט מחזיר את אותו span בלי לפרסר מחדש', () {
      final first = SimpleInlineHtml.tryParse(html, baseStyle);
      final second = SimpleInlineHtml.tryParse(html, baseStyle);
      expect(first, isNotNull);
      expect(identical(first, second), isTrue);
    });

    test('סגנון בסיס אחר מקבל תוצאה משלו', () {
      final small = SimpleInlineHtml.tryParse(html, baseStyle)!;
      final large = SimpleInlineHtml.tryParse(
        html,
        const TextStyle(fontSize: 30),
      )!;
      final smallChild = small.children!.cast<TextSpan>().last;
      final largeChild = large.children!.cast<TextSpan>().last;
      expect(smallChild.style?.fontSize, closeTo(20 * 5 / 6, 1e-9));
      expect(largeChild.style?.fontSize, closeTo(30 * 5 / 6, 1e-9));
    });

    test('שורה שנופלת ל-HtmlWidget נשארת null גם בקריאה חוזרת', () {
      const fallback = '<a href="x">קישור</a>';
      expect(SimpleInlineHtml.tryParse(fallback, baseStyle), isNull);
      expect(SimpleInlineHtml.tryParse(fallback, baseStyle), isNull);
    });
  });
}
