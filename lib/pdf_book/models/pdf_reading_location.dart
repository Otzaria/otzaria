import 'dart:ui';

import 'package:equatable/equatable.dart';
import 'package:pdfrx/pdfrx.dart';

/// עוגן קריאה בתוך עמוד, שאינו תלוי בגודל החלון או במיקום העמוד בפריסה.
class PdfReadingLocation extends Equatable {
  const PdfReadingLocation({
    required this.pageNumber,
    required this.pageOffset,
    required this.zoom,
  });

  final int pageNumber;
  final Offset pageOffset;
  final double zoom;

  static PdfReadingLocation? capture(PdfViewerController controller) {
    if (!controller.isReady) return null;
    final number = controller.pageNumber;
    final pages = controller.layout.pageLayouts;
    if (number == null || number < 1 || number > pages.length) return null;
    return PdfReadingLocation(
      pageNumber: number,
      pageOffset: controller.visibleRect.topLeft - pages[number - 1].topLeft,
      zoom: controller.currentZoom,
    );
  }

  Offset centerIn(Rect page, Size viewSize) =>
      page.topLeft +
      pageOffset +
      Offset(viewSize.width / zoom / 2, viewSize.height / zoom / 2);

  @override
  List<Object> get props => [pageNumber, pageOffset, zoom];
}

/// היסטוריית קפיצות זמנית של טאב; אינה מחזיקה מסמכים או תמונות.
class PdfLocationHistory {
  final _locations = <PdfReadingLocation>[];
  final _forward = <PdfReadingLocation>[];

  bool get canGoBack => _locations.isNotEmpty;
  bool get canGoForward => _forward.isNotEmpty;
  PdfReadingLocation? get last => _locations.lastOrNull;
  PdfReadingLocation? get next => _forward.lastOrNull;

  /// ניווט חדש: נקודת חזרה, ומסלול הקדימה מתבטל.
  void remember(PdfReadingLocation location) {
    _push(_locations, location);
    _forward.clear();
  }

  /// [current] נשמר לחזרה קדימה.
  PdfReadingLocation? takePrevious([PdfReadingLocation? current]) =>
      _travel(_locations, _forward, current);

  /// [current] נשמר לחזרה אחורה.
  PdfReadingLocation? takeNext([PdfReadingLocation? current]) =>
      _travel(_forward, _locations, current);

  static PdfReadingLocation? _travel(
    List<PdfReadingLocation> from,
    List<PdfReadingLocation> to,
    PdfReadingLocation? current,
  ) {
    if (from.isEmpty) return null;
    final target = from.removeLast();
    if (current != null && current != target) _push(to, current);
    return target;
  }

  static void _push(
    List<PdfReadingLocation> stack,
    PdfReadingLocation location,
  ) {
    if (stack.lastOrNull == location) return;
    stack.add(location);
    if (stack.length > 50) stack.removeAt(0);
  }
}
