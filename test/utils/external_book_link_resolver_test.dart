import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/utils/navigation/external_book_link_resolver.dart';
import 'package:test/test.dart';

void main() {
  final officialText = TextBook(id: 384, title: 'שו"ע אה"ע');
  final userText = TextBook(
    id: 384,
    title: 'ספר משתמש',
    source: BookSource.user,
  );
  final userDocument = DocumentBook(
    id: 384,
    title: 'מסמך משתמש',
    path: 'book.odt',
    fileType: 'odt',
    source: BookSource.user,
  );
  final officialPdf = PdfBook(id: 384, title: 'שו"ע אה"ע', path: 'book.pdf');

  test('קישור רשמי אינו נפתח כספר משתמש בעל מזהה זהה', () {
    expect(
      resolveExternalBookLink(
        [userText, officialText],
        384,
        source: BookSource.official,
        isPdf: false,
      ),
      same(officialText),
    );
  });

  test('קישור לספר משתמש אינו נפתח כספר רשמי בעל מזהה זהה', () {
    expect(
      resolveExternalBookLink(
        [officialText, userText],
        384,
        source: BookSource.user,
        isPdf: false,
      ),
      same(userText),
    );
  });

  test('קישור טקסט אינו נפתח כ-PDF בעל מזהה זהה', () {
    expect(
      resolveExternalBookLink(
        [officialPdf, officialText],
        384,
        source: BookSource.official,
        isPdf: false,
      ),
      same(officialText),
    );
  });

  test('קישור למסמך משתמש נפתח את ספר המסמך', () {
    expect(
      resolveExternalBookLink(
        [officialText, userDocument],
        384,
        source: BookSource.user,
        isPdf: false,
      ),
      same(userDocument),
    );
  });
}
