import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/personal_notes/utils/personal_notes_book_key.dart';

Library _library(List<Book> books) {
  final category = Category(
    title: 'root',
    description: '',
    shortDescription: '',
    order: 0,
    subCategories: [],
    books: books,
    parent: null,
  );
  final library = Library(categories: [category]);
  category.parent = library;
  return library;
}

void main() {
  final attachedSource = BookSource.attached('lib-a');

  test('title key never resolves to an attached book of the same title', () {
    final attached = TextBook(id: 1, title: 'book', source: attachedSource);
    final library = _library([attached]);

    expect(findBookForPersonalNotesKey(library, 'book'), isNull);
    expect(findTextBookForPersonalNotesKey(library, 'book'), isNull);
  });

  test('attached key resolves only the book of that library', () {
    final official = TextBook(id: 1, title: 'book');
    final attached = TextBook(id: 1, title: 'book', source: attachedSource);
    final other = TextBook(
      id: 1,
      title: 'book',
      source: BookSource.attached('lib-b'),
    );
    final library = _library([official, other, attached]);

    expect(
      findBookForPersonalNotesKey(library, personalNotesBookKey(attached)),
      same(attached),
    );
    expect(
      findTextBookForPersonalNotesKey(library, personalNotesBookKey(official)),
      same(official),
    );
  });

  test('attached PDF resolves as a book but not as a text book', () {
    final pdf = PdfBook(
      id: 2,
      title: 'scan',
      path: '/tmp/scan.pdf',
      source: attachedSource,
    );
    final library = _library([pdf]);
    final key = personalNotesBookKey(pdf);

    expect(findBookForPersonalNotesKey(library, key), same(pdf));
    expect(findTextBookForPersonalNotesKey(library, key), isNull);
  });

  test('category keys cover nested books as a set for O(1) lookup', () {
    final attached = TextBook(id: 3, title: 'deep', source: attachedSource);
    final child = Category(
      title: 'child',
      description: '',
      shortDescription: '',
      order: 0,
      subCategories: [],
      books: [
        attached,
        TextBook(id: 4, title: 'shared'),
      ],
      parent: null,
    );
    final root = Category(
      title: 'root',
      description: '',
      shortDescription: '',
      order: 0,
      subCategories: [child],
      books: [
        TextBook(id: 5, title: 'top'),
        PdfBook(title: 'shared', path: '/s.pdf'),
      ],
      parent: null,
    );

    final keys = personalNotesBookKeysInCategory(root);

    expect(keys, isA<Set<String>>());
    expect(keys, {'top', 'shared', personalNotesBookKey(attached)});
  });

  group('personalNotesCategoryCounts', () {
    Category cat(String title, List<Category> subs, List<Book> books) =>
        Category(
          title: title,
          description: '',
          shortDescription: '',
          order: 0,
          subCategories: subs,
          books: books,
          parent: null,
        );

    test('counts each category once, deduping books within a category', () {
      final leaf = cat('leaf', [], [
        TextBook(title: 'a'),
        PdfBook(title: 'a', path: '/a.pdf'),
        TextBook(title: 'b'),
      ]);
      final mid = cat('mid', [leaf], [TextBook(title: 'a')]);
      final empty = cat('empty', [], [TextBook(title: 'none')]);
      final root = cat('root', [mid, empty], [TextBook(title: 'c')]);
      final perBook = {'a': 2, 'b': 1, 'c': 4};

      final counts = personalNotesCategoryCounts(
        root,
        (key) => perBook[key] ?? 0,
      );

      expect(counts[leaf], 3);
      expect(counts[mid], 5);
      expect(counts[empty], 0);
      expect(counts[root], 9);
    });

    test('looks up each category book once regardless of depth', () {
      final deep = cat('d', [], [TextBook(title: 'x')]);
      final c = cat('c', [deep], [TextBook(title: 'y')]);
      final b = cat('b', [c], []);
      final root = cat('root', [b], []);
      final lookups = <String>[];

      personalNotesCategoryCounts(root, (key) {
        lookups.add(key);
        return 1;
      });

      expect(lookups..sort(), ['x', 'y']);
    });
  });
}
