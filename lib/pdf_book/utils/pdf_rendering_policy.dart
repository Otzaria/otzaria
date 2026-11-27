import 'dart:math';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:otzaria/pdf_book/utils/pdf_render_scale.dart';
import 'package:otzaria/pdf_book/utils/pdf_spread_layout.dart';
import 'package:otzaria/pdf_book/utils/pdf_viewport_geometry.dart';
import 'package:otzaria/settings/services/per_book_settings_service.dart';
import 'package:otzaria/shortcuts/shortcut_helper.dart';
import 'package:otzaria/shortcuts/shortcut_validator.dart';
import 'package:pdfrx/pdfrx.dart';

/// תקציב מטמון התמונות של טאב PDF, המתחלק בין חלוניותיו.
const int kPdfImageCacheBudgetBytes = 48 * 1024 * 1024;

/// חלקו של צפיין בתקציב הטאב; חלוניות טקסט אינן נספרות.
int pdfImageCacheBytesForPanes(int pdfPaneCount) =>
    kPdfImageCacheBudgetBytes ~/ max(1, pdfPaneCount);

/// קנה המידה של תמונת התצוגה המקדימה לפי הזום הנוכחי; ראה [pdfPreviewRenderingScale].
double pdfPreviewRenderingScaleFor(
  BuildContext context,
  PdfPage page,
  PdfViewerController controller,
  double estimatedScale,
) {
  final pageRect = controller.layout.pageLayouts[page.pageNumber - 1];
  final displayScale = page.width > 0
      ? controller.currentZoom *
            MediaQuery.devicePixelRatioOf(context) *
            pageRect.width /
            page.width
      : 0.0;
  return pdfPreviewRenderingScale(
    displayScale: displayScale,
    threshold: estimatedScale,
    pageWidth: page.width,
    pageHeight: page.height,
    // ברירת המחדל של onePassRenderingSizeThreshold ב-pdfrx.
    sizeThreshold: 2000,
  );
}

/// הסמל והכיתוב לפעולת ההתאמה הבאה, כולל הקיצור אם הוגדר.
({IconData icon, String tooltip}) pdfFitButtonVisual({
  required bool nextIsPage,
}) {
  final label = nextIsPage ? 'התאם לעמוד שלם' : 'התאם לרוחב';
  final shortcut = ShortcutValidator.getShortcutValue(
    ShortcutValidator.fitPdfViewKey,
  );
  return (
    icon: nextIsPage
        ? FluentIcons.arrow_autofit_height_24_regular
        : FluentIcons.arrow_autofit_width_24_regular,
    tooltip: shortcut == null || shortcut.isEmpty
        ? label
        : '$label (${ShortcutHelper.formatShortcutForDisplay(shortcut)})',
  );
}

/// מחזיר את מדיניות שינוי גודל ה-PDF לפי מצב התצוגה.
PdfViewerSizeDelegateProvider pdfSizeDelegateProviderForLayoutMode(
  PdfLayoutMode layoutMode,
) {
  return layoutMode.isBookView
      ? const PdfViewerSizeDelegateProviderLegacy(maxScale: 20)
      : _regularPdfSizeDelegate;
}

const _regularPdfSizeDelegate = PdfViewerSizeDelegateProviderSmart(
  maxScale: 20,
  smartMaxScale: 20,
  maxPagesVisible: 1,
);

/// שומר על ראש עמוד הפתיחה בזמן שהחלונית המוצמדת דוחקת את הקורא.
class PdfOpeningNavPaneSizeDelegateProvider
    extends PdfViewerSizeDelegateProvider {
  ({int pageIndex, double finalWidth, bool Function() isOpening})? _opening;

  /// עיגון זמני עד שרוחב הקורא מגיע לרוחב הסופי.
  void preserveOpeningPage({
    required int pageNumber,
    required double finalWidth,
    required bool Function() isOpening,
  }) {
    _opening = (
      pageIndex: pageNumber - 1,
      finalWidth: finalWidth,
      isOpening: isOpening,
    );
  }

  /// מפסיק את העיגון כשהפתיחה נקטעת.
  void cancel() => _opening = null;

  @override
  PdfViewerSizeDelegate create() => _OpeningNavPaneSizeDelegate(this);
}

class _OpeningNavPaneSizeDelegate extends PdfViewerSizeDelegateSmart {
  _OpeningNavPaneSizeDelegate(this.provider)
    : super(
        smartMaxScale: _regularPdfSizeDelegate.smartMaxScale,
        maxScale: _regularPdfSizeDelegate.maxScale,
        minScale: _regularPdfSizeDelegate.minScale,
        maxPagesVisible: _regularPdfSizeDelegate.maxPagesVisible,
        onePassRenderingScaleThreshold:
            _regularPdfSizeDelegate.onePassRenderingScaleThreshold,
      );

  final PdfOpeningNavPaneSizeDelegateProvider provider;
  late PdfViewerController _controller;

  @override
  void init(PdfViewerController controller) {
    super.init(controller);
    _controller = controller;
  }

  @override
  void onLayoutUpdate({
    required PdfViewerLayoutSnapshot oldState,
    required PdfViewerLayoutSnapshot newState,
    required double currentZoom,
    required Rect oldVisibleRect,
    required int? anchorPageNumber,
    required bool isLayoutChanged,
    required bool isViewSizeChanged,
  }) {
    final opening = provider._opening;
    final pages = oldState.layout?.pageLayouts;
    final oldWidth = oldState.viewSize.width;
    final newWidth = newState.viewSize.width;
    const tolerance = 0.1;
    final preserveTop =
        opening != null &&
        oldWidth != newWidth &&
        opening.isOpening() &&
        newWidth < oldWidth &&
        newWidth >= opening.finalWidth - tolerance &&
        pages != null &&
        opening.pageIndex < pages.length &&
        (pages[opening.pageIndex].top - oldVisibleRect.top).abs() < tolerance;
    if (opening != null &&
        oldWidth != newWidth &&
        (!preserveTop || newWidth <= opening.finalWidth + tolerance)) {
      provider.cancel();
    }
    // callback שינוי רוחב רץ ב־microtask; ניווט שכבר השתמש ברוחב החדש גובר.
    if (preserveTop &&
        _controller.value.calcVisibleRect(oldState.viewSize) !=
            oldVisibleRect) {
      provider.cancel();
      return;
    }
    super.onLayoutUpdate(
      oldState: oldState,
      newState: newState,
      currentZoom: currentZoom,
      oldVisibleRect: oldVisibleRect,
      anchorPageNumber: anchorPageNumber,
      isLayoutChanged: isLayoutChanged,
      isViewSizeChanged: isViewSizeChanged,
    );
    if (preserveTop &&
        !isLayoutChanged &&
        (_controller.visibleRect.top - oldVisibleRect.top).abs() > 0.001) {
      _controller.value = _controller.calcMatrixFor(
        pdfTopAnchoredCenter(
          anchorDocTop: oldVisibleRect.top,
          currentCenter: _controller.centerPosition,
          viewSize: newState.viewSize,
          zoom: _controller.currentZoom,
        ),
      );
    }
  }
}

/// העמוד הנוכחי: בתצוגה רגילה זה שבראש החלון, ובתצוגת ספר הכפולה שבמרכזו —
/// כפולה נמוכה מהחלון ממורכזת בו, וראש החלון נופל אז בכפולה הקודמת.
PdfViewerCalculateCurrentPageNumberFunction pdfCurrentPageCalculatorFor(
  PdfLayoutMode layoutMode,
) => layoutMode.isBookView
    ? (visibleRect, pageRects, controller) => pdfTopmostVisiblePage(
        Rect.fromLTWH(
          visibleRect.left,
          visibleRect.center.dy,
          visibleRect.width,
          0,
        ),
        pageRects,
      )
    : (visibleRect, pageRects, controller) =>
          pdfTopmostVisiblePage(visibleRect, pageRects);
