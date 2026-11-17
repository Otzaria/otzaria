import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/books.dart';

// המימוש הקודם (שרשור תוצאת כל תת-קטגוריה), כאורקל לסדר ולתוכן.
List<Book> _oracleBooks(Category c) => [
  ...c.books,
  for (final sub in c.subCategories) ..._oracleBooks(sub),
];

List<Category> _oracleCategories(Category c) => [
  ...c.subCategories,
  for (final sub in c.subCategories) ..._oracleCategories(sub),
];

Category _randomTree(Random rnd, int depth, String prefix) => Category(
  title: prefix,
  description: '',
  shortDescription: '',
  order: 0,
  subCategories: [
    for (var i = depth > 0 ? rnd.nextInt(4) : 0; i > 0; i--)
      _randomTree(rnd, depth - 1, '$prefix.$i'),
  ],
  books: [
    for (var i = rnd.nextInt(4); i > 0; i--) TextBook(title: '$prefix/$i'),
  ],
  parent: null,
);

void main() {
  test('נתיב קטגוריה עמוקה שומר סדר אבות גם אחרי הריפקטור', () {
    final library = Library(categories: []);
    final a = Category(
      title: 'תנ"ך',
      description: '',
      shortDescription: '',
      order: 0,
      subCategories: [],
      books: [],
      parent: library,
    );
    final b = Category(
      title: 'נביאים',
      description: '',
      shortDescription: '',
      order: 0,
      subCategories: [],
      books: [],
      parent: a,
    );
    final c = Category(
      title: 'ישעיה',
      description: '',
      shortDescription: '',
      order: 0,
      subCategories: [],
      books: [],
      parent: b,
    );
    expect(library.path, '/');
    expect(a.path, '/תנ"ך');
    expect(c.path, '/תנ"ך/נביאים/ישעיה');
  });

  test('getAllBooks/getAllCategories בסדר ובתוכן של המימוש הקודם (perf)', () {
    final rnd = Random(7);
    for (var round = 0; round < 300; round++) {
      final root = _randomTree(rnd, rnd.nextInt(6), '$round');
      expect(root.getAllBooks(), orderedEquals(_oracleBooks(root)));
      expect(root.getAllCategories(), orderedEquals(_oracleCategories(root)));
    }
  });
}
