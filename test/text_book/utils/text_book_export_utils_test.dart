import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/text_book/utils/text_book_export_utils.dart';
import 'package:otzaria/text_display/text_display_exports.dart';

void main() {
  group('text book export utils', () {
    test('normalizeTextBookExportPath משאיר סיומת תואמת ללא שינוי', () {
      expect(
        normalizeTextBookExportPath(
          r'C:\exports\book.docx',
          defaultExtension: 'docx',
        ),
        r'C:\exports\book.docx',
      );
    });

    test('normalizeTextBookExportPath מחליף סיומת קיימת בסיומת שנבחרה', () {
      expect(
        normalizeTextBookExportPath(
          r'C:\exports\book.txt',
          defaultExtension: 'docx',
        ),
        r'C:\exports\book.docx',
      );
    });

    test('normalizeTextBookExportPath מוסיף סיומת כשאין סיומת קיימת', () {
      expect(
        normalizeTextBookExportPath(
          r'C:\exports\book',
          defaultExtension: 'txt',
        ),
        r'C:\exports\book.txt',
      );
    });

    test('normalizeTextBookExportPath מתעלם מנקודה בשם התיקייה', () {
      expect(
        normalizeTextBookExportPath(
          r'C:\exports.v2\book',
          defaultExtension: 'docx',
        ),
        r'C:\exports.v2\book.docx',
      );
    });

    test('sanitizeTextBookExportFileName מחליף תווים אסורים בשם קובץ', () {
      expect(
        sanitizeTextBookExportFileName('ספר: בדיקה/א'),
        'ספר_ בדיקה_א',
      );
    });

    test('applyTextBookExportProfile מחיל פרופיל ייצוא ומנקה HTML', () {
      const profile = TextDisplayProfile(
        nikud: MarkVisibility.hide,
        punctuation: MarkVisibility.hide,
        holyName: HolyNameDisplay.hehApostrophe,
      );
      expect(
        applyTextBookExportProfile(
          '<b>בְּרֵאשִׁית,</b> יהוה',
          profile: profile,
          stripHtml: true,
        ),
        'בראשית ה\'',
      );
    });

    test('applyTextBookExportProfile משאיר HTML כש-stripHtml כבוי', () {
      expect(
        applyTextBookExportProfile(
          '<b>בְּרֵאשִׁית</b>',
          profile: const TextDisplayProfile(nikud: MarkVisibility.hide),
          stripHtml: false,
        ),
        '<b>בראשית</b>',
      );
    });
  });
}
