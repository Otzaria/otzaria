import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:otzaria/widgets/misc/smooth_wheel_scroll.dart';
import 'package:pdfrx/pdfrx.dart';

/// delegate הגלילה הפיזיקלי של pdfrx עם אפשרות עצירה: יעד הגלילה שלו נקבע
/// ב-translation של הזום הישן, ואחרי שינוי זום הוא מזיז את המסמך (issue #1258).
class StoppablePdfScrollPhysicsProvider
    extends PdfViewerScrollInteractionDelegateProvider {
  StoppablePdfScrollPhysicsProvider({
    PdfViewerScrollInteractionDelegateProvider? inner,
  }) : inner =
           inner ??
           PdfViewerScrollInteractionDelegateProviderPhysics(
             // ברירת המחדל של pdfrx (12/שנייה) היא 250ms ל-95% מהדרך, כמעט
             // כפול מגלילת הטקסט — מעבר בין ספר ל-PDF הרגיש כשינוי מהירות.
             panFriction: SmoothWheelScroll.decayRatePerMs * 1000,
           );

  /// ה-delegate שאליו מועברת העבודה בפועל.
  final PdfViewerScrollInteractionDelegateProvider inner;
  _PdfToolbarZoomDelegate? _delegate;

  @override
  PdfViewerScrollInteractionDelegate create() =>
      _delegate = _PdfToolbarZoomDelegate(inner.create());

  /// יעד הזום של פעולת סרגל שבדרך, או null.
  double? get zoomTarget => _delegate?.zoomTarget;

  /// עוצר אנימציית גלילה/זום שבדרך; ללא delegate פעיל אין פעולה.
  void stop() => _delegate?.stop();

  /// גלילה מונפשת כמו הגלגלת, בלי מסלול הגלגלת של pdfrx שהופך Ctrl לזום.
  /// ה-delegate הפיזיקלי לא קורא את המדדים ב-pan.
  void pan(Offset delta) => _delegate?.pan(delta, _panMetrics);

  static const _panMetrics = PdfViewerLayoutMetrics(
    minScale: 1,
    maxScale: 1,
    coverScale: 1,
  );

  /// זום מונפש למיקום המסמך [center]. ללא צפיין פעיל מחזיר false.
  bool zoomTo(double zoom, Offset center) =>
      _delegate?.zoomTo(zoom, center) ?? false;

  // זהות לפי המופע: pdfrx יוצר delegate חדש בכל שינוי provider, והמסך מחזיק
  // מופע יחיד לכל חיי ה-viewer.
  @override
  bool operator ==(Object other) => identical(this, other);

  @override
  int get hashCode => identityHashCode(this);
}

class _PdfToolbarZoomDelegate implements PdfViewerScrollInteractionDelegate {
  _PdfToolbarZoomDelegate(this._inner);

  static const _duration = Duration(milliseconds: 150);
  final PdfViewerScrollInteractionDelegate _inner;
  PdfViewerController? _controller;
  TickerProvider? _vsync;
  Ticker? _zoomTicker;
  Matrix4? _lastZoomMatrix;
  double? _zoomTarget;
  bool _writingZoomMatrix = false;

  double? get zoomTarget {
    final controller = _controller;
    if (controller == null || !controller.isReady) return null;
    return _writingZoomMatrix || controller.value == _lastZoomMatrix
        ? _zoomTarget
        : null;
  }

  bool zoomTo(double zoom, Offset center) {
    final controller = _controller;
    final vsync = _vsync;
    if (controller == null || !controller.isReady || vsync == null) {
      return false;
    }
    stop();
    controller.stopInteractiveViewerAnimation();
    final begin = controller.value;
    final end = controller.makeMatrixInSafeRange(
      controller.calcMatrixFor(center, zoom: zoom),
      forceClamp: true,
    );
    if (begin == end) return true;

    final tween = Matrix4Tween(begin: begin, end: end);
    _lastZoomMatrix = begin;
    _zoomTarget = zoom;
    _zoomTicker = vsync.createTicker((elapsed) {
      if (zoomTarget == null) {
        _stopZoom();
        return;
      }
      final progress = (elapsed.inMicroseconds / _duration.inMicroseconds)
          .clamp(0.0, 1.0);
      if (progress == 0) return;
      // setZoom מאפס את טיקר הניווט של pdfrx. כתיבת מטריצה מנורמלת מאפשרת לניווט לגבור.
      _writingZoomMatrix = true;
      try {
        controller.value = tween.transform(
          Curves.easeInOut.transform(progress),
        );
      } finally {
        _writingZoomMatrix = false;
      }
      _lastZoomMatrix = controller.value;
      if (progress == 1) _stopZoom();
    })..start();
    return true;
  }

  void _stopZoom() {
    _zoomTicker?.dispose();
    _zoomTicker = null;
    _lastZoomMatrix = null;
    _zoomTarget = null;
  }

  @override
  void init(PdfViewerController controller, TickerProvider vsync) {
    _controller = controller;
    _vsync = vsync;
    _inner.init(controller, vsync);
  }

  @override
  void dispose() {
    _stopZoom();
    _controller = null;
    _vsync = null;
    _inner.dispose();
  }

  @override
  void stop() {
    _stopZoom();
    _inner.stop();
  }

  @override
  void pan(Offset delta, PdfViewerLayoutMetrics layoutMetrics) {
    _stopZoom();
    _inner.pan(delta, layoutMetrics);
  }

  @override
  void zoom(
    double scale,
    Offset focalPoint,
    PdfViewerLayoutMetrics layoutMetrics,
  ) {
    _stopZoom();
    _inner.zoom(scale, focalPoint, layoutMetrics);
  }
}
