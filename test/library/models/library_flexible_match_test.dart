import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/books.dart';

Category _categoryWith(List<Book> books) => Category(
      title: 'קטגוריה',
      description: '',
      shortDescription: '',
      order: 0,
      subCategories: [],
      books: books,
      parent: null,
    );

void main() {
  group('findBookByTitleFlexible — הכלה כמילה שלמה', () {
    test('"רות" לא נתפס בתוך "טהרות"', () {
      final library = Library(categories: [
        _categoryWith([TextBook(title: 'רות')]),
      ]);

      expect(library.findBookByTitleFlexible('טהרות', TextBook), isNull);
    });

    test('התאמה מדויקת עדיין עובדת', () {
      final library = Library(categories: [
        _categoryWith([TextBook(title: 'רות')]),
      ]);

      final result = library.findBookByTitleFlexible('רות', TextBook);
      expect(result?.title, 'רות');
    });

    test('הכלה כמילה שלמה — "מסכת ברכות" מתאים ל-"ברכות"', () {
      final library = Library(categories: [
        _categoryWith([TextBook(title: 'ברכות')]),
      ]);

      final result = library.findBookByTitleFlexible('מסכת ברכות', TextBook);
      expect(result?.title, 'ברכות');
    });

    test('הכלה כמילה שלמה — "ברכות" מתאים ל-"מסכת ברכות"', () {
      final library = Library(categories: [
        _categoryWith([TextBook(title: 'מסכת ברכות')]),
      ]);

      final result = library.findBookByTitleFlexible('ברכות', TextBook);
      expect(result?.title, 'מסכת ברכות');
    });
  });
}
