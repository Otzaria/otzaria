import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/user_content_import/models/user_import_models.dart';
import 'package:otzaria/user_content_import/services/user_book_versions.dart';

void main() {
  final books = {
    for (final (id, title) in [
      (1, 'ראשי'),
      (2, 'קוק'),
      (3, 'ישן'),
      (4, 'בודד'),
    ])
      id: PdfBook(
        id: id,
        title: title,
        path: '/$title.pdf',
        source: BookSource.user,
      ),
  };
  const records = [
    UserBookVersionRecord(
      versionBookId: 3,
      primaryBookId: 1,
      versionTitle: 'דפוס ישן',
    ),
    UserBookVersionRecord(
      versionBookId: 2,
      primaryBookId: 1,
      versionTitle: 'מוסד הרב קוק',
      priority: 5,
    ),
    UserBookVersionRecord(
      versionBookId: 1,
      primaryBookId: 1,
      versionTitle: 'המהדורה הראשונה',
    ),
  ];

  List<String> titlesFor(int bookId) => [
    for (final v in buildUserBookVersions(
      bookId: bookId,
      records: records,
      booksById: books,
    ))
      v.displayTitle,
  ];

  test('הראשית תחילה, ואחריה לפי עדיפות ושם', () {
    expect(titlesFor(1), ['המהדורה הראשונה', 'מוסד הרב קוק', 'דפוס ישן']);
  });

  test('מגרסה משנית מתקבלת אותה קבוצה', () {
    expect(titlesFor(3), titlesFor(1));
  });

  test('כל גרסה מצביעה על קובץ הספר שלה', () {
    final versions = buildUserBookVersions(
      bookId: 1,
      records: records,
      booksById: books,
    );

    expect(versions.map((v) => v.separateBook?.id), [1, 2, 3]);
    expect(versions.every((v) => v.hasContent), isTrue);
  });

  test('ספר שאינו בקבוצה — אין גרסאות', () {
    expect(titlesFor(4), isEmpty);
  });

  test('בלי שם לגרסה הראשית מוצגת כותרת הספר', () {
    final versions = buildUserBookVersions(
      bookId: 1,
      records: records.take(2).toList(),
      booksById: books,
    );

    expect(versions.first.displayTitle, 'ראשי');
  });
}
