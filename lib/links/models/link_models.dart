/// מודלים לייצוג קישורים באוצריא
library;

/// סוגי קישורים נתמכים
enum LinkType {
  /// קישור לספר טקסט - otzaria://book/
  textBook,
  
  /// קישור לספר PDF - otzaria://pdf/
  pdfBook,
  
  /// קישור פשוט לספר - book://
  simpleBook,
  
  /// קישור פנימי לכותרת - #
  internal,
  
  /// קישור מבוסס תווים - otzaria://inline-link
  inlineLink,
  
  /// קישור חיצוני - http/https
  external,
}

/// מחלקה לייצוג קישור לספר
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
  final Map<String, String> additionalParams;

  const BookLink({
    required this.bookTitle,
    required this.type,
    this.position,
    this.highlightText,
    this.fullSectionHighlight = false,
    this.header,
    this.filePath,
    this.reference,
    this.additionalParams = const {},
  });

  /// יצירת קישור מURL
  factory BookLink.fromUrl(String url) {
    // הטמעה תהיה ב-link_parser.dart
    throw UnimplementedError('Use LinkParser.parseUrl() instead');
  }

  /// המרה ל-URL
  String toUrl() {
    // הטמעה תהיה ב-link_generator.dart
    throw UnimplementedError('Use LinkGenerator.generateUrl() instead');
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
    Map<String, String>? additionalParams,
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
      additionalParams: additionalParams ?? this.additionalParams,
    );
  }

  @override
  String toString() {
    return 'BookLink(title: $bookTitle, type: $type, position: $position)';
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

  const LinkParseResult.success(this.link) 
      : success = true, error = null;
      
  const LinkParseResult.failure(this.error) 
      : success = false, link = null;
}