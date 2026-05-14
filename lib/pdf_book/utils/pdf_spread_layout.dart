/// עוזרים טהורים לחישוב טווח עמודי ספירייד בתצוגת PDF.
library;

/// מחזיר את עמוד ההתחלה של הספירייד שמכיל את [pageNumber].
/// עמוד 1 עומד לבדו (כריכה ימנית בעברית); שאר העמודים מצומדים בזוגות —
/// (2,3), (4,5), וכן הלאה.
int pdfSpreadStartPage(int pageNumber) {
  if (pageNumber <= 1) return 1;
  return pageNumber.isEven ? pageNumber : pageNumber - 1;
}

/// מחזיר את טווח עמודי הספירייד עבור עמוד נתון:
/// [startPage] (כולל) ו-[endPageExclusive] (לא כולל).
///
/// בתצוגה רגילה ([bookView] = false) — תמיד עמוד אחד.
/// בתצוגת ספר ([bookView] = true) — שני עמודים, למעט עמוד 1 העומד לבדו.
///
/// כש-[totalPages] מסופק, [endPageExclusive] מוגבל ל-[totalPages] + 1 —
/// כך שספירייד אחרון במסמך עם מספר עמודים זוגי לא יפנה לעמוד שאינו קיים.
({int startPage, int endPageExclusive}) pdfSpreadPageRange(
  int pageNumber, {
  required bool bookView,
  int? totalPages,
}) {
  final int startPage;
  final int rawEnd;
  if (!bookView) {
    startPage = pageNumber;
    rawEnd = pageNumber + 1;
  } else {
    startPage = pdfSpreadStartPage(pageNumber);
    rawEnd = startPage == 1 ? 2 : startPage + 2;
  }
  if (totalPages == null) {
    return (startPage: startPage, endPageExclusive: rawEnd);
  }
  final maxExclusive = totalPages + 1;
  final endExclusive = rawEnd > maxExclusive ? maxExclusive : rawEnd;
  return (startPage: startPage, endPageExclusive: endExclusive);
}

/// משלב שתי כותרות לכותרת תצוגה אחת.
/// אם אחת ריקה — מחזיר את השנייה. אם הן זהות — מחזיר אחת.
/// אחרת — משלב עם מקף ארוך.
String pdfCombineSpreadTitles(String first, String second) {
  if (first.isEmpty) return second;
  if (second.isEmpty || second == first) return first;
  return '$first — $second';
}
