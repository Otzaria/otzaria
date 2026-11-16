import 'dart:math' as math;

/// קנה המידה של תמונת התצוגה המקדימה של עמוד: הרזולוציה המוצגת בפועל,
/// מעוגלת למעלה לחזקת 2 כדי ששינוי זום קטן לא ירנדר מחדש את כל העמודים.
///
/// [displayScale] - פיקסלים פיזיים לנקודת PDF כפי שהעמוד מוצג כעת.
/// [threshold] - התקרה של pdfrx; מעליה pdfrx משלים אריחים חדים לאזור הנראה.
/// [sizeThreshold] - כמו ב-pdfrx: עמוד שצלע שלו ארוכה מזה מוגבל לצלע זו בפיקסלים.
double pdfPreviewRenderingScale({
  required double displayScale,
  required double threshold,
  required double pageWidth,
  required double pageHeight,
  required double sizeThreshold,
}) {
  final longestEdge = math.max(pageWidth, pageHeight);
  final cap = longestEdge > sizeThreshold
      ? sizeThreshold / longestEdge
      : threshold;
  if (!displayScale.isFinite || displayScale <= 0) return cap;
  final quantized = math
      .pow(2, (math.log(displayScale) / math.ln2).ceil())
      .toDouble();
  return math.min(quantized, cap);
}

/// טווח המטמון האנכי של pdfrx, בגובהי מסך: העמוד הבא והקודם בטווח מכל מקום
/// בעמוד, גם כשהוא גבוה מהמסך. מעוגל לחצאים כדי שגלילה לא תבנה את הצפיין מחדש.
double pdfVerticalCacheExtent({
  required double pageStride,
  required double visibleHeight,
}) {
  if (!pageStride.isFinite || !visibleHeight.isFinite) return 1;
  if (pageStride <= 0 || visibleHeight <= 0) return 1;
  final extent = pageStride / visibleHeight - 1;
  // נגיעה בגבול העמוד הבא אינה חפיפה, ולכן נדרשת המדרגה שמעליו.
  return math.max(1.0, ((extent * 2).floor() + 1) / 2);
}
