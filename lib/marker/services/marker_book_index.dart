import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/marker/models/marker_book_uid.dart';
import 'package:otzaria/models/books.dart';

/// ספרי הספרייה לפי מזהה יציב ולפי כותרת, לאיתור הספר של סימון. ספר PDF
/// וספר טקסט באותה כותרת נשמרים בנפרד.
class MarkerBookIndex {
  MarkerBookIndex(Iterable<Book> books) {
    for (final book in books) {
      _byUid.putIfAbsent(markerBookUidOf(book), () => book);
      (book is PdfBook ? _pdfByTitle : _byTitle).putIfAbsent(
        book.title,
        () => book,
      );
    }
  }

  /// אינדקס אחד לכל טעינה של הספרייה, ולא בכל לחיצה על סימון.
  static final Expando<MarkerBookIndex> _ofLibrary = Expando();

  static MarkerBookIndex of(Library library) =>
      _ofLibrary[library] ??= MarkerBookIndex(library.getIndexableBooks());

  final Map<String, Book> _byUid = {};
  final Map<String, Book> _byTitle = {};
  final Map<String, Book> _pdfByTitle = {};

  static const String _versionMark = '|version:';

  /// לפי המזהה היציב, ואחרת לפי הכותרת. [pdf] — ספר ה-PDF ולא ספר הטקסט.
  /// סימון במהדורה חלופית מחזיר את הספר באותה מהדורה.
  Book? find(String bookTitle, String? bookUid, {bool pdf = false}) {
    final split = bookUid?.indexOf(_versionMark) ?? -1;
    final baseUid = split < 0 ? bookUid : bookUid!.substring(0, split);
    final version = split < 0
        ? null
        : bookUid!.substring(split + _versionMark.length);
    final byUid = baseUid == null ? null : _byUid[baseUid];
    final book = byUid != null && (byUid is PdfBook) == pdf
        ? byUid
        : (pdf ? _pdfByTitle : _byTitle)[bookTitle];
    return version != null && book is TextBook
        ? book.copyWith(versionTitle: version)
        : book;
  }
}
