/// מודל קישור מרכזי
library;

import 'link_types.dart';

/// מחלקה לייצוג קישור לספר באוצריא
class BookLink {
  /// שם הספר
  final String bookTitle;
  
  /// סוג הקישור
  final LinkType type;
  
  /// מספר עמוד (לPDF) או אינדקס (לטקסט)
  final int? position;
  
  /// טקסט להדגשה
  final String? highlightText;
  
  /// הדגשת כל המקטע
  final bool fullSectionHighlight;
  
  /// כותרת ספציפית (לקישורי book://)
  final String? header;
  
  /// נתיב מדויק לקובץ (לקישורי inline)
  final String? filePath;
  
  /// הפניה או תיאור
  final String? reference;
  
  /// פרמטרים נוספים
  final Map<String, String> params;

  const BookLink({
    required this.bookTitle,
    required this.type,
    this.position,
    this.highlightText,
    this.fullSectionHighlight = false,
    this.header,
    this.filePath,
    this.reference,
    this.params = const {},
  });

  /// יצירת קישור לספר טקסט
  factory BookLink.textBook(
    String title, {
    int? index,
    String? highlightText,
    bool fullSectionHighlight = false,
    Map<String, String>? params,
  }) {
    return BookLink(
      bookTitle: title,
      type: LinkType.textBook,
      position: index,
      highlightText: highlightText,
      fullSectionHighlight: fullSectionHighlight,
      params: params ?? {},
    );
  }

  /// יצירת קישור לספר PDF
  factory BookLink.pdfBook(
    String title, {
    int? page,
    Map<String, String>? params,
  }) {
    return BookLink(
      bookTitle: title,
      type: LinkType.pdfBook,
      position: page,
      params: params ?? {},
    );
  }

  /// יצירת קישור פשוט
  factory BookLink.simple(
    String title, {
    String? header,
  }) {
    return BookLink(
      bookTitle: title,
      type: LinkType.simpleBook,
      header: header,
    );
  }

  /// יצירת קישור פנימי
  factory BookLink.internal(String header) {
    return BookLink(
      bookTitle: '',
      type: LinkType.internal,
      header: header,
    );
  }

  /// יצירת קישור inline
  factory BookLink.inline(
    String title, {
    required String filePath,
    int? index,
    String? reference,
  }) {
    return BookLink(
      bookTitle: title,
      type: LinkType.inlineLink,
      position: index,
      filePath: filePath,
      reference: reference,
    );
  }

  /// יצירת קישור חיצוני
  factory BookLink.external(String url) {
    return BookLink(
      bookTitle: url,
      type: LinkType.external,
    );
  }

  /// העתקה עם שינויים
  BookLink copyWith({
    String? bookTitle,
    LinkType? type,
    int? position,
    String? highlightText,
    bool? fullSectionHighlight,
    String? header,
    String? filePath,
    String? reference,
    Map<String, String>? params,
  }) {
    return BookLink(
      bookTitle: bookTitle ?? this.bookTitle,
      type: type ?? this.type,
      position: position ?? this.position,
      highlightText: highlightText ?? this.highlightText,
      fullSectionHighlight: fullSectionHighlight ?? this.fullSectionHighlight,
      header: header ?? this.header,
      filePath: filePath ?? this.filePath,
      reference: reference ?? this.reference,
      params: params ?? this.params,
    );
  }

  /// בדיקה אם הקישור תקין
  bool get isValid {
    switch (type) {
      case LinkType.textBook:
      case LinkType.pdfBook:
      case LinkType.simpleBook:
        return bookTitle.isNotEmpty;
      case LinkType.internal:
        return header != null && header!.isNotEmpty;
      case LinkType.inlineLink:
        return bookTitle.isNotEmpty && 
               filePath != null && 
               filePath!.isNotEmpty;
      case LinkType.external:
        return bookTitle.isNotEmpty;
    }
  }

  /// קבלת תיאור הקישור
  String get description {
    switch (type) {
      case LinkType.textBook:
        if (position != null) {
          return '$bookTitle (מקטע $position)';
        }
        return bookTitle;
      case LinkType.pdfBook:
        if (position != null) {
          return '$bookTitle (עמוד $position)';
        }
        return bookTitle;
      case LinkType.simpleBook:
        if (header != null) {
          return '$bookTitle - $header';
        }
        return bookTitle;
      case LinkType.internal:
        return header ?? '';
      case LinkType.inlineLink:
        return reference ?? bookTitle;
      case LinkType.external:
        return bookTitle;
    }
  }

  @override
  String toString() {
    return 'BookLink(title: $bookTitle, type: ${type.value}, position: $position)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is BookLink &&
        other.bookTitle == bookTitle &&
        other.type == type &&
        other.position == position &&
        other.highlightText == highlightText &&
        other.fullSectionHighlight == fullSectionHighlight &&
        other.header == header &&
        other.filePath == filePath &&
        other.reference == reference;
  }

  @override
  int get hashCode {
    return Object.hash(
      bookTitle,
      type,
      position,
      highlightText,
      fullSectionHighlight,
      header,
      filePath,
      reference,
    );
  }
}

/// תוצאת פענוח קישור
class LinkParseResult {
  /// האם הפענוח הצליח
  final bool success;
  
  /// הקישור שנוצר (אם הצליח)
  final BookLink? link;
  
  /// הודעת שגיאה (אם נכשל)
  final String? error;
  
  /// סוג התוצאה
  final ParseResult result;

  const LinkParseResult._({
    required this.success,
    this.link,
    this.error,
    required this.result,
  });
      
  /// יצירת תוצאה מוצלחת
  factory LinkParseResult.success(BookLink link) {
    return LinkParseResult._(
      success: true,
      link: link,
      result: ParseResult.success,
    );
  }
  
  /// יצירת תוצאה כושלת
  factory LinkParseResult.failure(String error, [ParseResult? result]) {
    return LinkParseResult._(
      success: false,
      error: error,
      result: result ?? ParseResult.error,
    );
  }
  
  /// יצירת תוצאה עבור URL ריק
  factory LinkParseResult.empty() {
    return LinkParseResult._(
      success: false,
      error: 'URL ריק',
      result: ParseResult.emptyUrl,
    );
  }
  
  /// יצירת תוצאה עבור פורמט לא תקין
  factory LinkParseResult.invalidFormat(String details) {
    return LinkParseResult._(
      success: false,
      error: 'פורמט לא תקין: $details',
      result: ParseResult.invalidFormat,
    );
  }
  
  /// יצירת תוצאה עבור פרמטרים חסרים
  factory LinkParseResult.missingParams(String details) {
    return LinkParseResult._(
      success: false,
      error: 'פרמטרים חסרים: $details',
      result: ParseResult.missingParameters,
    );
  }
}