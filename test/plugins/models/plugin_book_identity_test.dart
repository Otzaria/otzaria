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
}
