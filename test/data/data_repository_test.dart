import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/books.dart';

void main() {
  group('DataRepository.findBooks', () {
    test('dedupes text and PDF variants of the same book in search results', () async {
      final category = Category(
        title: 'קטגוריה',
        description: '',
        shortDescription: '',
        order: 0,
        subCategories: [],
        books: [],
        parent: null,
      );

      final textBook = TextBook(
        id: 1,
        title: 'ספר מבחן',
        category: category,
        categoryId: 7,
        categoryPath: 'קטגוריה',
        topics: 'קטגוריה',
      );
      final pdfBook = PdfBook(
        id: 2,
        title: 'ספר מבחן',
        path: r'C:\library\ספר מבחן.pdf',
        category: category,
        categoryId: 7,
        categoryPath: 'קטגוריה',
        topics: 'קטגוריה',
      );

      category.books.addAll([textBook, pdfBook]);
      final library = Library(categories: [category]);
      category.parent = library;

      final repository = DataRepository()..library = Future.value(library);

      final results = await repository.findBooks('ספר מבחן', category);

      expect(results, hasLength(1));
      expect(results.single, same(textBook));
    });
  });
}
