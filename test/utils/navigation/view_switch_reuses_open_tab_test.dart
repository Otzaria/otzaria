import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// מעבר בין תצוגת טקסט ל-PDF של אותו ספר חייב לנווט לטאב הפתוח במקום לפתוח
/// כפילות (#5590) — כל הקריאות האלה חייבות להעביר את הדגל.
String _callBlock(String source, String anchor) {
  final start = source.indexOf(anchor);
  expect(start, isNonNegative, reason: 'חסרה הקריאה: $anchor');
  final end = source.indexOf(');', start);
  return source.substring(start, end);
}

void main() {
  final textScreen = File(
    'lib/text_book/view/text_book_screen.dart',
  ).readAsStringSync().replaceAll('\r\n', '\n');
  final pdfScreen = File(
    'lib/pdf_book/view/pdf_book_screen.dart',
  ).readAsStringSync().replaceAll('\r\n', '\n');

  const flag = 'navigateToPositionIfReused: true';

  test('טקסט→PDF בכפתור ובקיצור מנווטים לטאב קיים', () {
    expect(
      _callBlock(textScreen, '_pdfBook!,\n      index'),
      contains(flag),
    );
    expect(_callBlock(textScreen, 'book,\n    index'), contains(flag));
  });

  test('טקסט→ספר מקביל (טור/שולחן ערוך) מנווט לטאב קיים', () {
    expect(
      _callBlock(textScreen, 'target.book,\n      target.index'),
      contains(flag),
    );
  });

  test('PDF→טקסט ויעד קישור בבבלי מנווטים לטאב קיים', () {
    expect(
      _callBlock(pdfScreen, 'textBook,\n      index'),
      contains(flag),
    );
    expect(
      _callBlock(pdfScreen, 'pdfTarget.book,\n        pdfTarget.page'),
      contains(flag),
    );
    expect(
      _callBlock(pdfScreen, 'textBook,\n      textIndex'),
      contains(flag),
    );
  });
}
