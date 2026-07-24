import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/pdf_book/view/pdf_commentary_panel.dart';

void main() {
  group('pdfLinkInVisibleScope', () {
    test('קישור בטווח הראשי נכלל', () {
      expect(pdfLinkInVisibleScope(5, 3, 8, null), isTrue);
      expect(pdfLinkInVisibleScope(3, 3, 8, null), isTrue);
      expect(pdfLinkInVisibleScope(8, 3, 8, null), isTrue);
    });

    test('קישור מחוץ לטווח הראשי וללא extras לא נכלל', () {
      expect(pdfLinkInVisibleScope(2, 3, 8, null), isFalse);
      expect(pdfLinkInVisibleScope(9, 3, 8, null), isFalse);
      expect(pdfLinkInVisibleScope(20, 3, 8, const {}), isFalse);
    });

    test(
      'ריבוי-בחירה: שורה לא-רצופה מחוץ לטווח נכללת דרך extraLineIndices',
      () {
        expect(pdfLinkInVisibleScope(20, 3, 8, const {20, 25}), isTrue);
        expect(pdfLinkInVisibleScope(25, 3, 8, const {20, 25}), isTrue);
      },
    );

    test('שורה שאינה בטווח ואינה ב-extras לא נכללת', () {
      expect(pdfLinkInVisibleScope(15, 3, 8, const {20, 25}), isFalse);
    });

    test('extras אינו מצמצם את הטווח הראשי', () {
      // שורה בטווח הראשי נכללת גם כשיש extras שאינם כוללים אותה.
      expect(pdfLinkInVisibleScope(5, 3, 8, const {20}), isTrue);
    });
  });
}
