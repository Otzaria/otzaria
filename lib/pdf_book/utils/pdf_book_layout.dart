import 'dart:math';

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

/// מרווח השדרה בין שני עמודי הכפולה, ביחידות נקודות העמוד.
const double kBookViewSpineGap = 6.0;

/// פריסת הכפולות בתצוגת ספר, ביחידות נקודות העמוד.
///
/// קנה המידה הוא 1 במכוון: מלבן עמוד קטן מגודלו בנקודות גורם ל-pdfrx לרנדר
/// את הגזיר החד בקנה המידה בריבוע, והתוצאה מטושטשת (issue #1011).
@visibleForTesting
PdfPageLayout buildBookViewPageLayout({
  required List<Size> pageSizes,
  required bool hasCover,
  required double verticalMargin,
  double margin = 0.0,
}) {
  final pageLayouts = <Rect>[];
  const gap = kBookViewSpineGap;
  double totalHeight = 0;

  for (int i = 0; i < pageSizes.length; i++) {
    final current = pageSizes[i];

    if (hasCover && i == 0) {
      pageLayouts.add(
        Rect.fromLTWH(0, totalHeight, current.width, current.height),
      );
      totalHeight += current.height + verticalMargin;
      continue;
    }

    final pageIndex = hasCover ? i - 1 : i;
    if (pageIndex % 2 != 0) continue;

    final next = i + 1 < pageSizes.length ? pageSizes[i + 1] : null;
    pageLayouts.add(
      Rect.fromLTWH(
        current.width + gap,
        totalHeight,
        current.width,
        current.height,
      ),
    );

    if (next != null) {
      pageLayouts.add(Rect.fromLTWH(0, totalHeight, next.width, next.height));
      totalHeight += max(current.height, next.height) + verticalMargin;
      i++;
    } else {
      totalHeight += current.height + verticalMargin;
    }
  }

  return PdfPageLayout(
    pageLayouts: pageLayouts,
    documentSize: Size(
      pageLayouts.fold(0, (width, page) => max(width, page.right)),
      totalHeight,
    ),
    margin: margin,
    primaryAxis: Axis.vertical,
  );
}

/// יחס הפיקסלים של צילום הדפדוף: עד 1.6MP לכל החלון, ולא יותר מ-1.35.
double pdfSpreadSnapshotPixelRatio({
  required Size viewSize,
  required double devicePixelRatio,
}) {
  final viewportPixels = viewSize.width * viewSize.height;
  const maxCapturePixels = 1600000.0;
  final cappedPixelRatio = viewportPixels <= 0
      ? 1.0
      : sqrt(maxCapturePixels / viewportPixels);
  return min(devicePixelRatio, min(1.35, cappedPixelRatio));
}

/// קנה המידה לרינדור עמוד לצילום הדפדוף: מה שהצילום מצייר בפועל (בתצוגת ספר
/// מלבן העמוד = גודלו בנקודות), ולא יותר מ-1.5 — 2.0 הקריס מכונות חלשות.
/// מעוגל למעלה לחזקת 2, כדי שזום בגלגלת לא ירנדר את הכפולות מחדש בכל צעד.
double pdfSpreadPageRenderScale({
  required double zoom,
  required double snapshotPixelRatio,
}) {
  final needed = zoom * snapshotPixelRatio;
  if (!needed.isFinite || needed <= 0) return 1.5;
  return min(1.5, pow(2, (log(needed) / ln2).ceil()).toDouble());
}

/// פריסת תצוגת ספר כאסטרטגיית pdfrx; ניווט לעמוד וזום התאמה משתמשים ב-[margin].
@immutable
class BookViewLayout extends PdfPageLayoutStrategy {
  const BookViewLayout({required this.hasCover});

  /// כמו ברירת המחדל של [SequentialPagesLayout], כדי שהמעבר בין התצוגות לא ישנה זום.
  static const double margin = 8.0;

  final bool hasCover;

  @override
  PdfPageLayout resolve(PdfPageLayoutContext context) =>
      buildBookViewPageLayout(
        pageSizes: [
          for (final page in context.pages) Size(page.width, page.height),
        ],
        hasCover: hasCover,
        // המרווח הוכפל יחד עם הפריסה, לשמירת אותה פרופורציה בין כפולות.
        verticalMargin: margin * 2,
        margin: margin,
      );

  @override
  bool operator ==(Object other) =>
      other is BookViewLayout && other.hasCover == hasCover;

  @override
  int get hashCode => hasCover.hashCode;
}
