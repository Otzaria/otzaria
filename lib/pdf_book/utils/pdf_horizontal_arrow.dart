import 'dart:ui';

/// המרחק שנותר לגלילה אופקית בתוך העמוד, ביחידות המסמך.
double pdfHorizontalArrowTravel({
  required Rect visibleRect,
  required Rect pageRect,
  required bool towardLeft,
}) {
  const tolerance = 0.5;
  if (visibleRect.width >= pageRect.width - tolerance) return 0;
  final remaining = towardLeft
      ? visibleRect.left - pageRect.left
      : pageRect.right - visibleRect.right;
  return remaining > tolerance ? remaining : 0;
}
