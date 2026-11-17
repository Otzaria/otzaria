import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/diagnostics/smart_text_render_stats.dart';
import 'package:otzaria/utils/text/text_manipulation.dart' show HolyNameStyle;
import 'package:otzaria/widgets/smart_text/inline_html_document.dart';
import 'package:otzaria/widgets/smart_text/render_settings.dart';
import 'package:otzaria/widgets/smart_text/smart_text_widget.dart';
import 'package:otzaria/widgets/smart_text/text_renderer_service.dart';

const _anchorLine =
    'בראשית<a class="link-anchor link-anchor-0" '
    'href="otzaria://anchor?id=1">א</a> ברא';
const _blockLine = '<ul><li>א</li></ul>';

Widget _wrap(List<Widget> children) => MaterialApp(
  home: Scaffold(body: Column(children: children)),
);

void main() {
  setUp(() {
    SmartTextRenderStats.reset();
    SmartTextRenderStats.enabled = true;
    TextRendererService.clearRenderCacheForTesting();
  });

  tearDown(() {
    SmartTextRenderStats.enabled = false;
    SmartTextRenderStats.reset();
  });

  test('כבוי: לא נספר דבר', () {
    SmartTextRenderStats.enabled = false;
    SmartTextRenderStats.fastLine(heading: false);
    SmartTextRenderStats.fullLine(columnMode: true);
    SmartTextRenderStats.fullPathHtml(_anchorLine);
    SmartTextRenderStats.processTextHit();
    SmartTextRenderStats.processTextMiss(SmartTextRenderStats.startMicros());
    expect(SmartTextRenderStats.startMicros(), 0);
    expect(SmartTextRenderStats.takeAndReset(), isNull);
  });

  test('סיבת הנפילה נספרת רק בהחטאת מטמון של מסלול הספאנים', () {
    const style = TextStyle(fontSize: 17.25);
    expect(InlineHtmlDocument.parseLine(_blockLine, style), isNull);
    expect(InlineHtmlDocument.parseLine(_blockLine, style), isNull);
    expect(InlineHtmlDocument.parseLine(_anchorLine, style), isNotNull);

    final stats = SmartTextRenderStats.takeAndReset()!;
    expect(stats['fullReasons'], {'block': 1});
    expect(SmartTextRenderStats.takeAndReset(), isNull);
  });

  test('processText: פגיעה והחטאה במטמון', () {
    const settings = RenderSettings(fontSize: 20);
    TextRendererService.processText('ויאמר משה', settings);
    TextRendererService.processText('ויאמר משה', settings);
    TextRendererService.processText('ויאמר אהרן', settings);

    final stats = SmartTextRenderStats.takeAndReset()!;
    expect(stats['processMisses'], 2);
    expect(stats['processHits'], 1);
    expect(stats['processUncachedMs'], isA<double>());
  });

  test('processText: הגדרות חיפוש והחלפה כבויות חולקות תוצאה במטמון', () {
    const text = 'ויאמר יהוה';
    final first = TextRendererService.processText(text, const RenderSettings());
    final second = TextRendererService.processText(
      text,
      const RenderSettings(
        holyNameStyle: HolyNameStyle.hehApostrophe,
        currentSearchIndex: 1,
        searchOptions: {
          'משה': {'fuzzy': true},
        },
        alternativeWords: {
          0: ['אהרן'],
        },
        spacingValues: {'0': '2'},
        isFuzzySearch: true,
        searchDistance: 2,
        isSearchResultLine: true,
        highlightYellowBackground: true,
        partialWordHighlight: true,
        previousLineText: 'בראשית',
        nextLineText: 'וידבר משה',
      ),
    );

    expect(first, text);
    expect(second, text);
    final stats = SmartTextRenderStats.takeAndReset()!;
    expect(stats['processMisses'], 1);
    expect(stats['processHits'], 1);
  });

  test('processText: לכל סגנון החלפה פעיל תוצאה נפרדת במטמון', () {
    const text = 'ויאמר יהוה';
    final first = TextRendererService.processText(
      text,
      const RenderSettings(replaceHolyNames: true),
    );
    final second = TextRendererService.processText(
      text,
      const RenderSettings(
        replaceHolyNames: true,
        holyNameStyle: HolyNameStyle.hehApostrophe,
      ),
    );

    expect(first, 'ויאמר יקוק');
    expect(second, "ויאמר ה'");
    final stats = SmartTextRenderStats.takeAndReset()!;
    expect(stats['processMisses'], 2);
    expect(stats['processHits'], 0);
  });

  testWidgets('שורות מהירות ומלאות נצברות עם בניית fwfh', (tester) async {
    await tester.pumpWidget(
      _wrap(const [
        SmartTextWidget(text: 'ויאמר משה', settings: RenderSettings()),
        SmartTextWidget(
          text: '<h2>פרק א</h2>',
          settings: RenderSettings(),
        ),
        SmartTextWidget(text: _anchorLine, settings: RenderSettings()),
        SmartTextWidget(text: _blockLine, settings: RenderSettings()),
      ]),
    );

    final stats = SmartTextRenderStats.takeAndReset()!;
    expect(stats['fastInline'], 2);
    expect(stats['fastHeading'], 1);
    expect(stats['fullHtml'], 1);
    expect(stats['fwfhBuilds'], 1);
    expect(stats['fullReasons'], {'block': 1});
  });

  group('classifyFullPath', () {
    SmartTextFullPathReason classify(String html) =>
        SmartTextRenderStats.classifyFullPath(html);

    test('תג מבני גובר על עיצוב שאינו נתמך', () {
      expect(classify(_blockLine), SmartTextFullPathReason.block);
      expect(
        classify('<span style="margin: 4px">א</span><ul><li>ב</li></ul>'),
        SmartTextFullPathReason.block,
      );
      expect(classify('<img src="a.png">'), SmartTextFullPathReason.image);
      expect(
        classify('א<sup class="x">1</sup>'),
        SmartTextFullPathReason.supSub,
      );
      expect(classify('<a name="x">א</a>'), SmartTextFullPathReason.anchorId);
      expect(
        classify('<span style="line-height: 2">ב</span>'),
        SmartTextFullPathReason.unsupportedStyle,
      );
      expect(
        classify('<font color="red">ב</font>'),
        SmartTextFullPathReason.otherTag,
      );
      expect(classify('<br>'), SmartTextFullPathReason.structure);
    });
  });
}
