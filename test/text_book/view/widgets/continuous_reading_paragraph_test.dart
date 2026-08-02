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

    // התאום של הבדיקה הקודמת: בפסקה שנשברת לכמה שורות justify כן משנה את
    // הפריסה. בלי זה, הסרת הבדיקה המקדימה הייתה יכולה לבטל יישור בשקט.
    // הרוחב חייב להכיל כמה מילים בשורה — לשורה בת מילה אחת אין רווח למתוח.
    testWidgets('פסקה רב-שורתית ב-RTL: justify מותח שורות ביחס ל-start', (
      tester,
    ) async {
      const text =
          'זהו מקטע ארוך מספיק כדי להישבר לכמה שורות בתצוגה צרה '
          'ולכן היישור לשני הצדדים אמור למתוח את הרווחים שבתוכו';

      Future<List<TextBox>> boxesFor(TextAlign align) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Directionality(
              textDirection: TextDirection.rtl,
              child: Scaffold(
                body: SizedBox(
                  width: 300,
                  child: ContinuousReadingParagraph(
                    lines: const [
                      ContinuousReadingParagraphLine(
                        lineIndex: 0,
                        text: text,
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
          TextSelection(baseOffset: 0, extentOffset: text.length),
        );
      }

      final justified = await boxesFor(TextAlign.justify);
      final started = await boxesFor(TextAlign.start);

      expect(justified.length, greaterThan(2), reason: 'חייב להישבר לשורות');
      // השורה האחרונה אינה נמתחת בשני המצבים — ההשוואה היא על כל השאר.
      expect(
        justified.take(justified.length - 1).map((b) => b.left).toList(),
        isNot(started.take(started.length - 1).map((b) => b.left).toList()),
        reason: 'justify אמור למתוח את השורות שאינן אחרונות',
      );
    });

    testWidgets('ברירת המחדל של textAlign היא justify', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 300,
              child: ContinuousReadingParagraph(
                lines: [
                  ContinuousReadingParagraphLine(
                    lineIndex: 0,
                    text: 'טקסט',
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
        tester.widget<RichText>(find.byType(RichText)).textAlign,
        TextAlign.justify,
      );
    });

    testWidgets('רשימת שורות ריקה לא קורסת', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 300,
              child: ContinuousReadingParagraph(
                lines: [],
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

    testWidgets('שורה בלי htmlText נופלת לטקסט הגולמי', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 300,
              child: ContinuousReadingParagraph(
                lines: [
                  ContinuousReadingParagraphLine(
                    lineIndex: 0,
                    text: 'טקסט <b>גולמי</b> בלי פירוק',
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
      expect(
        _flattenText([richText.text]),
        contains('<b>'),
        reason: 'בלי htmlText התגיות אינן מפורקות ונשארות כטקסט',
      );
    });

    testWidgets('שורות מרובות מופרדות ברווח אחד', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              child: ContinuousReadingParagraph(
                lines: [
                  ContinuousReadingParagraphLine(
                    lineIndex: 0,
                    text: 'ראשונה',
                    style: TextStyle(fontSize: 20),
                  ),
                  ContinuousReadingParagraphLine(
                    lineIndex: 1,
                    text: 'שנייה',
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
      expect(_flattenText([richText.text]), 'ראשונה שנייה');
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

  // פירוק ה-HTML הוא עיקר עלות ה-rebuild בגלילה, והקלט זהה בין פריימים.
  // המלכוד: הסגנון מוחל *אחרי* הפירוק ולכן אסור לו להיתפס במטמון.
  group('מטמון פירוק ה-HTML', () {
    setUp(resetInlineHtmlCacheForTesting);
    tearDown(resetInlineHtmlCacheForTesting);

    const style = TextStyle(fontSize: 20);
    const html = 'שורה <b>מודגשת</b> עם <small>הערה</small>';

    test('אותו HTML מפורק פעם אחת בלבד', () {
      buildInlineHtmlSpans(html, style);
      expect(inlineHtmlParseCount, 1);

      for (var i = 0; i < 10; i++) {
        buildInlineHtmlSpans(html, style);
      }
      expect(inlineHtmlParseCount, 1, reason: 'הפירוק החוזר אמור לבוא מהמטמון');
    });

    test('HTML שונה מפורק מחדש', () {
      buildInlineHtmlSpans(html, style);
      buildInlineHtmlSpans('$html נוסף', style);
      expect(inlineHtmlParseCount, 2);
    });

    test('התוצאה מהמטמון זהה לפירוק טרי', () {
      final fresh = buildInlineHtmlSpans(html, style);
      final cached = buildInlineHtmlSpans(html, style);
      expect(_flattenText(cached), _flattenText(fresh));
      expect(_flattenStyles(cached), _flattenStyles(fresh));
    });

    test('סגנון חדש על HTML מהמטמון מוחל במלואו', () {
      buildInlineHtmlSpans(html, style);
      final recolored = buildInlineHtmlSpans(
        html,
        const TextStyle(fontSize: 40, color: Color(0xFF00FF00)),
      );

      expect(inlineHtmlParseCount, 1, reason: 'אותו HTML — פירוק אחד');
      final sizes = _flattenStyles(
        recolored,
      ).map((s) => s.fontSize).whereType<double>();
      expect(sizes, isNotEmpty);
      // <small> מקטין ביחס לבסיס החדש — הגודל הישן אסור שיישאר.
      expect(sizes.reduce((a, b) => a > b ? a : b), 40);
      expect(
        _flattenStyles(
          recolored,
        ).every((s) => s.color == const Color(0xFF00FF00)),
        isTrue,
      );
    });

    test('קישורים מקבלים recognizer טרי בכל בנייה גם מהמטמון', () {
      const linkHtml = '<a href="otzaria://note?line=1">הערה</a>';
      final firstSink = <TapGestureRecognizer>[];
      final secondSink = <TapGestureRecognizer>[];

      buildInlineHtmlSpans(
        linkHtml,
        style,
        onTapUrl: (_) async => true,
        recognizerSink: firstSink,
      );
      buildInlineHtmlSpans(
        linkHtml,
        style,
        onTapUrl: (_) async => true,
        recognizerSink: secondSink,
      );

      expect(inlineHtmlParseCount, 1);
      expect(firstSink, hasLength(1));
      expect(secondSink, hasLength(1));
      expect(
        identical(firstSink.first, secondSink.first),
        isFalse,
        reason: 'recognizer משותף היה נזרק (dispose) פעמיים',
      );
    });

    // המלכוד המרכזי בשיתוף DOM: אם בניית הספאנים הייתה משנה את ה-DOM,
    // הבנייה השלישית הייתה מחזירה את הסגנון של השנייה.
    test('בנייה חוזרת אחרי סגנון אחר מחזירה בדיוק את התוצאה הראשונה', () {
      const other = TextStyle(fontSize: 40, color: Color(0xFF00FF00));

      final first = _flattenStyles(buildInlineHtmlSpans(html, style));
      buildInlineHtmlSpans(html, other);
      final third = _flattenStyles(buildInlineHtmlSpans(html, style));

      expect(inlineHtmlParseCount, 1);
      expect(third, first);
    });

    test('מבנה התגיות המקונן נשמר בבנייה מהמטמון', () {
      const nested = '<b>מודגש <i>ונטוי</i></b> רגיל';
      final fresh = buildInlineHtmlSpans(nested, style);
      final cached = buildInlineHtmlSpans(nested, style);

      TextStyle? italicOf(List<InlineSpan> spans) => _flattenStyles(
        spans,
      ).where((s) => s.fontStyle == FontStyle.italic).firstOrNull;

      expect(italicOf(fresh)?.fontWeight, FontWeight.bold);
      expect(italicOf(cached)?.fontWeight, FontWeight.bold);
      expect(_flattenText(cached), _flattenText(fresh));
    });

    test('הדגשת חיפוש היא ערך מטמון נפרד, ושתי הגרסאות נכונות', () {
      const plain = 'ויאמר משה';
      const highlighted = 'ויאמר <span style="color: red">משה</span>';

      final plainSpans = buildInlineHtmlSpans(plain, style);
      final markedSpans = buildInlineHtmlSpans(highlighted, style);

      expect(inlineHtmlParseCount, 2, reason: 'מחרוזות שונות — מפתחות שונים');
      expect(_findColoredSpan(plainSpans), isNull);
      expect(
        _findColoredSpan(markedSpans)?.style?.color,
        const Color(0xFFFF0000),
      );
      expect(_flattenText(plainSpans), _flattenText(markedSpans));
    });

    test('מחלקות עוגן שורדות את המטמון', () {
      const anchorHtml =
          'לפני <a class="link-anchor link-anchor-0" '
          'href="otzaria://anchor?ref=3_0">(א)</a> אחרי';
      const linkStyle = TextStyle(
        color: Color(0xFF6750A4),
        decoration: TextDecoration.underline,
      );

      final sinks = [<TapGestureRecognizer>[], <TapGestureRecognizer>[]];
      final results = [
        for (final sink in sinks)
          buildInlineHtmlSpans(
            anchorHtml,
            style,
            onTapUrl: (_) async => true,
            linkStyle: linkStyle,
            recognizerSink: sink,
          ),
      ];

      expect(inlineHtmlParseCount, 1);
      for (final spans in results) {
        final anchor = _findLinkSpan(spans);
        expect(anchor?.style?.color, const Color(0xFF6750A4));
        expect(anchor?.style?.decoration, isNot(TextDecoration.underline));
      }
      for (final sink in sinks) {
        for (final r in sink) {
          r.dispose();
        }
      }
    });

    test('onTapUrl נורה גם כשה-DOM הגיע מהמטמון', () async {
      const linkHtml = '<a href="otzaria://note?line=7">הערה</a>';
      final tapped = <String>[];
      final sink = <TapGestureRecognizer>[];

      buildInlineHtmlSpans(linkHtml, style, onTapUrl: (_) async => true);
      final spans = buildInlineHtmlSpans(
        linkHtml,
        style,
        onTapUrl: (url) async {
          tapped.add(url);
          return true;
        },
        recognizerSink: sink,
      );

      expect(inlineHtmlParseCount, 1);
      (_findLinkSpan(spans)!.recognizer! as TapGestureRecognizer).onTap!();
      expect(tapped, ['otzaria://note?line=7']);
      for (final r in sink) {
        r.dispose();
      }
    });

    test('onEnter/onExit מחוברים מחדש גם מ-DOM שמור', () {
      const anchorHtml =
          '<a class="link-anchor link-anchor-0" '
          'href="otzaria://anchor?ref=3_0">(א)</a>';
      final hovered = <String>[];
      final sink = <TapGestureRecognizer>[];

      buildInlineHtmlSpans(anchorHtml, style, onTapUrl: (_) async => true);
      final spans = buildInlineHtmlSpans(
        anchorHtml,
        style,
        onTapUrl: (_) async => true,
        onAnchorHover: (url, _) => hovered.add(url),
        recognizerSink: sink,
      );

      expect(inlineHtmlParseCount, 1);
      _findSpanContaining(spans, '(א)')!.onEnter!(const PointerEnterEvent());
      expect(hovered, ['otzaria://anchor?ref=3_0']);
      for (final r in sink) {
        r.dispose();
      }
    });

    test('HTML ריק או פגום נשמר במטמון ולא קורס', () {
      for (final broken in ['', '<b>לא נסגר', '<<>>', '&nbsp;&#1500;']) {
        expect(() => buildInlineHtmlSpans(broken, style), returnsNormally);
      }
      final countAfterFirstPass = inlineHtmlParseCount;
      for (final broken in ['', '<b>לא נסגר', '<<>>', '&nbsp;&#1500;']) {
        buildInlineHtmlSpans(broken, style);
      }
      expect(inlineHtmlParseCount, countAfterFirstPass);
    });

    test('ערך שנעשה בו שימוש חוזר שורד פינוי LRU', () {
      for (var i = 0; i < 1024; i++) {
        buildInlineHtmlSpans('שורה $i', style);
      }
      expect(inlineHtmlParseCount, 1024);

      // שימוש חוזר מקדם את הוותיק ביותר לסוף התור.
      buildInlineHtmlSpans('שורה 0', style);
      expect(inlineHtmlParseCount, 1024);

      // הכנסה חדשה מפנה עכשיו את "שורה 1", לא את "שורה 0".
      buildInlineHtmlSpans('שורה חדשה', style);
      expect(inlineHtmlParseCount, 1025);

      buildInlineHtmlSpans('שורה 0', style);
      expect(inlineHtmlParseCount, 1025, reason: 'הוקדם ולכן עדיין במטמון');

      buildInlineHtmlSpans('שורה 1', style);
      expect(inlineHtmlParseCount, 1026, reason: 'זה הערך שפונה');
    });

    test('המטמון חסום בגודלו ולא צובר ספר שלם', () {
      for (var i = 0; i < 1300; i++) {
        buildInlineHtmlSpans('שורה מספר $i', style);
      }
      expect(inlineHtmlParseCount, 1300);

      // הערך האחרון עדיין במטמון; הראשון נדחק החוצה ויפורק שוב.
      buildInlineHtmlSpans('שורה מספר 1299', style);
      expect(inlineHtmlParseCount, 1300);

      buildInlineHtmlSpans('שורה מספר 0', style);
      expect(inlineHtmlParseCount, 1301);
    });
  });
}

List<TextStyle> _flattenStyles(List<InlineSpan> spans) {
  final result = <TextStyle>[];
  void visit(InlineSpan span) {
    if (span is! TextSpan) return;
    if (span.text != null && span.style != null) result.add(span.style!);
    span.children?.forEach(visit);
  }

  spans.forEach(visit);
  return result;
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
