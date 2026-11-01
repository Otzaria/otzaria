import 'package:flutter/material.dart';

/// רוחב השוליים שהקורא שומר משני צדי הפריטים; סמן הבחירה מצויר בשוליים
/// הימניים, מחוץ לטקסט.
const double kSelectionGutterWidth = 8;

/// מלבן הסמן לצד רכיב ברוחב [width]: בקצה החיצוני של שוליים ברוחב [gutter]
/// מימינו, כך שאינו עולה על האותיות שבתחילת השורה.
Rect selectionBarRect(double width, double gutter, double top, double bottom) =>
    Rect.fromLTRB(width + gutter - _barWidth, top, width + gutter, bottom);

const _barWidth = 3.0;

/// צורת הסמן: קצוות מעוגלים לגמרי, בלי לשנות את המלבן ששומר על הפריסה.
RRect selectionBarShape(Rect rect) =>
    RRect.fromRectAndRadius(rect, const Radius.circular(_barWidth / 2));

/// מאחד מלבני סמן שנוגעים זה בזה אנכית, כדי שבחירה מרובת שורות תצויר כפס אחד
/// עם קצוות מעוגלים רק בקצוות הרצף.
List<Rect> mergeSelectionBars(Iterable<Rect> rects) {
  final sorted = rects.toList()..sort((a, b) => a.top.compareTo(b.top));
  final merged = <Rect>[];
  for (final rect in sorted) {
    if (merged.isNotEmpty && rect.top <= merged.last.bottom + 0.5) {
      merged.last = merged.last.expandToInclude(rect);
    } else {
      merged.add(rect);
    }
  }
  return merged;
}

/// Paints the selected paragraph marker without affecting text layout or taps.
class SelectionGutterPainter extends CustomPainter {
  const SelectionGutterPainter(this.color, {required this.gutter});

  final Color color;

  /// רוחב השוליים הפנויים מימין לרכיב, שבהם מצויר הסמן.
  final double gutter;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    canvas.drawRRect(
      selectionBarShape(selectionBarRect(size.width, gutter, 0, size.height)),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(covariant SelectionGutterPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.gutter != gutter;

  @override
  bool? hitTest(Offset position) => false;
}
