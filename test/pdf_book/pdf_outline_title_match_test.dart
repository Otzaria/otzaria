import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/pdf_book/view/pdf_outlines_screen.dart';
import 'package:pdfrx/pdfrx.dart';

bool pdfOutlineTitleMatchesQuery(String title, String query) {
  final node = PdfOutlineNode(title: title, dest: null, children: const []);
  return filterPdfOutline(flattenPdfOutlineForSearch([node]), query).isNotEmpty;
}

void main() {
  group('filterPdfOutline', () {
    test('כותרת ברמה העליונה נמצאת גם בלי היררכיה', () {
      // רגרסיה: בעבר סוננו כל הכותרות ברמה 0 והרשימה התרוקנה בחיפוש.
      expect(pdfOutlineTitleMatchesQuery('זבחים דף קו', 'זבחים'), isTrue);
    });

    test('התאמה מתעלמת מגרשיים בכותרת', () {
      expect(pdfOutlineTitleMatchesQuery('ב"ב דף נה', 'בב'), isTrue);
      expect(pdfOutlineTitleMatchesQuery('אור שמח על הרמב"ם', 'הרמבם'), isTrue);
    });

    test('התאמה מתעלמת מניקוד בכותרת', () {
      expect(pdfOutlineTitleMatchesQuery('בְּרֵאשִׁית', 'בראשית'), isTrue);
    });

    test('שאילתה ריקה תואמת הכול', () {
      expect(pdfOutlineTitleMatchesQuery('כל כותרת', ''), isTrue);
    });

    test('כותרת שאינה תואמת מוחזרת כלא־תואמת', () {
      expect(pdfOutlineTitleMatchesQuery('זבחים דף קו', 'חולין'), isFalse);
    });
  });
}
