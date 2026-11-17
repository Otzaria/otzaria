import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/pdf_book/bloc/pdf_book_bloc.dart';
import 'package:pdfrx/pdfrx.dart';

/// המסך מרכיב את הצפיין רק אחרי שהבלוק בדק בלי לחסום שהקובץ קיים (#5364),
/// ובדיקת הדיסק האמיתית מסתיימת רק בתוך runAsync.
Future<PdfBookBloc> pumpUntilPdfViewer(WidgetTester tester) async {
  for (var i = 0; i < 100 && find.byType(PdfViewer).evaluate().isEmpty; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
  }
  return tester.element(find.byType(PdfViewer)).read<PdfBookBloc>();
}
