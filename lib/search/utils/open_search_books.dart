import 'package:otzaria/data/book_identity.dart';
import 'package:otzaria/indexing/repository/indexing_repository.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/tabs/models/combined_tab.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/models/text_tab.dart';

/// הספרים הפתוחים ב-[tabs] (כל חלונית, גם בטאב מפוצל) שנכנסים לאינדקס
/// החיפוש, בסדר הכרטיסיות ובלי כפילויות לפי זהות מסמך החיפוש — PDF
/// ששואל את ה-id של ספר הטקסט הוא מסמך נפרד ונשמר לצדו.
List<Book> openSearchableBooks(
  Iterable<OpenedTab> tabs, {
  required bool includePdfBooks,
  required bool includeUserBooks,
}) {
  final seen = <String>{};
  final books = <Book>[];
  for (final pane in tabs.expand(leafPanes)) {
    final Book book;
    if (pane is TextBookTab) {
      book = pane.book;
    } else if (pane is PdfBookTab && includePdfBooks) {
      book = pane.book;
    } else {
      continue;
    }
    if (!IndexingRepository.isIndexableBook(book)) continue;
    if (!includeUserBooks && book.source.isUser) continue;
    if (seen.add(BookIdentity.indexedFilePath(book))) books.add(book);
  }
  return books;
}
