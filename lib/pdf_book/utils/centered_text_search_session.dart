import 'package:pdfrx/pdfrx.dart';

/// מעבר להתאמה ממרכז אותה בתצוגה; ensureVisible של pdfrx עוצר בשולי המסך.
class CenteredTextSearchSession extends PdfTextSearchSession {
  CenteredTextSearchSession(super.controller, {super.contextLength});

  @override
  Future<void> goToMatch(PdfTextSearchResult match) async {
    final controller = this.controller;
    if (controller != null && controller.isReady) {
      final rect = controller.calcRectForRectInsidePage(
        pageNumber: match.pageNumber,
        rect: match.bounds,
      );
      await controller.goTo(controller.calcMatrixFor(rect.center));
    }
    await super.goToMatch(match);
  }
}
