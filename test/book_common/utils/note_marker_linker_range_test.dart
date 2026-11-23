import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:otzaria/book_common/utils/link_anchor_markers.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/text_book/models/book_notes.dart';
import 'package:otzaria/text_book/utils/inline_notes_utils.dart';
import 'package:otzaria/text_book/utils/numbered_note_markers.dart';
import 'package:otzaria/text_book/view/widgets/continuous_reading_paragraph.dart';
import 'package:otzaria/widgets/smart_text/raised_markers.dart';
import 'package:otzaria/widgets/smart_text/render_settings.dart';
import 'package:otzaria/widgets/smart_text/text_renderer_service.dart';

// issue #5030: ציטוט לינקר שעובר מטקסט השורה לגוף הערה כולל בשורה המלאה גם את
// סמן ההערה. בשורה המוצגת הסמן הופיע פעמיים — בכחול כקישור, ומורם כהערה.
void main() {
  const settings = RenderSettings(fontSize: 20, fontFamily: 'FrankRuhlCLM');
  const base = TextStyle(fontSize: 20);
  const linkColor = Color(0xFF0000FF);

  // השורה השמורה: "אבג דה" + סמן "21" + " וזח". גוף ההערה ב-charPos 9, אחרי הסמן.
  const stored = 'אבג דה <sup class="footnote-marker">21</sup> וזח';
  final bookNotes =
      (BookNotesBuilder()..add(19, 0, '21', 'דברים יז, ה.', charPos: 9))
          .build();

  Link linker(int start, int end) => Link(
    heRef: 'דברים יז, ה',
    index1: 20,
    path2: 'דברים',
    index2: 1,
    connectionType: 'LINKER',
    anchorStart: start,
    anchorEnd: end,
  );

  // מסלול השורה בקורא: סמני ההערות לחיצים, ואחריהם עוגני הקישורים.
  String readerLine(Link link) => injectLinkAnchorMarkers(
    rawLine: addInlineNotePreviewLinks(
      stored,
      lineIndex: 19,
      dbNotes: bookNotes,
    ),
    anchorLinks: [link],
    styleIndexByCommentator: const {},
    lineIndex: 19,
    notes: bookNotes.notesAt(19),
  );

  // כמה פעמים "21" נראה: גליף שאינו שקוף בשורה, ועוד כל ציור מורם.
  int visibleMarkerCount(String html) {
    final processed = TextRendererService.processText(html, settings);
    var inLine = 0;
    void walk(InlineSpan span) {
      if (span is! TextSpan) return;
      if ((span.text ?? '').contains('21') && (span.style?.color?.a ?? 1) > 0) {
        inLine++;
      }
      span.children?.forEach(walk);
    }

    buildInlineHtmlSpans(
      processed,
      base,
      onTapUrl: (_) async => true,
      linkStyle: const TextStyle(color: linkColor),
    ).forEach(walk);
    final raised = RaisedMarkers.extract(
      processed,
    ).where((marker) => marker.text.contains('21')).length;
    return inLine + raised;
  }

  test('ציטוט שנגמר בגוף ההערה אינו עוטף את סמן ההערה', () {
    // השורה המלאה: "אבג דה 21" + גוף + " וזח"; הציטוט "דה 21דבר".
    final html = readerLine(linker(4, 14));
    expect(visibleMarkerCount(html), 1);
    expect(
      html,
      contains(
        '<a class="book-note-marker" '
        'href="otzaria://book-note?line=19&note=0">21</a>',
      ),
    );
    expect(html, contains('link-anchor-range'));
  });

  test('ציטוט שמתחיל בסמן ההערה אינו עוטף אותו', () {
    final html = readerLine(linker(7, 14));
    expect(visibleMarkerCount(html), 1);
  });

  test('ציטוט שכולו בגוף ההערה אינו נוגע בשורה', () {
    final html = readerLine(linker(9, 20));
    expect(html, isNot(contains('link-anchor-range')));
    expect(visibleMarkerCount(html), 1);
  });

  test('ציטוטים חופפים שומרים על אותו יעד משני צדי הסמן', () {
    final html = injectLinkAnchorMarkers(
      rawLine: 'אב<sup class="footnote-marker">2</sup>גד',
      anchorLinks: [linker(1, 5), linker(0, 4)],
      styleIndexByCommentator: const {},
      lineIndex: 19,
      rangesOnly: true,
    );
    final anchors = html_parser
        .parseFragment(html)
        .querySelectorAll('a.link-anchor-range');
    expect(anchors.map((anchor) => anchor.text), ['אב', 'ג']);
    expect(
      anchors.map((anchor) => anchor.attributes['href']),
      List.filled(2, 'otzaria://anchor?ref=19_1&range=1'),
    );
  });

  test('ציטוט של מספר שמזוהה כסמן פוטנציאלי נשאר לחיץ', () {
    final html = injectLinkAnchorMarkers(
      rawLine: addNumberedNoteMarkerLinks('א (1) ב (99) ג', lineIndex: 19),
      anchorLinks: [linker(8, 12)],
      styleIndexByCommentator: const {},
      lineIndex: 19,
    );
    final anchors = html_parser
        .parseFragment(html)
        .querySelectorAll('a.link-anchor-range');
    expect(anchors.single.text, '(99)');
  });

  test('ציטוט שחוצה שתי הערות שומר קישור בשורה ובגופי ההערות', () {
    const line =
        'אב<sup class="footnote-marker">1</sup>'
        'גד<sup class="footnote-marker">2</sup>הו';
    final notes =
        (BookNotesBuilder()
              ..add(19, 0, '1', 'בב', charPos: 3)
              ..add(19, 1, '2', 'גג', charPos: 6))
            .build();
    String render(String rawLine, {int? note}) => injectLinkAnchorMarkers(
      rawLine: rawLine,
      anchorLinks: [linker(0, 12)],
      styleIndexByCommentator: const {},
      lineIndex: 19,
      notes: notes.notesAt(19),
      note: note,
    );
    final rendered = html_parser.parseFragment(
      render(
        addInlineNotePreviewLinks(line, lineIndex: 19, dbNotes: notes),
      ),
    );
    expect(rendered.querySelectorAll('.book-note-marker').map((a) => a.text), [
      '1',
      '2',
    ]);
    expect(rendered.querySelectorAll('.link-anchor-range').map((a) => a.text), [
      'אב',
      'גד',
      'הו',
    ]);
    for (final (index, body) in ['בב', 'גג'].indexed) {
      final anchor = html_parser
          .parseFragment(render(body, note: index))
          .querySelector('.link-anchor-range')!;
      expect(anchor.text, body);
      expect(anchor.attributes['href'], 'otzaria://anchor?ref=19_0&range=1');
    }
  });
}
