import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/widgets.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/text_book/utils/book_versions_action.dart';
import 'package:otzaria_icons/otzaria_icons.dart';
import 'package:otzaria/utils/file/document_format.dart';

/// אייקון הספר לפי פורמט המסמך — מקור יחיד לכל רשימות הספרייה, תוצאות
/// החיפוש, ההיסטוריה והתצוגות המקדימות.
///
/// הפורמט קודם למחלקת הספר: רשומות היסטוריה ותיקות של ספרי מסמך נשמרו
/// כ-`PdfBook`, ורק הנתיב מגלה שאינן PDF.
IconData bookFormatIcon(Book book) {
  final path = book is FileBook ? book.path : book.filePath;
  // הסיומת קודמת ל-`fileType`: ‏`PdfBook.fileType` הוא ברירת מחדל של הבנאי
  // ולא עובדה שנשמרה, ולכן ספר מסמך שנשמר בהיסטוריה כ-PdfBook היה מוצג
  // כ-PDF לנצח.
  final format =
      (path == null ? null : documentFormatFromExtension(path)) ??
      documentFormatFromFileType(book.fileType);
  if (format == null) {
    return book is PdfBook
        ? OtzariaIcons.book_pdf_24_regular
        : _plainTextIcon(book);
  }
  if (format == DocumentFormat.pdf) return OtzariaIcons.book_pdf_24_regular;
  if (format.isWordDocument) return OtzariaIcons.document_word_24_regular;
  if (format.isHtmlDocument) return OtzariaIcons.document_html_24_regular;
  if (book.isUserBook &&
      (format == DocumentFormat.md || format == DocumentFormat.markdown)) {
    return OtzariaIcons.document_md_24_regular;
  }
  return _plainTextIcon(book);
}

/// ספרי הספרייה הרשמית הם כולם טקסט, ולכן הפורמט אינו מבדיל ביניהם והם
/// נושאים את המסמך הגנרי. בספר אישי הפורמט הוא מידע — שם `document_alef`
/// אומר "טקסט", לצד `document_md`, `document_word` ו-`document_html`.
IconData _plainTextIcon(Book book) => book.isUserBook
    ? OtzariaIcons.document_alef_24_regular
    : FluentIcons.document_text_24_regular;

/// אייקון הספר ברשימות הספרייה. ספר שיש לו מהדורות נוספות לבחירה מקבל את
/// `document_multiple` במקום אייקון הפורמט — אותה בדיקה בדיוק שמציגה לו את
/// פריט "גרסאות" בתפריט השורה, כך שהאייקון והתפריט לעולם אינם סותרים.
///
/// תוצאה חיובית נשמרת לכל מופע ספר; שלילית נבדקת שוב בבנייה מחדש,
/// כי גם כשל זמני במסד מחזיר false.
class BookFormatIcon extends StatefulWidget {
  const BookFormatIcon({
    super.key,
    required this.book,
    this.color,
    this.size,
  });

  final Book book;
  final Color? color;
  final double? size;

  @override
  State<BookFormatIcon> createState() => _BookFormatIconState();
}

class _BookFormatIconState extends State<BookFormatIcon> {
  bool? _loadedVersions;
  late Future<bool> _hasVersions = _loadVersions();

  Future<bool> _loadVersions() {
    _loadedVersions = null;
    late final Future<bool> future;
    future = hasBookVersionsToOpen(widget.book).then((hasVersions) {
      if (identical(_hasVersions, future)) _loadedVersions = hasVersions;
      return hasVersions;
    });
    return future;
  }

  @override
  void didUpdateWidget(BookFormatIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.book, widget.book) || _loadedVersions == false) {
      _hasVersions = _loadVersions();
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      key: ObjectKey(widget.book),
      future: _hasVersions,
      builder: (context, snapshot) {
        final icon = snapshot.data == true
            ? FluentIcons.document_multiple_24_regular
            : bookFormatIcon(widget.book);
        return Icon(icon, color: widget.color, size: widget.size);
      },
    );
  }
}
