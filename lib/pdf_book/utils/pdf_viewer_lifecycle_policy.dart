import 'dart:math';

import 'package:otzaria/pdf_book/bloc/pdf_book_state.dart';
import 'package:otzaria/settings/services/per_book_settings_service.dart';
import 'package:pdfrx/pdfrx.dart';

/// הצופה נשאר מחובר כדי שפתיחה איטית תוכל להסתיים גם אחרי הצגת שגיאה.
/// ניסיון חוזר אוטומטי דורש בנייה מחדש.
bool pdfViewerStaysMountedFor(PdfBookState state) =>
    !(state is PdfBookError && state.autoRetry);

/// טווח השורות מכסה כפולה בתצוגת ספר ועמוד בתצוגה רגילה.
/// מחשבים אותו מחדש רק במעבר בין המצבים אחרי האתחול.
bool shouldRecomputeLineRangeOnLayoutModeChange(
  PdfLayoutMode? previous,
  PdfLayoutMode current,
) {
  return previous != null && previous != current;
}

/// האם דפדוף חדש מבטל את הדפדופים הממתינים בתור: לחיצה בכיוון ההפוך
/// לממתינים מרוקנת אותם, כך שהאנימציה שבאוויר מסיימת והבאה הפוכה ממנה.
bool shouldDropPendingPageTurns<T>({
  required Iterable<T> pendingDirections,
  required T incomingDirection,
}) {
  return pendingDirections.any((d) => d != incomingDirection);
}

/// משך דפדוף כשממתינים [pendingTurns] נוספים בתור: 1/(n+1) מהמשך הבודד, כך
/// שתור של לחיצות מהירות מתקצר ככל שהוא ארוך יותר.
Duration pdfQueuedPageTurnDuration(Duration single, int pendingTurns) =>
    Duration(microseconds: single.inMicroseconds ~/ (max(0, pendingTurns) + 1));

/// קוראת את מספר העמוד רק כשהבקר מחובר.
/// גישה ל-`pageNumber` בבקר שהתנתק זורקת חריגה.
int? resolveReadyPdfPageNumber({
  required bool isReady,
  required int? Function() readPageNumber,
}) {
  return isReady ? readPageNumber() : null;
}

/// ה-layout של [controller], או null אם עוד לא חושב: ב-pdfrx `isReady` נעשה
/// true לפני חישוב ה-layout, ו-`controller.layout` זורק בחלון הזה.
PdfPageLayout? pdfReadyLayoutOrNull(PdfViewerController controller) {
  if (!controller.isReady) return null;
  try {
    return controller.layout;
  } catch (_) {
    return null;
  }
}
