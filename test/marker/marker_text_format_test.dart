import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/marker/services/marker_text_format.dart';
import 'package:otzaria/marker/view/widgets/marker_marked_text.dart';
import 'package:otzaria/widgets/smart_text/render_settings.dart';
import 'package:otzaria/widgets/smart_text/text_renderer_service.dart';

import 'marker_test_helpers.dart';

String? formatted(String raw, String phrase, [RenderSettings? settings]) =>
    markerSegmentHtml(
      bookId: 'ספר',
      sectionIndex: 0,
      rawText: raw,
      processedHtml: TextRendererService.processText(
        raw,
        settings ?? const RenderSettings(formatParentheses: false),
      ),
      range: anchorFor(TextRendererService.stripHtml(raw), phrase),
    );

void main() {
  test('keeps bold, italic and headings of the marked words only', () {
    expect(
      formatted('<b>אמר רבי</b> יוחנן <i>משום</i> רבי', 'רבי יוחנן משום'),
      '<b>רבי</b> יוחנן <i>משום</i>',
    );
    expect(
      formatted('<h2>פרק ראשון</h2>', 'פרק ראשון'),
      '<b><big>פרק ראשון</big></b>',
    );
  });

  test('drops every other tag and escapes the text', () {
    expect(
      formatted(
        '<span style="color:red">א &lt; ב</span> <a href="x">ג</a>',
        'א < ב ג',
      ),
      'א &lt; ב ג',
    );
  });

  test('the text is as it was shown, without nikud when it was hidden', () {
    expect(
      formatted(
        '<b>בְּרֵאשִׁית</b> בָּרָא',
        'בְּרֵאשִׁית בָּרָא',
        const RenderSettings(removeNikud: true, formatParentheses: false),
      ),
      '<b>בראשית</b> ברא',
    );
  });

  test('a long mark keeps only its beginning', () {
    final raw = List.filled(200, 'מילה').join(' ');
    expect(
      markerSegmentHtml(
        bookId: 'ספר',
        sectionIndex: 0,
        rawText: raw,
        processedHtml: raw,
        range: anchorFor(raw, raw),
        maxChars: 20,
      )!.length,
      lessThanOrEqualTo(20),
    );
  });

  test('a mark is shown formatted only when it has formatting', () {
    expect(markerFormattedText(['<b>א</b>', 'ב']), '<b>א</b> ב');
    expect(markerFormattedText(['א', 'ב']), isNull);
    expect(markerFormattedText(['<b>א</b>', null]), isNull);
  });

  test('the spans carry the formatting', () {
    const base = TextStyle(fontSize: 20);
    final spans = markerTextSpans(
      '<b>א</b> <big>ב</big> <i>ג</i>',
      base,
    ).cast<TextSpan>();
    expect(spans.map((s) => s.text).join(), 'א ב ג');
    expect(spans.first.style!.fontWeight, FontWeight.bold);
    expect(spans.elementAt(2).style!.fontSize, closeTo(23, 0.01));
    expect(spans.last.style!.fontStyle, FontStyle.italic);
    final cut = markerTextSpans(
      '<b>אבגד</b>הוז',
      base,
      maxChars: 2,
    ).cast<TextSpan>();
    expect(cut.map((s) => s.text).join(), 'אב…');
  });
}
