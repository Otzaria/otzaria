import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/marker/models/marker_highlight.dart';
import 'package:otzaria/marker/models/marker_palette.dart';
import 'package:otzaria/marker/services/marker_paint.dart';
import 'package:otzaria/plugins/services/plugin_highlight_renderer.dart';
import 'package:otzaria/theme/marker_colors.dart';

import 'marker_test_helpers.dart';

const _line = 'בראשית ברא אלהים את השמים ואת הארץ';

List<(String, String)> _pieces(
  List<MarkerHighlight> marks, {
  int section = 0,
}) => [
  for (final piece in markerSectionPaint(
    highlights: marks,
    sectionIndex: section,
    palette: MarkerPalette.defaults(),
    brightness: Brightness.light,
  ))
    (piece.highlightId, piece.range.exactText),
];

void main() {
  test('a newer mark inside an older one is drawn on top of it', () {
    final older = highlightFor(
      'old',
      [segmentFor(0, _line, 'ברא אלהים את')],
      createdAt: DateTime.utc(2026, 1, 1),
    );
    final newer = highlightFor(
      'new',
      [segmentFor(0, _line, 'אלהים')],
      colorId: 'green',
      createdAt: DateTime.utc(2026, 1, 2),
    );
    expect(_pieces([newer, older]), [
      ('old', 'ברא '),
      ('new', 'אלהים'),
      ('old', ' את'),
    ]);
  });

  test(
    'an older mark inside a newer one is hidden until the newer is gone',
    () {
      final inner = highlightFor(
        'inner',
        [segmentFor(0, _line, 'אלהים')],
        createdAt: DateTime.utc(2026, 1, 1),
      );
      final outer = highlightFor(
        'outer',
        [segmentFor(0, _line, 'ברא אלהים את')],
        createdAt: DateTime.utc(2026, 1, 2),
      );
      expect(_pieces([inner, outer]), [('outer', 'ברא אלהים את')]);
      expect(_pieces([inner]), [('inner', 'אלהים')]);
    },
  );

  test('partial overlap keeps both visible parts', () {
    final a = highlightFor(
      'a',
      [segmentFor(0, _line, 'ברא אלהים')],
      createdAt: DateTime.utc(2026, 1, 1),
    );
    final b = highlightFor(
      'b',
      [segmentFor(0, _line, 'אלהים את')],
      createdAt: DateTime.utc(2026, 1, 2),
    );
    expect(_pieces([a, b]), [('a', 'ברא '), ('b', 'אלהים את')]);
  });

  test('only active segments of the requested section are drawn', () {
    final mark = highlightFor('m', [
      segmentFor(0, _line, 'בראשית'),
      segmentFor(1, _line, 'הארץ').copyWith(status: MarkerAnchorStatus.stale),
    ]);
    expect(_pieces([mark]), [('m', 'בראשית')]);
    expect(_pieces([mark], section: 1), isEmpty);
  });

  test('pieces carry the palette style and render through the renderer', () {
    final mark = highlightFor('m', [segmentFor(0, _line, 'השמים')]);
    final pieces = markerSectionPaint(
      highlights: [mark],
      sectionIndex: 0,
      palette: MarkerPalette.defaults(),
      brightness: Brightness.dark,
    );
    final piece = pieces.single;
    expect(piece.ownerPluginId, kMarkerHighlightOwner);
    expect(piece.style.backgroundColor, '#F1E784');
    expect(
      piece.style.opacity,
      MarkerColors.fillOpacity(MarkerColors.defaultOpacity, Brightness.dark),
    );
    final ranges = const PluginHighlightRenderer().resolveRenderedRanges(
      bookId: 'בראשית',
      sectionIndex: 0,
      rawText: _line,
      processedHtml: _line,
      highlights: pieces,
    );
    expect(ranges.single.start, _line.indexOf('השמים'));
  });

  test('a colour removed from the palette falls back to the stored colour', () {
    final mark = highlightFor('m', [
      segmentFor(0, _line, 'השמים'),
    ], colorId: 'gone');
    final piece = markerSectionPaint(
      highlights: [mark],
      sectionIndex: 0,
      palette: MarkerPalette.defaults(),
      brightness: Brightness.light,
    ).single;
    expect(piece.style.backgroundColor, mark.colorHex);
  });
}
