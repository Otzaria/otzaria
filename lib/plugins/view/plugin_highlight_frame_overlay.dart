import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:otzaria/plugins/services/plugin_highlight_renderer.dart';
import 'package:otzaria/widgets/smart_text/selection_fill_text.dart';

@visibleForTesting
int debugPluginHighlightParagraphScans = 0;

class PluginHighlightFrameOverlay extends SingleChildRenderObjectWidget {
  final List<PluginHighlightRenderedRange> ranges;

  const PluginHighlightFrameOverlay({
    super.key,
    required this.ranges,
    required super.child,
  });

  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderPluginHighlightFrameOverlay(ranges);

  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderPluginHighlightFrameOverlay renderObject,
  ) {
    renderObject.ranges = ranges;
  }
}

class RenderPluginHighlightFrameOverlay extends RenderProxyBox {
  RenderPluginHighlightFrameOverlay(this._ranges);

  List<PluginHighlightRenderedRange> _ranges;

  set ranges(List<PluginHighlightRenderedRange> value) {
    if (identical(value, _ranges)) return;
    _ranges = value;
    markNeedsPaint();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (child == null) return;
    if (_ranges.isEmpty) {
      super.paint(context, offset);
      return;
    }

    final paragraphs = _collectParagraphs();
    _paintRanges(context, offset, paragraphs, paintFrames: false);
    super.paint(context, offset);
    _paintRanges(context, offset, paragraphs, paintFrames: true);
  }

  List<_ParagraphGraphemes> _collectParagraphs() {
    final result = <_ParagraphGraphemes>[];
    var graphemeCursor = 0;
    void visit(RenderObject object) {
      if (object is RenderParagraph) {
        debugPluginHighlightParagraphScans++;
        final text = object.text.toPlainText();
        // utf16Offsets[i] = היסט ה-UTF-16 של תחילת הגרפמה ה-i.
        final utf16Offsets = <int>[0];
        for (final grapheme in text.characters) {
          utf16Offsets.add(utf16Offsets.last + grapheme.length);
        }
        final graphemeCount = utf16Offsets.length - 1;
        result.add(
          _ParagraphGraphemes(
            object,
            graphemeCursor,
            utf16Offsets,
            object.localToGlobal(Offset.zero, ancestor: this),
          ),
        );
        graphemeCursor += graphemeCount;
        return;
      }
      object.visitChildren(visit);
    }

    visit(child!);
    return result;
  }

  void _paintRanges(
    PaintingContext context,
    Offset offset,
    List<_ParagraphGraphemes> paragraphs, {
    required bool paintFrames,
  }) {
    for (final p in paragraphs) {
      final graphemeCount = p.utf16Offsets.length - 1;
      final paragraphStart = p.start;
      final paragraphEnd = paragraphStart + graphemeCount;

      for (final range in _ranges) {
        final mode = range.highlight.style.markerMode;
        if ((paintFrames ? mode != 'box' : mode != 'text-background') ||
            range.start >= paragraphEnd ||
            range.end <= paragraphStart) {
          continue;
        }
        final localStart = (range.start - paragraphStart)
            .clamp(0, graphemeCount)
            .toInt();
        final localEnd = (range.end - paragraphStart)
            .clamp(0, graphemeCount)
            .toInt();
        if (localStart >= localEnd) continue;
        final style = range.highlight.style;
        final paint = Paint()
          ..style = paintFrames ? PaintingStyle.stroke : PaintingStyle.fill
          ..strokeWidth = 1.5
          ..color = _parseColor(
            style.backgroundColor,
            opacity: paintFrames ? 1 : style.opacity,
          );
        final radius = Radius.circular(
          style.borderRadius.clamp(0, 16).toDouble(),
        );
        for (final box in glyphBoxesForSelection(
          p.paragraph,
          TextSelection(
            baseOffset: p.utf16Offsets[localStart],
            extentOffset: p.utf16Offsets[localEnd],
          ),
        )) {
          var rect = box.toRect().shift(offset + p.offset);
          rect = rect.inflate(paintFrames ? .5 : 1);
          context.canvas.drawRRect(
            RRect.fromRectAndRadius(rect, radius),
            paint,
          );
        }
      }
    }
  }
}

class _ParagraphGraphemes {
  const _ParagraphGraphemes(
    this.paragraph,
    this.start,
    this.utf16Offsets,
    this.offset,
  );

  final RenderParagraph paragraph;
  final int start;
  final List<int> utf16Offsets;
  final Offset offset;
}

Color _parseColor(String hex, {double opacity = 1}) {
  final value = hex.replaceFirst('#', '');
  final rgb = int.parse(value.substring(0, 6), radix: 16);
  final embeddedAlpha = value.length == 8
      ? int.parse(value.substring(6, 8), radix: 16)
      : 0xFF;
  final alpha = (embeddedAlpha * opacity.clamp(0, 1)).round();
  return Color((alpha << 24) | rgb);
}
