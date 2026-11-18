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
  PdfViewerScrollInteractionDelegate? _delegate;

  @override
  PdfViewerScrollInteractionDelegate create() => _delegate = inner.create();

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

  // זהות לפי המופע: pdfrx יוצר delegate חדש בכל שינוי provider, והמסך מחזיק
  // מופע יחיד לכל חיי ה-viewer.
  @override
  bool operator ==(Object other) => identical(this, other);

  @override
  int get hashCode => identityHashCode(this);
}
