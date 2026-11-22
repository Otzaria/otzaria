import 'dart:async';
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

/// שומר את פריסת הספר; במסמך קשור, אירועי העמודים מייתרים סריקת מידות
/// בכל pan/zoom. בלי קישור למסמך נבדקות גם מידות שהשתנו באותו אובייקט.
class BookViewLayoutMemo {
  PdfPageLayout? _layout;
  List<Size> _sizes = const [];
  bool? _hasCover;
  double? _verticalMargin;
  PdfDocument? _document;
  StreamSubscription<PdfDocumentEvent>? _documentSubscription;
  List<PdfPage>? _checkedPages;
  int _geometryRevision = 0;
  int _checkedGeometryRevision = -1;
  bool _disposed = false;

  /// קושר את המטמון לאירועי המסמך; null מחזיר לבדיקת מידות בכל קריאה.
  void bindDocument(PdfDocument? document) {
    if (_disposed || identical(document, _document)) return;
    unawaited(_documentSubscription?.cancel());
    _document = document;
    _reset();
    _documentSubscription = document?.events.listen((event) {
      if (identical(_document, document) &&
          event is PdfDocumentPageStatusChangedEvent &&
          identical(event.document, document)) {
        _geometryRevision++;
      }
    });
  }

  PdfPageLayout layout(
    List<PdfPage> pages, {
    required bool hasCover,
    required double verticalMargin,
  }) {
    // זהות הרשימה מגינה גם כשהעמודים הוחלפו לפני מסירת האירוע האסינכרוני.
    final sameSizes =
        (_document != null &&
            identical(pages, _document!.pages) &&
            identical(pages, _checkedPages) &&
            _geometryRevision == _checkedGeometryRevision &&
            _sizes.length == pages.length) ||
        _sameSizes(pages);
    _checkedPages = pages;
    _checkedGeometryRevision = _geometryRevision;
    final cached = _layout;
    if (cached != null &&
        hasCover == _hasCover &&
        verticalMargin == _verticalMargin &&
        sameSizes) {
      return cached;
    }
    _hasCover = hasCover;
    _verticalMargin = verticalMargin;
    if (!sameSizes) {
      _sizes = [for (final page in pages) Size(page.width, page.height)];
    }
    return _layout = buildBookViewPageLayout(
      pageSizes: _sizes,
      hasCover: hasCover,
      verticalMargin: verticalMargin,
    );
  }

  bool _sameSizes(List<PdfPage> pages) {
    if (_sizes.length != pages.length) return false;
    for (var i = 0; i < pages.length; i++) {
      if (_sizes[i].width != pages[i].width ||
          _sizes[i].height != pages[i].height) {
        return false;
      }
    }
    return true;
  }

  void _reset() {
    _layout = null;
    _sizes = const [];
    _checkedPages = null;
    _geometryRevision++;
  }

  void dispose() {
    unawaited(_documentSubscription?.cancel());
    _documentSubscription = null;
    _document = null;
    _disposed = true;
    _reset();
  }
}
