import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/pdf_book/view/pdf_book_screen.dart';
import 'package:otzaria/tabs/models/combined_tab.dart';
import 'package:otzaria/tabs/models/tab.dart';

class _LeafTab extends OpenedTab {
  _LeafTab(super.title);

  @override
  Map<String, dynamic> toJson() => {'type': '_LeafTab', 'title': title};
}

/// תקציב הזיכרון של ה-renderer מתחלק בין חלוניות אותו טאב: ארבע חלוניות PDF
/// עם התקציב המלא כל אחת הן תרחיש ה-OOM במחשבי 8GB.
void main() {
  group('חלוקת תקציב מטמון PDF', () {
    test('חלונית אחת מקבלת את התקציב המלא', () {
      expect(pdfImageCacheBytesForPanes(1), kPdfImageCacheBudgetBytes);
    });

    test('שתי חלוניות מתחלקות שווה בשווה', () {
      expect(pdfImageCacheBytesForPanes(2), kPdfImageCacheBudgetBytes ~/ 2);
    });

    test('ארבע חלוניות אינן יורדות מתחת לרצפה', () {
      final perPane = pdfImageCacheBytesForPanes(4);
      expect(perPane, kPdfImageCacheMinBytesPerPane);
      // גם בארבע חלוניות הסכום קטן משמעותית מארבעה תקציבים מלאים.
      expect(perPane * 4, lessThan(kPdfImageCacheBudgetBytes * 4));
    });

    test('מספר חלוניות חריג אינו מייצר ערך לא חוקי', () {
      for (final count in [0, -3, 1, 8, 64]) {
        final bytes = pdfImageCacheBytesForPanes(count);
        expect(bytes, greaterThanOrEqualTo(kPdfImageCacheMinBytesPerPane));
        expect(bytes, lessThanOrEqualTo(kPdfImageCacheBudgetBytes));
      }
    });

    test('התקציב יורד ככל שמתווספות חלוניות', () {
      expect(
        pdfImageCacheBytesForPanes(2),
        lessThan(pdfImageCacheBytesForPanes(1)),
      );
      expect(
        pdfImageCacheBytesForPanes(3),
        lessThanOrEqualTo(pdfImageCacheBytesForPanes(2)),
      );
    });
  });

  group('מספר החלוניות כמקור החלוקה', () {
    test('טאב שאינו מפוצל הוא חלונית אחת', () {
      expect(leafPanes(_LeafTab('בודד')).length, 1);
    });

    test('טאב מפוצל מדווח שתי חלוניות, וכל אחת מקבלת חצי תקציב', () {
      final split = CombinedTab(
        rightTab: _LeafTab('א'),
        leftTab: _LeafTab('ב'),
      );

      expect(leafPanes(split).length, 2);
      expect(
        pdfImageCacheBytesForPanes(leafPanes(split).length),
        kPdfImageCacheBudgetBytes ~/ 2,
      );
    });
  });
}
