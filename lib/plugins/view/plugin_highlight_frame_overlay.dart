import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:otzaria/plugins/services/plugin_highlight_renderer.dart';
import 'package:otzaria/widgets/smart_text/selection_fill_text.dart';

class PluginHighlightFrameOverlay extends SingleChildRenderObjectWidget {
  final List<PluginHighlightRenderedRange> ranges;

  /// הטקסט שבו [ranges] נמדדים, כשהוא שונה מהטקסט המוצג (רווחים שה-HTML
  /// מכווץ, `<br>` שמוצג כמעבר שורה). null — הטווחים כבר במרחב המוצג.
  final String? rangeText;

  const PluginHighlightFrameOverlay({
    super.key,
    required this.ranges,
    this.rangeText,
    required super.child,
  });

  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderPluginHighlightFrameOverlay(ranges, rangeText);

  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderPluginHighlightFrameOverlay renderObject,
  ) {
    renderObject
      ..ranges = ranges
      ..rangeText = rangeText;
  }
}

class RenderPluginHighlightFrameOverlay extends RenderProxyBox {
  RenderPluginHighlightFrameOverlay(this._ranges, [this._rangeText]);

  List<PluginHighlightRenderedRange> _ranges;
  String? _rangeText;

  set ranges(List<PluginHighlightRenderedRange> value) {
    if (identical(value, _ranges)) return;
    _ranges = value;
    markNeedsPaint();
  }

  set rangeText(String? value) {
    if (value == _rangeText) return;
    _rangeText = value;
    markNeedsPaint();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (child == null) return;
    if (_ranges.isEmpty) {
      super.paint(context, offset);
      return;
    }

    // המיפוי מחושב פעם אחת לשני המעברים: המילוי מתחת לטקסט והמסגרת מעליו.
    final ranges = _displayedRanges();
    final fills = [
      for (final range in ranges)
        if (range.highlight.style.markerMode == 'text-background') range,
    ];
    final frames = [
      for (final range in ranges)
        if (range.highlight.style.markerMode == 'box') range,
    ];
    if (fills.isNotEmpty) {
      _paintRanges(context, offset, fills, paintFrames: false);
    }
    super.paint(context, offset);
    if (frames.isNotEmpty) {
      _paintRanges(context, offset, frames, paintFrames: true);
    }
  }

  void _paintRanges(
    PaintingContext context,
    Offset offset,
    List<PluginHighlightRenderedRange> ranges, {
    required bool paintFrames,
  }) {
    var graphemeCursor = 0;
    void visit(RenderObject object) {
      if (object is RenderParagraph) {
        final text = object.text.toPlainText();
        final graphemes = text.characters.toList(growable: false);
        final paragraphStart = graphemeCursor;
        final paragraphEnd = paragraphStart + graphemes.length;
        graphemeCursor = paragraphEnd;
        if (!ranges.any(
          (range) => range.start < paragraphEnd && range.end > paragraphStart,
        )) {
          return;
        }
        final paragraphOffset = object.localToGlobal(
          Offset.zero,
          ancestor: this,
        );
        // מיקום UTF-16 של כל גבול grapheme בפסקה.
        final utf16 = List<int>.filled(graphemes.length + 1, 0);
        for (var i = 0; i < graphemes.length; i++) {
          utf16[i + 1] = utf16[i] + graphemes[i].length;
        }

        for (final range in ranges) {
          if (range.start >= paragraphEnd || range.end <= paragraphStart) {
            continue;
          }
          final localStart = (range.start - paragraphStart)
              .clamp(0, graphemes.length)
              .toInt();
          final localEnd = (range.end - paragraphStart)
              .clamp(0, graphemes.length)
              .toInt();
          if (localStart >= localEnd) continue;
          final startUtf16 = utf16[localStart];
          final endUtf16 = utf16[localEnd];
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
            object,
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
        return;
      }
      object.visitChildren(visit);
    }

    visit(child!);
  }

  /// הטווחים כפי שהם נצבעים, ב-graphemes של הטקסט המוצג.
  @visibleForTesting
  List<PluginHighlightRenderedRange> get displayedRanges => _displayedRanges();

  /// ממפה את הטווחים מ-[_rangeText] לטקסט המוצג לפי התווים שאינם רווח, שהם
  /// זהים בשניהם.
  List<PluginHighlightRenderedRange> _displayedRanges() {
    final source = _rangeText;
    if (source == null) return _ranges;
    final displayed = <String>[];
    void collect(RenderObject object) {
      if (object is RenderParagraph) {
        displayed.addAll(object.text.toPlainText().characters);
        return;
      }
      object.visitChildren(collect);
    }

    collect(child!);
    final sourceSolid = <int>[];
    final sourceChars = source.characters.toList(growable: false);
    for (var i = 0; i < sourceChars.length; i++) {
      if (sourceChars[i].trim().isNotEmpty) sourceSolid.add(i);
    }
    final displayedSolid = <int>[
      for (var i = 0; i < displayed.length; i++)
        if (displayed[i].trim().isNotEmpty) i,
    ];
    int solidBefore(int boundary) {
      var lo = 0;
      var hi = sourceSolid.length;
      while (lo < hi) {
        final mid = (lo + hi) >> 1;
        if (sourceSolid[mid] < boundary) {
          lo = mid + 1;
        } else {
          hi = mid;
        }
      }
      return lo;
    }

    return [
      for (final range in _ranges)
        if (solidBefore(range.end) > solidBefore(range.start) &&
            solidBefore(range.end) <= displayedSolid.length)
          PluginHighlightRenderedRange(
            start: displayedSolid[solidBefore(range.start)],
            end: displayedSolid[solidBefore(range.end) - 1] + 1,
            highlight: range.highlight,
          ),
    ];
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
