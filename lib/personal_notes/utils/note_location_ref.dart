import 'package:pdfrx/pdfrx.dart';

import 'package:otzaria/models/books.dart';
import 'package:otzaria/personal_notes/models/personal_note.dart';
import 'package:otzaria/utils/text/ref_helper.dart';

/// כתובת המיקום של הערה אישית (שם הספר + דף/עמוד), לתצוגה כשורת משנה בכרטיס.
///
/// בטקסט נגזרת מ-[tableOfContents] לפי שורת ההערה, וב-PDF מ-[pdfOutline] לפי
/// מספר העמוד. מחזירה null כשאין להערה מיקום או כשמקור הכתובת עדיין לא נטען.
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

  String ref;
  if (isPdf) {
    if (pdfOutline == null) return null;
    ref = referenceFromPageNumber(lineNumber, pdfOutline).trim();
  } else {
    if (tableOfContents == null) return null;
    // lineNumber הוא 1-based ואילו אינדקס ה-TOC הוא 0-based.
    ref = refFromTocList(lineNumber - 1, tableOfContents).trim();
  }

  if (includeBookTitle) {
    ref = addBookTitleToRef(ref, bookTitle);
  }

  final trimmed = ref.trim();
  return trimmed.isEmpty ? null : trimmed;
}
