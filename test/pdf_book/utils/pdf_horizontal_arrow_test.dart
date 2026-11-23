import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/pdf_book/utils/pdf_horizontal_arrow.dart';

void main() {
  bool pans(Rect visible, {required bool towardLeft}) =>
      pdfArrowPansHorizontally(
        visibleRect: visible,
        documentWidth: 600,
        towardLeft: towardLeft,
      );

  test('עמוד שנכנס ברוחב: החצים מדפדפים', () {
    const fits = Rect.fromLTWH(-100, 0, 800, 500);
    expect(pans(fits, towardLeft: true), isFalse);
    expect(pans(fits, towardLeft: false), isFalse);
  });

  test('עמוד רחב מהתצוגה: גוללים לכיוון שנותר בו תוכן מוסתר', () {
    const middle = Rect.fromLTWH(200, 0, 200, 500);
    expect(pans(middle, towardLeft: true), isTrue);
    expect(pans(middle, towardLeft: false), isTrue);
  });

  test('בקצה העמוד החץ לכיוון הקצה מדפדף', () {
    const leftEdge = Rect.fromLTWH(0.3, 0, 200, 500);
    expect(pans(leftEdge, towardLeft: true), isFalse);
    expect(pans(leftEdge, towardLeft: false), isTrue);

    const rightEdge = Rect.fromLTWH(399.8, 0, 200, 500);
    expect(pans(rightEdge, towardLeft: false), isFalse);
    expect(pans(rightEdge, towardLeft: true), isTrue);
  });
}
