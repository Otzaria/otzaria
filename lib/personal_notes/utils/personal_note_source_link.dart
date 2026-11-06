import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/personal_notes/models/personal_note.dart';
import 'package:otzaria/personal_notes/utils/personal_notes_book_key.dart';
import 'package:otzaria/utils/book_link_builder.dart';

/// עוגן פיזי שייך למהדורת ה-PDF גם כשיש ספר טקסט באותה כותרת.
Book? personalNoteSourceBook(Library library, PersonalNote note) =>
    note.pdfAnchor == null
    ? findBookForPersonalNotesKey(library, note.bookId)
    : findPdfBookForPersonalNotesKey(
        library,
        note.bookId,
        documentId: note.pdfAnchor?.documentId,
      );

/// קישור למיקום שמור בספר מזוהה. ב-PDF נדרשת רשימת המועמדים לקישור,
/// כי מזהה מסד עשוי להיות משותף לכמה מהדורות בעלות נתיבים שונים.
String? personalNoteSourceLink(
  Book? book,
  PersonalNote note, {
  Iterable<PdfBook>? pdfLinkCandidates,
}) {
  if (book == null ||
      book.id == null ||
      book.id! <= 0 ||
      !note.hasLocation ||
      note.lineNumber! <= 0 ||
      personalNotesBookKey(book) != note.bookId) {
    return null;
  }
  if (book is PdfBook) {
    final targetDocument = pdfPersonalNoteDocumentId(book);
    final documents = pdfLinkCandidates
        ?.where(
          (candidate) =>
              candidate.id == book.id && candidate.source == book.source,
        )
        .map(pdfPersonalNoteDocumentId)
        .toSet();
    if (documents == null ||
        documents.length != 1 ||
        documents.single != targetDocument) {
      return null;
    }
    final documentId = note.pdfAnchor?.documentId;
    if (documentId != null &&
        !pdfPersonalNoteDocumentIds(book).contains(documentId)) {
      return null;
    }
    return buildPdfPageLink(
      book.id!,
      note.pdfAnchor?.pageNumber ?? note.lineNumber!,
      source: book.source,
    );
  }
  if (book is TextBook && note.pdfAnchor == null) {
    return buildSectionLink(
      book.id!,
      note.lineNumber! - 1,
      source: book.source,
    );
  }
  return null;
}
