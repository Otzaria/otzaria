/// סוגי קישורים ו-enums
library;

/// סוגי קישורים נתמכים באוצריא
enum LinkType {
  /// קישור לספר טקסט - otzaria://book/
  textBook('textBook'),
  
  /// קישור לספר PDF - otzaria://pdf/
  pdfBook('pdfBook'),
  
  /// קישור פשוט לספר - book://
  simpleBook('simpleBook'),
  
  /// קישור פנימי לכותרת - #
  internal('internal'),
  
  /// קישור מבוסס תווים - otzaria://inline-link
  inlineLink('inlineLink'),
  
  /// קישור חיצוני - http/https
  external('external');

  const LinkType(this.value);
  
  /// ערך הטקסט של סוג הקישור
  final String value;
  
  /// המרה מטקסט לסוג קישור
  static LinkType? fromString(String value) {
    for (final type in LinkType.values) {
      if (type.value == value) return type;
    }
    return null;
  }
  
  /// בדיקה אם הקישור הוא לספר
  bool get isBookLink => this == textBook || this == pdfBook || this == simpleBook;
  
  /// בדיקה אם הקישור הוא פנימי
  bool get isInternal => this == internal;
  
  /// בדיקה אם הקישור הוא חיצוני
  bool get isExternal => this == external;
}

/// תוצאת פענוח קישור
enum ParseResult {
  /// פענוח הצליח
  success,
  
  /// URL ריק
  emptyUrl,
  
  /// פורמט לא תקין
  invalidFormat,
  
  /// פרמטרים חסרים
  missingParameters,
  
  /// שגיאה כללית
  error;
  
  /// בדיקה אם הפענוח הצליח
  bool get isSuccess => this == success;
  
  /// בדיקה אם הפענוח נכשל
  bool get isFailure => this != success;
}