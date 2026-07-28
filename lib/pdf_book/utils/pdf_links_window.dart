/// מדיניות "חלון הקישורים" של תצוגת PDF: במקום להחזיק את כל קישורי הספר
/// בזיכרון, נטען רק חלון שורות נדיב סביב המיקום הנוכחי, ומתרענן לפני
/// שהמשתמש מגיע לקצה שלו (prefetch) כדי שדפדוף רגיל לעולם לא ימתין ל-DB.
class PdfLinksWindowPolicy {
  PdfLinksWindowPolicy._();

  /// כמה שורות טקסט נטענות מעבר לטווח הנוכחי לכל כיוון.
  /// החלון מכסה עמודים סמוכים בלי לממש עשרות אלפי קישורים מראש.
  static const int marginLines = 100;

  /// מרחק ההתראה מקצה החלון: כשהטווח הנוכחי מתקרב לקצה עד כדי ערך זה,
  /// נטען חלון חדש ברקע עוד לפני שהמשתמש חוצה אותו.
  static const int slackLines = 50;

  /// מחזיר את גבולות החלון החדש (1-based, כולל) אם נדרשת טעינה,
  /// או null אם החלון הטעון עדיין מכסה את הטווח הנוכחי במרווח בטוח.
  static ({int startLine, int endLine})? nextWindow({
    required int rangeStart,
    required int rangeEnd,
    int? loadedStart,
    int? loadedEnd,
  }) {
    final neededStart = rangeStart - slackLines;
    final neededEnd = rangeEnd + slackLines;
    final covered =
        loadedStart != null &&
        loadedEnd != null &&
        (neededStart < 1 ? 1 : neededStart) >= loadedStart &&
        neededEnd <= loadedEnd;
    if (covered) return null;

    final startLine = rangeStart - marginLines;
    return (
      startLine: startLine < 1 ? 1 : startLine,
      endLine: rangeEnd + marginLines,
    );
  }
}
