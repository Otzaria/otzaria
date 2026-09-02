import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/pdf_book/models/pdf_search_page_range.dart';

void main() {
  group('PdfSearchPageRange.parse', () {
    test('שני שדות ריקים — אין טווח', () {
      expect(
        PdfSearchPageRange.parse(from: '', to: ' ', totalPages: 10),
        isNull,
      );
    });

    test('שדה ריק מתפרש כקצה הספר', () {
      final fromOnly = PdfSearchPageRange.parse(
        from: '4',
        to: '',
        totalPages: 10,
      );
      expect(fromOnly!.firstPage, 4);
      expect(fromOnly.lastPage, 10);

      final toOnly = PdfSearchPageRange.parse(
        from: '',
        to: '3',
        totalPages: 10,
      );
      expect(toOnly!.firstPage, 1);
      expect(toOnly.lastPage, 3);
    });

    test('סדר הפוך מתוקן והערכים נחתכים לגבולות הספר', () {
      final range = PdfSearchPageRange.parse(
        from: '50',
        to: '4',
        totalPages: 10,
      );
      expect(range!.firstPage, 4);
      expect(range.lastPage, 10, reason: '50 נחתך ל-10 ואז הוחלף עם 4');
      expect(range.contains(10), isTrue);
    });

    test('טווח שמכסה את כל הספר שקול ל"ללא טווח"', () {
      expect(
        PdfSearchPageRange.parse(from: '1', to: '10', totalPages: 10),
        isNull,
      );
    });

    test('contains ותווית', () {
      const range = PdfSearchPageRange(3, 5);
      expect(range.contains(2), isFalse);
      expect(range.contains(3), isTrue);
      expect(range.contains(5), isTrue);
      expect(range.contains(6), isFalse);
      expect(range.label, 'עמודים 3–5');
      expect(const PdfSearchPageRange(7, 7).label, 'עמוד 7');
    });
  });
}
