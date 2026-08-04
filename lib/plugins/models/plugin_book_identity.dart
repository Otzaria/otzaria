import 'package:otzaria/models/books.dart';

typedef PluginBookIdentityKey = ({
  String bookId,
  int? id,
  String type,
  String source,
});

/// זהות ספר קנונית עבור ה-Plugin SDK.
class PluginBookIdentity {
  static int? parseId(Object? rawId) => switch (rawId) {
    int value => value,
    num value when value == value.toInt() => value.toInt(),
    String value => int.tryParse(value),
    _ => null,
  };

  static String typeOf(Book book) {
    final fileType = book.fileType?.trim().toLowerCase();
    return switch (book) {
      PdfBook() => 'pdf',
      ExternalLibraryBook() => 'external',
      DocxBook() || TextBook() when fileType == 'docx' => 'docx',
      EpubBook() || TextBook() when fileType == 'epub' => 'epub',
      _ => 'text',
    };
  }

  static String sourceOf(Book book) => switch (book) {
    ExternalLibraryBook() => 'external',
    _ when book.isUserBook => 'user',
    _ => 'library',
  };

  static PluginBookIdentityKey keyOf(Book book) => (
    bookId: book.title,
    id: book.id,
    type: typeOf(book),
    source: sourceOf(book),
  );

  static Map<String, dynamic> toJson(Book book) => {
    'id': book.id,
    'type': typeOf(book),
    'bookId': book.title,
    'source': sourceOf(book),
  };

  static bool matches(
    Book book, {
    int? id,
    String? bookId,
    String? type,
    String? source,
  }) {
    if (id != null && book.id != id) return false;
    if (bookId != null && book.title != bookId) return false;
    if (type != null && typeOf(book) != type.trim().toLowerCase()) {
      return false;
    }
    if (source != null && sourceOf(book) != source.trim().toLowerCase()) {
      return false;
    }
    return true;
  }
}
