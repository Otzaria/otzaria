import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/library/bloc/library_bloc.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/models/books.dart';

void main() {
  final changed = BookSource.attached('lib-a');
  final other = BookSource.attached('lib-b');
  final books = [
    TextBook(id: 1, title: 'Official A'),
    TextBook(id: 1, title: 'User A', source: BookSource.user),
    TextBook(id: 1, title: 'Attached A', source: changed),
    TextBook(id: 2, title: 'Attached B', source: changed),
    TextBook(id: 1, title: 'Other A', source: other),
  ];

  test('קובץ מסד שהשתנה — כל ספריו, ורק הם, מאונדקסים מחדש', () {
    final result = LibraryBloc.booksToReindex(
      books,
      changedBookKeys: const {},
      changedAttachedSlugs: const {'lib-a'},
    );
    expect(result.map((b) => b.title), ['Attached A', 'Attached B']);
  });

  test('מפתחות ספרים ומסדים מצטרפים', () {
    final result = LibraryBloc.booksToReindex(
      books,
      changedBookKeys: const {'id:1'},
      changedAttachedSlugs: const {'lib-b'},
    );
    expect(result.map((b) => b.title), ['Official A', 'Other A']);
  });

  test('אין שינויים — רשימה ריקה', () {
    expect(
      LibraryBloc.booksToReindex(
        books,
        changedBookKeys: const {},
        changedAttachedSlugs: const {},
      ),
      isEmpty,
    );
  });
}
