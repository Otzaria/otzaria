/// A `pw.Widget` that draws shaped text.
///
/// It fits inside an existing document, so a print layout keeps its pages,
/// headers and page breaks and only swaps how the text itself is drawn.
library;

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'pdf_shaped_font.dart';
import 'shaped_text_layout.dart';

class ShapedText extends pw.Widget with pw.SpanningWidget {
  ShapedText(
    this.text, {
    required this.fonts,
    required this.fontSize,
    this.color = PdfColors.black,
    this.align = ShapedTextAlign.start,
    this.rtl = true,
    this.script = 'hebr',
    this.language,
    this.features,
    this.heightFactor,
  }) : assert(fonts.isNotEmpty, 'at least one font is required');

  final String text;

  /// Fonts to try per word, in order. A word goes to the first font that has a
  /// glyph for all of its characters.
  final List<PdfShapedFont> fonts;

  final double fontSize;
  final PdfColor color;
  final ShapedTextAlign align;
  final bool rtl;
  final String script;
  final String? language;
  final String? features;

  /// Line height as a multiple of the font size. Clamped up to the fonts' own
  /// line height so te'amim cannot reach into the next line.
  final double? heightFactor;

  ShapedTextBlock? _block;
  double? _blockWidth;
  final _ShapedTextContext _context = _ShapedTextContext();
  var _firstLine = 0;
  var _lastLine = 0;

  ShapedTextLayout get _layout => ShapedTextLayout(
    fonts: [for (final font in fonts) font.shaper],
    fontSize: fontSize,
    align: align,
    rtl: rtl,
    script: script,
    language: language,
    features: features,
    heightFactor: heightFactor,
  );

  /// A spanning widget is laid out once per page it reaches; without this the
  /// whole text would be broken into lines again on every one of them.
  ShapedTextBlock _blockFor(double maxWidth) {
    final cached = _block;
    if (cached != null && _blockWidth == maxWidth) {
      return cached;
    }
    _blockWidth = maxWidth;
    return _block = _layout.layout(text, maxWidth: maxWidth);
  }

  @override
  void layout(
    pw.Context context,
    pw.BoxConstraints constraints, {
    bool parentUsesSize = false,
  }) {
    final maxWidth = constraints.hasBoundedWidth
        ? constraints.maxWidth
        : constraints.constrainWidth();
    final block = _blockFor(maxWidth);
    final firstLine = _context.startLine.clamp(0, block.lines.length);
    var lastLine = block.lines.length;
    if (constraints.maxHeight.isFinite) {
      // Zero lines when none fits: MultiPage then moves the rest to the next
      // page, where forcing one would draw it into space the page lacks.
      final fittingLines = (constraints.maxHeight / block.lineHeight).floor();
      lastLine = firstLine + fittingLines;
      if (lastLine > block.lines.length) lastLine = block.lines.length;
    }
    _firstLine = firstLine;
    _lastLine = lastLine;
    _context.endLine = lastLine;
    box = PdfRect(
      0,
      0,
      maxWidth,
      (lastLine - firstLine) * block.lineHeight,
    );
  }

  @override
  bool get canSpan => true;

  @override
  bool get hasMoreWidgets =>
      _block != null && _context.endLine < _block!.lines.length;

  @override
  void restoreContext(covariant pw.WidgetContext context) {
    final shapedContext = context as _ShapedTextContext;
    _context
      ..startLine = shapedContext.endLine
      ..endLine = shapedContext.endLine;
  }

  @override
  pw.WidgetContext saveContext() => _context;

  @override
  void paint(pw.Context context) {
    super.paint(context);

    final block = _block;
    if (block == null || block.isEmpty) {
      return;
    }

    final canvas = context.canvas..setFillColor(color);
    final top = box!.bottom + box!.height;

    for (var index = _firstLine; index < _lastLine; index++) {
      final visibleIndex = index - _firstLine;
      final baseline =
          top - visibleIndex * block.lineHeight - block.baselineOffset;
      final segments = block.lines[index].segments;
      // One text object per stretch of the line that uses the same font.
      var start = 0;
      while (start < segments.length) {
        final fontIndex = segments[start].fontIndex;
        var end = start + 1;
        while (end < segments.length && segments[end].fontIndex == fontIndex) {
          end++;
        }
        fonts[fontIndex].drawShapedRuns(
          canvas,
          [
            for (final segment in segments.sublist(start, end))
              PlacedShapedRun(segment.run, box!.left + segment.x),
          ],
          y: baseline,
          fontSize: fontSize,
        );
        start = end;
      }
    }
  }
}

class _ShapedTextContext extends pw.WidgetContext {
  var startLine = 0;
  var endLine = 0;

  @override
  _ShapedTextContext clone() => _ShapedTextContext()
    ..startLine = startLine
    ..endLine = endLine;

  @override
  void apply(covariant _ShapedTextContext other) {
    startLine = other.startLine;
    endLine = other.endLine;
  }
}
