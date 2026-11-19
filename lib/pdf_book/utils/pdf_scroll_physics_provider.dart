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
             zoomFriction: SmoothWheelScroll.decayRatePerMs * 1000,
           );

  /// ה-delegate שאליו מועברת העבודה בפועל.
  final PdfViewerScrollInteractionDelegateProvider inner;
  _ZoomTargetTracker? _delegate;

  @override
  PdfViewerScrollInteractionDelegate create() =>
      _delegate = _ZoomTargetTracker(inner.create());

  /// יעד הזום של אנימציה שבדרך (מכפתור או מ-Ctrl+גלגלת), או null.
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

  /// זום מונפש ל-[zoom] סביב [localFocalPoint], באותה החלקה כמו Ctrl+גלגלת.
  /// ה-delegate מכפיל את היעד שבדרך, ולכן המקדם נמדד ממנו ולא מהזום הנוכחי.
  void zoomTo(
    double zoom,
    Offset localFocalPoint,
    PdfViewerController controller,
  ) {
    final delegate = _delegate;
    if (delegate == null || !controller.isReady) return;
    delegate.zoom(
      zoom / (delegate.zoomTarget ?? controller.currentZoom),
      localFocalPoint,
      PdfViewerLayoutMetrics(
        minScale: controller.minScale,
        maxScale: controller.maxScale,
        coverScale: controller.coverScale,
        alternativeFitScale: controller.alternativeFitScale,
      ),
    );
  }

  // זהות לפי המופע: pdfrx יוצר delegate חדש בכל שינוי provider, והמסך מחזיק
  // מופע יחיד לכל חיי ה-viewer.
  @override
  bool operator ==(Object other) => identical(this, other);

  @override
  int get hashCode => identityHashCode(this);
}

/// עוקב אחרי יעד הזום שה-delegate הפיזיקלי צובר; היעד שלו עצמו פרטי.
class _ZoomTargetTracker implements PdfViewerScrollInteractionDelegate {
  _ZoomTargetTracker(this._inner);

  final PdfViewerScrollInteractionDelegate _inner;
  PdfViewerController? _controller;
  double? _zoomTarget;

  double? get zoomTarget {
    final controller = _controller;
    final target = _zoomTarget;
    if (controller == null || target == null || !controller.isReady) {
      return null;
    }
    // ה-delegate נוחת בדיוק על היעד בסיום.
    if ((controller.currentZoom - target).abs() < 1e-6) _zoomTarget = null;
    return _zoomTarget;
  }

  @override
  void init(PdfViewerController controller, TickerProvider vsync) {
    _controller = controller;
    _inner.init(controller, vsync);
  }

  @override
  void dispose() {
    _zoomTarget = null;
    _controller = null;
    _inner.dispose();
  }

  @override
  void stop() {
    _zoomTarget = null;
    _inner.stop();
  }

  // pan עוצר את אנימציית הזום של ה-delegate.
  @override
  void pan(Offset delta, PdfViewerLayoutMetrics layoutMetrics) {
    _zoomTarget = null;
    _inner.pan(delta, layoutMetrics);
  }

  @override
  void zoom(
    double scale,
    Offset focalPoint,
    PdfViewerLayoutMetrics layoutMetrics,
  ) {
    final controller = _controller;
    if (controller != null && controller.isReady) {
      _zoomTarget = ((zoomTarget ?? controller.currentZoom) * scale).clamp(
        layoutMetrics.minScale,
        layoutMetrics.maxScale,
      );
    }
    _inner.zoom(scale, focalPoint, layoutMetrics);
  }
}
