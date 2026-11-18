import 'dart:math';

import 'package:flutter/material.dart';

/// מלבן הכפולה במרחב התצוגה, בלי חיתוך לגבולותיה. גאומטריית הדפדוף נשענת
/// עליו: מרכזו הוא השדרה, וחצי מרוחבו הוא עמוד אחד.
Rect pdfSpreadTurnViewportRect(Matrix4 matrix, Rect spreadRect) =>
    MatrixUtils.transformRect(matrix, spreadRect);

/// החלק הנראה של הכפולה — למסכת התצוגה ולאזורי הגרירה, שחייבים להישאר
/// בתוך המסך. אסור להאכיל בו את גאומטריית הדפדוף: הוא מזיז את השדרה.
Rect? pdfSpreadVisibleViewportRect(
  Matrix4 matrix,
  Rect spreadRect,
  Size viewportSize,
) {
  final clippedRect = pdfSpreadTurnViewportRect(
    matrix,
    spreadRect,
  ).intersect(Offset.zero & viewportSize);
  if (clippedRect.width <= 0 || clippedRect.height <= 0) return null;
  return clippedRect;
}

/// מרכז התצוגה שמציב את [anchorDocTop] בראשה, בזום ובגובה הנתונים.
/// האופק נשאר כפי שחישבה מדיניות שינוי-הגודל של pdfrx.
Offset pdfTopAnchoredCenter({
  required double anchorDocTop,
  required Offset currentCenter,
  required Size viewSize,
  required double zoom,
}) => Offset(currentCenter.dx, anchorDocTop + viewSize.height / 2 / zoom);

/// עוגן חד־פעמי לשימור קו הראש בעת שינוי רוחב קורא ה-PDF.
class PdfPaneToggleAnchor {
  double? _docTop;
  Size? _viewSize;

  /// מכין עוגן לשינוי רוחב אמיתי, או מנקה עוגן קודם כשהחלונית היא overlay.
  void prepare({
    required bool changesReaderWidth,
    double? docTop,
    Size? viewSize,
  }) {
    _docTop = null;
    _viewSize = null;
    if (!changesReaderWidth || docTop == null || viewSize == null) return;
    _docTop = docTop;
    _viewSize = viewSize;
  }

  /// צורך את העוגן פעם אחת ומחזיר אותו רק לשינוי הרוחב התואם.
  double? consume({
    required Size? oldViewSize,
    required Size newViewSize,
    required bool isBookView,
  }) {
    final docTop = _docTop;
    final capturedViewSize = _viewSize;
    _docTop = null;
    _viewSize = null;
    if (docTop == null ||
        oldViewSize != capturedViewSize ||
        isBookView ||
        oldViewSize!.width == newViewSize.width) {
      return null;
    }
    return docTop;
  }
}

/// זום ההתאמה לרוחב ולעמוד שלם של [shown] — העמוד, או הכפולה בתצוגת ספר.
({double width, double page}) pdfFitZooms({
  required Rect shown,
  required Size viewSize,
  required double margin,
}) {
  final width = (viewSize.width - margin * 2) / shown.width;
  final height = (viewSize.height - margin * 2) / shown.height;
  return (width: width, page: min(width, height));
}

/// המתג עובר לעמוד שלם כשהתצוגה כבר מותאמת לרוחב, ולרוחב בכל מצב אחר.
bool pdfNextFitIsPage({required double zoom, required double widthZoom}) =>
    (zoom - widthZoom).abs() <= widthZoom * 0.01;
