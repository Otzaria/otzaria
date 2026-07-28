import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/pdf_book/utils/pdf_links_window.dart';

void main() {
  group('PdfLinksWindowPolicy.nextWindow', () {
    test('בלי חלון טעון — מחזיר חלון סביב הטווח, לא יורד מתחת לשורה 1', () {
      final window = PdfLinksWindowPolicy.nextWindow(
        rangeStart: 100,
        rangeEnd: 150,
      );
      expect(window, isNotNull);
      expect(window!.startLine, 1);
      expect(window.endLine, 150 + PdfLinksWindowPolicy.marginLines);
    });

    test('טווח עמוק בספר — החלון סימטרי סביב הטווח', () {
      final window = PdfLinksWindowPolicy.nextWindow(
        rangeStart: 10000,
        rangeEnd: 10100,
      );
      expect(window!.startLine, 10000 - PdfLinksWindowPolicy.marginLines);
      expect(window.endLine, 10100 + PdfLinksWindowPolicy.marginLines);
    });

    test('טווח שמכוסה עם מרווח בטוח — אין טעינה חוזרת', () {
      final window = PdfLinksWindowPolicy.nextWindow(
        rangeStart: 10000,
        rangeEnd: 10100,
        loadedStart: 9000,
        loadedEnd: 11000,
      );
      expect(window, isNull);
    });

    test('התקרבות לקצה החלון (בתוך ה-slack) — נטען חלון חדש', () {
      final loadedEnd = 11000;
      final window = PdfLinksWindowPolicy.nextWindow(
        rangeStart: 10800,
        rangeEnd: loadedEnd - PdfLinksWindowPolicy.slackLines + 1,
        loadedStart: 9000,
        loadedEnd: loadedEnd,
      );
      expect(window, isNotNull);
    });

    test('קפיצה מחוץ לחלון — נטען חלון חדש סביב היעד', () {
      final window = PdfLinksWindowPolicy.nextWindow(
        rangeStart: 50000,
        rangeEnd: 50050,
        loadedStart: 9000,
        loadedEnd: 11000,
      );
      expect(window!.startLine, 50000 - PdfLinksWindowPolicy.marginLines);
      expect(window.endLine, 50050 + PdfLinksWindowPolicy.marginLines);
    });

    test('תחילת ספר — needed שלילי לא מפיל את בדיקת הכיסוי', () {
      final window = PdfLinksWindowPolicy.nextWindow(
        rangeStart: 5,
        rangeEnd: 60,
        loadedStart: 1,
        loadedEnd: 2000,
      );
      expect(window, isNull);
    });

    test('מצב ספר: החלון החדש מכסה את מלוא טווח השורות של שני העמודים', () {
      const firstPageStart = 2000;
      const secondPageEnd = 2290;
      final window = PdfLinksWindowPolicy.nextWindow(
        rangeStart: firstPageStart,
        rangeEnd: secondPageEnd,
      )!;

      expect(
        window.startLine,
        firstPageStart - PdfLinksWindowPolicy.marginLines,
      );
      expect(window.endLine, secondPageEnd + PdfLinksWindowPolicy.marginLines);
      expect(window.startLine, lessThanOrEqualTo(firstPageStart));
      expect(window.endLine, greaterThanOrEqualTo(secondPageEnd));
    });

    test('מצב ספר: טווח רחב משולי החלון אינו נחתך', () {
      final window = PdfLinksWindowPolicy.nextWindow(
        rangeStart: 1000,
        rangeEnd: 5000,
      )!;

      expect(window.startLine, 1000 - PdfLinksWindowPolicy.marginLines);
      expect(window.endLine, 5000 + PdfLinksWindowPolicy.marginLines);
    });

    test('חלון שמכסה את העמוד הראשון אך לא את השני מחייב טעינה חדשה', () {
      final window = PdfLinksWindowPolicy.nextWindow(
        rangeStart: 2000,
        rangeEnd: 2290,
        loadedStart: 1800,
        loadedEnd: 2150,
      );

      expect(window, isNotNull);
      expect(window!.endLine, greaterThan(2290));
    });

    test('שני עמודים המכוסים עם slack אינם גורמים לטעינה חוזרת', () {
      final window = PdfLinksWindowPolicy.nextWindow(
        rangeStart: 2000,
        rangeEnd: 2290,
        loadedStart: 1900,
        loadedEnd: 2390,
      );

      expect(window, isNull);
    });

    test('מעבר לספירייד סמוך המכוסה מראש אינו טוען שוב', () {
      final firstSpread = PdfLinksWindowPolicy.nextWindow(
        rangeStart: 2000,
        rangeEnd: 2290,
      )!;
      final nextSpread = PdfLinksWindowPolicy.nextWindow(
        rangeStart: 2291,
        rangeEnd: 2330,
        loadedStart: firstSpread.startLine,
        loadedEnd: firstSpread.endLine,
      );

      expect(nextSpread, isNull);
    });
  });
}
