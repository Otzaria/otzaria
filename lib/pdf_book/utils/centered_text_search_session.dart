import 'package:pdfrx/pdfrx.dart';

/// ממרכז התאמה באנימציה אחת, תוך שימור הבחירה וניהול הדור של pdfrx.
class CenteredTextSearchSession extends PdfTextSearchSession {
  CenteredTextSearchSession(super.controller, {super.contextLength})
    : super(onNavigateToMatch: _centerMatch);

  static Future<void> _centerMatch(
    PdfViewerController controller,
    PdfTextSearchResult match,
  ) {
    final rect = controller.calcRectForRectInsidePage(
      pageNumber: match.pageNumber,
      rect: match.bounds,
    );
    return controller.goTo(controller.calcMatrixFor(rect.center));
  }
}
