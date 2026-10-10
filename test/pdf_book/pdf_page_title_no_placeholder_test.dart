// PdfBookScreen דורש pdfrx נייטיב ותלויות רבות, ולכן הבדיקה סורקת את המקור.
// כותרת ביניים "עמוד N" במעבר עמוד מהבהבת לפני הכותרת מה-outline (#1864).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('מעבר עמוד ב-PDF לא מציג "עמוד N" לפני הכותרת האמיתית', () {
    final source = File(
      'lib/pdf_book/view/pdf_book_screen.dart',
    ).readAsStringSync();
    final start = source.indexOf('void _onPdfViewerControllerUpdate()');
    final end = source.indexOf('Future<void> _resolvePageMetadata(');
    expect(start, isNonNegative);
    expect(end, greaterThan(start));
    final handler = source.substring(start, end);

    expect(
      RegExp(r"'עמודים? \$").hasMatch(handler),
      isFalse,
      reason:
          'הכותרת מחושבת סינכרונית מה-outline שבזיכרון — אין צורך בכותרת ביניים',
    );
    expect(handler, contains('currentTitle.value = _titlesForPage('));
  });
}
