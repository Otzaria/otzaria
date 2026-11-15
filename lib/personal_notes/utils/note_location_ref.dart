import 'package:pdfrx/pdfrx.dart';

import 'package:otzaria/models/books.dart';
import 'package:otzaria/personal_notes/models/personal_note.dart';
import 'package:otzaria/utils/text/ref_helper.dart';

/// כתובת המיקום של הערה אישית (שם הספר + דף/עמוד), לתצוגה כשורת משנה בכרטיס.
///
/// בטקסט נגזרת מ-[tableOfContents] לפי שורת ההערה. ב-PDF נגזרת מ-[pdfOutline]
/// לפי מספר העמוד — אך כשלהערה יש כותרת (מילות הדף, ב-PDF עם טקסט מקביל)
/// מוחזר null, כי הכותרת כבר כוללת את המיקום והכתובת הנפרדת הייתה שגויה.
/// מחזירה null גם כשאין להערה מיקום או כשמקור הכתובת עדיין לא נטען.
/// [includeBookTitle] קובע אם להקדים את שם הספר — כבים אותו כשהשם כבר מוצג
/// בנפרד (למשל ככותרת קבוצה במסך הריכוז).
String? personalNoteLocationRef(
  PersonalNote note, {
  required bool isPdf,
  required String bookTitle,
  List<TocEntry>? tableOfContents,
  List<PdfOutlineNode>? pdfOutline,
  bool includeBookTitle = true,
}) {
  final lineNumber = note.lineNumber;
  if (lineNumber == null) return null;

  // ב-PDF הכתובת מחושבת ממספר עמוד ואינה תואמת לעוגן; כותרת (מילות הדף) כבר
  // מציינת את המיקום, ורק בלעדיה (PDF ללא טקסט) מציגים את הכתובת.
  if (isPdf &&
      note.pdfAnchor == null &&
      (note.displayTitle?.isNotEmpty ?? false)) {
    return null;
  }

  String ref;
  if (isPdf) {
    if (pdfOutline == null) return null;
    final page = note.pdfAnchor?.pageNumber ?? lineNumber;
    ref = referenceFromPageNumber(page, pdfOutline).trim();
    if (ref.isEmpty && note.pdfAnchor != null) ref = 'עמוד $page';
  } else {
    if (tableOfContents == null) return null;
    // lineNumber הוא 1-based ואילו אינדקס ה-TOC הוא 0-based.
    ref = refFromTocList(lineNumber - 1, tableOfContents).trim();
    final last = note.endLineNumber;
    if (last != null && last > lineNumber) {
      final endRef = refFromTocList(last - 1, tableOfContents).trim();
      if (endRef.isNotEmpty && endRef != ref) ref = '$ref – $endRef';
    }
  }

  if (includeBookTitle) {
    ref = addBookTitleToRef(ref, bookTitle);
  }

  final trimmed = ref.trim();
  return trimmed.isEmpty ? null : trimmed;
}
