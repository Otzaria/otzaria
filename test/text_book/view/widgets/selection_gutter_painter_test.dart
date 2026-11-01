import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/text_book/view/widgets/selection_gutter_painter.dart';

void main() {
  test('סמן הבחירה מעוגל לגמרי בקצוותיו ושומר על מידות המלבן', () {
    final rect = selectionBarRect(200, kSelectionGutterWidth, 10, 50);
    final shape = selectionBarShape(rect);

    expect(shape.outerRect, rect);
    expect(shape.tlRadius.x, rect.width / 2);
    expect(shape.brRadius.x, rect.width / 2);
  });

  test('שורות סמוכות מתאחדות לפס אחד, ופער משאיר פסים נפרדים', () {
    Rect bar(double top, double bottom) =>
        selectionBarRect(200, kSelectionGutterWidth, top, bottom);

    final merged = mergeSelectionBars([
      bar(30, 50),
      bar(10, 30),
      bar(50, 70),
      bar(90, 110),
    ]);

    expect(merged, [bar(10, 70), bar(90, 110)]);
  });
}
