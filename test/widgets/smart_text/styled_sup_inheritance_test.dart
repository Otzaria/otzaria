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

        final styles = <TextStyle>[];
        void visit(RenderObject object) {
          if (object is RenderParagraph) {
            styles.addAll(_markerStyles(object.text, const TextStyle()));
          }
          object.visitChildren(visit);
        }

        visit(tester.renderObject(find.byType(Scaffold)));
        expect(find.byType(RaisedMarkerOverlay), findsNothing);
        expect(
          styles.single.fontSize,
          closeTo(source.contains('2em') ? 100 / 3 : 50 / 3, 0.001),
        );
        if (source.startsWith('<b>')) {
          expect(styles.single.fontWeight, FontWeight.bold);
        }
        expect(
          styles.single.color,
          source.contains('currentcolor')
              ? const Color(0xffff0000)
              : const Color(0xff808080),
        );
      });
    }
  }

  test(
    'only root styled sup is lifted; siblings and offsets are preserved',
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
        expect(markers, hasLength(2));
        expect(markers[0].text, contains('1'));
        expect(markers[1].text, contains('3'));
        expect(result, contains('<sup style="color:gray">'));
      }
    },
  );

  test('an unclosed ancestor keeps styled sup in the HTML renderer', () {
    final result = TextRendererService.processText(
      '<b>טקסט<sup style="color:gray">1</sup>',
      const RenderSettings(),
    );
    expect(RaisedMarkers.extract(result), isEmpty);
    expect(result, contains('<sup style="color:gray">'));
  });
}
