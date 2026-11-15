import 'dart:ui';

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:otzaria/book_common/models/reading_history_stacks.dart';
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

  Map<String, Object> toJson() => {
    'page': pageNumber,
    'dx': pageOffset.dx,
    'dy': pageOffset.dy,
    'zoom': zoom,
  };

  static PdfReadingLocation? tryFromJson(Object? value) {
    if (value is! Map) return null;
    final page = value['page'];
    final dx = value['dx'];
    final dy = value['dy'];
    final zoom = value['zoom'];
    if (page is! int || page < 1 || dx is! num || dy is! num) return null;
    if (zoom is! num || !(zoom > 0) || !zoom.isFinite) return null;
    if (!dx.isFinite || !dy.isFinite) return null;
    return PdfReadingLocation(
      pageNumber: page,
      pageOffset: Offset(dx.toDouble(), dy.toDouble()),
      zoom: zoom.toDouble(),
    );
  }

  Offset centerIn(Rect page, Size viewSize) =>
      page.topLeft +
      pageOffset +
      Offset(viewSize.width / zoom / 2, viewSize.height / zoom / 2);

  @override
  List<Object> get props => [pageNumber, pageOffset, zoom];
}

/// היסטוריית הקפיצות של טאב; אינה מחזיקה מסמכים או תמונות.
class PdfLocationHistory extends ChangeNotifier {
  final _locations = <PdfReadingLocation>[];
  final _forward = <PdfReadingLocation>[];

  bool get canGoBack => _locations.isNotEmpty;
  bool get canGoForward => _forward.isNotEmpty;
  PdfReadingLocation? get last => _locations.lastOrNull;
  PdfReadingLocation? get next => _forward.lastOrNull;

  /// [at] — המיקום בעת השמירה; null כשאין היסטוריה.
  Map<String, Object>? toJson(PdfReadingLocation? Function() at) =>
      encodeReadingHistory(
        back: _locations,
        forward: _forward,
        at: at,
        encode: (location) => location.toJson(),
      );

  /// ראו [decodeReadingHistory].
  void restore(Object? json, {bool asNewJump = false}) {
    final stacks = decodeReadingHistory(
      json,
      PdfReadingLocation.tryFromJson,
      asNewJump: asNewJump,
    );
    if (stacks == null) return;
    _locations
      ..clear()
      ..addAll(stacks.back);
    _forward
      ..clear()
      ..addAll(stacks.forward);
    notifyListeners();
  }

  /// ניווט חדש: נקודת חזרה, ומסלול הקדימה מתבטל.
  void remember(PdfReadingLocation? location) {
    final previous = last;
    final hadForward = canGoForward;
    if (location != null) _push(_locations, location);
    _forward.clear();
    if (last != previous || hadForward) notifyListeners();
  }

  /// [current] נשמר לחזרה קדימה.
  PdfReadingLocation? takePrevious([PdfReadingLocation? current]) =>
      _travel(_locations, _forward, current);

  /// [current] נשמר לחזרה אחורה.
  PdfReadingLocation? takeNext([PdfReadingLocation? current]) =>
      _travel(_forward, _locations, current);

  PdfReadingLocation? _travel(
    List<PdfReadingLocation> from,
    List<PdfReadingLocation> to,
    PdfReadingLocation? current,
  ) {
    if (from.isEmpty) return null;
    final target = from.removeLast();
    if (current != null && current != target) _push(to, current);
    notifyListeners();
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
