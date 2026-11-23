import 'dart:ui';

/// האם חץ אופקי גולל בתוך המסמך במקום לדפדף: רק כשהמסמך רחב מהתצוגה ונותר
/// בו תוכן מוסתר לכיוון החץ. בקצה, או כשהעמוד נכנס ברוחב, החץ מדפדף.
bool pdfArrowPansHorizontally({
  required Rect visibleRect,
  required double documentWidth,
  required bool towardLeft,
}) {
  // סטייה של פחות מנקודה אחת היא שארית עיגול, לא תוכן מוסתר.
  const tolerance = 0.5;
  if (visibleRect.width >= documentWidth - tolerance) return false;
  return towardLeft
      ? visibleRect.left > tolerance
      : visibleRect.right < documentWidth - tolerance;
}
