import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/models/plugin_highlight.dart';
import 'package:otzaria/plugins/models/plugin_reader_selection.dart';
import 'package:otzaria/plugins/models/text_source_map.dart';
import 'package:otzaria/plugins/services/plugin_highlight_renderer.dart';
import 'package:otzaria/plugins/view/plugin_highlight_frame_overlay.dart';
import 'package:otzaria/text_book/view/widgets/continuous_reading_paragraph.dart';

/// טסטים לפיצ'ר ההצגה הרציפה. עיקר הסיכון הוא ב-`_styleForElement` החדש —
/// פירוש סטיילים inline (color/background-color) של ה-`<span>`-ים שמנוע
/// החיפוש מוסיף. שגיאה כאן הופכת תוצאות חיפוש לבלתי-מסומנות במצב רצף.
void main() {
  group('justify של פסקה רציפה', () {
    testWidgets('מקטע קצר נשאר justify — הערך מועבר כמות שהוא', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 500,
              child: ContinuousReadingParagraph(
                lines: [
                  ContinuousReadingParagraphLine(
                    lineIndex: 0,
                    text: 'מקטע קצר',
                    style: TextStyle(fontSize: 20),
                  ),
                ],
                baseStyle: TextStyle(fontSize: 20),
                onLineTap: _noopLineTap,
              ),
            ),
          ),
        ),
      );

      final richText = tester.widget<RichText>(find.byType(RichText));
      expect(richText.textAlign, TextAlign.justify);
    });

    testWidgets('מקטע ארוך משאיר justify', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 120,
              child: ContinuousReadingParagraph(
                lines: [
                  ContinuousReadingParagraphLine(
                    lineIndex: 0,
                    text:
                        'זהו מקטע ארוך מספיק כדי להישבר לכמה שורות בתצוגה צרה',
                    style: TextStyle(fontSize: 20),
                  ),
                ],
                baseStyle: TextStyle(fontSize: 20),
                onLineTap: _noopLineTap,
              ),
            ),
          ),
        ),
      );

      final richText = tester.widget<RichText>(find.byType(RichText));
      expect(richText.textAlign, TextAlign.justify);
    });

    testWidgets('textAlign מפורש מועבר בלי עקיפה', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 500,
              child: ContinuousReadingParagraph(
                lines: [
                  ContinuousReadingParagraphLine(
                    lineIndex: 0,
                    text: 'מקטע קצר',
                    style: TextStyle(fontSize: 20),
                  ),
                ],
                baseStyle: TextStyle(fontSize: 20),
                textAlign: TextAlign.center,
                onLineTap: _noopLineTap,
              ),
            ),
          ),
        ),
      );

      final richText = tester.widget<RichText>(find.byType(RichText));
      expect(richText.textAlign, TextAlign.center);
    });

    // הבדיקה שמצדיקה את הסרת ה-layout המקדים: justify אינו מותח שורה אחרונה,
    // ולכן פסקה בת שורה חזותית אחת נראית זהה ב-justify וב-start.
    testWidgets('שורה יחידה ב-RTL: justify ו-start מייצרים אותה פריסה', (
      tester,
    ) async {
      Future<List<TextBox>> boxesFor(TextAlign align) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Directionality(
              textDirection: TextDirection.rtl,
              child: Scaffold(
                body: SizedBox(
                  width: 500,
                  child: ContinuousReadingParagraph(
                    lines: const [
                      ContinuousReadingParagraphLine(
                        lineIndex: 0,
                        text: 'בראשית ברא',
                        style: TextStyle(fontSize: 20),
                      ),
                    ],
                    baseStyle: const TextStyle(fontSize: 20),
                    textAlign: align,
                    onLineTap: _noopLineTap,
                  ),
                ),
              ),
            ),
          ),
        );
        final paragraph = tester.renderObject<RenderParagraph>(
          find.byType(RichText),
        );
        return paragraph.getBoxesForSelection(
          const TextSelection(baseOffset: 0, extentOffset: 10),
        );
      }

      final justified = await boxesFor(TextAlign.justify);
      final started = await boxesFor(TextAlign.start);

      expect(justified, isNotEmpty);
      expect(justified.first.left, started.first.left);
      expect(justified.last.right, started.last.right);
    });

    testWidgets('אין LayoutBuilder בפסקה — הפריסה נעשית פעם אחת', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 300,
              child: ContinuousReadingParagraph(
                lines: [
                  ContinuousReadingParagraphLine(
                    lineIndex: 0,
                    text: 'שורה ראשונה',
                    style: TextStyle(fontSize: 20),
                  ),
                  ContinuousReadingParagraphLine(
                    lineIndex: 1,
                    text: 'שורה שנייה',
                    style: TextStyle(fontSize: 20),
                  ),
                ],
                baseStyle: TextStyle(fontSize: 20),
                onLineTap: _noopLineTap,
              ),
            ),
          ),
        ),
      );

      expect(
        find.descendant(
          of: find.byType(ContinuousReadingParagraph),
          matching: find.byType(LayoutBuilder),
        ),
        findsNothing,
      );
    });

    testWidgets('רוחב לא חסום (Row ללא Expanded) לא מפיל את הפסקה', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ContinuousReadingParagraph(
                lines: [
                  ContinuousReadingParagraphLine(
                    lineIndex: 0,
                    text: 'טקסט ברוחב לא חסום',
                    style: TextStyle(fontSize: 20),
                  ),
                ],
                baseStyle: TextStyle(fontSize: 20),
                onLineTap: _noopLineTap,
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.byType(RichText), findsOneWidget);
    });

    testWidgets('בנייה חוזרת של פסקה ארוכה יציבה ולא מדליפה', (tester) async {
      final tick = ValueNotifier<int>(0);
      addTearDown(tick.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              child: SingleChildScrollView(
                child: ValueListenableBuilder<int>(
                  valueListenable: tick,
                  builder: (context, _, _) => ContinuousReadingParagraph(
                    lines: [
                      for (var i = 0; i < 60; i++)
                        ContinuousReadingParagraphLine(
                          lineIndex: i,
                          text: 'שורה מספר $i עם קצת טקסט להשלמת רוחב',
                          htmlText:
                              'שורה מספר $i <b>עם</b> קצת טקסט להשלמת רוחב',
                          style: const TextStyle(fontSize: 18),
                        ),
                    ],
                    baseStyle: const TextStyle(fontSize: 18),
                    onLineTap: _noopLineTap,
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      for (var i = 0; i < 5; i++) {
        tick.value = i + 1;
        await tester.pump();
      }

      expect(tester.takeException(), isNull);
      expect(find.byType(RichText), findsOneWidget);
    });

    testWidgets('טווחי מסגרת מוזזים לפי השורות והרווח המחבר', (tester) async {
      final highlight = _frameHighlight();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ContinuousReadingParagraph(
              lines: [
                const ContinuousReadingParagraphLine(
                  lineIndex: 0,
                  text: 'אב',
                  style: TextStyle(fontSize: 20),
                ),
                ContinuousReadingParagraphLine(
                  lineIndex: 1,
                  text: 'גד',
                  style: const TextStyle(fontSize: 20),
                  frameRanges: [
                    PluginHighlightRenderedRange(
                      start: 0,
                      end: 1,
                      highlight: highlight,
                    ),
                  ],
                ),
              ],
              baseStyle: const TextStyle(fontSize: 20),
              onLineTap: _noopLineTap,
            ),
          ),
        ),
      );

      final overlay = tester.widget<PluginHighlightFrameOverlay>(
        find.byType(PluginHighlightFrameOverlay),
      );
      expect(overlay.ranges.single.start, 3);
      expect(overlay.ranges.single.end, 4);
    });
  });

  group('פירוש סטייל inline של תוצאות חיפוש', () {
    test('color: red — נצבע אדום', () {
      final spans = buildInlineHtmlSpans(
        '<span style="color: red">יוסף</span>',
        const TextStyle(fontSize: 20),
      );
      final colored = _findColoredSpan(spans);
      expect(colored, isNotNull);
      expect(colored!.style?.color, const Color(0xFFFF0000));
    });

    test('color + background-color (התוצאה הנוכחית) נצבעים יחד', () {
      final spans = buildInlineHtmlSpans(
        '<span style="color: blue; background-color: yellow;">יוסף</span>',
        const TextStyle(fontSize: 20),
      );
      final colored = _findColoredSpan(spans);
      expect(colored, isNotNull);
      expect(colored!.style?.color, const Color(0xFF0000FF));
      expect(colored.style?.backgroundColor, const Color(0xFFFFFF00));
    });

    test('background-color בלבד לא נתפס בטעות כ-color', () {
      // הregex של _inlineColor חייב להבדיל בין `color:` ל-`background-color:`.
      // אם הוא יתפוס את הערך אחרי `background-color:` כ-color — צבע
      // הטקסט יזחל בטעות.
      final spans = buildInlineHtmlSpans(
        '<span style="background-color: yellow">יוסף</span>',
        const TextStyle(fontSize: 20, color: Color(0xFF111111)),
      );
      final colored = _findColoredSpan(spans);
      expect(colored, isNotNull);
      expect(colored!.style?.backgroundColor, const Color(0xFFFFFF00));
      // הצבע הראשי לא שונה — צריך להישאר ה-baseStyle.
      expect(colored.style?.color, const Color(0xFF111111));
    });

    test('hex 6-תווים נפרס נכון', () {
      final spans = buildInlineHtmlSpans(
        '<span style="color: #ff8800">x</span>',
        const TextStyle(fontSize: 20),
      );
      final colored = _findColoredSpan(spans);
      expect(colored!.style?.color, const Color(0xFFFF8800));
    });

    test('hex 3-תווים מורחב נכון (rgb → rrggbb)', () {
      final spans = buildInlineHtmlSpans(
        '<span style="color: #f80">x</span>',
        const TextStyle(fontSize: 20),
      );
      final colored = _findColoredSpan(spans);
      expect(colored!.style?.color, const Color(0xFFFF8800));
    });

    test('הטקסט עצמו נשמר ב-spans', () {
      // רגרסיה: אם תיקון הצביעה משנה משהו בפירוש ה-HTML, גוף הטקסט
      // ישבר. החיפוש לא רק צובע — הוא גם חייב להציג את המילה.
      final spans = buildInlineHtmlSpans(
        'לפני <span style="color: red">יוסף</span> אחרי',
        const TextStyle(fontSize: 20),
      );
      final flattened = _flattenText(spans);
      expect(flattened, contains('יוסף'));
      expect(flattened, contains('לפני'));
      expect(flattened, contains('אחרי'));
    });
  });

  group('עיצוב קישורי inline (<a>)', () {
    test('עם linkStyle — הקישור מקבל את הצבע והקו התחתון שהוזרמו', () {
      final recognizers = <TapGestureRecognizer>[];
      final spans = buildInlineHtmlSpans(
        'לפני <a href="otzaria://inline-link?path=x">קישור</a> אחרי',
        const TextStyle(fontSize: 20, color: Color(0xFF111111)),
        onTapUrl: (_) async => true,
        linkStyle: const TextStyle(
          color: Color(0xFF6750A4),
          decoration: TextDecoration.underline,
        ),
        recognizerSink: recognizers,
      );
      final link = _findLinkSpan(spans);
      expect(link, isNotNull);
      expect(link!.style?.color, const Color(0xFF6750A4));
      expect(link.style?.decoration, TextDecoration.underline);
      for (final r in recognizers) {
        r.dispose();
      }
    });

    test('עוגן-מילה מקבל onEnter/onExit לריחוף; קישור רגיל — לא', () {
      final recognizers = <TapGestureRecognizer>[];
      final hovered = <String>[];
      final exited = <String>[];
      final spans = buildInlineHtmlSpans(
        'לפני <a class="link-anchor link-anchor-0" '
        'href="otzaria://anchor?ref=3_0">(א)</a> '
        '<a href="https://example.com">קישור</a> אחרי',
        const TextStyle(fontSize: 20, color: Color(0xFF111111)),
        onTapUrl: (_) async => true,
        onAnchorHover: (url, position) => hovered.add(url),
        onAnchorExit: exited.add,
        recognizerSink: recognizers,
      );
      final anchorSpan = _findSpanContaining(spans, '(א)');
      final plainLinkSpan = _findSpanContaining(spans, 'קישור');
      expect(anchorSpan, isNotNull);
      expect(anchorSpan!.onEnter, isNotNull);
      expect(anchorSpan.onExit, isNotNull);
      expect(plainLinkSpan!.onEnter, isNull);
      expect(plainLinkSpan.onExit, isNull);

      anchorSpan.onEnter!(const PointerEnterEvent(position: Offset(5, 7)));
      anchorSpan.onExit!(const PointerExitEvent());
      expect(hovered, ['otzaria://anchor?ref=3_0']);
      expect(exited, ['otzaria://anchor?ref=3_0']);
      for (final r in recognizers) {
        r.dispose();
      }
    });

    test('סימוני הערות מקבלים onEnter/onExit במצב רציף', () {
      final recognizers = <TapGestureRecognizer>[];
      final hovered = <String>[];
      final spans = buildInlineHtmlSpans(
        '<a class="book-note-marker" '
        'href="otzaria://book-note?line=3&note=0">א</a> '
        '<a href="otzaria://note?line=3">הערה</a>',
        const TextStyle(fontSize: 20),
        onTapUrl: (_) async => true,
        onAnchorHover: (url, _) => hovered.add(url),
        recognizerSink: recognizers,
      );

      _findSpanContaining(spans, 'א')!.onEnter!(const PointerEnterEvent());
      _findSpanContaining(spans, 'הערה')!.onEnter!(const PointerEnterEvent());
      expect(hovered, [
        'otzaria://book-note?line=3&note=0',
        'otzaria://note?line=3',
      ]);
      for (final r in recognizers) {
        r.dispose();
      }
    });

    test('עוגן-מילה (a.link-anchor) נצבע ב-primary ובלי קו תחתון', () {
      final recognizers = <TapGestureRecognizer>[];
      final spans = buildInlineHtmlSpans(
        'לפני <a class="link-anchor link-anchor-0" '
        'href="otzaria://anchor?ref=3_0">(א)</a> אחרי',
        const TextStyle(fontSize: 20, color: Color(0xFF111111)),
        onTapUrl: (_) async => true,
        linkStyle: const TextStyle(
          color: Color(0xFF6750A4),
          decoration: TextDecoration.underline,
        ),
        recognizerSink: recognizers,
      );
      final link = _findLinkSpan(spans);
      expect(link, isNotNull);
      // צבע primary אך בלי קו תחתון — סמן-נקודה נשאר ללא קו.
      expect(link!.style?.color, const Color(0xFF6750A4));
      expect(link.style?.decoration, isNot(TextDecoration.underline));
      for (final r in recognizers) {
        r.dispose();
      }
    });

    test('בלי linkStyle — קו תחתון בלבד, הצבע יורש מהטקסט (לא כחול קשיח)', () {
      final recognizers = <TapGestureRecognizer>[];
      final spans = buildInlineHtmlSpans(
        '<a href="otzaria://inline-link?path=x">קישור</a>',
        const TextStyle(fontSize: 20, color: Color(0xFF111111)),
        onTapUrl: (_) async => true,
        recognizerSink: recognizers,
      );
      final link = _findLinkSpan(spans);
      expect(link, isNotNull);
      expect(link!.style?.decoration, TextDecoration.underline);
      expect(link.style?.color, const Color(0xFF111111));
      for (final r in recognizers) {
        r.dispose();
      }
    });
  });

  group('פירוש סטייל inline — ערכי קצה', () {
    test('צבע לא חוקי לא קורס ולא משנה את הצבע', () {
      final spans = buildInlineHtmlSpans(
        '<span style="color: notacolor">x</span>',
        const TextStyle(fontSize: 20, color: Color(0xFF222222)),
      );
      final colored = _findColoredSpan(spans);
      expect(colored, isNotNull);
      expect(colored!.style?.color, const Color(0xFF222222));
    });

    test('ספאן בלי style — נשאר עם ה-baseStyle', () {
      final spans = buildInlineHtmlSpans(
        '<span>x</span>',
        const TextStyle(fontSize: 20, color: Color(0xFF333333)),
      );
      final colored = _findColoredSpan(spans);
      expect(colored!.style?.color, const Color(0xFF333333));
    });
  });

  test('underline preserves its rgba color and thickness', () {
    final spans = buildInlineHtmlSpans(
      '<span style="text-decoration: underline; '
      'text-decoration-color: rgba(10, 20, 30, 0.5); '
      'text-decoration-thickness: 2px">marked</span>',
      const TextStyle(fontSize: 20),
    );
    final underlined = _findUnderlinedSpan(spans);
    expect(underlined, isNotNull);
    expect(underlined!.style?.decoration, TextDecoration.underline);
    expect(underlined.style?.decorationColor, const Color(0x800A141E));
    expect(underlined.style?.decorationThickness, 2);
  });

  test('inline colors support CSS alpha without a leading zero', () {
    final spans = buildInlineHtmlSpans(
      '<span style="text-decoration: underline; '
      'text-decoration-color: rgba(10, 20, 30, .5)">marked</span>',
      const TextStyle(fontSize: 20),
    );
    final underlined = _findUnderlinedSpan(spans);
    expect(underlined?.style?.decorationColor, const Color(0x800A141E));
  });

  test('inline #RRGGBBAA colors keep CSS channel order', () {
    final spans = buildInlineHtmlSpans(
      '<span style="background-color: #ff000080">marked</span>',
      const TextStyle(fontSize: 20),
    );
    final colored = _findColoredSpan(spans);
    expect(colored?.style?.backgroundColor, const Color(0x80FF0000));
  });
}

void _noopLineTap(int lineIndex) {}

PluginHighlight _frameHighlight() {
  const context = PluginAnchorContext(
    raw: '',
    normalized: '',
    maxGraphemes: 30,
    actualGraphemes: 0,
    truncatedAtBoundary: true,
  );
  return PluginHighlight(
    highlightId: 'frame',
    ownerPluginId: 'plugin',
    bookId: 'book',
    sectionIndex: 1,
    range: const PluginTextRangeAnchor(
      layer: 'source',
      start: PluginTextOffset(grapheme: 0, codePoint: 0, utf16: 0),
      end: PluginTextOffset(grapheme: 1, codePoint: 1, utf16: 1),
      exactText: 'ג',
      beforeText: context,
      afterText: context,
      occurrenceIndexInSection: 0,
      occurrenceCountInSection: 1,
    ),
    style: const PluginHighlightStyle(backgroundColor: '#FFE066'),
    createdAt: DateTime.utc(2026, 7, 21),
    updatedAt: DateTime.utc(2026, 7, 21),
  );
}

/// מאתר את ה-`TextSpan` של קישור — מזוהה לפי recognizer מחובר.
/// ה-span הלחיץ (עם recognizer) שהטקסט השטוח שלו מכיל את [needle].
TextSpan? _findSpanContaining(List<InlineSpan> spans, String needle) {
  TextSpan? result;
  void visit(InlineSpan span) {
    if (result != null || span is! TextSpan) return;
    if (span.recognizer != null && span.toPlainText().contains(needle)) {
      result = span;
      return;
    }
    span.children?.forEach(visit);
  }

  spans.forEach(visit);
  return result;
}

TextSpan? _findLinkSpan(List<InlineSpan> spans) {
  TextSpan? result;
  void visit(InlineSpan span) {
    if (result != null || span is! TextSpan) return;
    if (span.recognizer != null) {
      result = span;
      return;
    }
    span.children?.forEach(visit);
  }

  spans.forEach(visit);
  return result;
}

/// מאתר את ה-`TextSpan` הראשון ברמה הפנימית ביותר שיש לו `style.color`
/// או `style.backgroundColor` שונה מ-baseStyle. משמש לבדוק שצביעת ה-HTML
/// אכן הגיעה לרינדור.
TextSpan? _findColoredSpan(List<InlineSpan> spans) {
  TextSpan? result;
  void visit(InlineSpan span) {
    if (span is! TextSpan) return;
    if (span.children != null) {
      for (final child in span.children!) {
        if (result != null) return;
        visit(child);
      }
    }
    if (result == null &&
        (span.style?.color != null || span.style?.backgroundColor != null)) {
      result = span;
    }
  }

  for (final span in spans) {
    visit(span);
    if (result != null) return result;
  }
  return result;
}

TextSpan? _findUnderlinedSpan(List<InlineSpan> spans) {
  TextSpan? result;
  void visit(InlineSpan span) {
    if (result != null || span is! TextSpan) return;
    if (span.style?.decoration == TextDecoration.underline) {
      result = span;
      return;
    }
    span.children?.forEach(visit);
  }

  spans.forEach(visit);
  return result;
}

String _flattenText(List<InlineSpan> spans) {
  final buffer = StringBuffer();
  void visit(InlineSpan span) {
    if (span is! TextSpan) return;
    if (span.text != null) buffer.write(span.text);
    span.children?.forEach(visit);
  }

  spans.forEach(visit);
  return buffer.toString();
}
