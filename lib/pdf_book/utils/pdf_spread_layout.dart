/// עוזרים טהורים לחישוב טווח עמודי ספירייד בתצוגת PDF.
library;

import 'dart:ui';

/// מחזיר את מספר העמוד (1-מבוסס) שנמצא בראש חלון התצוגה.
///
/// pdfrx מחזיר כברירת מחדל את העמוד ה"הכי נראה", כך שבראש עמוד מסוים הוא
/// מדווח את הקודם (שעדיין תופס נתח גדול מהחלון). מאחר שכל עמוד הוא יחידה
/// נפרדת והעיגון הוא לראש הדף, העמוד הנוכחי הוא זה שקצהו העליון של החלון
/// נופל בתוכו. מחזיר null אם אין עמודים.
int? pdfTopmostVisiblePage(Rect visibleRect, List<Rect> pageRects) {
  if (pageRects.isEmpty) return null;
  for (var i = 0; i < pageRects.length; i++) {
    if (pageRects[i].bottom > visibleRect.top + 0.5) return i + 1;
  }
  return pageRects.length;
}

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

/// עמוד היעד של דפדוף קדימה בתצוגת ספר: העמוד הראשון (הימני) של הזוג הבא.
/// אחרי הכריכה (עמוד 1) הזוג הבא מתחיל בעמוד 2. מחזיר null כשאין זוג הבא.
int? pdfNextSpreadFocusPage(int currentPage, int totalPages) {
  final spreadStart = pdfSpreadStartPage(currentPage);
  final next = spreadStart == 1 ? 2 : spreadStart + 2;
  return next > totalPages ? null : next;
}

/// עמוד היעד של דפדוף אחורה בתצוגת ספר: העמוד השני (השמאלי) של הזוג הקודם —
/// העמוד האחרון שנקרא לפני הזוג הנוכחי. מחזיר null כשאין זוג קודם.
int? pdfPreviousSpreadFocusPage(int currentPage) {
  final spreadStart = pdfSpreadStartPage(currentPage);
  return spreadStart <= 1 ? null : spreadStart - 1;
}

/// המפריד בין שתי כותרות הספירייד בכותרת תצוגה משולבת.
const String kSpreadTitleSeparator = ' — ';

/// משלב שתי כותרות לכותרת תצוגה אחת.
/// אם אחת ריקה — מחזיר את השנייה. אם הן זהות — מחזיר אחת.
/// אחרת — משלב עם מקף ארוך.
String pdfCombineSpreadTitles(String first, String second) {
  if (first.isEmpty) return second;
  if (second.isEmpty || second == first) return first;
  return '$first$kSpreadTitleSeparator$second';
}

/// מפצל כותרת תצוגה משולבת (מ-[pdfCombineSpreadTitles]) לשני חלקיה, כשכל אחד
/// מהם כותרת הקיימת ב-[known]. עובר על כל מופעי המפריד ובוחר את הפיצול הראשון
/// ששני חלקיו מוכרים — כך כותרת ראשונה שמכילה בעצמה מקף ארוך לא מתפצלת במקום
/// הלא נכון. מחזיר null אם אין פיצול תקף (כותרת עמוד יחיד או לא מוכרת).
({String first, String second})? pdfSplitSpreadTitleByKnown(
  String combined,
  Set<String> known,
) {
  var idx = combined.indexOf(kSpreadTitleSeparator);
  while (idx >= 0) {
    final first = combined.substring(0, idx);
    final second = combined.substring(idx + kSpreadTitleSeparator.length);
    if (known.contains(first) && known.contains(second)) {
      return (first: first, second: second);
    }
    idx = combined.indexOf(kSpreadTitleSeparator, idx + 1);
  }
  return null;
}
