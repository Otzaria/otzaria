import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/indexing/repository/indexing_repository.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/search/bloc/search_bloc.dart';

void main() {
  group('SearchBloc.bookForIndexedFilePathMap', () {
    late Library library;
    late TextBook official;
    late TextBook personal;
    late PdfBook pdf;

    setUp(() {
      official = TextBook(id: 5, title: 'שבת');
      personal = TextBook(id: 5, title: 'שבת', isUserBook: true);
      pdf = PdfBook(title: 'שבת', path: r'C:\books\shabbat.pdf');
      library = Library(categories: []);
      library.books.addAll([official, personal, pdf]);
    });

    test('ספר אישי החולק כותרת ו-id עם ספר רשמי נפתר לספר האישי', () {
      // רגרסיה: פתיחת תוצאת חיפוש לפי כותרת בלבד פתחה את הספר הרשמי
      // במקום האישי — הזהות חייבת להשתחזר ממפתח האינדקס היציב.
      final booksByPath = SearchBloc.bookForIndexedFilePathMap(library);

      expect(
        booksByPath[IndexingRepository.buildIndexedBookFilePath(official)],
        same(official),
      );
      final resolved =
          booksByPath[IndexingRepository.buildIndexedBookFilePath(personal)];
      expect(resolved, same(personal));
      expect(resolved!.isUserBook, isTrue);
    });

    test('תוצאת PDF נפתרת לפי נתיב הקובץ', () {
      final booksByPath = SearchBloc.bookForIndexedFilePathMap(library);

      expect(booksByPath[pdf.path], same(pdf));
    });

    test('מפתח שאינו בקטלוג מחזיר null', () {
      final booksByPath = SearchBloc.bookForIndexedFilePathMap(library);

      expect(booksByPath['uid:999'], isNull);
    });
  });
}
