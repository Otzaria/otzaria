import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/personal_notes/models/pdf_note_anchor.dart';
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

  test('PDF עם id שאול וכותרת זהה מובחן לפי הקובץ', () {
    final first = PdfBook(id: 1, title: 'מסמך', path: '/one/document.pdf');
    final second = PdfBook(id: 1, title: 'מסמך', path: '/two/document.pdf');
    final library = _library([first, second]);
    final identity = pdfPersonalNoteDocumentId(second);
    expect(identity, isNot(pdfPersonalNoteDocumentId(first)));
    expect(findPdfBookForPersonalNotesKey(library, 'מסמך'), isNull);
    expect(
      findPdfBookForPersonalNotesKey(library, 'מסמך', documentId: identity),
      same(second),
    );
    final anchor = PdfNoteAnchor(
      pageNumber: 3,
      x: .4,
      y: .7,
      documentId: identity,
    );
    expect(
      pdfPersonalNoteAnchorMatchesBook(anchor, first, library: library),
      isFalse,
    );
    expect(
      pdfPersonalNoteAnchorMatchesBook(anchor, second, library: library),
      isTrue,
    );
  });

  test('עוגן ללא זהות נפתר רק ל-PDF יחיד, גם כשאותו ספר נמצא פעמיים בעץ', () {
    final book = PdfBook(title: 'מסמך', path: '/one/document.pdf');
    final library = _library([book])..offTreeBooks = [book];
    const anchor = PdfNoteAnchor(pageNumber: 3, x: .4, y: .7);
    expect(findPdfBookForPersonalNotesKey(library, 'מסמך'), same(book));
    expect(
      pdfPersonalNoteAnchorMatchesBook(anchor, book, library: library),
      isTrue,
    );
    library.offTreeBooks = [PdfBook(title: 'מסמך', path: '/two/document.pdf')];
    expect(findPdfBookForPersonalNotesKey(library, 'מסמך'), isNull);
    expect(
      pdfPersonalNoteAnchorMatchesBook(anchor, book, library: library),
      isFalse,
    );
  });

  test('זהות PDF מכבדת מקור ומזהה קטלוג חיצוני או מסד מצורף', () {
    final official = PdfBook(title: 'מסמך', path: '/same.pdf');
    final user = PdfBook(
      title: 'מסמך',
      path: '/same.pdf',
      source: BookSource.user,
    );
    expect(
      pdfPersonalNoteDocumentId(official),
      isNot(pdfPersonalNoteDocumentId(user)),
    );
    final first = PdfBook(
      id: 3,
      title: 'מסמך',
      path: '/old.pdf',
      source: attachedSource,
    );
    final moved = PdfBook(
      id: 3,
      title: 'מסמך',
      path: '/new.pdf',
      source: attachedSource,
    );
    expect(pdfPersonalNoteDocumentId(first), pdfPersonalNoteDocumentId(moved));
    final external = PdfBook(
      title: 'מסמך',
      path: '/old.pdf',
      externalLibraryId: 'fixture:17',
    );
    final externalMoved = PdfBook(
      title: 'מסמך',
      path: '/new.pdf',
      externalLibraryId: 'fixture:17',
    );
    expect(
      pdfPersonalNoteDocumentId(external),
      pdfPersonalNoteDocumentId(externalMoved),
    );
    expect(
      findPdfBookForPersonalNotesKey(
        _library([moved]),
        personalNotesBookKey(first),
        documentId: pdfPersonalNoteDocumentId(first),
      ),
      same(moved),
    );
  });

  test('נתיב PDF שהוחלף אינו מנווט אוטומטית לקובץ אחר באותה כותרת', () {
    final old = PdfBook(title: 'מסמך', path: '/old.pdf');
    final replacement = PdfBook(title: 'מסמך', path: '/replacement.pdf');
    expect(
      findPdfBookForPersonalNotesKey(
        _library([replacement]),
        'מסמך',
        documentId: pdfPersonalNoteDocumentId(old),
      ),
      isNull,
    );
  });

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

  test('user book key is separate from the official title key', () {
    final official = TextBook(id: 1, title: 'ביצה');
    final user = TextBook(id: 1, title: 'ביצה', source: BookSource.user);

    expect(personalNotesBookKey(official), 'ביצה');
    expect(personalNotesBookKey(user), 'ביצה|user');
    final parsed = parsePersonalNotesBookKey(personalNotesBookKey(user));
    expect(parsed.title, 'ביצה');
    expect(parsed.source, BookSource.user);
  });

  test('title key resolves only the official book, user key only the user', () {
    final user = TextBook(id: 1, title: 'ביצה', source: BookSource.user);
    final official = TextBook(id: 2, title: 'ביצה');
    final library = _library([user, official]);

    expect(findBookForPersonalNotesKey(library, 'ביצה'), same(official));
    expect(findTextBookForPersonalNotesKey(library, 'ביצה'), same(official));
    expect(findBookForPersonalNotesKey(library, 'ביצה|user'), same(user));
    expect(findTextBookForPersonalNotesKey(library, 'ביצה|user'), same(user));
  });

  test('title key never resolves to a user book of the same title', () {
    final library = _library([
      TextBook(id: 1, title: 'יומן', source: BookSource.user),
    ]);

    expect(findBookForPersonalNotesKey(library, 'יומן'), isNull);
    expect(findTextBookForPersonalNotesKey(library, 'יומן'), isNull);
  });

  test(
    'source keys find secondary text versions outside the category tree',
    () {
      final official = TextBook(id: 1, title: 'ביצה', categoryId: 1);
      final user = TextBook(
        id: 2,
        title: 'ביצה',
        categoryId: 7,
        source: BookSource.user,
      );
      final attached = TextBook(
        id: 3,
        title: 'ביצה',
        categoryId: 8,
        source: attachedSource,
      );
      final library = _library([official])..offTreeBooks = [user, attached];

      expect(findBookForPersonalNotesKey(library, 'ביצה'), same(official));
      expect(findBookForPersonalNotesKey(library, 'ביצה|user'), same(user));
      expect(findTextBookForPersonalNotesKey(library, 'ביצה|user'), same(user));
      expect(
        findBookForPersonalNotesKey(library, 'ביצה|db:lib-a'),
        same(attached),
      );
      expect(findBookForPersonalNotesKey(library, 'ביצה|db:lib-b'), isNull);
    },
  );

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
