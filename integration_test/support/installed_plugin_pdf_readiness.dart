import 'dart:async';

import 'package:otzaria/pdf_book/utils/pdf_viewer_lifecycle_policy.dart';
import 'package:pdfrx/pdfrx.dart';

/// isReady מבטיח מסמך, אך הפריסה וגודל החלון עשויים להיקבע רק בפריים הבא.
bool installedPdfLayoutReady(PdfViewerController controller, int pageNumber) {
  final layout = pdfReadyLayoutOrNull(controller);
  if (layout == null ||
      pageNumber < 1 ||
      pageNumber > layout.pageLayouts.length) {
    return false;
  }
  try {
    final size = controller.viewSize;
    return size.width.isFinite &&
        size.height.isFinite &&
        size.width > 0 &&
        size.height > 0;
  } catch (_) {
    return false;
  }
}

/// ממרכזים את יעד המדידה לפני שמחכים לציורו; עיגון top יכול להשאירו מחוץ לחלון.
Future<void> navigateInstalledPdfTarget(
  PdfViewerController controller,
  int pageNumber, {
  required Future<void> Function() nextFrame,
  required Future<void> Function(
    bool Function(),
    String, {
    required Duration timeout,
  })
  wait,
  Duration timeout = const Duration(seconds: 45),
}) async {
  final clock = Stopwatch()..start();
  Duration remaining() {
    final value = timeout - clock.elapsed;
    if (value <= Duration.zero) {
      throw TimeoutException('PDF target page $pageNumber', timeout);
    }
    return value;
  }

  await wait(
    () => installedPdfLayoutReady(controller, pageNumber),
    'PDF layout for target page $pageNumber',
    timeout: remaining(),
  );
  await controller
      .goToPage(
        pageNumber: pageNumber,
        anchor: PdfPageAnchor.center,
        duration: Duration.zero,
      )
      .timeout(
        remaining(),
        onTimeout: () => throw TimeoutException(
          'Navigation to PDF target page $pageNumber',
          timeout,
        ),
      );
  await nextFrame().timeout(remaining());
  await wait(
    () => installedPdfTargetReady(controller, pageNumber),
    'Final reader image for page $pageNumber',
    timeout: remaining(),
  );
}

/// מספר העמוד הפעיל יכול להיות של שכן; היעד עצמו חייב להיות מצויר וגלוי.
bool installedPdfTargetReady(PdfViewerController controller, int pageNumber) {
  if (!controller.isReady) return false;
  final state = controller.visibleRenderState.value;
  if (state == PdfVisibleRenderState.failed) {
    throw StateError('Reader failed to render page $pageNumber');
  }
  if (state != PdfVisibleRenderState.ready) return false;
  final pages = controller.layout.pageLayouts;
  if (pages.length < pageNumber) return false;
  return controller.visibleRect.contains(pages[pageNumber - 1].center);
}
