import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/pdf_book/utils/pdf_horizontal_arrow.dart';

void main() {
  double travel(Rect visible, {required bool towardLeft}) =>
      pdfHorizontalArrowTravel(
        visibleRect: visible,
        pageRect: const Rect.fromLTWH(100, 0, 600, 500),
        towardLeft: towardLeft,
      );

  test('עמוד שנכנס ברוחב: החצים מדפדפים', () {
    const fits = Rect.fromLTWH(50, 0, 700, 500);
    expect(travel(fits, towardLeft: true), 0);
    expect(travel(fits, towardLeft: false), 0);
  });

  test('הגלילה מוגבלת למרחק שנותר עד קצה העמוד', () {
    const middle = Rect.fromLTWH(250, 0, 200, 500);
    expect(travel(middle, towardLeft: true), 150);
    expect(travel(middle, towardLeft: false), 250);
  });

  test('בקצה העמוד החץ לכיוון הקצה מדפדף', () {
    const leftEdge = Rect.fromLTWH(100.3, 0, 200, 500);
    expect(travel(leftEdge, towardLeft: true), 0);
    expect(travel(leftEdge, towardLeft: false), greaterThan(0));

    const rightEdge = Rect.fromLTWH(499.8, 0, 200, 500);
    expect(travel(rightEdge, towardLeft: false), 0);
    expect(travel(rightEdge, towardLeft: true), greaterThan(0));
  });
}
