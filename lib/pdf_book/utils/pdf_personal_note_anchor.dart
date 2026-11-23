import 'package:flutter/widgets.dart';
import 'package:otzaria/personal_notes/models/pdf_note_anchor.dart';
import 'package:pdfrx/pdfrx.dart';

/// מאתר את עמודי ה-PDF הנראים לפי הפריסה הפעילה של הצפיין.
class PdfNotePageLookup {
  PdfPageLayout? _layout;
  bool _orderedVertically = false;

  List<int> visiblePages(
    PdfPageLayout layout,
    Rect visibleRect, {
    ({int startPage, int endPageExclusive})? spread,
  }) {
    final pages = layout.pageLayouts;
    if (spread != null) {
      // בתצוגת ספר המסכה מסתירה כפולות אחרות גם כשמלבניהן נראים.
      return [
        for (
          var page = spread.startPage < 1 ? 1 : spread.startPage;
          page < spread.endPageExclusive && page <= pages.length;
          page++
        )
          if (pages[page - 1].overlaps(visibleRect)) page,
      ];
    }

    // הצפיין מחליף את מופע הפריסה כשהגאומטריה משתנה.
    if (!identical(layout, _layout)) {
      _layout = layout;
      _orderedVertically = _hasOrderedVerticalBounds(pages);
    }
    final searchVertically = _orderedVertically && visibleRect.isFinite;
    var first = 0;
    if (searchVertically) {
      var end = pages.length;
      while (first < end) {
        final middle = first + (end - first) ~/ 2;
        if (pages[middle].bottom <= visibleRect.top) {
          first = middle + 1;
        } else {
          end = middle;
        }
      }
    }

    final visible = <int>[];
    for (var index = first; index < pages.length; index++) {
      final page = pages[index];
      if (searchVertically && page.top >= visibleRect.bottom) break;
      if (page.overlaps(visibleRect)) visible.add(index + 1);
    }
    return visible;
  }

  bool _hasOrderedVerticalBounds(List<Rect> pages) {
    var previousTop = double.negativeInfinity;
    var previousBottom = double.negativeInfinity;
    for (final page in pages) {
      if (!page.top.isFinite ||
          !page.bottom.isFinite ||
          page.top < previousTop ||
          page.bottom < previousBottom) {
        return false;
      }
      previousTop = page.top;
      previousBottom = page.bottom;
    }
    return true;
  }
}

/// ממיר תוצאת hit-test של pdfrx לנקודה שאינה תלויה בזום, בפריסה או בסיבוב.
/// ממדי העמוד ב-pdfrx מסובבים, ואילו נקודת ה-hit-test היא בקואורדינטות המקור.
PdfNoteAnchor? pdfNoteAnchorFromHit(
  PdfPageHitTestResult? hit, {
  String? documentId,
}) {
  if (hit == null || !hit.page.isLoaded) return null;
  final page = hit.page;
  final swapped = page.rotation.index.isOdd;
  final width = swapped ? page.height : page.width;
  final height = swapped ? page.width : page.height;
  if (!width.isFinite || !height.isFinite || width <= 0 || height <= 0) {
    return null;
  }
  final x = hit.offset.x / width;
  final y = hit.offset.y / height;
  if (!x.isFinite || !y.isFinite) return null;
  return PdfNoteAnchor(
    pageNumber: page.pageNumber,
    x: x.clamp(0.0, 1.0),
    y: y.clamp(0.0, 1.0),
    documentId: documentId,
  );
}

/// ממיר נקודה שמורה לקואורדינטות הפריסה, כולל הסיבוב הנוכחי של העמוד.
Offset pdfNoteAnchorDocumentPosition(
  PdfNoteAnchor anchor, {
  required PdfPage page,
  required Rect pageRect,
}) {
  final swapped = page.rotation.index.isOdd;
  final width = swapped ? page.height : page.width;
  final height = swapped ? page.width : page.height;
  return PdfPoint(anchor.x * width, anchor.y * height).toOffsetInDocument(
    page: page,
    pageRect: pageRect,
  );
}

/// מרכז נקודה שמורה, בלי לשנות את הזום. ההורה מכין את נעילת הכפולה לפני הקריאה.
/// מחזיר false כשאי אפשר לנווט (מסמך נסגר, עמוד חסר או בקשה שהתיישנה).
Future<bool> navigateToPdfNoteAnchor(
  PdfViewerController controller,
  PdfNoteAnchor anchor, {
  bool Function()? isActive,
}) async {
  bool active() => controller.isReady && (isActive?.call() ?? true);
  if (!active() || anchor.pageNumber > controller.pageCount) return false;
  final document = controller.document;
  var page = controller.pages[anchor.pageNumber - 1];
  if (!page.isLoaded) {
    final loaded = await page.waitForLoaded(
      timeout: const Duration(seconds: 10),
    );
    if (loaded == null) return false;
    page = loaded;
  }
  if (!active() || !identical(controller.document, document)) return false;
  final pageLayouts = controller.layout.pageLayouts;
  if (anchor.pageNumber > pageLayouts.length) return false;
  final position = pdfNoteAnchorDocumentPosition(
    anchor,
    page: page,
    pageRect: pageLayouts[anchor.pageNumber - 1],
  );
  await controller.goTo(controller.calcMatrixFor(position));
  if (!active() || !identical(controller.document, document)) return false;
  controller.setCurrentPageNumber(anchor.pageNumber);
  return true;
}
