import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/text_book/utils/text_book_export_utils.dart';
import 'package:otzaria/text_display/text_display_exports.dart';

void main() {
  group('text book export utils', () {
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

    test('ייצוא לטקסט: שורת כותרת בלי רווח במקום התגים (issue #3758)', () {
      final text = createTextBookTextExport(
        TextBookExportRequest(
          rawContent:
              '<h1>בית פנחס (יבמות, מכות)</h1>\n'
              'רבי פנחס הלוי הורוויץ\n'
              '<h2>יבמות</h2>\n'
              '<h3>פרק ראשון חמש עשרה נשים</h3>\n'
              '<h4>דף ט.</h4>\n'
              '<b>בתוס\'</b> בד"ה מה<br>תדע דבפרק בתרא',
          profile: const TextDisplayProfile(),
        ),
      );
      expect(text.split('\n'), [
        'בית פנחס (יבמות, מכות)',
        'רבי פנחס הלוי הורוויץ',
        'יבמות',
        'פרק ראשון חמש עשרה נשים',
        'דף ט.',
        // תג שבירה באמצע השורה עדיין מפריד בין המילים (issue #949).
        'בתוס\' בד"ה מה תדע דבפרק בתרא',
      ]);
    });
  });
}
