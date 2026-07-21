import 'package:characters/characters.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:otzaria/plugins/models/plugin_highlight.dart';
import 'package:otzaria/plugins/models/plugin_reader_selection.dart';
import 'package:otzaria/plugins/models/text_source_map.dart';
import 'package:otzaria/plugins/services/plugin_highlight_renderer.dart';
import 'package:otzaria/widgets/smart_text/render_settings.dart';
import 'package:otzaria/widgets/smart_text/text_renderer_service.dart';

void main() {
  const renderer = PluginHighlightRenderer();

  test('מפצל Highlight שחוצה תג HTML בלי לשנות את הטקסט', () {
    const raw = 'אב <b>גד</b> הו';
    final processed = TextRendererService.processText(
      raw,
      const RenderSettings(formatParentheses: false),
    );

    final result = renderer.apply(
      bookId: 'book',
      sectionIndex: 0,
      rawText: raw,
      processedHtml: processed,
      highlights: [
        _highlight(id: 'cross', start: 1, end: 5, exactText: 'ב גד'),
      ],
    );
    final fragment = html_parser.parseFragment(result);
    final marks = fragment.querySelectorAll('.otzaria-plugin-highlight');

    expect(marks, hasLength(2));
    expect(marks.map((element) => element.text).join(), 'ב גד');
    expect(TextRendererService.stripHtml(result), 'אב גד הו');
  });

  test('priority גבוה מנצח באזור חפיפה', () {
    const raw = 'אבגדה';
    final result = renderer.apply(
      bookId: 'book',
      sectionIndex: 0,
      rawText: raw,
      processedHtml: raw,
      highlights: [
        _highlight(
          id: 'low',
          start: 0,
          end: 5,
          exactText: 'אבגדה',
          color: '#FF0000',
        ),
        _highlight(
          id: 'high',
          start: 2,
          end: 4,
          exactText: 'גד',
          color: '#0000FF',
          priority: 10,
        ),
      ],
    );
    final fragment = html_parser.parseFragment(result);
    final high = fragment.querySelector('[data-highlight-id="high"]');
    final low = fragment.querySelectorAll('[data-highlight-id="low"]');

    expect(high, isNotNull);
    expect(high!.text, 'גד');
    expect(low, hasLength(2));
    expect(
      high.attributes['style'],
      isNot(contains('background-color')),
      reason: 'background paint belongs to PluginHighlightFrameOverlay',
    );
  });

  test('טווח מקור מנוקד נשאר על האותיות לאחר הסרת ניקוד', () {
    const raw = 'אָב אמר';
    const settings = RenderSettings(
      removeNikud: true,
      removeTeamim: false,
      formatParentheses: false,
    );
    final processed = TextRendererService.processText(raw, settings);
    final result = renderer.apply(
      bookId: 'book',
      sectionIndex: 0,
      rawText: raw,
      processedHtml: processed,
      highlights: [
        _highlight(id: 'nikud', start: 0, end: 2, exactText: 'אָב'),
      ],
    );
    final fragment = html_parser.parseFragment(result);

    expect(
      fragment.querySelector('[data-highlight-id="nikud"]')?.text,
      'אב',
    );
  });
  test('marker modes and reveal styling are rendered', () {
    const raw = 'abc';
    final result = renderer.apply(
      bookId: 'book',
      sectionIndex: 0,
      rawText: raw,
      processedHtml: raw,
      highlights: [
        _highlight(
          id: 'box',
          start: 0,
          end: 3,
          exactText: raw,
          markerMode: 'box',
          borderRadius: 6,
        ),
      ],
    );
    final style = html_parser
        .parseFragment(result)
        .querySelector('[data-highlight-id="box"]')!
        .attributes['style']!;

    expect(style, isNot(contains('text-decoration')));
    expect(style, isNot(contains('text-shadow')));
    expect(style, isNot(contains('background-color')));
    expect(style, isNot(contains('border')));
    expect(style, isNot(contains('margin')));
    expect(style, isNot(contains('box-shadow')));

    final revealedResult = renderer.apply(
      bookId: 'book',
      sectionIndex: 0,
      rawText: raw,
      processedHtml: raw,
      highlights: [
        _highlight(
          id: 'box',
          start: 0,
          end: 3,
          exactText: raw,
          markerMode: 'box',
        ),
      ],
      revealedHighlightId: 'box',
    );
    final revealedStyle = html_parser
        .parseFragment(revealedResult)
        .querySelector('[data-highlight-id="box"]')!
        .attributes['style']!;
    expect(revealedStyle, contains('text-decoration-thickness: 3px'));

    final ranges = renderer.resolveRenderedRanges(
      bookId: 'book',
      sectionIndex: 0,
      rawText: raw,
      processedHtml: raw,
      highlights: [
        _highlight(
          id: 'box',
          start: 0,
          end: 3,
          exactText: raw,
          markerMode: 'box',
          borderRadius: 6,
        ),
      ],
    );
    expect(ranges.single.start, 0);
    expect(ranges.single.end, 3);
    expect(ranges.single.highlight.style.markerMode, 'box');
  });

  test('all marker modes preserve exact text order', () {
    const raw = 'אמר רבי יהודה: זה טקסט, עם מילים וסימנים.';
    for (final mode in const [
      'text-background',
      'underline',
      'box',
      'line-marker',
    ]) {
      final result = renderer.apply(
        bookId: 'book',
        sectionIndex: 0,
        rawText: raw,
        processedHtml: raw,
        highlights: [
          _highlight(
            id: mode,
            start: 4,
            end: 18,
            exactText: raw.characters.toList().sublist(4, 18).join(),
            markerMode: mode,
          ),
        ],
      );
      expect(TextRendererService.stripHtml(result), raw, reason: mode);
    }
  });

  test('multiple RTL highlights never emit layout-changing inline CSS', () {
    const raw = 'אשר קדשנו במצותיו וצונו על נטילת ידים';
    final result = renderer.apply(
      bookId: 'book',
      sectionIndex: 0,
      rawText: raw,
      processedHtml: raw,
      highlights: [
        _highlight(id: 'first', start: 4, end: 9, exactText: 'קדשנו'),
        _highlight(id: 'second', start: 18, end: 23, exactText: 'וצונו'),
        _highlight(
          id: 'third',
          start: 27,
          end: 32,
          exactText: 'נטילת',
          markerMode: 'box',
          borderRadius: 6,
        ),
      ],
    );

    expect(TextRendererService.stripHtml(result), raw);
    for (final element
        in html_parser
            .parseFragment(result)
            .querySelectorAll('.otzaria-plugin-highlight')) {
      final style = element.attributes['style'] ?? '';
      expect(style, isNot(contains('border:')));
      expect(style, isNot(contains('border-radius')));
      expect(style, isNot(contains('margin')));
      expect(style, isNot(contains('padding')));
      expect(style, isNot(contains('box-shadow')));
      expect(style, isNot(contains('outline')));
    }
  });

  test('line marker compatibility mode colors only the text', () {
    const raw = 'שורה';
    final result = renderer.apply(
      bookId: 'book',
      sectionIndex: 0,
      rawText: raw,
      processedHtml: raw,
      highlights: [
        _highlight(
          id: 'line',
          start: 0,
          end: 4,
          exactText: raw,
          markerMode: 'line-marker',
        ),
      ],
    );
    final style = html_parser
        .parseFragment(result)
        .querySelector('[data-highlight-id="line"]')!
        .attributes['style']!;

    expect(style, contains('color: rgba'));
    expect(style, isNot(contains('background-color')));
    expect(style, isNot(contains('text-decoration')));
    expect(style, isNot(contains('text-shadow')));
  });

  test('underline mode uses the thicker underline style', () {
    const raw = 'קו';
    final result = renderer.apply(
      bookId: 'book',
      sectionIndex: 0,
      rawText: raw,
      processedHtml: raw,
      highlights: [
        _highlight(
          id: 'underline',
          start: 0,
          end: 2,
          exactText: raw,
          markerMode: 'underline',
        ),
      ],
    );
    final style = html_parser
        .parseFragment(result)
        .querySelector('[data-highlight-id="underline"]')!
        .attributes['style']!;

    expect(style, contains('text-decoration: underline'));
    expect(style, contains('text-decoration-thickness: 2px'));
  });

  test('renderWithRanges מחזיר HTML וטווחי ציור מאותה מפה', () {
    const raw = 'אבג';
    final result = renderer.renderWithRanges(
      bookId: 'book',
      sectionIndex: 0,
      rawText: raw,
      processedHtml: raw,
      highlights: [
        _highlight(id: 'frame', start: 1, end: 3, exactText: 'בג'),
      ],
    );

    expect(TextRendererService.stripHtml(result.html), raw);
    expect(result.ranges, hasLength(1));
    expect(result.ranges.single.start, 1);
    expect(result.ranges.single.end, 3);
  });
}

PluginHighlight _highlight({
  required String id,
  required int start,
  required int end,
  required String exactText,
  String color = '#FFE066',
  int priority = 0,
  String markerMode = 'text-background',
  double borderRadius = 0,
}) {
  const context = PluginAnchorContext(
    raw: '',
    normalized: '',
    maxGraphemes: 30,
    actualGraphemes: 0,
    truncatedAtBoundary: true,
  );
  return PluginHighlight(
    highlightId: id,
    ownerPluginId: 'plugin',
    bookId: 'book',
    sectionIndex: 0,
    range: PluginTextRangeAnchor(
      layer: 'source',
      start: PluginTextOffset(
        grapheme: start,
        codePoint: start,
        utf16: start,
      ),
      end: PluginTextOffset(grapheme: end, codePoint: end, utf16: end),
      exactText: exactText,
      beforeText: context,
      afterText: context,
      occurrenceIndexInSection: 0,
      occurrenceCountInSection: 1,
    ),
    style: PluginHighlightStyle(
      backgroundColor: color,
      priority: priority,
      markerMode: markerMode,
      borderRadius: borderRadius,
    ),
    createdAt: DateTime.utc(2026, 7, 14),
    updatedAt: DateTime.utc(2026, 7, 14),
  );
}
