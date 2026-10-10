import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/pdf_book/utils/pdf_spread_layout.dart';
import 'package:otzaria/settings/services/per_book_settings_service.dart';
import 'package:pdfrx/pdfrx.dart';

/// בונה מיפוי מ-מספר עמוד ל-תווית מה-outline של ה-PDF.
/// משמש להצגת "דף ב'" במקום "2" בתפריטי בחירת טווח.
///
/// אם יותר מ-node מצביע על אותו עמוד, נשמרת התווית הראשונה (DFS).
Map<int, String> buildPdfPageLabels(List<PdfOutlineNode> outline) {
  final labels = <int, String>{};
  void traverse(List<PdfOutlineNode> nodes) {
    for (final node in nodes) {
      final page = node.dest?.pageNumber;
      if (page != null && node.title.isNotEmpty) {
        labels[page] ??= node.title;
      }
      traverse(node.children);
    }
  }

  traverse(outline);
  return labels;
}

/// מחזיר את התווית של עמוד — התווית מה-outline אם קיימת, אחרת מספר העמוד.
String labelForPdfPage(Map<int, String> labels, int pageNumber) =>
    labels[pageNumber] ?? pageNumber.toString();

/// מחשב את ה-endPage האפקטיבי להדפסת PDF.
///
/// מחזיר null כאשר אין צורך להגביל סוף — או כי לא במצב PDF, או כי
/// pdfEndPage לא נקבע (≤ 0), או כי הוא חורג מסך-העמודים הידוע.
///
/// כש-totalPdfPages הוא 0 (עדיין לא נטען המסמך) — סומכים על הערך
/// כדי לאפשר render מיידי לטווח שנבחר עוד לפני שגודל המסמך נודע.
int? computePdfPrintEndPage({
  required bool isPdfMode,
  required int pdfEndPage,
  required int totalPdfPages,
}) {
  if (!isPdfMode) return null;
  if (pdfEndPage <= 0) return null;
  if (totalPdfPages != 0 && pdfEndPage > totalPdfPages) return null;
  return pdfEndPage;
}

/// בודק אם נדרש חיתוך טווח עמודים. טווח עד העמוד האחרון [totalPages] אינו
/// חיתוך — אחרת כל PDF מוכן היה מרוסטר בפלט.
bool hasPdfPageRange({
  required int startPage,
  required int? endPage,
  int totalPages = 0,
}) {
  return startPage > 1 ||
      (endPage != null && (totalPages == 0 || endPage < totalPages));
}

/// תווית סיכום לטווח עמודי ה-PDF שנבחר; כשמאוחדים כמה עמודים בגיליון,
/// מוסיפה את מספר הגיליונות שיודפסו בפועל.
String pdfPageRangeSummary({
  required int startPage,
  required int endPage,
  required int totalPages,
  required int pagesPerSheet,
}) {
  final pages = endPage - startPage + 1;
  final base = '$pages עמודים מתוך $totalPages';
  if (pagesPerSheet <= 1) return base;
  final sheets = (pages / pagesPerSheet).ceil();
  return sheets == 1 ? '$base (גיליון אחד)' : '$base ($sheets גיליונות)';
}

/// מחזיר את עמוד-ההתחלה לטווח ההדפסה כברירת מחדל.
///
/// בתצוגה רגילה (או על העמוד הראשון) — מחזיר את העמוד הנוכחי כפי שהוא.
/// בתצוגת ספר (שני עמודים זה לצד זה), נדרש לסנכרן לתחילת ה-spread.
int resolveInitialPdfPrintPage({
  required int currentPage,
  required PdfLayoutMode layoutMode,
}) {
  if (!layoutMode.isBookView || currentPage <= 1) {
    return currentPage;
  }
  return pdfSpreadStartPage(currentPage, coverPage: layoutMode.hasCoverPage);
}

/// מחזיר את האינדקס של הכותרת האחרונה ברשימה ששורת ההתחלה שלה <= [lineIndex].
///
/// משמש לחישוב ברירת מחדל לטווח הדפסה: "מהכותרת האחרונה המוצגת עד הכותרת הבאה".
/// אם כל הכותרות מתחילות אחרי [lineIndex], או שהרשימה ריקה, מחזיר 0.
int findLastHeaderIndexAtOrBefore(List<TocEntry> headers, int lineIndex) {
  if (headers.isEmpty) return 0;
  int low = 0;
  int high = headers.length - 1;
  int result = 0;

  while (low <= high) {
    final mid = low + (high - low) ~/ 2;
    if (headers[mid].index <= lineIndex) {
      result = mid;
      low = mid + 1;
    } else {
      high = mid - 1;
    }
  }
  return result;
}

/// כותרות המשנה כרשימה שטוחה בסדר השורות, והתווית כוללת את נתיב האבות:
/// "דף א." חוזר בכל כרך של הזוהר, ובלי "כרך א, הקדמה" אי אפשר להבחין ביניהם.
List<TocEntry> buildAltHeaderEntries(
  List<({int id, int? parentId, int level, int? lineIndex, String text})> rows,
) {
  final byId = {for (final r in rows) r.id: r};
  String pathOf(
    ({int id, int? parentId, int level, int? lineIndex, String text}) r,
  ) {
    final parts = <String>[r.text];
    final seen = <int>{r.id};
    var parentId = r.parentId;
    while (parentId != null && seen.add(parentId)) {
      final parent = byId[parentId];
      if (parent == null) break;
      if (parent.text.isNotEmpty) parts.add(parent.text);
      parentId = parent.parentId;
    }
    return parts.reversed.join(', ');
  }

  final positioned = [
    for (var i = 0; i < rows.length; i++)
      if (rows[i].lineIndex != null) (order: i, row: rows[i]),
  ];
  positioned.sort((a, b) {
    final byLine = a.row.lineIndex!.compareTo(b.row.lineIndex!);
    if (byLine != 0) return byLine;
    final byLevel = a.row.level.compareTo(b.row.level);
    return byLevel != 0 ? byLevel : a.order.compareTo(b.order);
  });
  return [
    for (final p in positioned)
      TocEntry(
        text: pathOf(p.row),
        index: p.row.lineIndex!,
        level: p.row.level,
      ),
  ];
}

/// שורת הסיום (בלעדית) של סעיף הכותרת [index] ברשימה שטוחה בסדר המסמך:
/// תחילת הכותרת הבאה שרמתה אינה עמוקה יותר (כך שתתי-הכותרות נכללות), או [totalLines].
int headerSectionEndLine(List<TocEntry> headers, int index, int totalLines) {
  final level = headers[index].level;
  for (var i = index + 1; i < headers.length; i++) {
    if (headers[i].level <= level) return headers[i].index;
  }
  return totalLines;
}

/// התאמת טווח שורות שנמסר מבחוץ (למשל מתוסף) לכותרות, כדי שמסך ההדפסה יציג
/// אותו כ"מכותרת X עד כותרת Y" ולא כמספרי שורות.
///
/// `start` היא הכותרת הרדודה ביותר שמתחילה בדיוק ב-[startLine]; `end` היא
/// הכותרת הרדודה ביותר בטווח שהסעיף שלה (ראו [headerSectionEndLine]) מסתיים
/// בדיוק ב-[endLine] (בלעדי). כל אחת `null` כשאין התאמה מדויקת.
({int? start, int? end}) matchHeaderRange(
  List<TocEntry> headers,
  int startLine,
  int endLine,
  int totalLines,
) {
  int? start;
  int? end;
  for (var i = 0; i < headers.length; i++) {
    final header = headers[i];
    if (header.index == startLine &&
        (start == null || header.level < headers[start].level)) {
      start = i;
    }
    if (header.index >= startLine &&
        header.index < endLine &&
        headerSectionEndLine(headers, i, totalLines) == endLine &&
        (end == null || header.level < headers[end].level)) {
      end = i;
    }
  }
  return (start: start, end: end);
}

/// זהות התוכן והטרנספורמציות במטמון המפרשים להדפסה.
String printCommentaryContentCacheKey(
  Link link, {
  required bool removeNikud,
  required bool removeTaamim,
  required bool replaceHolyNames,
  required bool keepHtml,
}) =>
    '$removeNikud|$removeTaamim|$replaceHolyNames'
    '::${link.contentIdentityKey}::${link.heRef}::$keepHtml';

/// מספר השורות של טקסט הספר, שמור לפי זהות המחרוזת: מסך ההדפסה שואל עליו
/// בכל בנייה, ופיצול ספר שלם בכל פעם עולה עשרות מילי-שניות.
class LineCountCache {
  LineCountCache([this._countLines = _splitLineCount]);

  final int Function(String) _countLines;
  String? _source;
  int _count = 0;

  static int _splitLineCount(String text) => text.split('\n').length;

  int of(String text) {
    if (!identical(text, _source)) {
      _source = text;
      _count = _countLines(text);
    }
    return _count;
  }
}
