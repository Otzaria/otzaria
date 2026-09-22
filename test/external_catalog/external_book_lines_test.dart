import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/external_catalog/view/external_book_lines.dart';
import 'package:otzaria/models/books.dart';

/// שורות המשנה של ספר חיצוני — מחבר, מקור וקטגוריה.
void main() {
  ExternalLibraryBook external({
    required String id,
    String? link,
    String? heCategories,
    String? categoryPath,
  }) => ExternalLibraryBook(
    title: 'ספר',
    id: 1,
    link: link,
    externalLibraryId: id,
    heCategories: heCategories,
    categoryPath: categoryPath,
  );

  group('מקור הספר', () {
    test('כל ספק מוצג בשמו', () {
      expect(
        externalBookSourceLine(external(id: 'rp:1')),
        'פרויקט השו"ת בר אילן',
      );
      expect(externalBookSourceLine(external(id: 'oh:1')), 'אוצר החכמה');
      expect(externalBookSourceLine(external(id: 'hb:1')), 'היברובוקס');
    });

    /// ספר היברובוקס שהורד מומר ל-[PdfBook] ושומר את המזהה החיצוני.
    /// הוא עדיין הגיע משם, ולכן עדיין מוצג המקור.
    test('ספר שהורד למחשב שומר את שם המקור', () {
      final book = PdfBook(
        title: 'ספר',
        path: 'c:/books/x.pdf',
        externalLibraryId: 'hb:5',
      );
      expect(externalBookSourceLine(book), 'היברובוקס');
    });

    test('ספר מותקן אינו מקבל שורת מקור', () {
      expect(
        externalBookSourceLine(TextBook(title: 'ספר מקומי')),
        isNull,
      );
      expect(externalBookSourceLine(external(id: '')), isNull);
    });
  });

  group('קטגוריה', () {
    test('ספר בר אילן מוצג בקטגוריה של אוצריא ולא במדף של בר אילן', () {
      final book = external(
        id: 'rp:1',
        heCategories: 'ספרי שאלות ותשובות (שו"ת)',
        categoryPath: 'ספרי שאלות ותשובות (שו"ת)/תורת יקותיאל',
      );
      expect(externalBookCategoryLine(book), 'שו״ת');
    });

    /// מדף שנוסף במהדורה חדשה ואין לו מיפוי מוצג בשמו בבר אילן —
    /// שם אמיתי, ולא ניחוש לאיזו קטגוריה באוצריא הוא שייך.
    test('מדף בלי מיפוי מוצג בשמו בבר אילן', () {
      final book = external(
        id: 'rp:1',
        heCategories: 'קטגוריה חדשה במהדורה הבאה > תת-מדף',
        categoryPath: 'קטגוריה חדשה במהדורה הבאה/ספר',
      );
      expect(externalBookCategoryLine(book), 'קטגוריה חדשה במהדורה הבאה');
    });

    test('ספק אחר מציג את נתיב הקטגוריות שלו', () {
      final book = external(
        id: 'oh:1',
        categoryPath: 'הלכה/שולחן ערוך',
      );
      expect(externalBookCategoryLine(book), 'הלכה › שולחן ערוך');
    });

    test('ספר בלי נתיב אינו מקבל שורה ריקה', () {
      expect(externalBookCategoryLine(external(id: 'oh:1')), isNull);
      expect(
        externalBookCategoryLine(external(id: 'oh:1', categoryPath: '  ')),
        isNull,
      );
    });
  });
}
