import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/books.dart';

Category _category({
  List<Book> books = const [],
  List<Category> subCategories = const [],
}) => Category(
  title: 'קטגוריה',
  description: '',
  shortDescription: '',
  order: 0,
  subCategories: List.of(subCategories),
  books: List.of(books),
  parent: null,
);

void main() {
  group('Category.hasBooks', () {
    test('קטגוריה עם ספר ישיר — מכילה ספרים', () {
      expect(_category(books: [TextBook(title: 'רות')]).hasBooks, isTrue);
    });

    test('קטגוריה ריקה לחלוטין — אינה מכילה ספרים', () {
      expect(_category().hasBooks, isFalse);
    });

    test('בלי ספרים ישירים אך עם תת-קטגוריה שיש בה ספר — מכילה ספרים', () {
      final category = _category(
        subCategories: [
          _category(books: [TextBook(title: 'ברכות')]),
        ],
      );
      expect(category.hasBooks, isTrue);
    });

    test('תת-קטגוריות קיימות אך כולן ריקות — אינה מכילה ספרים', () {
      final category = _category(
        subCategories: [_category(), _category()],
      );
      expect(category.hasBooks, isFalse);
    });

    test('ספר מקונן עמוק — מכילה ספרים', () {
      final category = _category(
        subCategories: [
          _category(
            subCategories: [
              _category(books: [TextBook(title: 'שבת')]),
            ],
          ),
        ],
      );
      expect(category.hasBooks, isTrue);
    });
  });
}
