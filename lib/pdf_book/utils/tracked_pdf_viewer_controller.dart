import 'package:flutter/widgets.dart';
import 'package:pdfrx/pdfrx.dart';

/// [PdfViewerController] שמבדיל בין שינויי פריסה פנימיים לבין פקודות ניווט
/// מפורשות. כך תיקון פתיחה מושהה יכול להיפסל גם כשפקודת הניווט הגיעה מרכיב
/// אחר שמחזיק את אותו controller.
class TrackedPdfViewerController extends PdfViewerController {
  int _programmaticNavigationGeneration = 0;

  int get programmaticNavigationGeneration => _programmaticNavigationGeneration;

  void _recordProgrammaticNavigation() {
    _programmaticNavigationGeneration++;
  }

  @override
  set value(Matrix4 newValue) {
    _recordProgrammaticNavigation();
    super.value = newValue;
  }

  @override
  Future<void> goToArea({
    required Rect rect,
    PdfPageAnchor? anchor,
    Duration duration = const Duration(milliseconds: 200),
  }) {
    _recordProgrammaticNavigation();
    return super.goToArea(rect: rect, anchor: anchor, duration: duration);
  }

  @override
  Future<void> goToPage({
    required int pageNumber,
    PdfPageAnchor? anchor,
    Duration duration = const Duration(milliseconds: 200),
  }) {
    _recordProgrammaticNavigation();
    return super.goToPage(
      pageNumber: pageNumber,
      anchor: anchor,
      duration: duration,
    );
  }

  @override
  Future<void> goToRectInsidePage({
    required int pageNumber,
    required PdfRect rect,
    PdfPageAnchor? anchor,
    Duration duration = const Duration(milliseconds: 200),
  }) {
    _recordProgrammaticNavigation();
    return super.goToRectInsidePage(
      pageNumber: pageNumber,
      rect: rect,
      anchor: anchor,
      duration: duration,
    );
  }

  @override
  Future<void> goToPosition({
    required Offset documentOffset,
    double? zoom,
    Duration duration = Duration.zero,
  }) {
    _recordProgrammaticNavigation();
    return super.goToPosition(
      documentOffset: documentOffset,
      zoom: zoom,
      duration: duration,
    );
  }

  @override
  Future<bool> goToDest(
    PdfDest? dest, {
    Duration duration = const Duration(milliseconds: 200),
  }) {
    _recordProgrammaticNavigation();
    return super.goToDest(dest, duration: duration);
  }

  @override
  Future<void> goTo(
    Matrix4? destination, {
    Duration duration = const Duration(milliseconds: 200),
  }) {
    _recordProgrammaticNavigation();
    return super.goTo(destination, duration: duration);
  }

  @override
  Future<void> ensureVisible(
    Rect rect, {
    Duration duration = const Duration(milliseconds: 200),
    double margin = 0,
  }) {
    _recordProgrammaticNavigation();
    return super.ensureVisible(rect, duration: duration, margin: margin);
  }

  @override
  Future<void> setZoom(
    Offset position,
    double zoom, {
    Duration duration = const Duration(milliseconds: 200),
  }) {
    _recordProgrammaticNavigation();
    return super.setZoom(position, zoom, duration: duration);
  }

  @override
  Future<void> zoomUp({
    bool loop = false,
    Offset? zoomCenter,
    Duration duration = const Duration(milliseconds: 200),
  }) {
    _recordProgrammaticNavigation();
    return super.zoomUp(
      loop: loop,
      zoomCenter: zoomCenter,
      duration: duration,
    );
  }

  @override
  Future<void> zoomDown({
    bool loop = false,
    Offset? zoomCenter,
    Duration duration = const Duration(milliseconds: 200),
  }) {
    _recordProgrammaticNavigation();
    return super.zoomDown(
      loop: loop,
      zoomCenter: zoomCenter,
      duration: duration,
    );
  }

  @override
  Future<void> zoomOnLocalPosition({
    required Offset localPosition,
    required double newZoom,
    Duration duration = const Duration(milliseconds: 200),
  }) {
    _recordProgrammaticNavigation();
    return super.zoomOnLocalPosition(
      localPosition: localPosition,
      newZoom: newZoom,
      duration: duration,
    );
  }

  @override
  Future<void> zoomUpOnLocalPosition({
    required Offset localPosition,
    bool loop = false,
    Duration duration = const Duration(milliseconds: 200),
  }) {
    _recordProgrammaticNavigation();
    return super.zoomUpOnLocalPosition(
      localPosition: localPosition,
      loop: loop,
      duration: duration,
    );
  }

  @override
  Future<void> zoomDownOnLocalPosition({
    required Offset localPosition,
    bool loop = false,
    Duration duration = const Duration(milliseconds: 200),
  }) {
    _recordProgrammaticNavigation();
    return super.zoomDownOnLocalPosition(
      localPosition: localPosition,
      loop: loop,
      duration: duration,
    );
  }
}
