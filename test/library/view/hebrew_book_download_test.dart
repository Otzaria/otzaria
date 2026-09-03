import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/library/services/hebrew_books_download_service.dart';
import 'package:otzaria/library/view/otzar_book_dialog.dart';
import 'package:otzaria/models/books.dart';

Widget _wrap(Widget child) => MaterialApp(
  locale: const Locale('he', 'IL'),
  home: Scaffold(body: child),
);

ExternalLibraryBook _hebrewBook() => ExternalLibraryBook(
  title: 'ספר היברובוקס',
  id: 10022,
  link: 'https://hebrewbooks.org/10022',
  externalLibraryId: 'hb:10022',
  topics: '',
);

ExternalLibraryBook _otzarBook() => ExternalLibraryBook(
  title: 'ספר אוצר החכמה',
  id: 555,
  link: 'https://tablet.otzar.org/book/book.php?book=555',
  externalLibraryId: 'oh:555',
  topics: '',
);

void main() {
  group('כתובת ההורדה', () {
    test('נבנית מתוך מזהה הספר', () {
      expect(
        HebrewBooksDownloadService.fileUrl(10022).toString(),
        'https://files.hebrewbooksoffline.dpdns.org/HebrewBooks/books/10022.pdf',
      );
    });

    test('שם הקובץ תואם לתבנית שסורק תיקיית היברובוקס מזהה', () {
      expect(HebrewBooksDownloadService.fileNameFor(10022), '10022.pdf');
    });

    test('כותרת הגישה לשרת', () {
      expect(HebrewBooksDownloadService.appKeyHeader, 'x-app-key');
      expect(HebrewBooksDownloadService.appKeyValue, 'otzariatokendownload');
    });
  });

  group('כפתור ההורדה בדיאלוג הספר', () {
    testWidgets('מוצג לספר היברובוקס לצד "פתח באתר"', (tester) async {
      await tester.pumpWidget(_wrap(OtzarBookDialog(book: _hebrewBook())));
      await tester.pumpAndSettle();

      expect(find.text('פתח באתר'), findsOneWidget);
      expect(find.text('הורדת הקובץ'), findsOneWidget);
    });

    testWidgets('אינו מוצג לספר אוצר החכמה', (tester) async {
      // בדיקת הקיום המקומי של אוצר החכמה ניגשת לדיסק — חייב runAsync.
      await tester.runAsync(() async {
        await tester.pumpWidget(_wrap(OtzarBookDialog(book: _otzarBook())));
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pump();

      expect(find.text('פתח באתר'), findsOneWidget);
      expect(find.text('הורדת הקובץ'), findsNothing);
    });
  });
}
