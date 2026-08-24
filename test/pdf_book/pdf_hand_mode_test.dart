// בדיקות למצב יד בצפיין ה-PDF (issue #916): גרירת עכבר גוללת במקום לסמן.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';

void main() {
  group('מצב יד — reload guard', () {
    // המתג מחליף רק את enabled בזמן ריצה. אם שדרוג pdfrx יוסיף את enabled
    // להשוואת PdfTextSelectionParams, כל הפעלה של המתג תגרור reload מלא
    // של הצפיין (doChangesRequireReload) וקפיצה במיקום הגלילה.
    test('החלפת enabled אינה משנה את שוויון PdfTextSelectionParams', () {
      const selectionOn = PdfTextSelectionParams(enabled: true);
      const selectionOff = PdfTextSelectionParams(enabled: false);
      expect(selectionOn == selectionOff, isTrue);
    });

    test('החלפת enabled אינה מחייבת reload של PdfViewerParams', () {
      const before = PdfViewerParams(
        textSelectionParams: PdfTextSelectionParams(enabled: true),
      );
      const after = PdfViewerParams(
        textSelectionParams: PdfTextSelectionParams(enabled: false),
      );
      expect(after.doChangesRequireReload(before), isFalse);
    });
  });

  group('מצב יד — חיווט במסך ה-PDF', () {
    final sourceFile = File('lib/pdf_book/view/pdf_book_screen.dart');
    late final String source;

    setUpAll(() async {
      expect(sourceFile.existsSync(), isTrue);
      source = await sourceFile.readAsString();
    });

    test('textSelectionParams כפוף למצב היד', () {
      expect(
        source.contains(
          'textSelectionParams: PdfTextSelectionParams(enabled: !_isHandMode)',
        ),
        isTrue,
        reason:
            'סימון הטקסט חייב להיות מנוטרל כשמצב היד פעיל — '
            'זה מה שמפנה את גרירת העכבר לגלילה של pdfrx.',
      );
    });

    test('כפתור המתג קיים ואינו מוצג במובייל', () {
      final buttonBlock = RegExp(
        r'if \(!Platform\.isAndroid && !Platform\.isIOS\)\s*'
        r'ActionButtonData\.simple\([^;]*_isHandMode',
        dotAll: true,
      );
      expect(
        buttonBlock.hasMatch(source),
        isTrue,
        reason:
            'כפתור מצב היד רלוונטי לעכבר בלבד — במגע הגרירה כבר גוללת, '
            'ולכן הוא מוצג רק בדסקטופ.',
      );
    });
  });
}
