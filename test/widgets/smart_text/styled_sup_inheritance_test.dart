import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/text_book/view/widgets/continuous_reading_paragraph.dart';
import 'package:otzaria/widgets/smart_text/raised_markers.dart';
import 'package:otzaria/widgets/smart_text/render_settings.dart';
import 'package:otzaria/widgets/smart_text/smart_text_widget.dart';
import 'package:otzaria/widgets/smart_text/text_renderer_service.dart';

List<TextStyle> _markerStyles(InlineSpan span, TextStyle inherited) {
  if (span is! TextSpan) return const [];
  final style = inherited.merge(span.style);
  return [
    if ((span.text ?? '').contains('123')) style,
    for (final child in span.children ?? const <InlineSpan>[])
      ..._markerStyles(child, style),
  ];
}

void main() {
  setUpAll(() async {
    final loader = FontLoader('FrankRuhlCLM');
    for (final weight in ['Medium', 'Bold']) {
      loader.addFont(rootBundle.load('fonts/FrankRuehlCLM-$weight.ttf'));
    }
    await loader.load();
  });

  for (final mode in ['smart', 'html', 'continuous']) {
    for (final source in [
      '<span style="font-size: 2em">כותרת<sup style="color: #808080;">123</sup>סוף</span>',
      '<b>כותרת<sup style="color: #808080;">123</sup>סוף</b>',
      '<span style="color: red">מילה<sup style="color: currentcolor;">123</sup>סוף</span>',
      'מילה<sup style="color: #808080;">(123)</sup>סוף',
      '<span style="color: red">מילה<sup style="color: inherit;">123</sup>סוף</span>',
      if (mode != 'continuous') ...[
        '<span style="font-family: NotoRashiHebrew, serif">מילה<sup style="color: gray">123</sup>סוף</span>',
        '<u>מילה<sup style="color: gray">123</sup>סוף</u>',
      ],
    ]) {
      testWidgets('styled sup retains inherited typography: $mode $source', (
        tester,
      ) async {
        SmartTextWidget.debugForceHtmlWidget = mode == 'html';
        addTearDown(() => SmartTextWidget.debugForceHtmlWidget = false);
        const settings = RenderSettings(
          fontSize: 20,
          fontFamily: 'FrankRuhlCLM',
        );
        const style = TextStyle(fontSize: 20, fontFamily: 'FrankRuhlCLM');
        await tester.pumpWidget(
          MaterialApp(
            home: Directionality(
              textDirection: TextDirection.rtl,
              child: Scaffold(
                body: mode == 'continuous'
                    ? ContinuousReadingParagraph(
                        lines: [
                          ContinuousReadingParagraphLine(
                            lineIndex: 0,
                            htmlText: TextRendererService.processText(
                              source,
                              settings,
                            ),
                            style: style,
                          ),
                        ],
                        baseStyle: style,
                      )
                    : SmartTextWidget(text: source, settings: settings),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // sup עם צבע משלו מצויר בשכבה המורמת ויורש מאבות ה-HTML; currentcolor
        // נשאר ב-HTML כי הציור אינו יורש את צבע ההורה.
        final lifted =
            !source.contains('currentcolor') &&
            !source.contains('color: inherit');
        final styles = <TextStyle>[];
        if (lifted) {
          final overlay = tester.renderObject<RenderRaisedMarkerOverlay>(
            find.byType(RaisedMarkerOverlay),
          );
          styles.addAll(
            _markerStyles(
              overlay.debugPaintedSpan(overlay.debugPlacements().single),
              const TextStyle(),
            ),
          );
        } else {
          void visit(RenderObject object) {
            if (object is RenderParagraph) {
              styles.addAll(_markerStyles(object.text, const TextStyle()));
            }
            object.visitChildren(visit);
          }

          visit(tester.renderObject(find.byType(Scaffold)));
          expect(find.byType(RaisedMarkerOverlay), findsNothing);
        }
        expect(
          styles.single.fontSize,
          closeTo(
            source.contains('2em')
                ? 100 / 3
                : source.contains('(123)')
                ? 125 / 9
                : 50 / 3,
            0.001,
          ),
        );
        if (source.startsWith('<b>')) {
          expect(styles.single.fontWeight, FontWeight.bold);
        }
        expect(
          styles.single.color,
          lifted ? const Color(0xff808080) : const Color(0xffff0000),
        );
        if (source.contains('NotoRashiHebrew')) {
          expect(styles.single.fontFamily, 'NotoRashiHebrew');
          expect(styles.single.fontFamilyFallback, contains('serif'));
        }
        if (source.startsWith('<u>')) {
          expect(styles.single.decoration, TextDecoration.underline);
        }
      });
    }
  }

  for (final html in [false, true]) {
    testWidgets('identical sup text keeps each inherited style: html=$html', (
      tester,
    ) async {
      SmartTextWidget.debugForceHtmlWidget = html;
      addTearDown(() => SmartTextWidget.debugForceHtmlWidget = false);
      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: SmartTextWidget(
                text:
                    '<u><span style="font-family: NotoRashiHebrew">'
                    'ראשון<sup style="color: gray">123</sup></span></u> '
                    'שני<sup style="color: gray">123</sup>',
                settings: const RenderSettings(
                  fontSize: 20,
                  fontFamily: 'FrankRuhlCLM',
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
      final styles = [
        for (final placement in overlay.debugPlacements())
          ..._markerStyles(
            overlay.debugPaintedSpan(placement),
            const TextStyle(),
          ),
      ];
      expect(styles, hasLength(2));
      expect(styles[0].fontFamily, 'NotoRashiHebrew');
      expect(styles[0].decoration, TextDecoration.underline);
      expect(styles[1].fontFamily, 'FrankRuhlCLM');
      expect(styles[1].decoration, isNot(TextDecoration.underline));
    });
  }

  test(
    'nested styled sup is lifted too, in order (issue #3239)',
    () {
      const html =
          '<!-- ראש -->🙂<b>אח</b><br><img src="x"/>'
          '<SUP style="color: gray">1</SUP>'
          '<span><sup style="color:gray">2</sup></span>'
          '<sup style="color:gray">3</sup>';
      for (final search in ['', '1']) {
        final result = TextRendererService.processText(
          html,
          RenderSettings(searchText: search),
        );
        final markers = RaisedMarkers.extract(result);
        expect(markers.map((m) => m.text.replaceAll(RegExp(r'\D'), '')), [
          '1',
          '2',
          '3',
        ]);
        expect(result, isNot(contains('<sup')));
      }
    },
  );

  test('styled sup under an unclosed ancestor is lifted', () {
    final result = TextRendererService.processText(
      '<b>טקסט<sup style="color:gray">1</sup>',
      const RenderSettings(),
    );
    expect(RaisedMarkers.extract(result), hasLength(1));
    expect(result, isNot(contains('<sup')));
  });

  test('nested styled sup without its own color stays in HTML', () {
    for (final style in [
      'font-weight: bold',
      'color: currentcolor',
      'color: inherit',
      'color: unset',
      'color: revert',
    ]) {
      final result = TextRendererService.processText(
        '<sup style="$style">1</sup>'
        '<span style="color: red">מילה<sup style="$style">2</sup></span>',
        const RenderSettings(),
      );
      final markers = RaisedMarkers.extract(result);
      expect(markers.single.text, contains('1'));
      expect(result, contains('<sup style="$style">'));
    }
  });
}
