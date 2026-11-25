// Use as lib/main.dart in a minimal Flutter Windows release app. Pass an
// absolute output path when launching the executable. Compare "geometry" from
// two runs with the same SDK and fonts, then compare "layoutMicros" separately.
// Pass --large after the output path on the fully patched engine to measure
// mixed-direction and single-run paragraphs near the size reported in #5906.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

void main(List<String> args) {
  final (outputPath, includeLarge) = switch (args) {
    [final path] => (path, false),
    [final path, '--large'] => (path, true),
    _ => throw ArgumentError('Expected an output path and optional --large.'),
  };
  File(outputPath).writeAsStringSync(
    jsonEncode(probeParagraphStyleLookup(includeLarge: includeLarge)),
    flush: true,
  );
  exit(0);
}

Map<String, Object> probeParagraphStyleLookup({bool includeLarge = false}) {
  final geometry = [
    _measure(
      groups: 48,
      letterSpacing: 0.25,
      wordSpacing: 1.5,
      includeGeometry: true,
    ),
    _measure(
      groups: 48,
      letterSpacing: 0.0,
      wordSpacing: 1.5,
      includeGeometry: true,
      direction: ui.TextDirection.ltr,
    ),
    _measure(
      groups: 48,
      letterSpacing: 0.25,
      wordSpacing: 0.0,
      includeGeometry: true,
      maxLines: 1,
    ),
    for (final direction in [ui.TextDirection.ltr, ui.TextDirection.rtl])
      _measureSingleRun(
        groups: 60,
        direction: direction,
        includeGeometry: true,
        measureRelayout: true,
      ),
  ].map((sample) => sample['geometry']).toList();

  return {
    'geometry': geometry,
    'scaling': [
      for (final letterSpacing in [0.0, 0.25])
        for (final groups in [4000, 8000, 16000])
          _measure(groups: groups, letterSpacing: letterSpacing),
    ],
    'singleRunScaling': {
      'ltr': _measureSingleRun(
        groups: 16000,
        direction: ui.TextDirection.ltr,
        measureRelayout: true,
      ),
      'rtl': _measureSingleRun(
        groups: 15200,
        direction: ui.TextDirection.rtl,
        measureRelayout: true,
      ),
    },
    if (includeLarge)
      // 1,985,804 UTF-16 code units, close to the 1,985,795 in the report.
      'large': _measure(groups: 104516, letterSpacing: 0.25),
    if (includeLarge)
      'largeSingleRun': _measureSingleRun(
        groups: 99290,
        direction: ui.TextDirection.rtl,
        measureRelayout: true,
      ),
  };
}

Map<String, Object> _measure({
  required int groups,
  required double letterSpacing,
  double wordSpacing = 0.0,
  bool includeGeometry = false,
  ui.TextDirection direction = ui.TextDirection.rtl,
  int? maxLines,
}) {
  final builder = ui.ParagraphBuilder(
    ui.ParagraphStyle(
      textDirection: direction,
      textAlign: ui.TextAlign.justify,
      fontFamily: 'Arial',
      fontSize: 16,
      maxLines: maxLines,
      ellipsis: maxLines == null ? null : '…',
    ),
  );
  final normal = ui.TextStyle(
    letterSpacing: letterSpacing,
    wordSpacing: wordSpacing,
  );
  final highlighted = ui.TextStyle(
    // Give the geometry cases different spacing on either side of a style
    // boundary. With zero letter spacing, the match can also form ligatures.
    letterSpacing: includeGeometry ? 0.0 : letterSpacing,
    wordSpacing: includeGeometry ? wordSpacing + 2.0 : wordSpacing,
    fontFamily: includeGeometry ? 'Times New Roman' : null,
    fontFamilyFallback: includeGeometry ? const ['Segoe UI Emoji'] : null,
    fontFeatures: includeGeometry
        ? const [ui.FontFeature.enable('liga')]
        : null,
    background: ui.Paint()..color = const ui.Color(0xffffff00),
  );

  var textLength = 0;
  for (var group = 0; group < groups; group++) {
    final start = 'שָׁלוֹם abc ${group % 10} ';
    final match = includeGeometry ? 'office עָוֹלָם \u{1f52c}' : 'עולם';
    final end = group % 7 == 6 ? '\n' : ' ';
    builder
      ..pushStyle(normal)
      ..addText(start)
      ..pop();
    if (includeGeometry && group % 6 == 4) {
      builder.addPlaceholder(14, 20, ui.PlaceholderAlignment.middle);
      textLength++;
    }
    builder
      ..pushStyle(highlighted)
      ..addText(match)
      ..pop()
      ..pushStyle(normal)
      ..addText(end)
      ..pop();
    textLength += start.length + match.length + end.length;
  }

  return _reportLayout(
    builder.build(),
    groups: groups,
    textLength: textLength,
    letterSpacing: letterSpacing,
    includeGeometry: includeGeometry,
  );
}

Map<String, Object> _measureSingleRun({
  required int groups,
  required ui.TextDirection direction,
  bool includeGeometry = false,
  bool measureRelayout = false,
}) {
  // One font, one direction and no hard breaks. The same shaping run continues
  // across the wrapped and justified lines, including after a width change.
  final fragment = direction == ui.TextDirection.rtl
      ? 'אוצריא מילים נוספות '
      : 'alpha beta word fx ';
  final text = List.filled(groups, fragment).join();
  final builder = ui.ParagraphBuilder(
    ui.ParagraphStyle(
      textDirection: direction,
      textAlign: ui.TextAlign.justify,
      fontFamily: 'Arial',
      fontSize: 16,
    ),
  )..addText(text);
  return _reportLayout(
    builder.build(),
    groups: groups,
    textLength: text.length,
    letterSpacing: 0.0,
    includeGeometry: includeGeometry,
    measureRelayout: measureRelayout,
  );
}

Map<String, Object> _reportLayout(
  ui.Paragraph paragraph, {
  required int groups,
  required int textLength,
  required double letterSpacing,
  required bool includeGeometry,
  bool measureRelayout = false,
}) {
  try {
    final stopwatch = Stopwatch()..start();
    paragraph.layout(const ui.ParagraphConstraints(width: 600));
    stopwatch.stop();
    final lines = paragraph.computeLineMetrics();
    final geometry = includeGeometry
        ? _geometry(paragraph, lines, textLength)
        : null;
    final report = <String, Object>{
      'groups': groups,
      'characters': textLength,
      'letterSpacing': letterSpacing,
      'layoutMicros': stopwatch.elapsedMicroseconds,
      'lineCount': lines.length,
      'geometry': ?geometry,
    };
    if (measureRelayout) {
      stopwatch
        ..reset()
        ..start();
      paragraph.layout(const ui.ParagraphConstraints(width: 624));
      stopwatch.stop();
      final reflowedLines = paragraph.computeLineMetrics();
      report['widthRelayoutMicros'] = stopwatch.elapsedMicroseconds;
      report['widthRelayoutLineCount'] = reflowedLines.length;
      geometry?['widthRelayout'] = _geometry(
        paragraph,
        reflowedLines,
        textLength,
      );
    }
    return report;
  } finally {
    paragraph.dispose();
  }
}

Map<String, Object> _geometry(
  ui.Paragraph paragraph,
  List<ui.LineMetrics> lines,
  int textLength,
) => {
  'height': paragraph.height,
  'longestLine': paragraph.longestLine,
  'minIntrinsicWidth': paragraph.minIntrinsicWidth,
  'maxIntrinsicWidth': paragraph.maxIntrinsicWidth,
  'exceededMaxLines': paragraph.didExceedMaxLines,
  'lines': [
    for (final line in lines)
      [
        line.hardBreak,
        line.left,
        line.width,
        line.height,
        line.baseline,
        line.ascent,
        line.descent,
      ],
  ],
  'selectionBoxes': paragraph
      .getBoxesForRange(1, textLength - 1)
      .map(_box)
      .toList(),
  'placeholderBoxes': paragraph.getBoxesForPlaceholders().map(_box).toList(),
};

List<Object> _box(ui.TextBox box) => [
  box.left,
  box.top,
  box.right,
  box.bottom,
  box.direction.name,
];
