import 'package:flutter/gestures.dart';

/// מזהה מחוות pan של לוח מגע מדויק (אירועי PointerPanZoom מסוג trackpad)
/// ו"גונב" אותן מה-InteractiveViewer של pdfrx, כדי שנעילת הציר החכמה
/// תחול גם עליהן (issue #969).
///
/// הרקע: ב-Windows, גלילה בשתי אצבעות על לוח מגע מדויק מגיעה כמחוות
/// PointerPanZoom - לא כאירועי גלילה - ולכן היא עוקפת את TrackpadAxisLock
/// ומטופלת ישירות ב-InteractiveViewer, שבו `PanAxis` מציע רק נעילה גסה
/// (הכרעה מהתזוזה הזעירה הראשונה, קיצוץ מוחלט לציר אחד).
///
/// אסטרטגיית הזירה (gesture arena):
/// - מחווה שמתחילה כ-pan (תזוזה מצטברת בלי שינוי scale) נתבעת אצלנו
///   לפני שה-ScaleGestureRecognizer של pdfrx מגיע לסף הקבלה שלו
///   (pan slop), כי סף הקבלה שלנו נמוך יותר ואנחנו ראשונים בסדר ה-hit test.
/// - מחווה שמתחילה כ-pinch (ה-scale סוטה מ-1) נדחית אצלנו מיד, כדי
///   ש-pdfrx ימשיך לטפל בזום בדיוק כמו היום.
class TrackpadPanRecognizer extends OneSequenceGestureRecognizer {
  TrackpadPanRecognizer({
    required this.onPanDelta,
    required this.onPanEnd,
    super.debugOwner,
  }) : super(supportedDevices: {PointerDeviceKind.trackpad});

  /// תזוזת pan (בכיוון תנועת האצבעות) יחד עם מיקום המצביע הגלובלי.
  final void Function(Offset panDelta, Offset globalPosition) onPanDelta;

  /// סוף מחווה שנתבעה - כאן מאפסים את נעילת הציר.
  final void Function() onPanEnd;

  /// מרחק ה-pan המצטבר שממנו המחווה נתבעת בזירה. חייב להיות קטן מסף
  /// הקבלה של ScaleGestureRecognizer (pan slop, ~36px) כדי לנצח אותו.
  static const double _acceptDistance = 6.0;

  /// סטיית scale שממנה המחווה מסווגת כ-pinch ונמסרת ל-pdfrx.
  static const double _pinchScaleDeviation = 0.015;

  _PanClaim _claim = _PanClaim.undecided;
  Offset _pendingPan = Offset.zero;

  @override
  void addAllowedPointerPanZoom(PointerPanZoomStartEvent event) {
    super.addAllowedPointerPanZoom(event);
    startTrackingPointer(event.pointer, event.transform);
    _claim = _PanClaim.undecided;
    _pendingPan = Offset.zero;
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event is PointerPanZoomUpdateEvent) {
      switch (_claim) {
        case _PanClaim.rejected:
          return;
        case _PanClaim.undecided:
          if ((event.scale - 1.0).abs() > _pinchScaleDeviation) {
            // pinch - משאירים ל-pdfrx לטפל בזום.
            _claim = _PanClaim.rejected;
            resolve(GestureDisposition.rejected);
            return;
          }
          _pendingPan += event.panDelta;
          if (_pendingPan.distance < _acceptDistance) {
            return;
          }
          _claim = _PanClaim.accepted;
          resolve(GestureDisposition.accepted);
          // מפצים על התזוזה שנצברה עד התביעה כדי לא "לבלוע" את תחילת המחווה.
          onPanDelta(_pendingPan, event.position);
        case _PanClaim.accepted:
          onPanDelta(event.panDelta, event.position);
      }
    } else if (event is PointerPanZoomEndEvent) {
      if (_claim == _PanClaim.accepted) {
        onPanEnd();
      }
      stopTrackingPointer(event.pointer);
    }
  }

  @override
  void rejectGesture(int pointer) {
    _claim = _PanClaim.rejected;
  }

  @override
  void didStopTrackingLastPointer(int pointer) {
    if (_claim != _PanClaim.accepted) {
      resolve(GestureDisposition.rejected);
    }
    _claim = _PanClaim.undecided;
    _pendingPan = Offset.zero;
  }

  @override
  String get debugDescription => 'trackpad pan (pdf axis lock)';
}

/// הכרעת הזירה עבור המחווה הנוכחית - ערך יחיד, בלי צירופי מצב לא-חוקיים.
enum _PanClaim { undecided, accepted, rejected }
