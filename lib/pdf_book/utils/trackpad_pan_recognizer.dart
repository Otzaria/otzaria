import 'package:flutter/gestures.dart';

/// מנתב pan לנעילת הציר החכמה, ומשאיר pinch במסלול המקורי של pdfrx.
/// [onPanZoomEvent] מאפשר להעביר גם מחווה שהופכת מ-pan ל-pinch בהמשכה.
class TrackpadPanRecognizer extends OneSequenceGestureRecognizer {
  TrackpadPanRecognizer({
    required this.onPanDelta,
    required this.onPanEnd,
    this.onPanZoomEvent,
    this.canPanHorizontally,
    super.debugOwner,
  }) : super(supportedDevices: {PointerDeviceKind.trackpad});

  /// תזוזת pan (בכיוון תנועת האצבעות) יחד עם מיקום המצביע הגלובלי.
  final void Function(Offset panDelta, Offset globalPosition) onPanDelta;

  /// סוף מחווה שנתבעה - כאן מאפסים את נעילת הציר.
  final void Function() onPanEnd;

  /// מחווה שנתבעה כ-pan והופכת ל-pinch מועברת למסלול הזום המקורי.
  final void Function(PointerEvent event)? onPanZoomEvent;

  /// האם למסמך יש לאן לגלול לרוחב. כשלא - מחווה אופקית נמסרת
  /// הלאה, למעבר בין כרטיסיות.
  final bool Function()? canPanHorizontally;

  /// מרחק ה-pan המצטבר שממנו המחווה נתבעת בזירה. חייב להיות קטן מסף
  /// הקבלה של ScaleGestureRecognizer (pan slop, ~36px) כדי לנצח אותו.
  static const double _acceptDistance = 6.0;

  /// סטיית scale שממנה המחווה מסווגת כ-pinch ונמסרת ל-pdfrx.
  static const double _pinchScaleDeviation = 0.015;

  _PanClaim _claim = _PanClaim.undecided;
  int? _pointer;
  Offset _pendingPan = Offset.zero;
  PointerPanZoomUpdateEvent? _lastUpdate;
  Offset _scaleOriginPan = Offset.zero;
  double _scaleOrigin = 1;
  double _rotationOrigin = 0;

  @override
  void addAllowedPointerPanZoom(PointerPanZoomStartEvent event) {
    final previous = _pointer;
    if (previous != null) {
      handleEvent(PointerPanZoomEndEvent(pointer: previous));
    }
    super.addAllowedPointerPanZoom(event);
    startTrackingPointer(event.pointer, event.transform);
    _pointer = event.pointer;
    _claim = _PanClaim.undecided;
    _pendingPan = Offset.zero;
    _lastUpdate = null;
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event is PointerPanZoomUpdateEvent) {
      switch (_claim) {
        case _PanClaim.rejected:
          return;
        case _PanClaim.scaling:
          _forwardScale(event);
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
          if (_pendingPan.dx.abs() > _pendingPan.dy.abs() &&
              !(canPanHorizontally?.call() ?? true)) {
            _claim = _PanClaim.rejected;
            resolve(GestureDisposition.rejected);
            return;
          }
          _claim = _PanClaim.accepted;
          resolve(GestureDisposition.accepted);
          if (_beginScaleIfNeeded(event)) return;
          // מפצים על התזוזה שנצברה עד התביעה כדי לא "לבלוע" את תחילת המחווה.
          onPanDelta(_pendingPan, event.position);
        case _PanClaim.accepted:
          if (_beginScaleIfNeeded(event)) return;
          onPanDelta(event.panDelta, event.position);
      }
      _lastUpdate = event;
    } else if (event is PointerPanZoomEndEvent || event is PointerCancelEvent) {
      final claim = _claim;
      _claim = _PanClaim.rejected;
      if (claim == _PanClaim.scaling) onPanZoomEvent?.call(event);
      if (claim == _PanClaim.accepted || claim == _PanClaim.scaling) {
        onPanEnd();
      }
      stopTrackingPointer(event.pointer);
    }
  }

  bool _beginScaleIfNeeded(PointerPanZoomUpdateEvent event) {
    if (onPanZoomEvent == null || event.scale == 1) return false;
    final previous = _lastUpdate;
    _scaleOriginPan = previous?.pan ?? Offset.zero;
    _scaleOrigin = previous?.scale ?? 1;
    _rotationOrigin = previous?.rotation ?? 0;
    _claim = _PanClaim.scaling;
    onPanZoomEvent!(
      PointerPanZoomStartEvent(
        viewId: event.viewId,
        timeStamp: event.timeStamp,
        pointer: event.pointer,
        device: event.device,
        // הסמן לא זז במחוות לוח מגע - הזום מעוגן אליו ולא לסכום ה-pan שקדם.
        position: event.position,
      ),
    );
    if (_claim == _PanClaim.scaling) _forwardScale(event);
    return true;
  }

  void _forwardScale(PointerPanZoomUpdateEvent event) {
    _lastUpdate = event;
    onPanZoomEvent!(
      PointerPanZoomUpdateEvent(
        viewId: event.viewId,
        timeStamp: event.timeStamp,
        pointer: event.pointer,
        device: event.device,
        position: event.position,
        pan: event.pan - _scaleOriginPan,
        panDelta: event.panDelta,
        scale: event.scale / _scaleOrigin,
        rotation: event.rotation - _rotationOrigin,
      ),
    );
  }

  @override
  void dispose() {
    final claim = _claim;
    _claim = _PanClaim.rejected;
    if (claim == _PanClaim.scaling) {
      final last = _lastUpdate;
      onPanZoomEvent?.call(
        PointerPanZoomEndEvent(
          pointer: last?.pointer ?? 0,
          viewId: last?.viewId ?? 0,
          device: last?.device ?? 0,
          position: last?.position ?? Offset.zero,
        ),
      );
    }
    if (claim == _PanClaim.accepted || claim == _PanClaim.scaling) {
      onPanEnd();
    }
    super.dispose();
  }

  @override
  void rejectGesture(int pointer) {
    _claim = _PanClaim.rejected;
  }

  @override
  void didStopTrackingLastPointer(int pointer) {
    if (_claim != _PanClaim.accepted && _claim != _PanClaim.scaling) {
      resolve(GestureDisposition.rejected);
    }
    _claim = _PanClaim.undecided;
    _pendingPan = Offset.zero;
    _lastUpdate = null;
    _pointer = null;
  }

  @override
  String get debugDescription => 'trackpad pan (pdf axis lock)';
}

/// הכרעת הזירה עבור המחווה הנוכחית - ערך יחיד, בלי צירופי מצב לא-חוקיים.
enum _PanClaim { undecided, accepted, scaling, rejected }
