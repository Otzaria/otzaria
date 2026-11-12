import 'package:bidi/bidi.dart' as bidi;
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/src/pdf/font/bidi_utils.dart' as pdf_bidi;

void main() {
  test('mixed printing lines retain UTF-16 word ownership after emoji', () {
    const logical = 'אב 😀 Latin';
    final paragraph = bidi.BidiString.fromLogical(logical).paragraphs.single;
    expect(String.fromCharCodes(paragraph.bidiText), 'Latin 😀 בא');
    expect(paragraph.indices, [6, 7, 8, 9, 10, 5, 3, 2, 1, 0]);
  });

  test('Arabic ligatures retain the source owner of intervening marks', () {
    const logical = 'ل\u064eاX';
    final paragraph = bidi.BidiString.fromLogical(logical).paragraphs.single;
    final mark = paragraph.bidiText.indexOf(0x064e);
    expect(mark, isNonNegative);
    expect(paragraph.indices[mark], 1);
    expect(paragraph.indices[paragraph.bidiText.indexOf(0x58)], 3);
  });

  test('PDF titles keep each Hebrew mark over its original base glyph', () {
    expect(pdf_bidi.logicalToVisual('אְבֱג'), 'גֱבְא');
    expect(pdf_bidi.logicalToVisual('אְֱב'), 'בְֱא');
    expect(pdf_bidi.logicalToVisual('אָבֶג'), 'גֶבאָ');
  });
}
