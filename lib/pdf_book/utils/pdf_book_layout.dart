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

  static final _layouts =
      Expando<Map<bool, ({List<Size> sizes, PdfPageLayout layout})>>();

  /// כמו ברירת המחדל של [SequentialPagesLayout], כדי שהמעבר בין התצוגות לא ישנה זום.
  static const double margin = 8.0;

  final bool hasCover;

  @override
  PdfPageLayout resolve(PdfPageLayoutContext context) {
    final pages = context.pages;
    // טעינה הדרגתית עשויה להחליף את רשימת העמודים של אותו מסמך.
    final layouts = pages.isEmpty
        ? null
        : (_layouts[pages.first.document] ??= {});
    final cached = layouts?[hasCover];
    final sizes = _readSizes(pages, cached?.sizes);
    if (cached != null && identical(sizes, cached.sizes)) return cached.layout;

    final layout = buildBookViewPageLayout(
      pageSizes: sizes,
      hasCover: hasCover,
      verticalMargin: margin * 2,
      margin: margin,
    );
    layouts?[hasCover] = (sizes: sizes, layout: layout);
    return layout;
  }

  static List<Size> _readSizes(List<PdfPage> pages, List<Size>? previous) {
    if (previous == null || previous.length != pages.length) {
      return [for (final page in pages) Size(page.width, page.height)];
    }
    List<Size>? updated;
    for (var i = 0; i < pages.length; i++) {
      final page = pages[i];
      final width = page.width;
      final height = page.height;
      final size = previous[i];
      if (width == size.width && height == size.height) continue;
      updated ??= List.of(previous, growable: false);
      updated[i] = Size(width, height);
    }
    return updated ?? previous;
  }

  @override
  bool operator ==(Object other) =>
      other is BookViewLayout && other.hasCover == hasCover;

  @override
  int get hashCode => hasCover.hashCode;
}
