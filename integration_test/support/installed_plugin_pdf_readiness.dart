import 'package:pdfrx/pdfrx.dart';

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
