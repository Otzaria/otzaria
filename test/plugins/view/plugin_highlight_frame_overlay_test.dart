import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/models/plugin_highlight.dart';
import 'package:otzaria/plugins/models/plugin_reader_selection.dart';
import 'package:otzaria/plugins/models/text_source_map.dart';
import 'package:otzaria/plugins/services/plugin_highlight_renderer.dart';
import 'package:otzaria/plugins/view/plugin_highlight_frame_overlay.dart';

const _text =
    'בְּרֵאשִׁ֖ית בָּרָ֣א אֱלֹהִ֑ים אֵ֥ת הַשָּׁמַ֖יִם וְאֵ֥ת הָאָֽרֶץ';

void main() {
  testWidgets('ציור הדגשות סורק את הפסקה פעם אחת לכל ציור', (tester) async {
    final ranges = [
      _range(2, 9, 'text-background'),
      _range(12, 20, 'box'),
    ];
    await _pump(tester, ranges);
    final overlay = _overlay(tester);

    debugPluginHighlightParagraphScans = 0;
    for (var i = 0; i < 3; i++) {
      _paintedRects(overlay);
    }

    expect(debugPluginHighlightParagraphScans, 3);
  });

  testWidgets('הקופסאות המצוירות זהות לחישוב עצמאי לפי גרפמות', (tester) async {
    final ranges = [
      _range(2, 9, 'text-background'),
      _range(12, 20, 'box'),
      _range(30, 5000, 'text-background'),
    ];
    await _pump(tester, ranges);
    final overlay = _overlay(tester);
    final paragraph = _paragraph(overlay);
    final graphemes = _text.characters.toList();

    final expectedFills = <Rect>[];
    final expectedFrames = <Rect>[];
    for (final r in ranges) {
      final end = r.end.clamp(0, graphemes.length);
      final start = graphemes.take(r.start).join().length;
      final stop = graphemes.take(end).join().length;
      final boxes = paragraph.getBoxesForSelection(
        TextSelection(baseOffset: start, extentOffset: stop),
      );
      final frame = r.highlight.style.markerMode == 'box';
      for (final box in boxes) {
        (frame ? expectedFrames : expectedFills).add(
          box.toRect().inflate(frame ? .5 : 1),
        );
      }
    }
    expect(expectedFills, isNotEmpty);
    expect(expectedFrames, isNotEmpty);

    expect(_paintedRects(overlay), [...expectedFills, ...expectedFrames]);
  });
}

List<Rect> _paintedRects(RenderPluginHighlightFrameOverlay overlay) {
  final canvas = TestRecordingCanvas();
  overlay.paint(TestRecordingPaintingContext(canvas), Offset.zero);
  return [
    for (final call in canvas.invocations)
      if (call.invocation.memberName == #drawRRect)
        (call.invocation.positionalArguments[0] as RRect).outerRect,
  ];
}

PluginHighlightRenderedRange _range(int start, int end, String mode) =>
    PluginHighlightRenderedRange(
      start: start,
      end: end,
      highlight: PluginHighlight(
        highlightId: 'h$start',
        ownerPluginId: 'plugin',
        bookId: 'book',
        sectionIndex: 0,
        range: const PluginTextRangeAnchor(
          layer: 'source',
          start: PluginTextOffset(grapheme: 0, codePoint: 0, utf16: 0),
          end: PluginTextOffset(grapheme: 1, codePoint: 1, utf16: 1),
          exactText: 'ב',
          beforeText: _ctx,
          afterText: _ctx,
          occurrenceIndexInSection: 0,
          occurrenceCountInSection: 1,
        ),
        style: PluginHighlightStyle(
          backgroundColor: '#FFE066',
          markerMode: mode,
        ),
        createdAt: DateTime.utc(2026, 7, 21),
        updatedAt: DateTime.utc(2026, 7, 21),
      ),
    );

const _ctx = PluginAnchorContext(
  raw: '',
  normalized: '',
  maxGraphemes: 30,
  actualGraphemes: 0,
  truncatedAtBoundary: true,
);

Future<void> _pump(
  WidgetTester tester,
  List<PluginHighlightRenderedRange> ranges,
) => tester.pumpWidget(
  MaterialApp(
    home: Scaffold(
      body: SizedBox(
        width: 200,
        child: PluginHighlightFrameOverlay(
          ranges: ranges,
          child: const Text(_text),
        ),
      ),
    ),
  ),
);

RenderPluginHighlightFrameOverlay _overlay(WidgetTester tester) =>
    tester.renderObject<RenderPluginHighlightFrameOverlay>(
      find.byType(PluginHighlightFrameOverlay),
    );

RenderParagraph _paragraph(RenderObject root) {
  late RenderParagraph found;
  void visit(RenderObject o) {
    if (o is RenderParagraph) {
      found = o;
      return;
    }
    o.visitChildren(visit);
  }

  visit(root);
  return found;
}
