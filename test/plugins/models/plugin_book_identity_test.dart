import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/plugins/models/plugin_book_identity.dart';

void main() {
  test('Docx שנעטף ל-TextBook שומר על סוג הזהות הקנוני', () {
    final docx = DocxBook(id: 7, title: 'מסמך', path: 'document.docx');

    expect(PluginBookIdentity.typeOf(docx), 'docx');
    expect(PluginBookIdentity.typeOf(docx.toTextBook()), 'docx');
  });

  test('source מבדיל בין IDs חופפים של ספרייה וספרי משתמש', () {
    final libraryBook = TextBook(id: 1, title: 'ספר');
    final userBook = TextBook(id: 1, title: 'ספר', isUserBook: true);

    expect(PluginBookIdentity.sourceOf(libraryBook), 'library');
    expect(PluginBookIdentity.sourceOf(userBook), 'user');
    expect(PluginBookIdentity.keyOf(libraryBook), isNot(userBook));
  });

  test('uidOf מבדיל בין ספרייה, משתמש וחיצוני עם id חופף', () {
    final libraryBook = TextBook(id: 5, title: 'גיטין');
    final userBook = TextBook(id: 5, title: 'גיטין', isUserBook: true);

    expect(PluginBookIdentity.uidOf(libraryBook), 'id:5');
    expect(PluginBookIdentity.uidOf(userBook), 'uid:5');
    expect(
      PluginBookIdentity.uidOf(libraryBook),
      isNot(PluginBookIdentity.uidOf(userBook)),
    );
  });

  test('toJson נשאר רזה (בלי bookUid) לתאימות round-trip דקלרטיבי', () {
    final book = TextBook(id: 5, title: 'גיטין', isUserBook: true);
    final json = PluginBookIdentity.toJson(book);

    expect(json.containsKey('bookUid'), isFalse);
    expect(json['id'], 5);
    expect(json['bookId'], 'גיטין');
    expect(json['source'], 'user');
  });

  test('toJsonWithUid מוסיף bookUid מעל שדות toJson', () {
    final book = TextBook(id: 5, title: 'גיטין', isUserBook: true);
    final json = PluginBookIdentity.toJsonWithUid(book);

    expect(json['bookUid'], 'uid:5');
    expect(json['id'], 5);
    expect(json['bookId'], 'גיטין');
    expect(json['source'], 'user');
  });

  test('matches לפי bookUid חד-משמעי — מתעלם מ-id/כותרת סותרים', () {
    final userBook = TextBook(id: 5, title: 'גיטין', isUserBook: true);

    // bookUid נכון מכריע גם כשה-id/כותרת שנשלחו לצדו שגויים.
    expect(
      PluginBookIdentity.matches(
        userBook,
        bookUid: 'uid:5',
        id: 999,
        bookId: 'שם אחר',
      ),
      isTrue,
    );
    // bookUid שגוי פוסל גם כשהכותרת תואמת (זו בדיוק ההתנגשות שהוא פותר).
    expect(
      PluginBookIdentity.matches(userBook, bookUid: 'id:5', bookId: 'גיטין'),
      isFalse,
    );
  });

  test('matches בלי bookUid נשאר בהתנהגות הקיימת', () {
    final book = TextBook(id: 5, title: 'גיטין');
    expect(PluginBookIdentity.matches(book, bookId: 'גיטין'), isTrue);
    expect(PluginBookIdentity.matches(book, id: 5), isTrue);
    expect(PluginBookIdentity.matches(book, bookId: 'אחר'), isFalse);
  });
}
