import 'dart:math';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:otzaria/pdf_book/utils/pdf_render_scale.dart';
import 'package:otzaria/pdf_book/utils/pdf_spread_layout.dart';
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
      : const PdfViewerSizeDelegateProviderSmart(
          maxScale: 20,
          smartMaxScale: 20,
          maxPagesVisible: 1,
        );
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
