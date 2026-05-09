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

/// בודק אם נדרשת חיתוך טווח עמודים (startPage > 1 או endPage מוגדר).
bool hasPdfPageRange({required int startPage, required int? endPage}) {
  return startPage > 1 || endPage != null;
}

/// מחזיר את עמוד-ההתחלה לטווח ההדפסה כברירת מחדל.
///
/// בתצוגה רגילה (או על העמוד הראשון) — מחזיר את העמוד הנוכחי כפי שהוא.
/// בתצוגת ספר (שני עמודים זה לצד זה), נדרש לסנכרן לתחילת ה-spread:
/// אם currentPage זוגי — זו התחלת ה-spread, אחרת מקדימים בעמוד אחד.
int resolveInitialPdfPrintPage({
  required int currentPage,
  required PdfLayoutMode layoutMode,
}) {
  if (layoutMode != PdfLayoutMode.bookView || currentPage <= 1) {
    return currentPage;
  }
  return currentPage.isEven ? currentPage : currentPage - 1;
}
