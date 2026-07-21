import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:otzaria/plugins/services/plugin_highlight_renderer.dart';

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

    _paintRanges(context, offset, paintFrames: false);
    super.paint(context, offset);
    _paintRanges(context, offset, paintFrames: true);
  }

  void _paintRanges(
    PaintingContext context,
    Offset offset, {
    required bool paintFrames,
  }) {
    var graphemeCursor = 0;
    void visit(RenderObject object) {
      if (object is RenderParagraph) {
        final text = object.text.toPlainText();
        final graphemes = text.characters.toList(growable: false);
        final paragraphStart = graphemeCursor;
        final paragraphEnd = paragraphStart + graphemes.length;
        final paragraphOffset = object.localToGlobal(
          Offset.zero,
          ancestor: this,
        );

        for (final range in _ranges) {
          final mode = range.highlight.style.markerMode;
          if ((paintFrames ? mode != 'box' : mode != 'text-background') ||
              range.start >= paragraphEnd ||
              range.end <= paragraphStart) {
            continue;
          }
          final localStart = (range.start - paragraphStart)
              .clamp(0, graphemes.length)
              .toInt();
          final localEnd = (range.end - paragraphStart)
              .clamp(0, graphemes.length)
              .toInt();
          if (localStart >= localEnd) continue;
          final startUtf16 = graphemes.take(localStart).join().length;
          final endUtf16 = graphemes.take(localEnd).join().length;
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
          for (final box in object.getBoxesForSelection(
            TextSelection(baseOffset: startUtf16, extentOffset: endUtf16),
          )) {
            var rect = box.toRect().shift(offset + paragraphOffset);
            rect = rect.inflate(paintFrames ? .5 : 1);
            context.canvas.drawRRect(
              RRect.fromRectAndRadius(rect, radius),
              paint,
            );
          }
        }
        graphemeCursor = paragraphEnd;
        return;
      }
      object.visitChildren(visit);
    }

    visit(child!);
  }
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
