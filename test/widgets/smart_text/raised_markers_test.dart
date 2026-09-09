import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart'
    show HtmlWidget;
import 'package:otzaria/text_book/utils/link_anchor_variants.dart'
    show kLinkAnchorMarkerScale;
import 'package:otzaria/text_book/view/widgets/continuous_reading_paragraph.dart';
import 'package:otzaria/widgets/smart_text/raised_markers.dart';
import 'package:otzaria/widgets/smart_text/render_settings.dart';
import 'package:otzaria/widgets/smart_text/simple_inline_html.dart';
import 'package:otzaria/widgets/smart_text/smart_text_widget.dart';
import 'package:otzaria/widgets/smart_text/text_renderer_service.dart';

/// LRI/RLI/PDI — `_fixFootnoteMarkers` עוטף בהם את תוכן הסימון. נבנים
/// מ-code point כדי לא לשתול תווי כיווניות בקוד המקור עצמו.
final rli = String.fromCharCode(0x2067);
final lri = String.fromCharCode(0x2066);
final pdi = String.fromCharCode(0x2069);

void main() {
  setUp(() {
    RaisedMarkers.clearCacheForTesting();
    TextRendererService.clearRenderCacheForTesting();
  });

  group('processText — sup פשוט ולא-מספרי הופך ל-span טקסט טהור', () {
    String process(String html) =>
        TextRendererService.processText(html, const RenderSettings());

    test('sup עם class מרקר', () {
      final out = process('ברא<sup class="footnote-marker">א</sup> אלהים');
      expect(out, contains('class="$kFootnoteMarkerClass"'));
      expect(out, isNot(contains('<sup')));
    });

    test('sup חשוף מקובץ משתמש — התיקון האמיתי של הבאג', () {
      // זה המקרה מהתמלול: קובץ HTML שנטען דרך "אוסף קבצים" עם <sup> רגיל.
      // לפני התיקון הוא נשאר <sup> → WidgetSpan → סדר הפוך בשני סימונים.
      final out = process('בראשית<sup>א</sup> ברא');
      expect(out, contains('class="$kRaisedSupClass"'));
      expect(out, isNot(contains('<sup')));
    });

    test('superscript תוכני (מילה שלמה) גם הוא span', () {
      final out = process('טקסט<sup>מעלית</sup>');
      expect(out, contains('class="$kRaisedSupClass"'));
      expect(out, isNot(contains('<sup')));
    });

    test('sup מספרי גם הוא span (ספרות רגילות בגופן הספר, issue #1236)', () {
      final out = process('ברא<sup>12</sup>');
      expect(out, contains('class="$kRaisedSupClass"'));
      expect(out, contains('12'));
      expect(out, isNot(contains('¹²')));
    });

    test('מרקר הערה נטוי ומוקטן 0.75, sup חשוף 5/6 בלי נטייה', () {
      final footnote = RaisedMarkers.extract(
        process('ברא<sup class="footnote-marker">א</sup>'),
      ).single;
      expect(footnote.scale, kFootnoteMarkerScale);
      expect(footnote.italic, isTrue);

      final bare = RaisedMarkers.extract(process('ברא<sup>א</sup>')).single;
      expect(bare.scale, kHtmlSmallerFontScale);
      expect(bare.italic, isFalse);
    });

    test('sup ריק מוסר', () {
      expect(process('ברא<sup> </sup> אלהים'), 'ברא אלהים');
    });

    test('תוכן הסימון עטוף בבידוד כיווניות', () {
      final out = process('ברא<sup>א</sup>');
      expect(
        out,
        contains(
          '$rli'
          'א'
          '$pdi',
        ),
      );
    });

    test('סימון לועזי מקבל בידוד LTR', () {
      final out = process('text<sup>a</sup>');
      expect(
        out,
        contains(
          '$lri'
          'a'
          '$pdi',
        ),
      );
    });

    test('HTML entity מפוענח לאותו טקסט שמוצג בפריסה', () {
      final marker = RaisedMarkers.extract(
        process('לפני<sup>&ast;</sup>אחרי'),
      ).single;

      expect(marker.text, '$lri*$pdi');
    });
  });

  group('RaisedMarkers.extract — חילוץ', () {
    test('טקסט בלי סימונים מחזיר רשימה ריקה', () {
      expect(RaisedMarkers.extract('בראשית ברא אלהים'), isEmpty);
    });

    test('סימון אחד נקלט עם תווי הבידוד', () {
      final markers = RaisedMarkers.extract(
        'ברא<span class="$kFootnoteMarkerClass">$rli'
        'א'
        '$pdi</span>',
      );
      expect(markers, hasLength(1));
      expect(
        markers.single.text,
        '$rli'
        'א'
        '$pdi',
      );
      expect(markers.single.occurrence, 1);
    });

    test('שני סימונים באותה שורה — שניהם, לפי הסדר', () {
      final markers = RaisedMarkers.extract(
        'בראשית<span class="$kFootnoteMarkerClass">$rli'
        'א'
        '$pdi</span>'
        ' ברא ואת<span class="$kFootnoteMarkerClass">$rli'
        'ב'
        '$pdi</span>',
      );
      expect(
        markers.map((m) => m.text.replaceAll(rli, '').replaceAll(pdi, '')),
        ['א', 'ב'],
      );
    });

    test('אותו סימון פעמיים — מספר המופע עולה', () {
      final markers = RaisedMarkers.extract(
        'א<span class="$kFootnoteMarkerClass">$rli'
        'א'
        '$pdi</span>'
        'ב<span class="$kFootnoteMarkerClass">$rli'
        'א'
        '$pdi</span>',
      );
      expect(markers, hasLength(2));
      expect(markers[0].occurrence, 1);
      expect(markers[1].occurrence, 2);
    });

    test('המטמון מחזיר את אותה רשימה לקלט זהה', () {
      final html =
          'ברא<span class="$kFootnoteMarkerClass">$rli'
          'א'
          '$pdi</span>';
      expect(
        identical(RaisedMarkers.extract(html), RaisedMarkers.extract(html)),
        isTrue,
      );
    });
  });

  group('RaisedMarkerOverlay — גאומטריה על עץ הרינדור', () {
    Future<RenderRaisedMarkerOverlay> pump(
      WidgetTester tester,
      String html, {
      double width = 600,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: Align(
                alignment: Alignment.topRight,
                child: SizedBox(
                  width: width,
                  child: SmartTextWidget(
                    text: html,
                    settings: const RenderSettings(),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return tester.renderObject<RenderRaisedMarkerOverlay>(
        find.byType(RaisedMarkerOverlay),
      );
    }

    testWidgets('הסימון מצויר מעל מקומו בשורה', (tester) async {
      final overlay = await pump(
        tester,
        'בראשית<sup>א</sup> ברא אלהים את השמים',
      );
      final placements = overlay.debugPlacements();
      expect(placements, hasLength(1));
      final p = placements.single;
      expect(
        p.paintRect.top,
        lessThan(p.anchorRect.top),
        reason: 'הציור חייב להיות גבוה מהעוגן — זו כל הפואנטה של אות גבוהה',
      );
      expect(
        (p.paintRect.center.dx - p.anchorRect.center.dx).abs(),
        lessThanOrEqualTo(1.5),
        reason: 'הציור חייב להתלבש אופקית על הגליפים השקופים',
      );
    });

    testWidgets('סימון שמקודד כ-HTML entity אינו נעלם', (tester) async {
      final overlay = await pump(tester, 'לפני<sup>&ast;</sup> אחרי');
      final placement = overlay.debugPlacements().single;

      expect(placement.text, '$lri*$pdi');
      expect(placement.paintRect.top, lessThan(placement.anchorRect.top));
    });

    testWidgets('שני סימונים באותה שורה — הסדר לא מתהפך', (tester) async {
      final overlay = await pump(
        tester,
        'בראשית<sup>א</sup> ברא אלהים את השמיים ואת<sup>ב</sup> הארץ',
      );
      final placements = overlay.debugPlacements();
      expect(placements, hasLength(2));
      // ב-RTL הסימון הראשון (א) חייב להיות ימני מהשני (ב).
      expect(
        placements[0].anchorRect.center.dx,
        greaterThan(placements[1].anchorRect.center.dx),
        reason: 'הבאג המקורי: א ו-ב מוצגים הפוך',
      );
      expect(
        placements[0].paintRect.center.dx,
        greaterThan(placements[1].paintRect.center.dx),
        reason: 'גם הציור עצמו חייב לשמור על הסדר',
      );
    });

    testWidgets('שלושה סימונים — הסדר עולה מימין לשמאל', (tester) async {
      final overlay = await pump(
        tester,
        'אחד<sup>א</sup> שנים<sup>ב</sup> שלשה<sup>ג</sup> ארבעה',
      );
      final placements = overlay.debugPlacements();
      expect(placements, hasLength(3));
      for (var i = 0; i < placements.length - 1; i++) {
        expect(
          placements[i].anchorRect.center.dx,
          greaterThan(placements[i + 1].anchorRect.center.dx),
          reason: 'סימון $i חייב להיות ימני מסימון ${i + 1}',
        );
      }
    });

    testWidgets('סימונים לועזיים לא הופכים את הסדר', (tester) async {
      final overlay = await pump(
        tester,
        'ראשון<sup>a</sup> ואחרון<sup>b</sup> בסוגיה',
      );
      final placements = overlay.debugPlacements();
      expect(placements, hasLength(2));
      expect(
        placements[0].anchorRect.center.dx,
        greaterThan(placements[1].anchorRect.center.dx),
      );
    });

    testWidgets('סימון בשורה הראשונה לא נחתך מעל הגבול', (tester) async {
      final overlay = await pump(tester, 'בראשית<sup>א</sup> ברא');
      final p = overlay.debugPlacements().single;
      expect(p.paintRect.top, greaterThanOrEqualTo(0.0));
    });

    testWidgets('גלישת שורה: הסימון נשאר על השורה של המילה שלו', (
      tester,
    ) async {
      final overlay = await pump(
        tester,
        'ובחרת בחיים למען תחיה אתה וזרעך<sup>א</sup> לאהבה את השם',
        width: 150,
      );
      final p = overlay.debugPlacements().single;
      expect(p.paintRect.top, lessThan(p.anchorRect.top));
      expect(
        (p.paintRect.center.dx - p.anchorRect.center.dx).abs(),
        lessThanOrEqualTo(1.5),
      );
    });

    testWidgets('טקסט הסימון נשאר בטקסט (בחירה והעתקה)', (tester) async {
      final overlay = await pump(tester, 'בראשית<sup>א</sup> ברא');
      var joined = '';
      void visit(RenderObject object) {
        if (object is RenderParagraph) {
          joined += object.text.toPlainText();
          return;
        }
        object.visitChildren(visit);
      }

      visit(overlay);
      expect(joined, contains('א'), reason: 'הסימון חייב להישאר בטקסט');
      expect(joined, contains('בראשית'));
    });

    testWidgets('קטע בלי סימונים לא נעטף בשכבה', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: SmartTextWidget(
                text: 'בראשית ברא אלהים',
                settings: const RenderSettings(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(RaisedMarkerOverlay), findsNothing);
    });

    testWidgets(
      'תמיכה בסיסית: שורת סימונים נשארת במסלול המהיר (בלי HtmlWidget)',
      (tester) async {
        final overlay = await pump(
          tester,
          'בראשית<sup>א</sup> ברא ואת<sup>ב</sup> הארץ',
        );
        // SimpleInlineHtml מזהה את תגי הסימון בעצמו — אין נפילה ל-HtmlWidget.
        expect(
          find.byType(HtmlWidget),
          findsNothing,
          reason: 'שורת סימונים חייבת להישאר במסלול המהיר',
        );
        expect(overlay.debugPlacements(), hasLength(2));
      },
    );

    testWidgets('תמיכה בסיסית: גליפי הסימון במסלול המהיר שקופים ומוקטנים', (
      tester,
    ) async {
      await pump(tester, 'בראשית<sup>א</sup> ברא');
      TextStyle? markerStyle;
      for (final rich in tester.widgetList<RichText>(find.byType(RichText))) {
        void visit(InlineSpan span) {
          if (span is TextSpan) {
            if ((span.text ?? '').contains('א') &&
                span.style?.color != null &&
                span.style!.color!.a == 0) {
              markerStyle = span.style;
            }
            span.children?.forEach(visit);
          }
        }

        visit(rich.text);
      }
      expect(markerStyle, isNotNull, reason: 'לא נמצא ספאן סימון שקוף');
      expect(
        markerStyle!.fontSize,
        closeTo(18.0 * kHtmlSmallerFontScale, 0.001),
        reason: 'sup חשוף חייב לשמור על יחס 5/6 גם במסלול המהיר',
      );
      expect(
        markerStyle!.fontStyle ?? FontStyle.normal,
        FontStyle.normal,
        reason: 'sup חשוף אינו נוטה',
      );
    });

    testWidgets('מסלול HtmlWidget (תגים מורכבים) — אותה התנהגות', (
      tester,
    ) async {
      // span זר מפיל את המסלול המהיר — מוודאים שהשכבה עובדת גם שם.
      final overlay = await pump(
        tester,
        'בראשית<sup>א</sup> ברא ואת<sup>ב</sup> הארץ <span class="x">.</span>',
      );
      expect(find.byType(HtmlWidget), findsOneWidget);
      final placements = overlay.debugPlacements();
      expect(placements, hasLength(2));
      expect(
        placements[0].anchorRect.center.dx,
        greaterThan(placements[1].anchorRect.center.dx),
        reason: 'הסדר חייב להישמר גם במסלול HtmlWidget',
      );
      for (final p in placements) {
        expect(p.paintRect.top, lessThan(p.anchorRect.top));
      }
    });

    test('SimpleInlineHtml: span זר עדיין מפיל ל-HtmlWidget', () {
      const style = TextStyle(fontSize: 18);
      expect(
        SimpleInlineHtml.tryParse('טקסט <span class="x">זר</span>', style),
        isNull,
      );
      expect(SimpleInlineHtml.tryParse('טקסט יתום</span>', style), isNull);
    });

    test('SimpleInlineHtml: מרקר הערה מקבל 0.75 ונטוי, בתוך מודגש', () {
      const style = TextStyle(fontSize: 20);
      final html = TextRendererService.processText(
        '<b>מודגש<sup class="footnote-marker">א</sup></b>',
        const RenderSettings(fontSize: 20),
      );
      final span = SimpleInlineHtml.tryParse(html, style);
      expect(span, isNotNull, reason: 'שורת מרקר חייבת להתקבל במסלול המהיר');
      TextStyle? found;
      void visit(InlineSpan s) {
        if (s is TextSpan) {
          if ((s.text ?? '').contains('א')) found = s.style;
          s.children?.forEach(visit);
        }
      }

      visit(span!);
      expect(found, isNotNull);
      expect(found!.fontSize, closeTo(20 * kFootnoteMarkerScale, 0.001));
      expect(found!.fontStyle, FontStyle.italic);
      expect(found!.fontWeight, FontWeight.bold, reason: 'הבולד העוטף נשמר');
      expect(found!.color!.a, 0, reason: 'הגליף שקוף — השכבה מציירת אותו');
    });

    test(
      'buildInlineHtmlSpans: בלי שכבה הסימון נשאר גלוי (hideRaisedMarkers)',
      () {
        final html = TextRendererService.processText(
          'ברא<sup>א</sup>',
          const RenderSettings(),
        );
        TextStyle? styleOf(List<InlineSpan> spans) {
          TextStyle? found;
          void visit(InlineSpan s, TextStyle? inherited) {
            if (s is! TextSpan) return;
            final style = s.style ?? inherited;
            if ((s.text ?? '').contains('א')) found = style;
            for (final c in s.children ?? const <InlineSpan>[]) {
              visit(c, style);
            }
          }

          for (final s in spans) {
            visit(s, null);
          }
          return found;
        }

        const base = TextStyle(fontSize: 18, color: Colors.black);
        final hidden = styleOf(buildInlineHtmlSpans(html, base));
        expect(hidden?.color?.a, 0, reason: 'ברירת המחדל: שקוף לטובת השכבה');

        final visible = styleOf(
          buildInlineHtmlSpans(html, base, hideRaisedMarkers: false),
        );
        expect(
          visible?.color?.a,
          isNot(0),
          reason: 'קורא בלי שכבה חייב לקבל גליפים גלויים',
        );
      },
    );

    testWidgets('מצב קריאה רציפה — הסימון מורם גם שם', (tester) async {
      const base = TextStyle(fontSize: 20, fontFamily: 'FrankRuhlCLM');
      final firstLine = TextRendererService.processText(
        'בראשית<sup>א</sup> ברא אלהים',
        const RenderSettings(fontSize: 20, fontFamily: 'FrankRuhlCLM'),
      );
      final secondLine = TextRendererService.processText(
        'ואת<sup>ב</sup> הארץ',
        const RenderSettings(fontSize: 20, fontFamily: 'FrankRuhlCLM'),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: Align(
                alignment: Alignment.topRight,
                child: SizedBox(
                  width: 600,
                  child: ContinuousReadingParagraph(
                    lines: [
                      ContinuousReadingParagraphLine(
                        lineIndex: 0,
                        text: 'בראשית ברא אלהים',
                        htmlText: firstLine,
                        style: base,
                      ),
                      ContinuousReadingParagraphLine(
                        lineIndex: 1,
                        text: 'ואת הארץ',
                        htmlText: secondLine,
                        style: base,
                      ),
                    ],
                    baseStyle: base,
                    onLineTap: (_) {},
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final overlay = tester.renderObject<RenderRaisedMarkerOverlay>(
        find.byType(RaisedMarkerOverlay),
      );
      final placements = overlay.debugPlacements();
      expect(placements, hasLength(2));
      for (final p in placements) {
        expect(
          p.paintRect.top,
          lessThan(p.anchorRect.top),
          reason: 'גם בקריאה רציפה הסימון חייב להיות מורם',
        );
      }
      expect(
        placements[0].anchorRect.center.dx,
        greaterThan(placements[1].anchorRect.center.dx),
        reason: 'הסדר נשמר גם כששני הסימונים באים משורות שונות באותה פסקה',
      );
    });

    testWidgets('סימון מספרי עובר בשכבה כמו סימון-אות (issue #1236)', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: SmartTextWidget(
                text: 'ברא<sup>1</sup> אלהים',
                settings: const RenderSettings(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(RaisedMarkerOverlay), findsOneWidget);
      expect(find.textContaining('¹'), findsNothing);
    });
  });

  group('סימונים לחיצים — חילוץ', () {
    test('book-note-marker: מטריקות מרקר הערה + הפניית לחיצה', () {
      final markers = RaisedMarkers.extract(
        'מנשא <a class="book-note-marker" '
        'href="otzaria://book-note?line=0&note=0">*</a> עוני',
      );
      expect(markers, hasLength(1));
      final marker = markers.single;
      expect(marker.text, '*');
      expect(marker.scale, kFootnoteMarkerScale);
      expect(marker.italic, isTrue);
      expect(marker.clickable, isTrue);
      expect(marker.useLinkColor, isFalse);
      expect(marker.active, isFalse);
    });

    test('link-anchor: וריאנט, צבע קישור ומצב פעיל', () {
      final markers = RaisedMarkers.extract(
        'מילה <a class="link-anchor link-anchor-3 link-anchor-active" '
        'href="otzaria://anchor?ref=0_0">(א)</a> אחרי',
      );
      final marker = markers.single;
      expect(marker.text, '(א)');
      expect(marker.scale, kLinkAnchorMarkerScale);
      expect(marker.italic, isFalse);
      expect(marker.clickable, isTrue);
      expect(marker.useLinkColor, isTrue);
      expect(marker.variantIndex, 3);
      expect(marker.active, isTrue);
    });

    test('גם צורת ה-span הלא-אינטראקטיבית של אות מפרש מחולצת', () {
      final markers = RaisedMarkers.extract(
        '<span class="link-anchor link-anchor-1">(ב)</span>',
      );
      expect(markers.single.variantIndex, 1);
      expect(markers.single.active, isFalse);
      expect(markers.single.clickable, isTrue);
    });

    test('link-anchor חשוף (בלי וריאנט) מחולץ — הגנה מפני טקסט נעלם', () {
      // customStylesBuilder צובע כל link-anchor שקוף; כל צורה שנצבעת חייבת
      // להיקלט כאן, אחרת האות תיעלם מהמסך.
      final markers = RaisedMarkers.extract(
        '<span class="link-anchor">א</span>',
      );
      expect(markers, hasLength(1));
      expect(markers.single.variantIndex, isNull);
      expect(markers.single.scale, kLinkAnchorMarkerScale);
    });

    test('טווח-ציטוט וסמן-מספר מודפס נשארים במקומם — לא מחולצים', () {
      expect(
        RaisedMarkers.extract(
          '<a class="link-anchor-range" href="otzaria://anchor?ref=0_0&range=1">'
          'ציטוט ארוך</a>',
        ),
        isEmpty,
      );
      expect(
        RaisedMarkers.extract(
          '<a class="numbered-note-marker" href="otzaria://note-marker?x=1">(9)</a>',
        ),
        isEmpty,
      );
    });

    test('עיצוב סוגריים (<small> בתוך הסימון) מקטין את הציור באותו יחס', () {
      // processText עוטף "(א)" ב-<small>; הגליף בשורה קטן בהתאם, והציור
      // חייב להתלבש עליו בדיוק — לא לבלוט מעבר למקום ששמור בשורה.
      final markers = RaisedMarkers.extract(
        TextRendererService.processText(
          'מילה <a class="link-anchor link-anchor-0" '
          'href="otzaria://anchor?ref=0_0">(א)</a> אחרי',
          const RenderSettings(),
        ),
      );
      expect(markers, hasLength(1));
      expect(
        markers.single.scale,
        closeTo(kLinkAnchorMarkerScale * kHtmlSmallerFontScale, 0.0001),
      );
    });

    test('ספירת מופעים משותפת בין המשפחות — אותה ספירה שהציור מבצע', () {
      final markers = RaisedMarkers.extract(
        '<span class="$kRaisedSupClass">א</span> ביניים '
        '<a class="book-note-marker" href="otzaria://book-note?line=0&note=0">'
        'א</a>',
      );
      expect(markers, hasLength(2));
      expect(markers[0].occurrence, 1);
      expect(markers[1].occurrence, 2);
      expect(markers[0].clickable, isFalse);
      expect(markers[1].clickable, isTrue);
    });
  });

  group('סימונים לחיצים — הרמה והפניית hit-test', () {
    Future<RenderRaisedMarkerOverlay> pump(
      WidgetTester tester,
      String html, {
      double width = 600,
      void Function(String url)? onAnchorTap,
      void Function(String url, Offset position)? onAnchorHover,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: Align(
                alignment: Alignment.topRight,
                child: SizedBox(
                  width: width,
                  child: SmartTextWidget(
                    text: html,
                    settings: const RenderSettings(),
                    onAnchorTap: onAnchorTap,
                    onAnchorHover: onAnchorHover,
                    onNoteTap: (_) {},
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return tester.renderObject<RenderRaisedMarkerOverlay>(
        find.byType(RaisedMarkerOverlay),
      );
    }

    /// נקודה שנמצאת בציור המורם אך מחוץ לעוגן שבשורה — פגיעה בה מוכיחה
    /// שההפניה עובדת ולא סתם חפיפה בין המלבנים.
    Offset raisedOnlyPoint(RaisedMarkerPlacement placement) {
      final point = Offset(
        placement.paintRect.center.dx,
        placement.paintRect.top + 1,
      );
      expect(
        placement.anchorRect.contains(point),
        isFalse,
        reason: 'נקודת הבדיקה חייבת להיות מחוץ לעוגן — אחרת הבדיקה ריקה',
      );
      return point;
    }

    // הסימון בשורה השנייה כדי שההרמה לא תיחסם בגבול העליון של הקטע.
    const twoLineAnchor =
        'ובני ישראל יוצאים ביד רמה והמצרים רודפים אחריהם '
        'וישיגו אותם חונים על הים '
        '<a class="link-anchor link-anchor-0" href="otzaria://anchor?ref=5_0">'
        '(א)</a> ואחרי הדברים האלה';

    testWidgets('אות מפרש מצוירת מורמת מעל העוגן שבשורה', (tester) async {
      final overlay = await pump(
        tester,
        twoLineAnchor,
        width: 320,
        onAnchorTap: (_) {},
      );
      final placement = overlay.debugPlacements().single;
      expect(placement.marker.clickable, isTrue);
      expect(placement.marker.useLinkColor, isTrue);
      expect(placement.paintRect.top, lessThan(placement.anchorRect.top));
      expect(
        (placement.paintRect.center.dx - placement.anchorRect.center.dx).abs(),
        lessThanOrEqualTo(1.5),
      );
    });

    testWidgets('לחיצה על הציור המורם מפעילה את העוגן (הפניית hit-test)', (
      tester,
    ) async {
      String? tapped;
      final overlay = await pump(
        tester,
        twoLineAnchor,
        width: 320,
        onAnchorTap: (url) => tapped = url,
      );
      final placement = overlay.debugPlacements().single;
      await tester.tapAt(overlay.localToGlobal(raisedOnlyPoint(placement)));
      await tester.pump();
      expect(tapped, 'otzaria://anchor?ref=5_0');
    });

    testWidgets('ריחוף על הציור המורם מפעיל את תצוגת העוגן', (tester) async {
      final hovered = <String>[];
      final overlay = await pump(
        tester,
        twoLineAnchor,
        width: 320,
        onAnchorTap: (_) {},
        onAnchorHover: (url, _) => hovered.add(url),
      );
      final placement = overlay.debugPlacements().single;

      final gesture = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
      );
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);
      await gesture.moveTo(
        overlay.localToGlobal(raisedOnlyPoint(placement)),
      );
      await tester.pump();

      expect(hovered, contains('otzaria://anchor?ref=5_0'));
    });

    testWidgets('גם סימון הערה מוטמעת (כוכבית) מורם ולחיץ', (tester) async {
      final hovered = <String>[];
      final overlay = await pump(
        tester,
        'ולא אוכל מנשוא את כל העם הזה כי כבד הוא ממני '
        'ואם ככה את עושה לי הרגני נא הרוג '
        '<a class="book-note-marker" '
        'href="otzaria://book-note?line=3&note=0">*</a> ואל אראה ברעתי',
        width: 320,
        onAnchorHover: (url, _) => hovered.add(url),
      );
      final placement = overlay.debugPlacements().single;
      expect(placement.marker.italic, isTrue);
      expect(placement.paintRect.top, lessThan(placement.anchorRect.top));

      final gesture = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
      );
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);
      await gesture.moveTo(
        overlay.localToGlobal(raisedOnlyPoint(placement)),
      );
      await tester.pump();
      expect(hovered, contains('otzaria://book-note?line=3&note=0'));
    });

    testWidgets('שתי אותיות מפרשים בפסקת RTL — הסדר לא מתהפך', (tester) async {
      final overlay = await pump(
        tester,
        'ראשון <a class="link-anchor link-anchor-0" '
        'href="otzaria://anchor?ref=0_0">(א)</a> '
        'ושני <a class="link-anchor link-anchor-1" '
        'href="otzaria://anchor?ref=0_1">(ב)</a> בשורה',
        onAnchorTap: (_) {},
      );
      final placements = overlay.debugPlacements();
      expect(placements, hasLength(2));
      expect(
        placements[0].anchorRect.center.dx,
        greaterThan(placements[1].anchorRect.center.dx),
        reason: 'אות א חייבת להישאר ימנית מאות ב',
      );
      expect(placements[0].marker.variantIndex, 0);
      expect(placements[1].marker.variantIndex, 1);
    });

    testWidgets('קטע עם סימונים לא-לחיצים בלבד אינו סורק ב-hit-test', (
      tester,
    ) async {
      final overlay = await pump(tester, 'בראשית<sup>א</sup> ברא');
      // לחיצה על אמצע הקטע — לא אמורה לזרוק ולא להפנות לשום מקום.
      await tester.tapAt(overlay.localToGlobal(const Offset(50, 10)));
      await tester.pump();
      expect(overlay.debugPlacements(), hasLength(1));
    });

    testWidgets('קריאה רציפה: אות מפרש מורמת ולחיצה עליה מנתבת', (
      tester,
    ) async {
      final tapped = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: Align(
                alignment: Alignment.topRight,
                child: SizedBox(
                  width: 320,
                  child: ContinuousReadingParagraph(
                    lines: [
                      ContinuousReadingParagraphLine(
                        lineIndex: 0,
                        text: 'ובני ישראל יוצאים ביד רמה וישיגו אותם (א) חונים',
                        htmlText:
                            'ובני ישראל יוצאים ביד רמה וישיגו אותם '
                            '<a class="link-anchor link-anchor-0" '
                            'href="otzaria://anchor?ref=0_0">(א)</a> חונים',
                        style: const TextStyle(fontSize: 20),
                      ),
                    ],
                    baseStyle: const TextStyle(fontSize: 20),
                    onLineTap: (_) {},
                    onTapUrl: (url) async {
                      tapped.add(url);
                      return true;
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final overlay = tester.renderObject<RenderRaisedMarkerOverlay>(
        find.byType(RaisedMarkerOverlay),
      );
      final placement = overlay.debugPlacements().single;
      expect(placement.paintRect.top, lessThan(placement.anchorRect.top));

      final point = Offset(
        placement.paintRect.center.dx,
        placement.paintRect.top + 1,
      );
      if (!placement.anchorRect.contains(point)) {
        await tester.tapAt(overlay.localToGlobal(point));
        await tester.pump();
        expect(tapped, ['otzaria://anchor?ref=0_0']);
      } else {
        // הסימון בשורה הראשונה וההרמה נחסמה — עדיין לחיץ דרך העוגן עצמו.
        await tester.tapAt(
          overlay.localToGlobal(placement.anchorRect.center),
        );
        await tester.pump();
        expect(tapped, ['otzaria://anchor?ref=0_0']);
      }
    });
  });
}
